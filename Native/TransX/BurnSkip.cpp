#include "BurnSkip.h"
#include "Flight.h"
#include "TimeAcceleration.h"
#include <algorithm>
#include <chrono>
#include <cmath>

namespace native::transx {
namespace {
constexpr double Day=86400.;
// Keep expensive powered, rotating and atmospheric flight bounded. This
// mirrors the flight model's integration choice without changing its rules.
bool needsIntegration(const Flight &flight){
    bool atmospheric=(flight.reference==BodyId::Earth?flight.altitude()<120000:
        bodyAtmosphere(flight.reference,flight.altitude()).rho>1e-12)||
        (flight.centralBody().solid&&flight.altitude()<20);
    bool powered=flight.assist==Assist::Maneuver||flight.throttle>0||flight.glider.hover>0||
        flight.glider.hoverControl.holdActive||flight.glider.retro>0||flight.angularVelocity.length2()>1e-16;
    auto orbit=flight.orbit();
    return atmospheric||powered||(flight.centralBody().solid&&orbit.PeDist()<flight.centralBody().radius+20)||
        std::fabs(orbit.e-1)<1e-8;
}
}

bool BurnSkip::begin(Flight &flight,Session &session,std::string &error){
    if(running()){error="A skip is already in progress.";return false;}
    if(flight.impacted){error="Restart the flight before skipping time.";return false;}
    if(session.windowSearchStatus().state==SearchState::Running){error="Finish or cancel the window search first.";return false;}
    StageInfo info;BurnTiming timing;int stage=session.selectedStage();
    if(!session.stageInfo(stage,info)||!info.enabled||!session.stageTiming(stage,timing)||timing.deltaV<=.1){
        error="Select an enabled, nonzero burn first.";return false;
    }
    double untilIgnition=timing.secondsToBurn-timing.duration*.5;
    if(!std::isfinite(untilIgnition)||untilIgnition<=Day){error="The selected burn is already less than one day away.";return false;}
    reference_=info.reference;maneuver_=info.maneuver;stageToken_=session.selectedStageToken();epoch_=flight.mjd;
    flight.paused=false;flight.warp=MaximumTimeAcceleration;state_=State::Running;error.clear();return true;
}

bool BurnSkip::samePlan(Session &session)const{
    StageInfo info;if(session.selectedStageToken()!=stageToken_||!session.stageInfo(session.selectedStage(),info)||!info.enabled||info.reference!=reference_)return false;
    const auto &v=info.maneuver;
    return v.date==maneuver_.date&&v.prograde==maneuver_.prograde&&v.outward==maneuver_.outward&&v.plane==maneuver_.plane;
}
void BurnSkip::stop(Flight &flight,State state){flight.warp=1;flight.paused=true;state_=state;}
void BurnSkip::cancel(Flight &flight){if(running())stop(flight,State::Cancelled);}
void BurnSkip::reset(){state_=State::Idle;}

void BurnSkip::advance(Flight &flight,Session &session,size_t maxSteps,double budgetSeconds){
    if(!running())return;
    if(flight.impacted||flight.paused){stop(flight,State::FlightStopped);return;}
    if(flight.mjd!=epoch_||!samePlan(session)){stop(flight,State::PlanChanged);return;}
    if(flight.warp!=MaximumTimeAcceleration){stop(flight,State::Cancelled);return;}
    auto started=std::chrono::steady_clock::now();
    for(size_t i=0;i<maxSteps&&running();++i){
        BurnTiming timing;
        if(!session.stageTiming(session.selectedStage(),timing)){stop(flight,State::PlanChanged);return;}
        double target=(maneuver_.date-flight.mjd)*Day-timing.duration*.5-Day;
        double remaining=target-flight.elapsed;
        if(!std::isfinite(remaining)){stop(flight,State::PlanChanged);return;}
        if(remaining<=1e-6){stop(flight,State::Reached);return;}
        double chunk=std::min(remaining,needsIntegration(flight)?1.:600.);
        double before=flight.elapsed;BodyId oldReference=flight.reference;
        flight.advance(chunk/MaximumTimeAcceleration);
        if(flight.impacted||flight.paused||flight.elapsed<=before){stop(flight,State::FlightStopped);return;}
        if(flight.reference!=oldReference){
            for(int n=0;n<64;++n)session.tick();
            if(!samePlan(session)){stop(flight,State::PlanChanged);return;}
        }
        if(budgetSeconds>0&&std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count()>=budgetSeconds)break;
    }
    BurnTiming timing;
    if(running()&&session.stageTiming(session.selectedStage(),timing)&&
       timing.secondsToBurn-timing.duration*.5<=Day+1e-5)stop(flight,State::Reached);
}
}

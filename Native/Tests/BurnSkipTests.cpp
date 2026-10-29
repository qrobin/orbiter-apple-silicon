#include "BurnSkip.h"
#include "Flight.h"
#include "SolarSystem.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){try{
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    Flight flight;flight.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    flight.automaticReferenceChanges=false;flight.paused=true;flight.warp=50;
    transx::Session session(flight);for(int i=0;i<100;++i)session.tick();
    transx::RouteValues burn{flight.mjd+3.7,3500,50,0};
    check(session.setStageManeuver(1,burn),"Set a future burn");
    transx::BurnSkip skip;std::string error;
    const double fuel=flight.fuel,throttle=flight.throttle;Elements coast=flight.orbit();
    check(skip.begin(flight,session,error)&&!flight.paused,"Skipping starts from a paused flight");
    for(int i=0;i<1000&&skip.running();++i)skip.advance(flight,session,128,0);
    transx::BurnTiming timing;
    check(skip.state()==transx::BurnSkip::State::Reached&&flight.paused&&flight.warp==1,"Skipping stops and pauses at normal speed");
    check(session.stageTiming(1,timing)&&fabs(timing.secondsToBurn-timing.duration*.5-86400.)<.01,
          "The flight stops one day before estimated ignition");
    Vector expectedPosition,expectedVelocity;coast.PosVel(expectedPosition,expectedVelocity,flight.elapsed);
    check(expectedPosition.dist(flight.position)<10&&expectedVelocity.dist(flight.velocity)<.02,"Skipping advances the ordinary orbital simulation");
    check(flight.fuel==fuel&&flight.throttle==throttle,"Skipping a coast does not fire the engines");
    check(!skip.begin(flight,session,error)&&flight.paused&&flight.warp==1,"Skipping never moves time backward when the burn is too close");

    burn.date=flight.mjd+flight.elapsed/86400.+4;check(session.setStageManeuver(1,burn),"Set another future burn");
    check(skip.begin(flight,session,error),"Start another skip");burn.prograde+=10;
    check(session.setStageManeuver(1,burn),"Change the selected burn while skipping");skip.advance(flight,session);
    check(skip.state()==transx::BurnSkip::State::PlanChanged&&flight.paused&&flight.warp==1,"Changing the burn cancels the skip safely");
    check(skip.begin(flight,session,error),"Start a cancellable skip");skip.cancel(flight);
    check(skip.state()==transx::BurnSkip::State::Cancelled&&flight.paused&&flight.warp==1,"Cancel returns to a paused flight");

    flight.throttle=.2;check(skip.begin(flight,session,error),"A powered flight can still request a skip");
    double before=flight.elapsed,poweredFuel=flight.fuel;skip.advance(flight,session,1,0);
    check(skip.running()&&flight.elapsed-before<=1.0001&&flight.fuel<poweredFuel&&flight.throttle==.2,
          "Powered flight remains simulated and each integration chunk is bounded");
    skip.cancel(flight);flight.throttle=0;

    transx::Route route;check(session.createRoute(BodyId::Mars,route,error),"Create a multi-stage route");
    double now=flight.mjd+flight.elapsed/86400.;
    transx::RouteValues first{now+3,1200,0,0},second{now+4.25,500,25,0};
    check(session.setStageManeuver(1,first)&&session.setStageManeuver(2,second)&&session.selectStage(2),"Configure distinct stage burns");
    check(skip.begin(flight,session,error),"A future stage can start a skip");
    check(session.selectStage(1),"Select a different stage during the skip");skip.advance(flight,session);
    check(skip.state()==transx::BurnSkip::State::PlanChanged&&flight.paused,"Changing the selected stage cancels its skip");
    check(session.selectStage(2)&&skip.begin(flight,session,error),"Restart the skip for the second stage");
    double beforeFuel=flight.fuel;
    for(int i=0;i<1000&&skip.running();++i)skip.advance(flight,session,128,0);
    transx::BurnTiming firstTiming,secondTiming;
    check(skip.state()==transx::BurnSkip::State::Reached&&session.stageTiming(2,secondTiming)&&
        fabs(secondTiming.secondsToBurn-secondTiming.duration*.5-86400.)<.01,
        "The skip targets the selected second-stage ignition");
    check(session.stageTiming(1,firstTiming)&&firstTiming.secondsToBurn<0&&flight.fuel==beforeFuel,
        "Skipping to a later stage advances time without executing an earlier burn");

    // The selected stage is the same TransX object after earlier stages are
    // removed on a real sphere-of-influence transition.
    double soi=sphereOfInfluence(BodyId::Earth,flight.mjd+flight.elapsed/86400.);
    flight.reference=BodyId::Earth;flight.position={soi*1.02,0,0};flight.velocity={40000,0,1000};
    flight.automaticReferenceChanges=true;flight.clearAssist();flight.angularVelocity={0,0,0};
    second.date=flight.mjd+flight.elapsed/86400.+1.7;
    check(session.setStageManeuver(2,second)&&session.selectStage(2)&&skip.begin(flight,session,error),"Start a skip through an Earth escape");
    auto token=session.selectedStageToken();
    for(int i=0;i<1000&&skip.running();++i){session.tick();skip.advance(flight,session,64,0);}
    check(skip.state()==transx::BurnSkip::State::Reached&&flight.reference==BodyId::Sun&&
        session.selectedStage()==1&&session.selectedStageToken()==token,
        "The skip follows the selected stage through its automatic renumbering");
    std::cout<<"burn skip checks passed\n";
}catch(const std::exception &error){std::cerr<<error.what()<<'\n';return 1;}}

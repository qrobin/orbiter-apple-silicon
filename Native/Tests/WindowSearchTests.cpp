#include "Session.h"
#include "Flight.h"
#include "SolarSystem.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool value,const std::string &message){if(!value)throw std::runtime_error(message);}
int main(){try{
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    Flight flight;flight.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    transx::Session session(flight);for(int i=0;i<100;++i)session.tick();
    transx::Route route;std::string error;
    check(session.createRoute(BodyId::Mars,route,error),error);
    double fuel=flight.fuel,rcs=flight.rcs,throttle=flight.throttle;
    check(session.beginWindowSearch(route,error),error);
    for(int i=0;i<1000&&session.windowSearchStatus().state==transx::SearchState::Running;++i)session.stepWindowSearch(64);
    auto result=session.windowSearchStatus();
    std::cout<<"status="<<(int)result.state<<" miss="<<result.missDistance<<" m, arrival="<<result.arrivalMJD<<" dv="<<result.departureDV<<" capture="<<result.captureDV<<" message="<<result.message<<'\n';
    check(result.state==transx::SearchState::Complete,result.message);
    check(result.missDistance<sphereOfInfluence(BodyId::Mars,result.arrivalMJD),"TransX predicts an encounter within Mars's sphere of influence");
    transx::StageInfo stage;check(session.stageInfo(1,stage)&&stage.enabled&&stage.maneuver.date>flight.mjd,"Search applies a future departure maneuver");
    VECTOR3 direction;check(session.maneuverDirectionForStage(1,direction)&&std::isfinite(length(direction)),"The optimized maneuver supplies an RCS direction");
    check(flight.fuel==fuel&&flight.rcs==rcs&&flight.throttle==throttle,"Searching never fires engines or RCS");
    auto saved=(std::filesystem::temp_directory_path()/"orbiter-window-test.scn").string();
    session.save(saved);session.load(saved);std::filesystem::remove(saved);
    transx::Route restored;transx::Approach approach;
    check(session.currentRoute(restored)&&session.routeApproach(restored,approach)&&approach.distance<sphereOfInfluence(BodyId::Mars,approach.mjd),
          "A saved and reloaded route retains the verified encounter");
    transx::Route moon;check(session.createRoute(BodyId::Moon,moon,error),error);
    check(session.beginWindowSearch(moon,error),error);
    for(int i=0;i<1000&&session.windowSearchStatus().state==transx::SearchState::Running;++i)session.stepWindowSearch(64);
    auto lunar=session.windowSearchStatus();
    std::cout<<"moon status="<<(int)lunar.state<<" miss="<<lunar.missDistance<<" message="<<lunar.message<<'\n';
    check(lunar.state==transx::SearchState::Complete&&lunar.missDistance<sphereOfInfluence(BodyId::Moon,lunar.arrivalMJD),
          "A direct lunar route has a verified encounter");
    transx::StageInfo prior;check(session.stageInfo(1,prior),"Read the lunar maneuver");
    check(session.beginWindowSearch(moon,error),error);session.stepWindowSearch(4);session.cancelWindowSearch();
    transx::StageInfo afterCancel;check(session.stageInfo(1,afterCancel)&&afterCancel.maneuver.date==prior.maneuver.date&&
          afterCancel.maneuver.prograde==prior.maneuver.prograde,"Cancel leaves the existing maneuver unchanged");
    check(session.beginWindowSearch(moon,error),error);Vector originalVelocity=flight.velocity;flight.velocity.x+=30;
    for(int i=0;i<1000&&session.windowSearchStatus().state==transx::SearchState::Running;++i)session.stepWindowSearch(64);
    check(session.windowSearchStatus().state==transx::SearchState::Failed&&session.stageInfo(1,afterCancel)&&
          afterCancel.maneuver.date==prior.maneuver.date,"Changing orbit rejects the result and keeps the prior maneuver");
    flight.velocity=originalVelocity;
    check(session.beginWindowSearch(moon,error),error);transx::Route changed;
    check(session.createRoute(BodyId::Mars,changed,error),error);session.stepWindowSearch(1);
    check(session.windowSearchStatus().state==transx::SearchState::Failed&&session.routeMatches(changed),
          "Changing the shared TransX route cancels the stale search");
    for(auto target:{BodyId::Venus,BodyId::Jupiter}){
        transx::Route next;check(session.createRoute(target,next,error),error);check(session.beginWindowSearch(next,error),error);
        for(int i=0;i<1000&&session.windowSearchStatus().state==transx::SearchState::Running;++i)session.stepWindowSearch(64);
        auto found=session.windowSearchStatus();
        check(found.state==transx::SearchState::Complete&&found.missDistance<sphereOfInfluence(target,found.arrivalMJD),
              std::string("Verified encounter for ")+body(target).name+": "+found.message);
    }
    transx::Route multi;check(session.createRoute(std::vector<BodyId>{BodyId::Mars,BodyId::Jupiter},multi,error),error);
    flight.startOrbit(BodyId::Sun);for(int i=0;i<256;++i)session.tick();
    flight.startOrbit(BodyId::Mars);for(int i=0;i<256;++i)session.tick();
    transx::Route onward;check(session.currentRoute(onward)&&onward.origin==BodyId::Mars&&onward.destination==BodyId::Jupiter&&
        onward.ejectStage==2&&session.routeMatches(onward),"The remaining leg survives the original TransX stage transition");
    transx::RouteValues ejection{flight.mjd+20,2700,100,-80},roundTrip;
    check(session.setRouteValues(onward,false,ejection)&&session.routeValues(onward,false,roundTrip)&&
        fabs(roundTrip.prograde-ejection.prograde)<1e-6&&fabs(roundTrip.outward-ejection.outward)<1e-6&&
        fabs(roundTrip.plane-ejection.plane)<1e-6,"Sling Direct ejection values round trip through the shared plan");
    check(session.beginWindowSearch(onward,error),error);
    for(int i=0;i<1000&&session.windowSearchStatus().state==transx::SearchState::Running;++i)session.stepWindowSearch(64);
    auto onwardResult=session.windowSearchStatus();
    check(onwardResult.state==transx::SearchState::Complete&&session.routeMatches(onward)&&
        onwardResult.missDistance<sphereOfInfluence(BodyId::Jupiter,onwardResult.arrivalMJD),
        std::string("Search the next leg after entering Mars orbit: ")+onwardResult.message);
    check(session.alignStage(1)&&flight.assist==Assist::Maneuver,"The new current-stage burn can be aligned with RCS");flight.clearAssist();
    session.save(saved);session.load(saved);std::filesystem::remove(saved);
    transx::Route savedOnward;transx::Approach savedApproach;
    check(session.currentRoute(savedOnward)&&savedOnward.ejectStage==2&&session.routeApproach(savedOnward,savedApproach)&&
        savedApproach.distance<sphereOfInfluence(BodyId::Jupiter,savedApproach.mjd),
        "A solved onward Sling Direct leg survives scenario save and reload");
    std::cout<<"window search checks passed\n";
}catch(const std::exception &error){std::cerr<<error.what()<<'\n';return 1;}}

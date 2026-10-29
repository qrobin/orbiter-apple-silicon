#include "Session.h"
#include "Flight.h"
#include "SolarSystem.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static int checks=0;
static void check(bool condition,const char *message){++checks;if(!condition)throw std::runtime_error(message);}
static bool near(double a,double b){return std::fabs(a-b)<1e-5;}
int main(){try{
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    Flight flight;flight.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    transx::Route route;std::string error;
    const double fuel=flight.fuel,throttle=flight.throttle;
    auto saved=(std::filesystem::temp_directory_path()/"orbiter-route-test.scn").string();
    {
    transx::Session session(flight);for(int i=0;i<100;++i)session.tick();
    check(session.createRoute(BodyId::Mars,route,error),"Earth to Mars route created");
    check(route.legs.size()==2&&route.legs[0].center==BodyId::Earth&&route.legs[0].escape&&
          route.legs[1].center==BodyId::Sun&&route.legs[1].next==BodyId::Mars&&route.targetStage==2&&route.ejectStage==2,
          "Earth escape and Mars target use original TransX stages");
    check(session.routeMatches(route),"Created route matches TransX state");
    check(session.frame(0).stage==1&&session.frame(1).stage==1,"Route view does not move the two flight MFDs");
    transx::RouteValues ejection;
    check(session.routeValues(route,false,ejection),"Original TransX ejection values available");
    double estimate=0;check(session.routeHohmann(route,estimate)&&estimate>1000&&estimate<5000,"Original Hohmann estimate for Mars");
    ejection={flight.mjd+20,estimate,200,-50};
    check(session.setRouteValues(route,false,ejection),"Original ejection variables accept values");
    transx::RouteValues readback;
    check(session.routeValues(route,false,readback)&&near(readback.date,ejection.date)&&near(readback.prograde,ejection.prograde)&&
          near(readback.outward,ejection.outward)&&near(readback.plane,ejection.plane),"Ejection values round trip through TransX");
    for(int i=0;i<100;++i)session.tick();transx::Approach approach;
    check(session.routeApproach(route,approach)&&approach.source==1&&std::isfinite(approach.distance),"Approach uses original ejection plan");
    transx::RouteValues burn={flight.mjd+.01,3500,100,50};
    check(session.setRouteValues(route,true,burn),"Burn variables configure original maneuver");
    check(session.routeValues(route,true,readback)&&near(readback.date,burn.date)&&near(readback.prograde,burn.prograde)&&
          near(readback.outward,burn.outward)&&near(readback.plane,burn.plane),"Burn variables round trip through TransX");
    VECTOR3 direction;check(session.routeView(2,2)&&session.maneuverDirectionForStage(1,direction)&&near(length(direction),1),
          "Departure alignment remains available while viewing the transfer stage");
    session.button(0,1);session.frame(0);
    check(session.frame(0).stage==2,"Set the left MFD to the transfer stage");
    auto invalid=burn;invalid.plane=NAN;
    check(!session.setRouteValues(route,true,invalid)&&session.routeValues(route,true,readback)&&near(readback.prograde,burn.prograde),
          "Invalid input leaves the burn unchanged");
    check(!session.createRoute(BodyId::Earth,route,error)&&session.routeMatches(route),"Invalid destination preserves the existing route");
    check(flight.fuel==fuel&&flight.throttle==throttle&&flight.assist!=Assist::Maneuver,"Planning does not fire engines or engage RCS");
    transx::Route moon;check(session.createRoute(BodyId::Moon,moon,error)&&session.routeMatches(moon),"Earth to Moon replaces the prior route");
    check(moon.legs.size()==1&&!moon.legs[0].escape&&moon.targetStage==1&&moon.ejectStage==0,"Direct moon transfer uses the departure stage");
    check(!session.routeMatches(route),"Prior route becomes stale when the shared TransX plan changes");
    check(session.setRouteValues(moon,true,burn),"Direct route uses departure maneuver fields");
    for(int i=0;i<100;++i)session.tick();
    check(session.routeApproach(moon,approach)&&approach.source==2,"Direct route approach uses the original maneuver orbit");
    transx::Route europa;check(session.createRoute(BodyId::Europa,europa,error),(std::string("Route to another planet's moon: ")+error).c_str());
    check(session.routeMatches(europa),"Route to another planet's moon matches TransX");
    check(europa.legs.size()==3&&europa.legs[1].next==BodyId::Jupiter&&europa.legs[2].next==BodyId::Europa,
          "Moon route targets its parent before the moon");
    session.button(0,1);session.frame(0);
    check(session.frame(0).stage==2,"Left MFD moved to stage two");
    transx::Route marsAgain;
    check(session.createRoute(BodyId::Mars,marsAgain,error)&&session.frame(0).stage==2,
          "Creating a route keeps an existing MFD stage when it is still available");
    transx::Route sun;check(session.createRoute(BodyId::Sun,sun,error),(std::string("Escape into the parent system works: ")+error).c_str());
    check(session.routeMatches(sun),"Parent escape matches the TransX state");
    check(sun.targetStage==0&&sun.legs.size()==1&&sun.legs[0].escape,"Parent escape is not presented as an intercept");
    for(const auto &target:bodies()){
        if(target.id==flight.reference)continue;
        transx::Route candidate;
        if(!session.createRoute(target.id,candidate,error)||!session.routeMatches(candidate))
            throw std::runtime_error(std::string("Route to ")+target.name+": "+error);
        ++checks;
    }
    check(session.createRoute(BodyId::Mars,route,error),"Restore a Mars route for serialization");
    ejection={flight.mjd+20,3000,200,-50};burn={flight.mjd+.01,3500,100,50};
    check(session.setRouteValues(route,false,ejection)&&session.setRouteValues(route,true,burn),"Set values before save");
    session.frame(0);session.save(saved);
    }
    {
    transx::Session restored(flight);for(int i=0;i<100;++i)restored.tick();restored.load(saved);
    check(restored.routeMatches(route),"Saved route is restored in a new TransX session");
    transx::Route recovered;
    check(restored.currentRoute(recovered)&&recovered.origin==BodyId::Earth&&recovered.destination==BodyId::Mars&&recovered.ejectStage==2,
          "Route tool reconstructs the saved route from original TransX state");
    transx::RouteValues values;
    check(restored.routeValues(route,false,values)&&near(values.prograde,3000),"Saved ejection values are restored");
    check(restored.routeValues(route,true,values)&&near(values.prograde,3500),"Saved burn values are restored");
    }
    std::filesystem::remove(saved);
    flight.startOrbit(BodyId::Io);
    {
    transx::Session session(flight);for(int i=0;i<100;++i)session.tick();
    transx::Route deep;
    check(session.createRoute(BodyId::Mars,deep,error)&&session.routeMatches(deep),"Moon-to-planet route uses multiple escape stages");
    check(deep.legs.size()==3&&deep.legs[0].next==BodyId::Jupiter&&deep.legs[1].next==BodyId::Sun&&deep.legs[2].next==BodyId::Mars,
          "Multi-escape route follows the original hierarchy");
    }
    std::cout<<checks<<" route checks passed\n";
}catch(const std::exception &error){std::cerr<<"After "<<checks<<" checks: "<<error.what()<<'\n';return 1;}}

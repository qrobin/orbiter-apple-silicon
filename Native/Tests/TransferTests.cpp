#include "Transfer.h"
#include <iostream>
#include <stdexcept>
using namespace native;
static int checks;
static void check(bool ok,const std::string &label){++checks;if(!ok)throw std::runtime_error(label);}
// Independent fourth-order integration verifies Lambert and conic propagation.
static BodyState integrate(BodyState s,double dt,double mu,int steps=6000){
    double h=dt/steps;auto a=[&](Vector p){return p*(-mu/pow(p.length(),3));};
    for(int i=0;i<steps;++i){auto p1=s.velocity,v1=a(s.position),p2=s.velocity+v1*(h*.5),v2=a(s.position+p1*(h*.5));
        auto p3=s.velocity+v2*(h*.5),v3=a(s.position+p2*(h*.5)),p4=s.velocity+v3*h,v4=a(s.position+p3*h);
        s.position+=(p1+p2*2+p3*2+p4)*(h/6);s.velocity+=(v1+v2*2+v3*2+v4)*(h/6);
    }return s;
}
int main(){try{
    double mu=3.986004418e14,r=7000000,v=sqrt(mu/r),period=Pi2*r/v;
    Vector p(r,0,0),q(0,r,0),north(0,0,1);
    auto circular=solveLambert(p,q,period/4,mu,north);
    check(circular.has_value(),"Circular quarter-orbit Lambert solution");
    check(circular->departure.dist(Vector(0,v,0))<1e-6&&circular->arrival.dist(Vector(-v,0,0))<1e-6,"Circular endpoint velocities");
    for(double tof:{period*.05,period*.25,period*.7}){
        for(Vector n:{north,-north}){
            auto l=solveLambert(p,q,tof,mu,n);check(l.has_value(),"Elliptic/hyperbolic and long/short Lambert branch");
            auto actual=integrate({p,l->departure},tof,mu);check(actual.position.dist(q)<3,"Independent RK4 Lambert endpoint: "+std::to_string(actual.position.dist(q)));
            check(actual.velocity.dist(l->arrival)<.01,"Independent RK4 arrival velocity");
        }
    }
    check(!solveLambert(p,q,-1,mu)&&!solveLambert(p,p,100,mu)&&!solveLambert(p,-p,100,mu),"Reject negative time and degenerate geometry");
    auto textbook=solveLambert({5000000,10000000,2100000},{-14600000,2500000,7000000},3600,mu,north);
    check(textbook&&textbook->departure.dist(Vector(-5992.5,1925.4,3245.6))<.15,"Published Lambert example velocity");
    BodyState initial{p,{0,v,0}};auto propagated=propagateConic(initial,period*12.25,mu);
    check(propagated.position.dist(q)<.01&&propagated.velocity.dist(Vector(-v,0,0))<1e-5,"Multirevolution conic propagation");
    auto back=propagateConic(propagated,-period*12.25,mu);check(back.position.dist(p)<.03&&back.velocity.dist(initial.velocity)<1e-4,"Negative-time conic reversibility");
    // For a known hyperbola at periapsis, recover the velocity from its outgoing asymptote.
    double w=3200,e=1+r*w*w/mu;Vector excess(-w/e,w*sqrt(1-1/(e*e)),0);
    auto escape=escapeVelocity(p,excess,mu);check(escape&&escape->dist(Vector(0,sqrt(w*w+2*mu/r),0))<1e-6,"Hyperbolic periapsis ejection direction");
    for(Vector direction:{Vector(-.8,.4,.2).unit(),Vector(.5,.7,-.3).unit(),Vector(-.1,-.7,.6).unit()}){
        Vector inf=direction*w;auto departure=escapeVelocity(p,inf,mu);check(departure.has_value(),"Three-dimensional escape targeting");
        check(fabs(departure->length2()-w*w-2*mu/r)<1e-5,"Escape energy invariant");
        auto far=propagateConic({p,*departure},86400*40,mu);
        check(far.velocity.unit().dist(direction)<2e-4&&fabs(far.velocity.length()-w)<40,"Propagated outgoing asymptote, direction and speed");
    }
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    check(departureSystem(BodyId::Moon)==BodyId::Earth&&departureSystem(BodyId::Europa)==BodyId::Jupiter,"Moon references use their departure planet system");
    Flight f;f.startOrbit(BodyId::Earth);f.assist=Assist::Free;
    TransferRequest request;request.departureMJD=f.mjd;request.flightDays=nominalTransferDays(request.origin,request.target,f.mjd);
    request.parking=parkingOrbit(f);request.departureAltitude=f.altitude();request.arrivalAltitude=defaultParkingAltitude(request.target);
    auto unguided=planTransfer(request,false);TransferSearch search;search.begin(request,900);
    while(search.active())search.step(200);
    check(search.result().has_value()&&search.progress()==1,"Launch-window search completes");
    check(search.result()->totalDV()<=unguided.totalDV(),"Window search lowers departure-plus-capture cost");
    auto plan=planTransfer(search.result()->request);
    check(plan.guidedDeparture&&plan.departureDV>0&&plan.departureDV<30000,"Parking-orbit plane included in guided ejection");
    auto endpoint=propagateConic({plan.start.position,plan.trajectory.departure},request.flightDays*86400,body(BodyId::Sun).mu());
    // The search chooses its own duration.
    endpoint=propagateConic({plan.start.position,plan.trajectory.departure},plan.request.flightDays*86400,body(BodyId::Sun).mu());
    check(endpoint.position.dist(plan.end.position)<1000,"Earth–Mars transfer arrives at moving Mars position");
    auto independent=integrate({plan.start.position,plan.trajectory.departure},plan.request.flightDays*86400,body(BodyId::Sun).mu());
    check(independent.position.dist(plan.end.position)<10000,"Earth–Mars independently integrated arrival");
    auto node=propagateConic(request.parking->state,(plan.departureMJD-f.mjd)*86400,f.gravityMu());
    check(node.position.dist(plan.burnPosition)<100,"Ejection node date matches the spacecraft parking orbit");
    auto actualEscape=escapeVelocity(node.position,plan.departureExcess,f.gravityMu());
    check(actualEscape&&(*actualEscape-node.velocity).dist(plan.burnVector)<.01,"Ejection burn vector uses the correct departure state");
    auto g=transferGuidance(plan,f);check(g.valid&&g.burnSeconds>0&&g.availableDV>0&&g.propellant>0,"Live fuel and manual-burn guidance");
    auto parkingFrameNormal=crossp(plan.burnPosition,plan.burnVelocityBefore).unit();
    check(fabs(g.normal-dotp(plan.burnVector,parkingFrameNormal))<1e-8&&!g.live,"Planned components use the fixed burn-node frame");
    auto coasted=f;coastToDeparture(coasted,plan);auto nearNode=transferGuidance(plan,coasted);
    check(fabs(nearNode.secondsToBurn-300)<.001&&coasted.fuel==f.fuel&&coasted.rcs==f.rcs,"Coast stops five minutes before departure without consuming propellant");
    auto exact=propagateConic({f.position,f.velocity},coasted.elapsed-f.elapsed,f.gravityMu());
    check(exact.position.dist(coasted.position)<.001&&exact.velocity.dist(coasted.velocity)<1e-8,"Coast advances the actual parking-orbit state");
    bool coastRejected=false;coasted=f;coasted.throttle=.2;try{coastToDeparture(coasted,plan);}catch(...){coastRejected=true;}
    check(coastRejected&&coasted.elapsed==f.elapsed,"Powered coast rejected without mutating flight");
    auto before=f;f.maneuverDirection=g.deltaVelocity.unit();f.assist=Assist::Maneuver;f.glider.rcsMode=1;f.warp=1000;
    double angle=acos(std::clamp(dotp(f.forward,f.maneuverDirection),-1.,1.));
    for(int i=0;i<4000;++i)f.advance(.01);
    double aligned=acos(std::clamp(dotp(f.forward,f.maneuverDirection),-1.,1.));
    check(aligned<angle*.25&&aligned<.04,"Finite RCS maneuver alignment converges, start="+std::to_string(angle)+" end="+std::to_string(aligned));
    check(f.rcs<before.rcs&&f.fuel==before.fuel&&f.throttle==0&&f.warp==1,"Alignment consumes RCS only and keeps engines manual at real time");
    f=before;f.elapsed=(plan.departureMJD-f.mjd)*86400+86400;
    check(!transferGuidance(plan,f).valid,"Missed departure disables stale burn guidance");f=before;
    f.reference=BodyId::Moon;check(!transferGuidance(plan,f).valid,"Guidance disabled in a different gravity reference");
    f.startOrbit(BodyId::Sun);request.origin=BodyId::Sun;request.parking=parkingOrbit(f);request.departureMJD=f.mjd;request.flightDays=200;
    auto heliocentric=planTransfer(request);check(heliocentric.guidedDeparture&&transferGuidance(heliocentric,f).valid,"Heliocentric spacecraft departure guidance");
    for(BodyId target:{BodyId::Mercury,BodyId::Venus,BodyId::Vesta,BodyId::Jupiter,BodyId::Saturn,BodyId::Uranus,BodyId::Neptune}){
        TransferRequest q;q.target=target;q.arrivalAltitude=defaultParkingAltitude(target);q.flightDays=nominalTransferDays(q.origin,target,q.departureMJD);
        auto result=planTransfer(q);auto end=propagateConic({result.start.position,result.trajectory.departure},q.flightDays*86400,body(BodyId::Sun).mu());
        check(end.position.dist(result.end.position)<20000,std::string(body(target).name)+" Lambert arrival");
    }
    bool rejected=false;try{request.arrivalAltitude=-1;planTransfer(request);}catch(...){rejected=true;}check(rejected,"Reject unsafe arrival altitude");
    std::cout<<checks<<" transfer navigation checks passed; Earth–Mars window Δv "<<plan.totalDV()<<" m/s, departure MJD "<<plan.departureMJD<<'\n';
}catch(const std::exception &e){std::cerr<<"After "<<checks<<" checks: "<<e.what()<<'\n';return 1;}}

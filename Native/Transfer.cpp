#include "Transfer.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace native {
namespace {
constexpr double Day=86400;
bool finite(const Vector &v){return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z);}
void stumpff(double z,double &c,double &s){
    if(std::abs(z)<1e-5){c=.5-z/24+z*z/720-z*z*z/40320;s=1./6-z/120+z*z/5040-z*z*z/362880;}
    else if(z>0){double x=sqrt(z);c=2*pow(sin(x*.5),2)/z;s=(x-sin(x))/(x*x*x);}
    else{double x=sqrt(-z);c=(cosh(x)-1)/(-z);s=(sinh(x)-x)/(x*x*x);}
}
double excessBurn(double speed,double mu,double radius){return sqrt(speed*speed+2*mu/radius)-sqrt(mu/radius);}
bool safeEscape(const BodyState &s,const Vector &v,BodyId id){
    if(dotp(s.position,v)>=0)return true; // Any low periapsis is already behind the spacecraft.
    double mu=body(id).mu(),h2=crossp(s.position,v).length2();
    double e=sqrt(std::max(0.,1+(v.length2()-2*mu/s.position.length())*h2/(mu*mu)));
    return h2/(mu*(1+e))>body(id).radius+navigationAtmosphereLimit(id);
}
struct Ejection {double time=0,cost=std::numeric_limits<double>::infinity();BodyState state;Vector delta;};
Ejection ejection(const ParkingOrbit &parking,const Vector &excess,double requestedDate){
    double mu=body(parking.reference).mu(),r=parking.state.position.length();
    double alpha=2/r-parking.state.velocity.length2()/mu;
    if(alpha<=0)throw std::runtime_error("Ejection guidance needs a bound parking orbit. Use heliocentric navigation after escape.");
    double period=Pi2/sqrt(mu*alpha*alpha*alpha);
    // Search one revolution around the requested departure. Never choose a past burn.
    double start=std::max(0.,(requestedDate-parking.mjd)*Day-period*.5);
    auto evaluate=[&](double t){
        Ejection out;out.time=t;out.state=propagateConic(parking.state,t,mu);
        auto desired=escapeVelocity(out.state.position,excess,mu);
        if(desired&&safeEscape(out.state,*desired,parking.reference)){
            out.delta=*desired-out.state.velocity;out.cost=out.delta.length();
        }
        return out;
    };
    Ejection best;constexpr int N=96;
    for(int i=0;i<=N;++i){auto next=evaluate(start+period*i/N);if(next.cost<best.cost)best=next;}
    if(!std::isfinite(best.cost))throw std::runtime_error("No safe departure from this orbit. Raise periapsis above the atmosphere first.");
    double lo=std::max(start,best.time-period/N),hi=std::min(start+period,best.time+period/N);
    for(int i=0;i<28;++i){double a=lo+(hi-lo)*.38196601125,b=hi-(hi-lo)*.38196601125;auto x=evaluate(a),y=evaluate(b);
        if(x.cost<best.cost)best=x;if(y.cost<best.cost)best=y;if(x.cost<y.cost)hi=b;else lo=a;
    }
    return best;
}
}
std::optional<LambertSolution> solveLambert(const Vector &r1,const Vector &r2,double seconds,double mu,const Vector &normal){
    double a=r1.length(),b=r2.length();
    if(!(seconds>0&&mu>0&&a>0&&b>0)||!finite(r1)||!finite(r2)||!std::isfinite(seconds+mu))return {};
    double cosine=std::clamp(dotp(r1,r2)/(a*b),-1.,1.);
    Vector plane=crossp(r1/a,r2/b);double sine=plane.length();
    // Exactly antipodal endpoints need a separately specified transfer plane.
    if(sine<1e-10||1-cosine<1e-14)return {};
    if(dotp(plane,normal)<0)sine=-sine;
    double A=sine*sqrt(a*b/(1-cosine)),sqrtMu=sqrt(mu);
    auto time=[&](double z,double *outY=nullptr){
        double c,s;stumpff(z,c,s);if(!(c>0))return std::numeric_limits<double>::infinity();
        double y=a+b+A*(z*s-1)/sqrt(c);if(outY)*outY=y;
        if(y<0)return 0.;
        return (pow(y/c,1.5)*s+A*sqrt(y))/sqrtMu;
    };
    double lo=-4*Pi*Pi,hi=4*Pi*Pi-1e-7;
    for(int i=0;i<8&&time(lo)>seconds;++i)lo*=2;
    if(time(lo)>seconds||time(hi)<seconds)return {};
    double z=0,t=0;
    for(int i=0;i<100;++i){z=(lo+hi)*.5;t=time(z);if(!std::isfinite(t))hi=z;else if(t<seconds)lo=z;else hi=z;
        if(std::abs(t-seconds)<std::max(1e-7,seconds*2e-13))break;
    }
    double y;time(z,&y);if(!(y>0))return {};
    double f=1-y/a,g=A*sqrt(y/mu),gd=1-y/b;
    if(std::abs(g)<1e-12)return {};
    LambertSolution result{(r2-r1*f)/g,(r2*gd-r1)/g,t-seconds};
    if(!finite(result.departure)||!finite(result.arrival)||std::abs(result.residualSeconds)>std::max(.001,seconds*1e-9))return {};
    return result;
}
BodyState propagateConic(const BodyState &state,double seconds,double mu){
    if(seconds==0)return state;
    if(seconds<0){auto s=propagateConic({state.position,-state.velocity},-seconds,mu);s.velocity=-s.velocity;return s;}
    double r=state.position.length(),sqrtMu=sqrt(mu),rv=dotp(state.position,state.velocity)/sqrtMu;
    if(!(r>0&&mu>0)||!finite(state.position)||!finite(state.velocity)||!std::isfinite(seconds))throw std::runtime_error("Invalid conic state.");
    double alpha=2/r-state.velocity.length2()/mu;
    auto equation=[&](double x){double c,s,z=alpha*x*x;stumpff(z,c,s);return rv*x*x*c+(1-alpha*r)*x*x*x*s+r*x-sqrtMu*seconds;};
    double lo=0,hi=std::max(1.,sqrtMu*seconds/r);
    for(int i=0;i<100&&equation(hi)<0;++i)hi*=2;
    double x=0;
    for(int i=0;i<100;++i){x=(lo+hi)*.5;double f=equation(x);if(f<0)lo=x;else hi=x;if(hi-lo<1e-12*std::max(1.,x))break;}
    double c,s,z=alpha*x*x;stumpff(z,c,s);
    double f=1-x*x*c/r,g=seconds-x*x*x*s/sqrtMu;
    Vector p=state.position*f+state.velocity*g;double endRadius=p.length();
    Vector v=state.position*(sqrtMu*x*(z*s-1)/(r*endRadius))+state.velocity*(1-x*x*c/endRadius);
    if(!finite(p)||!finite(v))throw std::runtime_error("Conic propagation did not converge.");
    return {p,v};
}
std::optional<Vector> escapeVelocity(const Vector &position,const Vector &excess,double mu){
    double r=position.length(),w=excess.length();if(!(r>0&&w>1e-6&&mu>0))return {};
    Vector radial=position/r,S=excess/w;double c=std::clamp(dotp(radial,S),-1.,1.);
    Vector tangent=S-radial*c;double sine=tangent.length();if(sine<1e-9)return {};
    tangent/=sine;double k=mu/r,D=(1+c)*w*w+2*k;
    // Outgoing asymptote branch. Derived from e·S=-1 and v²=v∞²+2μ/r.
    double transverse=sqrt((1-c)*.5*(D+sqrt(std::max(0.,D*D-4*k*k))));
    if(transverse<1e-12)return {};
    double radialSpeed=(c*transverse*transverse+k*(1-c))/(sine*transverse);
    Vector v=radial*radialSpeed+tangent*transverse;
    if(!finite(v))return {};return v;
}
BodyId departureSystem(BodyId reference){while(reference!=BodyId::Sun&&body(reference).parent!=BodyId::Sun)reference=body(reference).parent;return reference;}
double navigationAtmosphereLimit(BodyId id){return id==BodyId::Earth?120000:body(id).atmosphereLimit;}
double defaultParkingAltitude(BodyId id){return std::max(200000.,navigationAtmosphereLimit(id)+20000);}
ParkingOrbit parkingOrbit(const Flight &f){return {f.reference,{f.position,f.velocity},f.mjd+f.elapsed/Day};}
double nominalTransferDays(BodyId origin,BodyId target,double mjd,double solarRadius){
    double a=origin==BodyId::Sun?solarRadius:bodyState(origin,mjd).position.length(),b=bodyState(target,mjd).position.length();
    return Pi*sqrt(pow((a+b)*.5,3)/body(BodyId::Sun).mu())/Day;
}
TransferPlan planTransfer(const TransferRequest &request,bool refineParking){
    if(request.target==BodyId::Sun||body(request.target).parent!=BodyId::Sun||
       (request.origin!=BodyId::Sun&&body(request.origin).parent!=BodyId::Sun)||request.origin==request.target)
        throw std::runtime_error("Choose another planet system or Vesta as the destination.");
    if(!std::isfinite(request.departureMJD+request.flightDays+request.departureAltitude+request.arrivalAltitude)||request.flightDays<=0||request.flightDays>100000)
        throw std::runtime_error("Enter a positive flight duration of at most 100000 days.");
    if(request.origin!=BodyId::Sun&&(request.departureAltitude<navigationAtmosphereLimit(request.origin)||request.departureAltitude<0))
        throw std::runtime_error("Departure parking altitude must be above the planet's atmosphere.");
    if(request.arrivalAltitude<navigationAtmosphereLimit(request.target)||request.arrivalAltitude<0)
        throw std::runtime_error("Arrival parking altitude must be above the destination's atmosphere.");
    TransferPlan plan;plan.request=request;plan.departureMJD=request.departureMJD;
    auto calculate=[&](){
        plan.arrivalMJD=plan.departureMJD+request.flightDays;
        if(request.origin==BodyId::Sun){
            if(!request.parking||request.parking->reference!=BodyId::Sun)throw std::runtime_error("Heliocentric planning needs the current spacecraft orbit.");
            plan.start=propagateConic(request.parking->state,(plan.departureMJD-request.parking->mjd)*Day,body(BodyId::Sun).mu());
        }else plan.start=bodyState(request.origin,plan.departureMJD);
        plan.end=bodyState(request.target,plan.arrivalMJD);
        auto result=solveLambert(plan.start.position,plan.end.position,request.flightDays*Day,body(BodyId::Sun).mu());
        if(!result)throw std::runtime_error("No zero-revolution transfer at these dates. Change departure or flight duration.");
        plan.trajectory=*result;plan.departureExcess=result->departure-plan.start.velocity;plan.arrivalExcess=result->arrival-plan.end.velocity;
        plan.departureDV=request.origin==BodyId::Sun?plan.departureExcess.length():excessBurn(plan.departureExcess.length(),body(request.origin).mu(),body(request.origin).radius+request.departureAltitude);
        plan.captureDV=excessBurn(plan.arrivalExcess.length(),body(request.target).mu(),body(request.target).radius+request.arrivalAltitude);
    };
    calculate();
    if(request.origin==BodyId::Sun){plan.guidedDeparture=true;plan.burnVector=plan.departureExcess;plan.burnPosition=plan.start.position;plan.burnVelocityBefore=plan.start.velocity;}
    else if(refineParking&&request.parking&&request.parking->reference==request.origin){
        const auto &parking=*request.parking;double r=parking.state.position.length();
        Vector h=crossp(parking.state.position,parking.state.velocity);
        double e=(crossp(parking.state.velocity,h)/body(request.origin).mu()-parking.state.position/r).length();
        double peri=h.length2()/(body(request.origin).mu()*(1+e));
        if(e>.25||peri<body(request.origin).radius+navigationAtmosphereLimit(request.origin))
            throw std::runtime_error("Guidance needs a parking orbit with eccentricity ≤0.25 and periapsis above the atmosphere.");
        Ejection node;
        for(int i=0;i<3;++i){node=ejection(parking,plan.departureExcess,plan.departureMJD);plan.departureMJD=parking.mjd+node.time/Day;calculate();}
        auto v=escapeVelocity(node.state.position,plan.departureExcess,body(request.origin).mu());
        if(!v)throw std::runtime_error("Cannot determine the ejection direction at this node.");
        plan.guidedDeparture=true;plan.burnVector=*v-node.state.velocity;plan.burnPosition=node.state.position;plan.burnVelocityBefore=node.state.velocity;plan.departureDV=plan.burnVector.length();
    }
    return plan;
}
BurnGuidance transferGuidance(const TransferPlan &plan,const Flight &f){
    BurnGuidance g;double now=f.mjd+f.elapsed/Day;
    if(!plan.guidedDeparture||f.reference!=plan.request.origin||f.impacted)return g;
    g.valid=true;g.secondsToBurn=(plan.departureMJD-now)*Day;g.deltaVelocity=plan.burnVector;
    // Before ignition, point at the fixed planned impulse. Around the node and
    // during the manual burn, close the remaining velocity error continuously.
    double fuel=f.mass()*(1-exp(-plan.departureDV/ExhaustVelocity));
    double estimatedBurn=fuel/(400000/ExhaustVelocity);
    if(now>plan.arrivalMJD||-g.secondsToBurn>std::max(3600.,estimatedBurn*3)){g.valid=false;return g;}
    bool atBurn=g.secondsToBurn<estimatedBurn*.5+10;
    g.live=atBurn;
    if(atBurn){
        if(f.reference==BodyId::Sun){auto desired=propagateConic({plan.start.position,plan.trajectory.departure},(now-plan.departureMJD)*Day,f.gravityMu());g.deltaVelocity=desired.velocity-f.velocity;}
        else {auto desired=escapeVelocity(f.position,plan.departureExcess,f.gravityMu());if(desired)g.deltaVelocity=*desired-f.velocity;else g.valid=false;}
    }
    double dv=g.deltaVelocity.length();g.propellant=f.mass()*(1-exp(-dv/ExhaustVelocity));g.burnSeconds=g.propellant/(400000/ExhaustVelocity);
    g.availableDV=ExhaustVelocity*log(f.mass()/(f.mass()-f.fuel));
    g.alignmentDegrees=dv>.01?acos(std::clamp(dotp(f.forward,g.deltaVelocity/dv),-1.,1.))*DEG:0;
    Vector r=atBurn?f.position:plan.burnPosition,v=atBurn?f.velocity:plan.burnVelocityBefore;
    Vector radial=r.unit(),normal=crossp(r,v).unit(),along=crossp(normal,radial).unit();
    g.prograde=dotp(g.deltaVelocity,along);g.normal=dotp(g.deltaVelocity,normal);g.radial=dotp(g.deltaVelocity,radial);
    return g;
}
void coastToDeparture(Flight &f,const TransferPlan &plan,double leadSeconds){
    if(!plan.guidedDeparture||f.reference!=plan.request.origin||f.reference==BodyId::Sun||f.impacted)
        throw std::runtime_error("Coast to departure is available in the departure planet's bound parking orbit.");
    if(f.throttle>0||f.glider.hover>0||f.glider.retro>0||f.glider.hoverControl.holdActive||f.assist==Assist::Maneuver)
        throw std::runtime_error("Cut engines with X and release maneuver alignment before coasting.");
    bool tracking=f.assist==Assist::Prograde||f.assist==Assist::Retrograde;
    if(!tracking&&f.angularVelocity.length()>1e-8)
        throw std::runtime_error("Use K to stop rotation, then release with N before coasting.");
    double now=f.mjd+f.elapsed/86400,dt=(plan.departureMJD-now)*86400-leadSeconds;
    if(!std::isfinite(leadSeconds)||leadSeconds<60||dt<=0)
        throw std::runtime_error("Departure is already close. Use normal time controls for the final approach.");
    double r=f.position.length(),alpha=2/r-f.velocity.length2()/f.gravityMu();
    Vector h=crossp(f.position,f.velocity);double e=(crossp(f.velocity,h)/f.gravityMu()-f.position/r).length();
    if(alpha<=0||e>=1)throw std::runtime_error("Coast requires a bound parking orbit.");
    double peri=(1-e)/alpha,apo=(1+e)/alpha;
    if(peri<=f.centralBody().radius+navigationAtmosphereLimit(f.reference)+100||apo>sphereOfInfluence(f.reference,now)*.25)
        throw std::runtime_error("Use normal time acceleration in atmospheric or high escape orbits.");
    for(const auto &moon:bodies())if(moon.parent==f.reference&&moon.id!=f.reference){
        double radius=relativeBodyState(moon.id,now).position.length(),soi=sphereOfInfluence(moon.id,now);
        if(peri<radius*1.25+soi&&apo>radius*.75-soi)
            throw std::runtime_error("This orbit crosses a moon's orbital region. Use normal time acceleration.");
    }
    auto state=propagateConic({f.position,f.velocity},dt,f.gravityMu());f.position=state.position;f.velocity=state.velocity;f.elapsed+=dt;f.warp=1;
    if(tracking)f.align(f.assist==Assist::Prograde?f.velocity:-f.velocity);
    f.angularVelocity={};f.glider.rcsRotation={};f.glider.rcsTranslation={};
}
void TransferSearch::begin(const TransferRequest &request,double spanDays){
    base=request;span=std::clamp(spanDays,1.,20000.);best.reset();samples.clear();cursor=done=0;stage=0;running=true;
    departureStep=span/71;durationStep=base.flightDays*1.1/19;
    for(int i=0;i<72;++i)for(int j=0;j<20;++j)samples.emplace_back(base.departureMJD+i*departureStep,base.flightDays*.55+j*durationStep);
}
double TransferSearch::progress()const{return running?std::min(.99,double(done)/(1440+81+81)):1;}
void TransferSearch::refine(){
    if(++stage>2||!best){running=false;return;}
    double date=best->departureMJD,duration=best->request.flightDays;
    samples.clear();cursor=0;departureStep*=.25;durationStep*=.25;
    for(int i=-4;i<=4;++i)for(int j=-4;j<=4;++j){double d=date+i*departureStep,t=duration+j*durationStep;
        if(d>=base.departureMJD&&d<=base.departureMJD+span&&t>0)samples.emplace_back(d,t);
    }
}
void TransferSearch::step(size_t budget){
    while(running&&budget--){if(cursor==samples.size()){refine();continue;}
        auto [date,duration]=samples[cursor++];++done;auto q=base;q.departureMJD=date;q.flightDays=duration;
        try{auto next=planTransfer(q,false);if(!best||next.totalDV()<best->totalDV())best=next;}catch(const std::exception &){}
    }
}
}

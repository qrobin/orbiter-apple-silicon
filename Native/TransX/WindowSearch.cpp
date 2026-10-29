#include "WindowSearch.h"
#include "Flight.h"
#include "SolarSystem.h"
#include "orbitelements.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace native::transx {
namespace {
constexpr double Day=86400.;
bool finite(VECTOR3 v){return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z);}
void clone(OrbitElements &out,const OrbitElements &in){
    VECTOR3 p,v;in.getcurrentvectors(&p,&v);out.init(p,v,in.gettimestamp(),in.getgmplanet());
}
void stumpff(double z,double &c,double &s){
    if(fabs(z)<1e-5){c=.5-z/24+z*z/720-z*z*z/40320;s=1./6-z/120+z*z/5040-z*z*z/362880;}
    else if(z>0){double x=sqrt(z);c=2*pow(sin(x*.5),2)/z;s=(x-sin(x))/(x*x*x);}
    else {double x=sqrt(-z);c=(cosh(x)-1)/(-z);s=(sinh(x)-x)/(x*x*x);}
}
struct Lambert {VECTOR3 departure,arrival;};
std::optional<Lambert> lambert(VECTOR3 r1,VECTOR3 r2,double seconds,double mu,VECTOR3 normal){
    double a=length(r1),b=length(r2);
    if(!(seconds>0&&mu>0&&a>0&&b>0)||!finite(r1)||!finite(r2))return {};
    double cosine=std::clamp(dotp(r1,r2)/(a*b),-1.,1.);VECTOR3 plane=crossp(r1/a,r2/b);double sine=length(plane);
    if(sine<1e-10||1-cosine<1e-14)return {};
    if(dotp(plane,normal)<0)sine=-sine;
    double A=sine*sqrt(a*b/(1-cosine)),root=sqrt(mu);
    auto time=[&](double z,double *outY=nullptr){double c,s;stumpff(z,c,s);if(!(c>0))return std::numeric_limits<double>::infinity();
        double y=a+b+A*(z*s-1)/sqrt(c);if(outY)*outY=y;if(y<0)return 0.;return (pow(y/c,1.5)*s+A*sqrt(y))/root;};
    double lo=-4*PI*PI,hi=4*PI*PI-1e-7;
    for(int i=0;i<8&&time(lo)>seconds;++i)lo*=2;
    if(time(lo)>seconds||time(hi)<seconds)return {};
    double z=0,t=0;
    for(int i=0;i<100;++i){z=(lo+hi)*.5;t=time(z);if(!std::isfinite(t))hi=z;else if(t<seconds)lo=z;else hi=z;
        if(fabs(t-seconds)<std::max(1e-7,seconds*2e-13))break;}
    double y=0;time(z,&y);if(!(y>0))return {};
    double f=1-y/a,g=A*sqrt(y/mu),gd=1-y/b;if(fabs(g)<1e-12)return {};
    Lambert result{(r2-r1*f)/g,(r2*gd-r1)/g};
    if(!finite(result.departure)||!finite(result.arrival)||fabs(t-seconds)>std::max(.001,seconds*1e-9))return {};
    return result;
}
std::optional<VECTOR3> escapeVelocity(VECTOR3 position,VECTOR3 excess,double mu){
    double r=length(position),speed=length(excess);if(!(r>0&&speed>1e-6&&mu>0))return {};
    VECTOR3 radial=position/r,direction=excess/speed;double c=std::clamp(dotp(radial,direction),-1.,1.);
    VECTOR3 tangent=direction-radial*c;double sine=length(tangent);if(sine<1e-9)return {};tangent/=sine;
    double k=mu/r,d=(1+c)*speed*speed+2*k;
    double transverse=sqrt((1-c)*.5*(d+sqrt(std::max(0.,d*d-4*k*k))));if(transverse<1e-12)return {};
    double radialSpeed=(c*transverse*transverse+k*(1-c))/(sine*transverse);
    VECTOR3 v=radial*radialSpeed+tangent*transverse;return finite(v)?std::optional<VECTOR3>(v):std::nullopt;
}
// Solve three linear equations whose columns are the response to one m/s on
// each axis. Used only to correct a Lambert seed against TransX's own conics.
std::optional<VECTOR3> solve(VECTOR3 a,VECTOR3 b,VECTOR3 c,VECTOR3 rhs){
    double determinant=dotp(a,crossp(b,c));
    if(!std::isfinite(determinant)||fabs(determinant)<1e-10)return {};
    VECTOR3 x={dotp(rhs,crossp(b,c))/determinant,dotp(a,crossp(rhs,c))/determinant,
               dotp(a,crossp(b,rhs))/determinant};
    return finite(x)?std::optional<VECTOR3>(x):std::nullopt;
}
double parkingRadius(BodyId id){const auto &b=body(id);return b.radius+std::max(200000.,b.atmosphereLimit+20000.);}
double safeOrbitRadius(BodyId id){const auto &b=body(id);return b.radius+(id==BodyId::Earth?120000.:b.atmosphereLimit);}
double captureDV(BodyId id,double speed){double r=parkingRadius(id),mu=body(id).mu();return sqrt(speed*speed+2*mu/r)-sqrt(mu/r);}
struct Candidate {double depart=0,duration=0,cost=std::numeric_limits<double>::infinity();};
}

struct WindowSearch::Impl {
    Flight flight;BodyId targetId;bool eject=false,active=true;
    OrbitElements origin,target,parking,targetOffset;
    bool haveTargetOffset=false;
    double now=0,epoch=0,span=0,nominal=0,dateStep=0,durationStep=0;
    std::vector<std::pair<double,double>> samples;
    size_t cursor=0,done=0,total=0;int pass=0;
    Candidate best;
    std::optional<WindowSolution> solution;
    std::string error;
    Impl(const Flight &f,BodyId destination,bool e,const OrbitElements &o,const OrbitElements &t):flight(f),targetId(destination),eject(e){
        if(!o.isvalid()||!t.isvalid())throw std::runtime_error("TransX does not yet have both orbits for this step.");
        clone(origin,o);clone(target,t);
        auto *offset=t.getminorbarycentricorbit();if(offset&&offset->isvalid()){clone(targetOffset,*offset);haveTargetOffset=true;}
        VECTOR3 p={f.position.x,f.position.y,f.position.z},v={f.velocity.x,f.velocity.y,f.velocity.z};
        parking.init(p,v,f.elapsed,f.gravityMu());
        if(!parking.isvalid()||parking.geteccentricity()>=1||parking.getpedistance()<=safeOrbitRadius(f.reference))
            throw std::runtime_error("Automatic search needs a bound parking orbit above the atmosphere.");
        if(origin.geteccentricity()>=1||target.geteccentricity()>=1)throw std::runtime_error("Automatic search currently needs bound TransX reference and target orbits.");
        now=f.mjd+f.elapsed/Day;epoch=f.mjd;
        double p1=origin.gettimeorbit(),p2=target.gettimeorbit(),synodic=1/fabs(1/p1-1/p2);
        span=std::clamp(synodic*1.15,Day*.25,Day*3652.5);
        VECTOR3 p1v,v1,p2v,v2;origin.getcurrentvectors(&p1v,&v1);target.getcurrentvectors(&p2v,&v2);
        nominal=PI*sqrt(pow((length(p1v)+length(p2v))*.5,3)/origin.getgmplanet());
        if(!std::isfinite(span)||!std::isfinite(nominal)||nominal<=0)throw std::runtime_error("Unable to find a finite search window for these orbits.");
        dateStep=span/63;durationStep=nominal*1.35/23;
        for(int i=0;i<64;++i)for(int j=0;j<24;++j)samples.emplace_back(now+(600+i*dateStep)/Day,nominal*.45+j*durationStep);
        total=samples.size()+2*81;
    }
    void vectors(const OrbitElements &o,double date,VECTOR3 &p,VECTOR3 &v){o.timetovectors((date-epoch)*Day-o.gettimestamp(),&p,&v);}
    void targetVectors(double date,VECTOR3 &p,VECTOR3 &v){
        vectors(target,date,p,v);
        if(haveTargetOffset){VECTOR3 q,w;vectors(targetOffset,date,q,w);if(finite(q)&&finite(w)){p+=q;v+=w;}}
    }
    Candidate evaluate(double date,double duration){
        Candidate candidate{date,duration};VECTOR3 p,v,q,w;vectors(origin,date,p,v);targetVectors(date+duration/Day,q,w);
        auto transfer=lambert(p,q,duration,origin.getgmplanet(),origin.getplanevector());if(!transfer)return candidate;
        double departure=length(transfer->departure-v),arrival=length(transfer->arrival-w);
        if(eject){double r=flight.position.length(),mu=flight.gravityMu();departure=sqrt(departure*departure+2*mu/r)-sqrt(mu/r);}
        candidate.cost=departure+captureDV(targetId,arrival);return candidate;
    }
    void refine(){
        if(!std::isfinite(best.cost)){active=false;error="No transfer found in the sampled window.";return;}
        if(++pass>2){finish();return;}
        samples.clear();cursor=0;dateStep*=.25;durationStep*=.25;
        for(int i=-4;i<=4;++i)for(int j=-4;j<=4;++j){double date=best.depart+i*dateStep/Day,duration=best.duration+j*durationStep;
            if(date>=now+600/Day&&date<=now+(600+span)/Day&&duration>0)samples.emplace_back(date,duration);}
    }
    void finish(){
        active=false;double depart=best.depart,duration=best.duration,arrival=depart+duration/Day;
        VECTOR3 p,v,q,w;vectors(origin,depart,p,v);targetVectors(arrival,q,w);
        auto transfer=lambert(p,q,duration,origin.getgmplanet(),origin.getplanevector());
        if(!transfer){error="The selected transfer could not be reconstructed.";return;}
        // Aim for a safe flyby rather than the center of the target. The
        // gravitational-focusing term converts a periapsis into an impact
        // parameter in the parent-centered patched-conic trajectory.
        VECTOR3 incoming=transfer->arrival-w,normal=unit(origin.getplanevector());
        VECTOR3 side=unit(crossp(incoming,normal));
        if(!finite(side)||length(side)<.5){error="Could not establish a safe arrival direction.";return;}
        double radius=std::max(parkingRadius(targetId),body(targetId).radius*1.2);
        double impact=radius*sqrt(1+2*body(targetId).mu()/(radius*std::max(1.,dotp(incoming,incoming))));
        q+=side*impact;
        transfer=lambert(p,q,duration,origin.getgmplanet(),origin.getplanevector());
        if(!transfer){error="Could not construct a safe arrival trajectory.";return;}
        VECTOR3 excess=transfer->departure-v,burnPosition,burnVelocity,burn;
        if(eject){
            double period=parking.gettimeorbit(),start=std::max(now+600/Day,depart-period/(2*Day));
            double bestCost=std::numeric_limits<double>::infinity(),bestDate=0;
            for(int i=0;i<=96;++i){double date=start+period*i/(96*Day);VECTOR3 pp,pv;vectors(parking,date,pp,pv);
                auto desired=escapeVelocity(pp,excess,flight.gravityMu());if(!desired)continue;
                OrbitElements escaping;escaping.init(pp,*desired,(date-epoch)*Day,flight.gravityMu());
                if(!escaping.isvalid()||escaping.geteccentricity()<=1||
                   (dotp(pp,*desired)<0&&escaping.getpedistance()<=safeOrbitRadius(flight.reference)))continue;
                double cost=length(*desired-pv);if(cost<bestCost){bestCost=cost;bestDate=date;}}
            if(!std::isfinite(bestCost)){error="No safe ejection was found from the current parking orbit.";return;}
            depart=bestDate;duration=(arrival-depart)*Day;if(duration<=0){error="The selected departure is after arrival.";return;}
            vectors(origin,depart,p,v);transfer=lambert(p,q,duration,origin.getgmplanet(),origin.getplanevector());
            if(!transfer){error="The parking-orbit departure could not be matched to the transfer.";return;}
            excess=transfer->departure-v;vectors(parking,depart,burnPosition,burnVelocity);
            auto desired=escapeVelocity(burnPosition,excess,flight.gravityMu());if(!desired){error="Could not determine the ejection maneuver.";return;}
            // TransX models a finite planetary escape before switching to the
            // parent orbit. Correct the actual local burn against that same
            // model, rather than treating the body as a point departure.
            double soi=sphereOfInfluence(flight.reference,now);
            auto predict=[&](VECTOR3 velocity,VECTOR3 &position){
                OrbitElements escaping,parent;escaping.init(burnPosition,velocity,(depart-epoch)*Day,flight.gravityMu());
                if(!escaping.isvalid()||escaping.geteccentricity()<=1||
                   (dotp(burnPosition,velocity)<0&&escaping.getpedistance()<=safeOrbitRadius(flight.reference)))return false;
                parent.minortomajorinit(escaping,origin,soi);if(!parent.isvalid())return false;
                VECTOR3 unused;vectors(parent,arrival,position,unused);return finite(position);
            };
            VECTOR3 velocity=*desired,position;
            for(int i=0;i<14;++i){
                if(!predict(velocity,position)){error="Could not propagate the escape trajectory.";return;}
                VECTOR3 residual=q-position;if(length(residual)<10000)break;
                VECTOR3 a,b,c;
                if(!predict(velocity+_V(1,0,0),a)||!predict(velocity+_V(0,1,0),b)||!predict(velocity+_V(0,0,1),c)){
                    error="Could not refine the escape trajectory.";return;
                }
                auto delta=solve(a-position,b-position,c-position,residual);
                if(!delta||length(*delta)>3000){error="The escape correction did not converge.";return;}
                velocity+=*delta;
            }
            if(!predict(velocity,position)||length(q-position)>50000){error="The escape correction did not converge.";return;}
            burn=velocity-burnVelocity;
            OrbitElements escaping;escaping.init(burnPosition,velocity,(depart-epoch)*Day,flight.gravityMu());
            escaping.getinfinityvelvector(true,&excess);
        }else{vectors(parking,depart,burnPosition,burnVelocity);burn=transfer->departure-burnVelocity;}
        VECTOR3 plane=unit(parking.getplanevector()),forward=unit(burnVelocity),outward=unit(crossp(burnVelocity,plane));
        if(!finite(plane)||!finite(forward)||!finite(outward)||length(plane)<.5||length(outward)<.5){error="The parking orbit has no stable maneuver frame.";return;}
        WindowSolution result;result.arrivalMJD=arrival;result.hasTransfer=eject;
        result.burn={depart,dotp(burn,forward),dotp(burn,outward),dotp(burn,plane)};
        result.departureDV=length(burn);result.captureDV=captureDV(targetId,length(transfer->arrival-w));
        if(eject){VECTOR3 normal=unit(origin.getplanevector()),prograde=unit(v),out=unit(crossp(v,normal));
            result.transfer={depart,dotp(excess,prograde),dotp(excess,out),dotp(excess,normal)};}
        solution=result;
    }
};
WindowSearch::WindowSearch(const Flight &f,BodyId target,bool eject,const OrbitElements &o,const OrbitElements &t):impl(std::make_unique<Impl>(f,target,eject,o,t)){}
WindowSearch::~WindowSearch()=default;
void WindowSearch::step(size_t budget){while(impl->active&&budget--){
    if(impl->cursor==impl->samples.size()){impl->refine();continue;}
    auto [date,duration]=impl->samples[impl->cursor++];++impl->done;auto c=impl->evaluate(date,duration);
    if(c.cost<impl->best.cost)impl->best=c;
}}
bool WindowSearch::running() const{return impl->active;}
double WindowSearch::progress()const{return impl->active?std::min(.99,double(impl->done)/std::max<size_t>(1,impl->total)):1.;}
const std::optional<WindowSolution> &WindowSearch::result()const{return impl->solution;}
const std::string &WindowSearch::error()const{return impl->error;}
}

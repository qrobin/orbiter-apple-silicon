// Thruster configuration from Src/Vessel/DeltaGlider/DeltaGlider.cpp (MIT).
// Main visual exits are measured from the original deltaglider_ns.msh nozzle lips.
#include "Exhaust.h"
#include "Aerodynamics.h"
#include "SolarSystem.h"
#include <algorithm>
#include <cmath>
namespace native {
std::vector<ExhaustEmitter> gliderExhaust(const Flight &f) {
    const auto &g=f.glider;std::vector<ExhaustEmitter> out;out.reserve(31);
    unsigned id=0;
    auto emit=[&](Vector p,Vector d,double level,double radius,ExhaustKind kind){
        unsigned nozzle=id++;level=std::clamp(level,0.,1.);if(level>1e-6)out.push_back({p,d.unit(),level,radius,kind,nozzle});
    };
    // Force is applied at z=-7.7; the exterior mesh nozzle lips end at z=-8.043.
    Vector main(-g.gimbalYaw/7.7,-tan(5*RAD)*g.gimbalPitch,-1);
    emit({-1,0,-8.043},main,g.mainLevel*std::clamp(1-g.mainBalance,0.,1.),.55,ExhaustKind::Main);
    emit({1,0,-8.043},main,g.mainLevel*std::clamp(1+g.mainBalance,0.,1.),.55,ExhaustKind::Main);
    for(double x:{-3.,3.})emit({x,-.236,5.6},{0,-.04210548,.99911317},g.retroLevel,.22,ExhaustKind::Retro);
    const auto &h=g.hoverControl.levels;
    emit({0,-1.5,3},{0,-1,0},h[0],.45,ExhaustKind::Hover);
    emit({-3,-1.3,-4.55},{0,-1,0},h[1],.35,ExhaustKind::Hover);
    emit({3,-1.3,-4.55},{0,-1,0},h[2],.35,ExhaustKind::Hover);
    if(g.rcsMode==0&&f.assist==Assist::Free)return out;
    // Mix the already fuel-scaled force and torque commands at the original visual nozzles.
    auto jet=[&](Vector p,Vector d,double command){emit(p,d,command,.078,ExhaustKind::Rcs);};
    const auto &r=g.rcsRotation;const auto &t=g.rcsTranslation;
    // Positive pitch torque: front down force and rear up force.
    for(double x:{-.816081,.816081}) {
        jet({x,-.35857,9.594813},{0,1,0},r.x-t.y);
        jet({x,-.616431,9.594813},{0,-1,0},-r.x+t.y);
    }
    for(double x:{-.120063,.120063}) {
        jet({x,.409999,-7.357354},{0,1,0},-r.x-t.y);
        jet({x,-.409999,-7.357354},{0,-1,0},r.x+t.y);
    }
    jet({.888971,-.488177,9.3408},{1,0,0},-r.y-t.x);
    jet({-2.029295,.182903,-6.043046},{-1,0,0},-r.y+t.x);
    jet({-.888971,-.488177,9.3408},{-1,0,0},r.y+t.x);
    jet({2.029295,.182903,-6.043046},{1,0,0},r.y-t.x);
    jet({-5.121185,-.073903,.375386},{0,1,0},r.z);
    jet({5.121185,-.654322,.375386},{0,-1,0},r.z);
    jet({5.121185,-.073903,.375386},{0,1,0},-r.z);
    jet({-5.121185,-.654322,.375386},{0,-1,0},-r.z);
    for(double y:{-.228914,.229})jet({0,y,-7.462329},{0,0,-1},t.z);
    for(double x:{-.817096,.817096})jet({x,-.488177,9.729635},{0,0,1},-t.z);
    return out;
}
static PlumeShape pressureShape(double pressure,ExhaustKind kind) {
    const double air=pow(std::clamp(pressure/101325.,0.,1.),.25);
    if(kind==ExhaustKind::Rcs)return {55, .035, .10+(1-air)*.3};
    return {260+(1-air)*300, .085+(1-air)*.035, .035+(1-air)*.10};
}
PlumeShape plumeShape(double altitude,ExhaustKind kind){return pressureShape(earthAtmosphere(altitude).p,kind);}
PlumeShape plumeShape(const Flight &f,ExhaustKind kind){return pressureShape(bodyAtmosphere(f.reference,f.altitude()).p,kind);}
ExhaustCameraFrame::ExhaustCameraFrame(const Flight &f,const Vector &offset)
    :reference(f.reference),date(f.mjd+f.elapsed/86400),camera(f.position+offset){}
bool ExhaustCameraFrame::relative(BodyId id,const Vector &point,Vector &result){
    if((size_t)id>=BodyCount)return false;
    Vector center;
    if(id!=reference){
        if(!ephemeridesReady())return false;
        size_t index=(size_t)id;
        if(!cached[index]){
            if(!haveReferenceCenter){referenceCenter=bodyState(reference,date).position;haveReferenceCenter=true;}
            centers[index]=bodyState(id,date).position-referenceCenter;cached[index]=true;
        }
        center=centers[index];
    }
    result=center+point-camera;return true;
}

static Vector atmosphericVelocity(BodyId id,const Vector &position,const Vector &earthWind,bool rotating){
    struct AirFrame{Vector pole,spin,equatorZ;double radius;};
    static const auto frames=[](){std::array<AirFrame,BodyCount> result{};for(const auto &b:bodies())result[(size_t)b.id]={b.pole(),b.period?b.pole()*(Pi2/b.period):Vector(),b.equatorZ(),b.radius};return result;}();
    const auto &b=frames[(size_t)id];Vector spin=rotating?b.spin:Vector();
    if(id==BodyId::Earth)return crossp(spin,position)+earthWind;
    Vector radial=position.unit(),east=crossp(b.pole,radial);
    if(east.length2()<1e-12)east=b.equatorZ;else east.unify();
    Vector north=crossp(radial,east).unit();
    // A modest prevailing wind with altitude-dependent shear.
    double altitude=std::max(0.,position.length()-b.radius);
    return crossp(spin,position)+east*(7+4*sqrt(std::min(altitude,50000.)/10000))+north*(3+2*sin(altitude/6500));
}
static void advect(ExhaustTrailPuff &p,double dt,const Vector &earthWind,bool rotating){
    if(dt<=0)return;
    if(p.age+dt>=p.lifetime){p.age=p.lifetime;return;}
    const auto &b=body(p.body);
    if(p.vacuum){
        double r=p.position.length();Vector gravity=p.position*(-b.mu()/(r*r*r));
        p.position+=p.velocity*dt+gravity*(dt*dt*.5);p.velocity+=gravity*dt;p.age+=dt;return;
    }
    Vector radial=p.position.unit();
    Vector air=atmosphericVelocity(p.body,p.position,earthWind,rotating)+radial*(2.5*exp(-p.age/15));
    // Hot exhaust rapidly mixes into ambient air, then drifts with the atmosphere.
    double damping=exp(-2*dt);Vector relative=p.velocity-air;
    p.position+=air*dt+relative*((1-damping)*.5);
    p.velocity=air+relative*damping;p.age+=dt;
    if(b.solid&&p.position.length()<b.radius+.5){
        Vector radial=p.position.unit();p.position=radial*(b.radius+.5);
        double down=dotp(p.velocity,radial);if(down<0)p.velocity-=radial*down;
    }
}
double exhaustTrailRadius(const ExhaustTrailPuff &p){
    double age=std::max(0.,p.age);
    return p.radius+(p.vacuum?age*130:sqrt(age)*2.4+age*.28);
}
double exhaustTrailOpacity(const ExhaustTrailPuff &p){
    double age=std::clamp(p.age/p.lifetime,0.,1.),growth=exhaustTrailRadius(p);
    double dilution=p.vacuum?sqrt(p.radius/growth)/sqrt(1+p.age*.03):.65+.35*sqrt(p.radius/growth);
    return p.opacity*pow(1-age,1.35)*dilution;
}
void ExhaustTrail::reset(){particles.clear();history={};haveBody=false;nextStream=0;}
void ExhaustTrail::update(const Flight &f,double dt,double humidity){
    if(!std::isfinite(dt)||dt<=0)return;
    humidity=std::isfinite(humidity)?std::clamp(humidity,0.,1.):.5;
    Vector earthWind=f.reference==BodyId::Earth?f.currentWeather().wind:Vector();
    bool rotating=!bodyRotationsPaused();
    for(auto &p:particles)advect(p,dt,earthWind,rotating);
    particles.erase(std::remove_if(particles.begin(),particles.end(),[](const auto &p){return p.age>=p.lifetime;}),particles.end());
    if(!haveBody||previousBody!=f.reference){history={};previousBody=f.reference;haveBody=true;}
    auto atmosphere=bodyAtmosphere(f.reference,f.altitude());
    double pressure=std::max(0.,atmosphere.p)/101325.;
    // Original DG contrails are atmosphere-dependent; vacuum has no smoke trail.
    double ambient=pressure>1e-4?std::clamp((log10(pressure)+4)/3,0.,1.):0;
    double rarefied=pressure<=1e-4?1:pressure>=1e-3?0:1-(log10(pressure)+4);
    std::array<bool,32> active{};
    auto world=[&](const Vector &v){return f.right*v.x+f.up*v.y+f.forward*v.z;};
    for(const auto &jet:gliderExhaust(f)){
        if(jet.id>=history.size())continue;
        active[jet.id]=true;auto &h=history[jet.id];Vector offset=world(jet.position),position=f.position+offset,direction=world(jet.direction);
        // Released gas retains the nozzle's instantaneous inertial velocity,
        // including the motion of an off-centre nozzle on a rotating vessel.
        Vector nozzleVelocity=f.velocity+crossp(world(f.angularVelocity),offset);
        if(!h.active){h.position=position;h.direction=direction;h.velocity=nozzleVelocity;h.remainder=0;h.active=true;}
        bool medium[2]={ambient>0,rarefied>0};
        for(int i=0;i<2;++i){if(medium[i]&&!h.mediumActive[i]){h.stream[i]=++nextStream;h.sequence[i]=0;}h.mediumActive[i]=medium[i];}
        double interval=jet.kind==ExhaustKind::Rcs?.30:.15;
        double pending=h.remainder+dt;int emitted=0;
        while(pending>=interval&&emitted<256){
            pending-=interval;++emitted;double fraction=std::clamp((dt-pending)/dt,0.,1.);
            Vector origin=h.position+(position-h.position)*fraction;
            Vector firingDirection=h.direction+(direction-h.direction)*fraction;
            if(firingDirection.length2()<1e-12)firingDirection=direction;else firingDirection.unify();
            Vector firingVelocity=h.velocity+(nozzleVelocity-h.velocity)*fraction;
            auto append=[&](bool vacuum,double weight){
                double exhaustSpeed=vacuum?(jet.kind==ExhaustKind::Rcs?900:1600):(jet.kind==ExhaustKind::Rcs?40:120);
                double life=vacuum?(jet.kind==ExhaustKind::Rcs?8:24):(jet.kind==ExhaustKind::Rcs?35:jet.kind==ExhaustKind::Main?240:180)*(.7+.6*humidity);
                double opacity=weight*(vacuum?sqrt(jet.level)*(jet.kind==ExhaustKind::Rcs?.025:.12):ambient*(.72+.28*humidity)*(jet.kind==ExhaustKind::Rcs?.12:.78)*sqrt(jet.level));
                int mediumIndex=vacuum?1:0;
                ExhaustTrailPuff puff{f.reference,origin,firingVelocity+firingDirection*exhaustSpeed,0,life,jet.radius,opacity,h.stream[mediumIndex],h.sequence[mediumIndex]++,jet.id,vacuum};
                advect(puff,pending,earthWind,rotating);if(puff.age<puff.lifetime)particles.push_back(puff);
            };
            if(ambient>0)append(false,1);
            if(rarefied>0)append(true,rarefied);
        }
        h.position=position;h.direction=direction;h.velocity=nozzleVelocity;h.remainder=std::fmod(pending,interval);
    }
    for(size_t i=0;i<history.size();++i)if(!active[i])history[i]={};
    if(particles.size()>capacity)particles.erase(particles.begin(),particles.begin()+(particles.size()-capacity));
}
std::vector<ExhaustTrailSegment> ExhaustTrail::segments(const Flight &f)const{
    std::vector<ExhaustTrailSegment> result;result.reserve(particles.size()+64);
    std::array<const ExhaustTrailPuff*,64> last{};
    auto point=[](const ExhaustTrailPuff &p){return ExhaustTrailPoint{p.position,exhaustTrailRadius(p),exhaustTrailOpacity(p),p.age};};
    for(const auto &p:particles){
        size_t index=p.nozzle*2+(p.vacuum?1:0);if(index>=last.size())continue;
        auto prior=last[index];
        if(prior&&prior->stream==p.stream&&prior->sequence+1==p.sequence&&prior->body==p.body&&prior->position.dist(p.position)>.001)
            result.push_back({p.body,point(*prior),point(p),p.stream,p.nozzle,p.vacuum});
        last[index]=&p;
    }
    for(const auto &jet:gliderExhaust(f))if(jet.id<history.size()){
        const auto &h=history[jet.id];if(!h.active)continue;
        for(int medium=0;medium<2;++medium){
            auto p=last[jet.id*2+medium];if(!p||!h.mediumActive[medium]||p->stream!=h.stream[medium]||p->sequence+1!=h.sequence[medium]||p->body!=f.reference||p->position.dist(h.position)<=.001)continue;
            result.push_back({p->body,point(*p),{h.position,jet.radius,p->opacity,0},p->stream,p->nozzle,p->vacuum});
        }
    }
    return result;
}

}

// Thruster configuration from Src/Vessel/DeltaGlider/DeltaGlider.cpp (MIT).
// Main visual exits are measured from the original deltaglider_ns.msh nozzle lips.
#include "Exhaust.h"
#include "Aerodynamics.h"
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

static Vector atmosphericVelocity(BodyId id,const Vector &position){
    struct AirFrame{Vector pole,spin,equatorZ;double radius;};
    static const auto frames=[](){std::array<AirFrame,BodyCount> result{};for(const auto &b:bodies())result[(size_t)b.id]={b.pole(),b.spin(),b.equatorZ(),b.radius};return result;}();
    const auto &b=frames[(size_t)id];Vector radial=position.unit(),east=crossp(b.pole,radial);
    if(east.length2()<1e-12)east=b.equatorZ;else east.unify();
    Vector north=crossp(radial,east).unit();
    // A modest prevailing wind with altitude-dependent shear.
    double altitude=std::max(0.,position.length()-b.radius);
    return crossp(b.spin,position)+east*(7+4*sqrt(std::min(altitude,50000.)/10000))+north*(3+2*sin(altitude/6500));
}
static void advect(ExhaustTrailPuff &p,double dt){
    if(dt<=0)return;
    if(p.age+dt>=p.lifetime){p.age=p.lifetime;return;}
    const auto &b=body(p.body);
    if(p.vacuum){
        double r=p.position.length();Vector gravity=p.position*(-b.mu()/(r*r*r));
        p.position+=p.velocity*dt+gravity*(dt*dt*.5);p.velocity+=gravity*dt;p.age+=dt;return;
    }
    Vector air=atmosphericVelocity(p.body,p.position)+p.position.unit()*(2.5*exp(-p.age/15));
    // Hot exhaust rapidly mixes into ambient air, then drifts with the atmosphere.
    double damping=exp(-2*dt);Vector relative=p.velocity-air;
    p.position+=air*dt+relative*((1-damping)*.5);
    p.velocity=air+relative*damping;p.age+=dt;
    if(b.solid&&p.position.length()<b.radius+.5){
        Vector radial=p.position.unit();p.position=radial*(b.radius+.5);
        double down=dotp(p.velocity,radial);if(down<0)p.velocity-=radial*down;
    }
}
void ExhaustTrail::reset(){particles.clear();history={};haveBody=false;serial=0;}
void ExhaustTrail::update(const Flight &f,double dt,double humidity){
    if(!std::isfinite(dt)||dt<=0)return;
    humidity=std::isfinite(humidity)?std::clamp(humidity,0.,1.):.5;
    for(auto &p:particles)advect(p,dt);
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
        active[jet.id]=true;auto &h=history[jet.id];Vector position=f.position+world(jet.position),direction=world(jet.direction);
        if(!h.active){h.position=position;h.remainder=0;h.active=true;}
        double interval=jet.kind==ExhaustKind::Rcs?.30:.15;
        double pending=h.remainder+dt;int emitted=0;
        while(pending>=interval&&emitted<256){
            pending-=interval;++emitted;double fraction=std::clamp((dt-pending)/dt,0.,1.);
            Vector origin=h.position+(position-h.position)*fraction;
            auto append=[&](bool vacuum,double weight){
                Vector air=vacuum?Vector{}:atmosphericVelocity(f.reference,origin),motion=f.velocity-air;
                double exhaustSpeed=vacuum?(jet.kind==ExhaustKind::Rcs?900:1600):(jet.kind==ExhaustKind::Rcs?40:120);
                Vector axis=vacuum?direction:motion.length2()>1?motion.unit():direction;
                uint32_t hash=++serial*747796405u+2891336453u;hash=((hash>>((hash>>28u)+4u))^hash)*277803737u;hash=(hash>>22u)^hash;
                double seed=(hash&0xffffffu)/16777215.;
                Vector base=crossp(direction,fabs(direction.y)<.9?Vector(0,1,0):Vector(1,0,0)).unit();
                Vector lateral=base*cos(seed*Pi2)+crossp(direction,base)*sin(seed*Pi2);
                Vector birth=origin+lateral*(jet.radius*.35*seed);
                double life=vacuum?(jet.kind==ExhaustKind::Rcs?8:24):(jet.kind==ExhaustKind::Rcs?35:jet.kind==ExhaustKind::Main?240:180)*(.7+.6*humidity);
                double size=jet.radius*(jet.kind==ExhaustKind::Rcs?1.8:3.5)+.4;
                double opacity=weight*(vacuum?sqrt(jet.level)*(jet.kind==ExhaustKind::Rcs?.025:.065):ambient*(.55+.45*humidity)*sqrt(jet.level)*(jet.kind==ExhaustKind::Rcs?.08:.22));
                double halfLength=std::max(size,(vacuum?exhaustSpeed:motion.length())*interval*.65+size);
                ExhaustTrailPuff puff{f.reference,birth,f.velocity+direction*exhaustSpeed+lateral*(vacuum?30:10),axis,0,life,size,opacity,halfLength,seed,vacuum};
                advect(puff,pending);if(puff.age<puff.lifetime)particles.push_back(puff);
            };
            if(ambient>0)append(false,1);
            if(rarefied>0)append(true,rarefied);
        }
        h.position=position;h.remainder=std::fmod(pending,interval);
    }
    for(size_t i=0;i<history.size();++i)if(!active[i])history[i]={};
    if(particles.size()>capacity)particles.erase(particles.begin(),particles.begin()+(particles.size()-capacity));
}

}

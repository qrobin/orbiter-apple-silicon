// Nozzle locations from Src/Vessel/DeltaGlider/DeltaGlider.cpp (MIT).
#include "Exhaust.h"
#include "Aerodynamics.h"
#include <algorithm>
namespace native {
std::vector<ExhaustEmitter> gliderExhaust(const Flight &f) {
    const auto &g=f.glider;std::vector<ExhaustEmitter> out;out.reserve(31);
    auto emit=[&](Vector p,Vector d,double level,double radius,ExhaustKind kind){
        level=std::clamp(level,0.,1.);if(level>1e-6)out.push_back({p,d.unit(),level,radius,kind});
    };
    Vector main(-g.gimbalYaw/7.7,-tan(5*RAD)*g.gimbalPitch,-1);
    emit({-1,0,-7.7},main,g.mainLevel*std::clamp(1-g.mainBalance,0.,1.),.55,ExhaustKind::Main);
    emit({1,0,-7.7},main,g.mainLevel*std::clamp(1+g.mainBalance,0.,1.),.55,ExhaustKind::Main);
    for(double x:{-3.,3.})emit({x,-.236,5.6},{0,-.04210548,.99911317},g.retroLevel,.22,ExhaustKind::Retro);
    const auto &h=g.hoverControl.levels;
    emit({0,-1.5,3},{0,-1,0},h[0],.45,ExhaustKind::Hover);
    emit({-3,-1.3,-4.55},{0,-1,0},h[1],.35,ExhaustKind::Hover);
    emit({3,-1.3,-4.55},{0,-1,0},h[2],.35,ExhaustKind::Hover);
    if(g.rcsMode==0)return out;
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
PlumeShape plumeShape(double altitude,ExhaustKind kind) {
    const double air=pow(std::clamp(earthAtmosphere(altitude).p/101325.,0.,1.),.25);
    if(kind==ExhaustKind::Rcs)return {55, .035, .10+(1-air)*.3};
    return {260+(1-air)*300, .085+(1-air)*.035, .035+(1-air)*.10};
}
}

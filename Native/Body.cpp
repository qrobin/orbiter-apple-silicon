#include "Body.h"
#include <algorithm>
#include <cctype>
#include <cmath>
#include <stdexcept>
namespace native {
namespace {
bool rotationsPaused=false;
double rotationOffset=0,frozenRotationDate=0;
}
bool bodyRotationsPaused(){return rotationsPaused;}
BodyRotationState bodyRotationState(){return {rotationsPaused,rotationOffset,frozenRotationDate};}
bool restoreBodyRotationState(const BodyRotationState &state){
    if(!std::isfinite(state.offset)||!std::isfinite(state.frozenDate)||fabs(state.offset)>1e9||fabs(state.frozenDate)>1e9)return false;
    rotationsPaused=state.paused;rotationOffset=state.offset;frozenRotationDate=state.frozenDate;return true;
}
void setBodyRotationsPaused(bool paused,double mjd){
    if(!std::isfinite(mjd)||paused==rotationsPaused)return;
    if(paused)frozenRotationDate=mjd-rotationOffset;
    else rotationOffset=mjd-frozenRotationDate;
    rotationsPaused=paused;
}
const std::array<CelestialBody,BodyCount> &bodies(){static const std::array<CelestialBody,BodyCount> all={{
#include "SolarCatalogue.inc"
}};return all;}
const CelestialBody &body(BodyId id){if((size_t)id>=BodyCount)throw std::out_of_range("Unknown celestial body");return bodies()[(size_t)id];}
BodyId findBody(std::string_view name){std::string key(name);std::transform(key.begin(),key.end(),key.begin(),[](unsigned char c){return std::tolower(c);});if(key=="luna")key="moon";for(auto &b:bodies()){std::string n=b.name;std::transform(n.begin(),n.end(),n.begin(),[](unsigned char c){return std::tolower(c);});if(n==key)return b.id;}throw std::invalid_argument("Unknown planet or moon: "+std::string(name));}
Vector CelestialBody::pole()const{return {-sin(node)*sin(obliquity),cos(obliquity),cos(node)*sin(obliquity)};}
Vector CelestialBody::equatorX()const{return {cos(node),0,sin(node)};}
Vector CelestialBody::equatorZ()const{return crossp(equatorX(),pole()).unit();}
Vector CelestialBody::spin()const{return period&&!rotationsPaused?pole()*(Pi2/period):Vector(0,0,0);}
double CelestialBody::rotation(double mjd)const{
    if(!period)return offset;
    double date=rotationsPaused?frozenRotationDate:mjd-rotationOffset;
    return remainder(offset+(date-51544.5)*86400*Pi2/period,Pi2);
}
Atmosphere bodyAtmosphere(BodyId id,double altitude){
    if(id==BodyId::Earth)return earthAtmosphere(altitude);
    auto &b=body(id);if(b.pressure<.01||b.density<=0||altitude>=b.atmosphereLimit)return {};
    double gravity=b.mu()/(b.radius*b.radius),height=b.pressure/(b.density*gravity);
    double scale=exp(-std::max(0.,altitude)/height);
    // Hydrostatic isothermal approximation for non-Earth atmospheres.
    double fade=std::clamp((b.atmosphereLimit-altitude)/std::max(1.,height),0.,1.);
    return {b.pressure/(b.density*b.gasConstant),b.pressure*scale*fade,b.density*scale*fade};
}
}

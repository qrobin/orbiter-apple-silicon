#pragma once
#include "Vecmat.h"
#include "Astro.h"
#include "Aerodynamics.h"
#include <array>
#include <string_view>
namespace native {
constexpr double EarthMass=5.973698968e24,EarthRadius=6.37101e6;
inline const double Mu=Ggrav*EarthMass;
enum class BodyId { Sun,Mercury,Venus,Earth,Moon,Mars,Phobos,Deimos,Vesta,Jupiter,Io,Europa,Ganymede,Callisto,Saturn,Mimas,Enceladus,Tethys,Dione,Rhea,Titan,Hyperion,Iapetus,Uranus,Miranda,Ariel,Umbriel,Titania,Oberon,Neptune,Triton,Proteus,Nereid,Count };
constexpr size_t BodyCount=(size_t)BodyId::Count;
struct CelestialBody {
    BodyId id,parent;const char *name,*texture;
    double mass,radius,period,offset,obliquity,node;
    double pressure,density,gasConstant,gamma,atmosphereLimit;
    Vector color;bool solid;
    std::array<double,7> elements; // a,e,i,node,longitude of periapsis,mean longitude,epoch MJD
    double mu()const{return Ggrav*mass;}
    Vector pole()const;
    Vector equatorX()const;
    Vector equatorZ()const;
    Vector spin()const;
    double rotation(double mjd)const;
};
// Freeze axial rotation at the current simulation date without pausing orbits.
struct BodyRotationState {bool paused=false;double offset=0,frozenDate=0;};
bool bodyRotationsPaused();
BodyRotationState bodyRotationState();
bool restoreBodyRotationState(const BodyRotationState &state);
void setBodyRotationsPaused(bool paused,double mjd);
const std::array<CelestialBody,BodyCount> &bodies();
const CelestialBody &body(BodyId id);
BodyId findBody(std::string_view name);
Atmosphere bodyAtmosphere(BodyId id,double altitude);
}

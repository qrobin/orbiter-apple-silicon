#pragma once
#include "Vecmat.h"
#include "Body.h"
#include <array>
#include <filesystem>
namespace native {
constexpr double SiderealDay=86164.10132;
constexpr double GearClearance=2.57;
struct SurfaceFrame { Vector up,north,east; };
Vector earthSpin();
SurfaceFrame bodySurface(BodyId body,double latitude,double longitude,double mjd,double elapsed=0);
void bodyCoordinates(BodyId body,const Vector &position,double mjd,double elapsed,double &latitude,double &longitude);
SurfaceFrame earthSurface(double latitude,double longitude,double mjd,double elapsed=0);
void earthCoordinates(const Vector &position,double mjd,double elapsed,double &latitude,double &longitude);
bool loadTerrainMask(const std::filesystem::path &path);
bool surfaceWater(BodyId body,const Vector &position,double mjd,double elapsed=0);
double terrainElevation(BodyId body,const Vector &position,double mjd,double elapsed=0);
Vector terrainNormal(BodyId body,const Vector &position,double mjd,double elapsed=0);
struct ContactPoint { Vector position; double stiffness,damping,lateralFriction; bool wheel; int wheelIndex; };
const std::array<ContactPoint,13> &gliderContacts(bool gearDown);
struct GroundResponse { Vector force,torque; int contacts=0,wheels=0; double maximumClosingSpeed=0,load=0; };
GroundResponse groundForces(const Vector &position,const Vector &velocity,
    const Vector &right,const Vector &up,const Vector &forward,const Vector &angularVelocity,
    double mass,bool gearDown,double steering,double leftBrake,double rightBrake,double dt,BodyId body=BodyId::Earth,double mjd=0,double elapsed=0);
GroundResponse waterForces(const Vector &position,const Vector &velocity,
    const Vector &right,const Vector &up,const Vector &forward,const Vector &angularVelocity,
    double mass,double dt);
}

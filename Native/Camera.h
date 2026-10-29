#pragma once
#include "Flight.h"
namespace native {
constexpr double MaxExternalCameraDistance=1000000.;
enum class ExternalCameraMode { OrbitalChase, TargetRelative, AbsoluteDirection, GlobalFrame, TargetTo, TargetFrom, GroundObserver };
const char *externalCameraModeName(ExternalCameraMode mode);
struct CameraPose { Vector offset,up; };
// The first three tracking frames and object/ground views follow Orbiter's external camera.
struct OrbitCamera {
    double yaw=25*RAD,pitch=17*RAD,distance=43;
    ExternalCameraMode mode=ExternalCameraMode::OrbitalChase;
    BodyId target=BodyId::Earth,groundBody=BodyId::Earth;
    double groundLatitude=0,groundLongitude=0,groundHeight=2,groundFov=50*RAD;
    void drag(double horizontalPoints,double verticalPoints);
    void zoom(double scrollPoints);
    Vector offset(const Flight &flight) const;
    CameraPose pose(const Flight &flight) const;
    bool setMode(ExternalCameraMode next,const Flight &flight,BodyId reference=BodyId::Earth);
    double tanHalfFov()const;
};
// A camera detached from the vessel, with no collision constraints.
struct FreeCamera {
    bool active=false;
    int returnView=0;
    BodyId reference=BodyId::Earth;
    Vector position,baseForward{0,0,1},baseRight{1,0,0},baseUp{0,1,0};
    double yaw=0,pitch=0,speed=250;
    void enter(BodyId body,const Vector &eye,const Vector &direction,const Vector &up);
    Vector direction() const;
    Vector right() const;
    Vector up() const;
    void drag(double horizontalPoints,double verticalPoints);
    void move(double side,double vertical,double forward,double realSeconds);
    void adjustSpeed(double scrollPoints);
    void changeReference(BodyId body,double mjd);
};
// Cockpit zoom changes the field of view, not the position of the pilot's eye.
struct CockpitCamera {
    double fov=50*RAD;
    void zoom(double scrollPoints);
    // Keep the line of sight under the cursor fixed while changing FOV.
    void zoomAt(double scrollPoints,double normalizedX,double normalizedY,double aspect,double &yaw,double &pitch);
    double tanHalfFov() const;
    Vector ray(double yaw,double pitch,double normalizedX,double normalizedY,double aspect) const;
};
}

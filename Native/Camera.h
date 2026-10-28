#pragma once
#include "Flight.h"
namespace native {
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
// Cockpit zoom changes the field of view, not the position of the pilot's eye.
struct CockpitCamera {
    double fov=50*RAD;
    void zoom(double scrollPoints);
    double tanHalfFov() const;
    Vector ray(double yaw,double pitch,double normalizedX,double normalizedY,double aspect) const;
};
}

#include "Camera.h"
#include "Surface.h"
#include "SolarSystem.h"
#include <algorithm>
#include <cmath>
namespace native {
const char *externalCameraModeName(ExternalCameraMode mode){
    switch(mode){
    case ExternalCameraMode::OrbitalChase:return "Orbital chase";
    case ExternalCameraMode::TargetRelative:return "Target-relative";
    case ExternalCameraMode::AbsoluteDirection:return "Absolute direction";
    case ExternalCameraMode::GlobalFrame:return "Global frame";
    case ExternalCameraMode::TargetTo:return "Target to";
    case ExternalCameraMode::TargetFrom:return "Target from";
    case ExternalCameraMode::GroundObserver:return "Ground observer";
    }
    return "Orbital chase";
}
static Vector safeUp(const Vector &offset,Vector preferred,Vector fallback){
    Vector axis=offset.unit();preferred-=axis*dotp(preferred,axis);
    if(preferred.length2()<1e-12)preferred=fallback-axis*dotp(fallback,axis);
    if(preferred.length2()<1e-12){fallback=fabs(axis.y)<.9?Vector(0,1,0):Vector(1,0,0);preferred=fallback-axis*dotp(fallback,axis);}
    return preferred.unit();
}
static void orbitalBasis(const Flight &flight,Vector &radial,Vector &tangent,Vector &lateral){
    radial=flight.position.unit();Vector direction=flight.altitude()<10000?flight.forward:flight.velocity;
    tangent=direction-radial*dotp(direction,radial);
    if(tangent.length2()<1e-12){double latitude,longitude;bodyCoordinates(flight.reference,flight.position,flight.mjd,flight.elapsed,latitude,longitude);tangent=bodySurface(flight.reference,latitude,longitude,flight.mjd,flight.elapsed).north;}
    tangent.unify();lateral=crossp(radial,tangent).unit();
}
static Vector pointInFrame(const Vector &right,const Vector &up,const Vector &forward,double yaw,double pitch){
    return -forward*(cos(yaw)*cos(pitch))+right*(sin(yaw)*cos(pitch))+up*sin(pitch);
}
static Vector upwardInFrame(const Vector &right,const Vector &up,const Vector &forward,double yaw,double pitch){
    return (forward*cos(yaw)-right*sin(yaw))*sin(pitch)+up*cos(pitch);
}
static Vector bodyRelativeToVessel(BodyId id,const Flight &flight){
    if(id==flight.reference)return -flight.position;
    if(!ephemeridesReady())return {};
    double date=flight.mjd+flight.elapsed/86400;
    return bodyState(id,date).position-bodyState(flight.reference,date).position-flight.position;
}
void OrbitCamera::drag(double horizontalPoints,double verticalPoints){
    if(!std::isfinite(horizontalPoints)||!std::isfinite(verticalPoints))return;
    if(mode==ExternalCameraMode::TargetTo||mode==ExternalCameraMode::TargetFrom)return;
    if(mode==ExternalCameraMode::GroundObserver){
        double radius=body(groundBody).radius;
        groundLatitude=std::clamp(groundLatitude+verticalPoints*2/radius,-Pi05+.0001,Pi05-.0001);
        groundLongitude=std::remainder(groundLongitude+horizontalPoints*2/(radius*std::max(.0001,cos(groundLatitude))),Pi2);return;
    }
    yaw=std::remainder(yaw+horizontalPoints*.009,Pi2);
    if(mode==ExternalCameraMode::OrbitalChase)pitch=std::clamp(pitch+verticalPoints*.009,-1.35,1.35);
    else pitch=std::remainder(pitch+verticalPoints*.009,Pi2);
}
void OrbitCamera::zoom(double scrollPoints){
    if(!std::isfinite(scrollPoints))return;
    if(mode==ExternalCameraMode::GroundObserver){groundFov=std::clamp(groundFov*exp(std::clamp(-scrollPoints*.025,-30.,30.)),.001*RAD,100*RAD);return;}
    distance=std::clamp(distance*exp(std::clamp(-scrollPoints*.025,-30.,30.)),14.,MaxExternalCameraDistance);
}
double OrbitCamera::tanHalfFov()const{return tan((mode==ExternalCameraMode::GroundObserver?groundFov:50*RAD)*.5);}
void CockpitCamera::zoom(double scrollPoints){
    if(!std::isfinite(scrollPoints))return;
    fov=std::clamp(fov*exp(std::clamp(-scrollPoints*.025,-30.,30.)),15*RAD,85*RAD);
}
void CockpitCamera::zoomAt(double scrollPoints,double x,double y,double aspect,double &yaw,double &pitch){
    if(!std::isfinite(scrollPoints)||!std::isfinite(x)||!std::isfinite(y)||!std::isfinite(aspect)||aspect<=0)return;
    x=std::clamp(x,-1.,1.);y=std::clamp(y,-1.,1.);
    Vector anchor=ray(yaw,pitch,x,y,aspect);double oldFov=fov;zoom(scrollPoints);if(fov==oldFov)return;
    double a=x*tanHalfFov()*aspect,b=y*tanHalfFov();
    double vertical=std::clamp(anchor.y*sqrt(1+a*a+b*b)/sqrt(1+b*b),-1.,1.);
    double newPitch=asin(vertical)-atan(b);
    pitch=std::clamp(newPitch,-1.1,1.1);
    double c=cos(pitch)-b*sin(pitch);
    yaw=std::clamp(std::remainder(atan2(anchor.x,anchor.z)-atan2(a,c),Pi2),-2.5,2.5);
}
double CockpitCamera::tanHalfFov() const {return tan(fov*.5);}
Vector CockpitCamera::ray(double yaw,double pitch,double normalizedX,double normalizedY,double aspect) const {
    Vector forward(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch));
    Vector right=crossp(Vector(0,1,0),forward).unit(),up=crossp(forward,right).unit();
    double t=tanHalfFov();return (forward+right*(normalizedX*t*aspect)+up*(normalizedY*t)).unit();
}
Vector OrbitCamera::offset(const Flight &flight) const {
    return pose(flight).offset;
}
CameraPose OrbitCamera::pose(const Flight &flight) const {
    Vector radial,tangent,lateral;orbitalBasis(flight,radial,tangent,lateral);
    Vector result,up;
    if(mode==ExternalCameraMode::OrbitalChase){
        result=pointInFrame(lateral,radial,tangent,yaw,pitch)*distance;up=radial;
        if(flight.altitude()<1000)result+=radial*std::max(0.,1.5-flight.altitude()-dotp(result,radial));
    }else if(mode==ExternalCameraMode::TargetRelative){
        result=pointInFrame(flight.right,flight.up,flight.forward,yaw,pitch)*distance;
        up=upwardInFrame(flight.right,flight.up,flight.forward,yaw,pitch);
    }else if(mode==ExternalCameraMode::AbsoluteDirection||mode==ExternalCameraMode::GlobalFrame){
        result=pointInFrame({1,0,0},{0,1,0},{0,0,1},yaw,pitch)*distance;
        up=mode==ExternalCameraMode::AbsoluteDirection?flight.up:upwardInFrame({1,0,0},{0,1,0},{0,0,1},yaw,pitch);
    }else if(mode==ExternalCameraMode::TargetTo||mode==ExternalCameraMode::TargetFrom){
        Vector direction=bodyRelativeToVessel(target,flight);
        if(direction.length2()<1e-12)direction=-flight.position;
        result=direction.unit()*(mode==ExternalCameraMode::TargetTo?-distance:distance);up=flight.up;
    }else{
        auto surface=bodySurface(groundBody,groundLatitude,groundLongitude,flight.mjd,flight.elapsed);
        Vector center=groundBody==flight.reference?Vector{}:ephemeridesReady()?bodyState(groundBody,flight.mjd+flight.elapsed/86400).position-bodyState(flight.reference,flight.mjd+flight.elapsed/86400).position:Vector{};
        result=center+surface.up*(body(groundBody).radius+groundHeight)-flight.position;up=surface.up;
        if(result.length2()<1e-12)result=surface.north;
        return {result,safeUp(result,up,surface.north)};
    }
    return {result,safeUp(result,up,flight.right)};
}
bool OrbitCamera::setMode(ExternalCameraMode next,const Flight &flight,BodyId reference){
    if((int)reference<0||(size_t)reference>=BodyCount)return false;
    if((next==ExternalCameraMode::TargetTo||next==ExternalCameraMode::TargetFrom)&&reference!=flight.reference&&!ephemeridesReady())return false;
    if(next==ExternalCameraMode::GroundObserver&&!flight.centralBody().solid)return false;
    Vector previous=pose(flight).offset.unit();
    if(next==ExternalCameraMode::GroundObserver){
        groundBody=flight.reference;Vector radial=flight.position.unit(),horizontal=previous-radial*dotp(previous,radial);
        if(horizontal.length2()<1e-12)horizontal=flight.right-radial*dotp(flight.right,radial);
        if(horizontal.length2()<1e-12){Vector tangent,lateral;orbitalBasis(flight,radial,tangent,lateral);horizontal=lateral;}
        Vector site=radial*flight.centralBody().radius+horizontal.unit()*150.;
        bodyCoordinates(groundBody,site,flight.mjd,flight.elapsed,groundLatitude,groundLongitude);
    }else if(next==ExternalCameraMode::TargetRelative){
        yaw=atan2(dotp(previous,flight.right),-dotp(previous,flight.forward));pitch=asin(std::clamp(dotp(previous,flight.up),-1.,1.));
    }else if(next==ExternalCameraMode::AbsoluteDirection||next==ExternalCameraMode::GlobalFrame){
        yaw=atan2(previous.x,-previous.z);pitch=asin(std::clamp(previous.y,-1.,1.));
    }else if(next==ExternalCameraMode::OrbitalChase){
        Vector radial,tangent,lateral;orbitalBasis(flight,radial,tangent,lateral);
        yaw=atan2(dotp(previous,lateral),-dotp(previous,tangent));pitch=std::clamp(asin(std::clamp(dotp(previous,radial),-1.,1.)),-1.35,1.35);
    }
    target=reference;mode=next;return true;
}
}

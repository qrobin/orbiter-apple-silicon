#include "Camera.h"
#include "Surface.h"
#include <algorithm>
#include <cmath>
namespace native {
void OrbitCamera::drag(double horizontalPoints,double verticalPoints){
    if(!std::isfinite(horizontalPoints)||!std::isfinite(verticalPoints))return;
    yaw=std::remainder(yaw+horizontalPoints*.009,Pi2);
    pitch=std::clamp(pitch+verticalPoints*.009,-1.35,1.35);
}
void OrbitCamera::zoom(double scrollPoints){
    if(!std::isfinite(scrollPoints))return;
    distance=std::clamp(distance*exp(std::clamp(scrollPoints*.025,-30.,30.)),14.,1000.);
}
void CockpitCamera::zoom(double scrollPoints){
    if(!std::isfinite(scrollPoints))return;
    fov=std::clamp(fov*exp(std::clamp(scrollPoints*.025,-30.,30.)),15*RAD,85*RAD);
}
double CockpitCamera::tanHalfFov() const {return tan(fov*.5);}
Vector CockpitCamera::ray(double yaw,double pitch,double normalizedX,double normalizedY,double aspect) const {
    Vector forward(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch));
    Vector right=crossp(Vector(0,1,0),forward).unit(),up=crossp(forward,right).unit();
    double t=tanHalfFov();return (forward+right*(normalizedX*t*aspect)+up*(normalizedY*t)).unit();
}
Vector OrbitCamera::offset(const Flight &flight) const {
    Vector radial=flight.position.unit(),direction=flight.altitude()<10000?flight.forward:flight.velocity;
    Vector tangent=direction-radial*dotp(direction,radial);
    if(tangent.length2()<1e-12){
        double latitude,longitude;bodyCoordinates(flight.reference,flight.position,flight.mjd,flight.elapsed,latitude,longitude);
        tangent=bodySurface(flight.reference,latitude,longitude,flight.mjd,flight.elapsed).north;
    }
    tangent.unify();Vector lateral=crossp(radial,tangent).unit();
    Vector result=(-tangent*(cos(yaw)*cos(pitch))+lateral*(sin(yaw)*cos(pitch))+radial*sin(pitch))*distance;
    if(flight.altitude()<1000)result+=radial*std::max(0.,1.5-flight.altitude()-dotp(result,radial));
    return result;
}
}

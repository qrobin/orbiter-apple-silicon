// Delta-glider touchdown locations and spring/damper ratings are from
// Src/Vessel/DeltaGlider/DeltaGlider.cpp. Copyright (c) Martin Schweiger, MIT License.
#include "Surface.h"
#include "Flight.h"
#include <algorithm>
#include <cmath>
namespace native {
Vector earthSpin() { return Vector(0,cos(.4090928023),sin(.4090928023))*(Pi2/SiderealDay); }
SurfaceFrame bodySurface(BodyId id,double latitude,double longitude,double mjd,double elapsed) {
    const auto &b=body(id);double phi=longitude-b.rotation(mjd+elapsed/86400),cl=cos(latitude),sl=sin(latitude),cp=cos(phi),sp=sin(phi);
    Vector x=b.equatorX(),y=b.pole(),z=b.equatorZ();
    return {x*(cl*cp)+y*sl+z*(cl*sp),x*(-sl*cp)+y*cl+z*(-sl*sp),x*(-sp)+z*cp};
}
SurfaceFrame earthSurface(double lat,double lon,double mjd,double elapsed){return bodySurface(BodyId::Earth,lat,lon,mjd,elapsed);}
void bodyCoordinates(BodyId id,const Vector &p,double mjd,double elapsed,double &latitude,double &longitude){
    const auto &b=body(id);auto n=p.unit();latitude=asin(std::clamp(dotp(n,b.pole()),-1.,1.));
    longitude=remainder(atan2(dotp(n,b.equatorZ()),dotp(n,b.equatorX()))+b.rotation(mjd+elapsed/86400),Pi2);
}
void earthCoordinates(const Vector &p,double mjd,double elapsed,double &latitude,double &longitude){bodyCoordinates(BodyId::Earth,p,mjd,elapsed,latitude,longitude);}
const std::array<ContactPoint,13> &gliderContacts(bool down) {
    static const std::array<ContactPoint,13> deployed={{{{0,-2.57,10},1e6,1e5,1.6,true,0},
        {{-3.5,-2.57,-1},1e6,1e5,3,true,1},{{3.5,-2.57,-1},1e6,1e5,3,true,2},
        {{-8.5,-.3,-7.05},1e7,1e5,3,false,-1},{{8.5,-.3,-7.05},1e7,1e5,3,false,-1},
        {{-8.5,-.4,-3},1e7,1e5,3,false,-1},{{8.5,-.4,-3},1e7,1e5,3,false,-1},
        {{-8.85,2.3,-5.05},1e7,1e5,3,false,-1},{{8.85,2.3,-5.05},1e7,1e5,3,false,-1},
        {{-8.85,2.3,-7.05},1e7,1e5,3,false,-1},{{8.85,2.3,-7.05},1e7,1e5,3,false,-1},
        {{0,2,6.2},1e7,1e5,3,false,-1},{{0,-.6,10.65},1e7,1e5,3,false,-1}}};
    static const auto retracted=[] { auto contacts=deployed;
        contacts[0]={{0,-1.5,9},1e7,1e5,3,false,-1};
        contacts[1]={{-6,-.8,-5},1e7,1e5,3,false,-1};
        contacts[2]={{3,-1.2,-5},1e7,1e5,3,false,-1}; return contacts; }();
    return down?deployed:retracted;
}
GroundResponse groundForces(const Vector &position,const Vector &velocity,
    const Vector &right,const Vector &up,const Vector &forward,const Vector &angularVelocity,
    double mass,bool gearDown,double steering,double leftBrake,double rightBrake,double dt,BodyId id) {
    GroundResponse result;
    auto world=[&](const Vector &v){return right*v.x+up*v.y+forward*v.z;};
    auto body=[&](const Vector &v){return Vector(dotp(v,right),dotp(v,up),dotp(v,forward));};
    Vector omega=world(angularVelocity),inertia=Vector(15.5,22.1,7.7)*mass;
    for(const auto &contact:gliderContacts(gearDown)) {
        Vector lever=world(contact.position),point=position+lever; double depth=native::body(id).radius-point.length();
        if(depth<=0) continue;
        Vector normal=point.unit();
        Vector v=velocity+crossp(omega,lever)-crossp(native::body(id).spin(),point);
        double normalSpeed=dotp(v,normal);
        result.maximumClosingSpeed=std::max(result.maximumClosingSpeed,-normalSpeed);
        double load=std::clamp(contact.stiffness*depth-contact.damping*normalSpeed,0.,mass*9.81*100);
        if(load<=0) continue;
        ++result.contacts;if(contact.wheel) ++result.wheels;result.load+=load;
        Vector force=normal*load;
        Vector wheelForward=forward-normal*dotp(forward,normal);
        if(wheelForward.length2()<1e-12) wheelForward=right-normal*dotp(right,normal);
        wheelForward.unify();
        Vector lateral=crossp(normal,wheelForward).unit();
        double speed=(v-normal*normalSpeed).length();
        if(contact.wheelIndex==0) {
            double angle=std::clamp(steering,-1.,1.)*45*Pi/180/(1+speed/12);
            wheelForward=wheelForward*cos(angle)+lateral*sin(angle);
            lateral=crossp(normal,wheelForward).unit();
        }
        auto friction=[&](const Vector &direction,double limit) {
            Vector d=body(direction),arm=crossp(contact.position,d);
            double inverseEffectiveMass=1/mass+dotp(arm,arm/inertia);
            // Relax simultaneous tire impulses to avoid three contacts over-correcting the same slip.
            double desired=-dotp(v,direction)/(3*std::max(dt,1e-5)*inverseEffectiveMass);
            return direction*std::clamp(desired,-limit,limit);
        };
        if(contact.wheel) {
            double brake=contact.wheelIndex==1?leftBrake:contact.wheelIndex==2?rightBrake:0;
            double longitudinalLimit=.015*load+std::min(100000*brake,.9*load);
            force+=friction(wheelForward,longitudinalLimit);
            force+=friction(lateral,contact.lateralFriction*load);
        } else {
            Vector slip=v-normal*normalSpeed;
            if(slip.length2()>1e-10) force+=friction(slip.unit(),contact.lateralFriction*load);
        }
        result.force+=force;result.torque+=body(crossp(lever,force));
    }
    return result;
}
}

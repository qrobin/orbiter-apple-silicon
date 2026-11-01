// Delta-glider touchdown locations and spring/damper ratings are from
// Src/Vessel/DeltaGlider/DeltaGlider.cpp. Copyright (c) Martin Schweiger, MIT License.
#include "Surface.h"
#include "Flight.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <vector>
namespace native {
Vector earthSpin() { return body(BodyId::Earth).spin(); }
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
namespace {
constexpr int terrainWidth=2048,terrainHeight=1024;
std::vector<unsigned char> terrainMask;
double smoothTerrain(double a,double b,double x) { double t=std::clamp((x-a)/(b-a),0.,1.);return t*t*(3-2*t); }
double terrainNoise(Vector p) {
    int x=(int)floor(p.x),y=(int)floor(p.y),z=(int)floor(p.z);
    double u=p.x-x,v=p.y-y,w=p.z-z;u=u*u*(3-2*u);v=v*v*(3-2*v);w=w*w*(3-2*w);
    auto hash=[](int a,int b,int c){uint32_t n=(uint32_t)a+(uint32_t)b*157u+(uint32_t)c*11317u;n^=n>>16;n*=0x7feb352du;n^=n>>15;n*=0x846ca68bu;n^=n>>16;return double(n&0xffffffu)/16777216.;};
    auto lerp=[](double a,double b,double t){return a+(b-a)*t;};
    return lerp(lerp(lerp(hash(x,y,z),hash(x+1,y,z),u),lerp(hash(x,y+1,z),hash(x+1,y+1,z),u),v),lerp(lerp(hash(x,y,z+1),hash(x+1,y,z+1),u),lerp(hash(x,y+1,z+1),hash(x+1,y+1,z+1),u),v),w);
}
double waterAt(double lat,double lon){
    double x=(lon/Pi2+.5)*terrainWidth-.5,y=(.5-lat/Pi)*terrainHeight-.5;long ix=(long)floor(x),iy=(long)floor(y);double fx=x-ix,fy=y-iy;
    auto at=[](long a,long b){a=(a%terrainWidth+terrainWidth)%terrainWidth;b=std::clamp(b,0L,(long)terrainHeight-1);return terrainMask[b*terrainWidth+a]/255.;};
    return (at(ix,iy)*(1-fx)+at(ix+1,iy)*fx)*(1-fy)+(at(ix,iy+1)*(1-fx)+at(ix+1,iy+1)*fx)*fy;
}
}
bool loadTerrainMask(const std::filesystem::path &path) {
    std::ifstream f(path,std::ios::binary);std::vector<unsigned char> bytes(terrainWidth*terrainHeight);
    if(!f.read((char*)bytes.data(),bytes.size())||f.peek()!=std::char_traits<char>::eof())return false;
    terrainMask=std::move(bytes);return true;
}
double terrainElevation(BodyId id,const Vector &position,double mjd,double elapsed) {
    if(id!=BodyId::Earth||terrainMask.empty()||position.length2()<1)return 0;
    double lat,lon;bodyCoordinates(id,position,mjd,elapsed,lat,lon);
    Vector n(cos(lat)*cos(lon),sin(lat),cos(lat)*sin(lon));
    double land=(1-smoothTerrain(.03,.30,waterAt(lat,lon)))*(1-smoothTerrain(1.38,1.43,fabs(lat)));
    Vector cape(cos(Rad(28.58438))*cos(Rad(-80.65165)),sin(Rad(28.58438)),cos(Rad(28.58438))*sin(Rad(-80.65165)));
    Vector france(cos(Rad(46.))*cos(Rad(2.)),sin(Rad(46.)),cos(Rad(46.))*sin(Rad(2.)));
    double base=smoothTerrain(20000,35000,(n-cape).length()*body(id).radius)*smoothTerrain(25000,45000,(n-france).length()*body(id).radius);
    double broad=terrainNoise(n*160),detail=terrainNoise(n*600),ridge=1-fabs(2*terrainNoise(n*340)-1);
    double mountains=smoothTerrain(.43,.72,broad);
    return land*base*(35+100*detail+1100*mountains*ridge*ridge);
}
Vector terrainNormal(BodyId id,const Vector &position,double mjd,double elapsed){
    Vector n=position.unit();if(id!=BodyId::Earth||terrainMask.empty())return n;
    double lat,lon;bodyCoordinates(id,position,mjd,elapsed,lat,lon);auto frame=bodySurface(id,lat,lon,mjd,elapsed);double d=10;
    double east=(terrainElevation(id,position+frame.east*d,mjd,elapsed)-terrainElevation(id,position-frame.east*d,mjd,elapsed))/(2*d);
    double north=(terrainElevation(id,position+frame.north*d,mjd,elapsed)-terrainElevation(id,position-frame.north*d,mjd,elapsed))/(2*d);
    return (n-frame.east*east-frame.north*north).unit();
}
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
    double mass,bool gearDown,double steering,double leftBrake,double rightBrake,double dt,BodyId id,double mjd,double elapsed) {
    GroundResponse result;
    auto world=[&](const Vector &v){return right*v.x+up*v.y+forward*v.z;};
    auto body=[&](const Vector &v){return Vector(dotp(v,right),dotp(v,up),dotp(v,forward));};
    Vector omega=world(angularVelocity),inertia=Vector(15.5,22.1,7.7)*mass;
    for(const auto &contact:gliderContacts(gearDown)) {
        Vector lever=world(contact.position),point=position+lever; double depth=native::body(id).radius+terrainElevation(id,point,mjd,elapsed)-point.length();
        if(depth<=0) continue;
        Vector normal=terrainNormal(id,point,mjd,elapsed);
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

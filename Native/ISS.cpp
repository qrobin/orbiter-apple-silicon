#include "ISS.h"
#include "Flight.h"
#include "TimeData.h"
#include <algorithm>
#include <cmath>

extern TimeData td;
namespace native {
const DockPort &issPort(int index) {
    // Src/Vessel/ISS/Config/ProjectAlpha_ISS.cfg, in mesh coordinates.
    static const std::array<DockPort,ISSPortCount> ports{{
        {{.08,-5.8,15.7},{0,0,1},{0,-1,0},588},
        {{.09,-17.9,-3.8},{0,-1,0},{0,0,1},586},
        {{.05,-4.30,-36.3},{0,0,-1},{0,1,0},584},
        {{.05,-7.7,10.3},{0,-1,0},{0,0,-1},582},
        {{.05,-18.3,-23.7},{0,-1,0},{0,0,-1},580}
    }};
    return ports[std::clamp(index,0,ISSPortCount-1)];
}
ISSState issState(const ISSOrbit &orbit,double mjd) {
    const auto &v=orbit.elements;
    Elements e(v[0],v[1],Rad(v[2]),Rad(v[3]),Rad(v[4]),Rad(v[5]),v[6]);
    e.Setup(0,body(BodyId::Earth).mass,mjd);
    ISSState s; e.PosVel(s.position,s.velocity,(mjd-td.MJD_ref)*86400.0);
    Matrix m; m.Set(orbit.attitude*RAD);
    s.right=mul(m,Vector(1,0,0));s.up=mul(m,Vector(0,1,0));s.forward=mul(m,Vector(0,0,1));
    return s;
}
static Vector localVector(const ISSState &s,const Vector &p) {return s.right*p.x+s.up*p.y+s.forward*p.z;}
DockingTelemetry issDockingTelemetry(const Flight &ship,const ISSState &station,int port) {
    const auto &p=issPort(port); DockingTelemetry t;
    t.target=station.position+localVector(station,p.position);
    t.direction=localVector(station,p.direction).unit();t.up=localVector(station,p.up).unit();
    // DeltaGlider.cpp: SetDockParams(0,-0.49,10.076), direction +Z, up +Y.
    Vector shipPort=ship.position-ship.up*.49+ship.forward*10.076;
    t.relative=t.target-shipPort;t.relativeVelocity=ship.velocity-station.velocity;
    t.distance=t.relative.length();
    if(t.distance>1e-9)t.closingSpeed=dotp(t.relativeVelocity,t.relative/t.distance);
    t.lateral=(t.relative-t.direction*dotp(t.relative,t.direction)).length();
    t.alignment=acos(std::clamp(dotp(ship.forward,-t.direction),-1.,1.));
    t.roll=acos(std::clamp(dotp(ship.up,t.up),-1.,1.));
    return t;
}
bool issDockCapture(const Flight &ship,const DockingTelemetry &t) {
    return ship.reference==BodyId::Earth&&ship.glider.part(Part::Nose).open()&&
        t.distance<.75&&t.relativeVelocity.length()<.5&&t.alignment<10*RAD&&t.roll<15*RAD;
}
void attachISS(Flight &ship,const ISSState &station,int port) {
    const auto &p=issPort(port);
    ship.forward=-localVector(station,p.direction).unit();
    ship.up=localVector(station,p.up).unit();ship.right=crossp(ship.up,ship.forward).unit();
    ship.up=crossp(ship.forward,ship.right).unit();
    ship.position=station.position+localVector(station,p.position)+ship.up*.49-ship.forward*10.076;
    ship.velocity=station.velocity;ship.angularVelocity=Vector();
}
}

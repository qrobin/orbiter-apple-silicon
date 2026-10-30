#pragma once
#include "Body.h"
#include <array>

namespace native {
class Flight;
// Orbiter's standard DG-in-orbit scenario supplies the initial station orbit.
struct ISSOrbit {
    std::array<double,7> elements{6734916.8,.00091,74.51287,169.03392,326.63622,528.41930,51982.51829991};
    Vector attitude{30,0,50};
};
struct ISSState { Vector position,velocity,right,up,forward; };
struct DockPort { Vector position,direction,up; int frequency; };
struct DockingTelemetry {
    Vector target,direction,up,relative,relativeVelocity;
    double distance=0,closingSpeed=0,lateral=0,alignment=0,roll=0;
};
constexpr int ISSPortCount=5;
const DockPort &issPort(int index);
ISSState issState(const ISSOrbit &orbit,double mjd);
DockingTelemetry issDockingTelemetry(const Flight &ship,const ISSState &station,int port);
bool issDockCapture(const Flight &ship,const DockingTelemetry &telemetry);
void attachISS(Flight &ship,const ISSState &station,int port);
}

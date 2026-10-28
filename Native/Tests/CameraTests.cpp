#include "Camera.h"
#include <iostream>
#include <limits>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool ok,const char *name){++checks;if(!ok)throw std::runtime_error(name);}
int main(){try {
    OrbitCamera full,split;full.drag(100,25);
    for(int i=0;i<400;++i)split.drag(.25,.0625);
    check(fabs(full.yaw-split.yaw)<1e-12&&fabs(full.pitch-split.pitch)<1e-12,"Fractional input and event batching preserve the same orbit");
    check(fabs(full.yaw-25*RAD-.9)<1e-12,"Horizontal sensitivity matches native .009 radians per point");
    check(fabs(full.pitch-17*RAD-.225)<1e-12,"Vertical sensitivity and direction match native");
    OrbitCamera fractional;double before=fractional.yaw;fractional.drag(.125,0);check(fractional.yaw>before,"Subpixel motion is not discarded");
    fractional.drag(0,10000);check(fractional.pitch==1.35,"Upper native pitch stop");fractional.drag(0,-10000);check(fractional.pitch==-1.35,"Lower native pitch stop");
    full.zoom(5);check(fabs(full.distance-43*exp(.125))<1e-10,"Continuous native zoom response");
    full.zoom(-100000);check(full.distance==14,"Near distance stop");full.zoom(100000);check(full.distance==1000,"Far distance stop");
    CockpitCamera cockpit,steps;check(fabs(cockpit.fov-50*RAD)<1e-12,"Original cockpit field of view");
    Vector edge=cockpit.ray(0,0,1,0,16./9);cockpit.zoom(-10);for(int i=0;i<10;++i)steps.zoom(-1);
    check(fabs(cockpit.fov-steps.fov)<1e-12,"Cockpit zoom is independent of event batching");
    check(cockpit.ray(0,0,1,0,16./9).x<edge.x,"Zoom narrows cockpit picking rays with the image");
    check(cockpit.ray(0,0,0,0,16./9).dist(Vector(0,0,1))<1e-12,"Center cockpit ray follows the view direction");
    cockpit.zoom(-100000);check(cockpit.fov==15*RAD,"Cockpit maximum zoom");
    cockpit.zoom(100000);check(cockpit.fov==85*RAD,"Cockpit minimum zoom");
    double fov=cockpit.fov;cockpit.zoom(std::numeric_limits<double>::quiet_NaN());check(cockpit.fov==fov,"Invalid scroll is ignored");
    Flight flight;OrbitCamera camera;auto expected=camera.offset(flight);
    flight.align(Vector(-1,3,.5));check((camera.offset(flight)-expected).length()<1e-8,"Orbital chase camera does not roll with vessel attitude");
    check(fabs(expected.length()-camera.distance)<1e-8,"Orbit retains chosen distance");
    flight.placeOnEarth(28*RAD,-80*RAD,0);camera.pitch=-1.35;
    check(flight.altitude()+dotp(camera.offset(flight),flight.position.unit())>=1.5-1e-8,"Surface camera stays above ground");
    camera.yaw=0;camera.pitch=0;flight.position*=((EarthRadius+350000)/flight.position.length());flight.velocity=flight.position.unit()*20;
    auto offset=camera.offset(flight);check(std::isfinite(offset.length()),"Camera has a stable frame during radial motion");
    std::cout<<checks<<" camera checks passed\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

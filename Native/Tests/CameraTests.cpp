#include "Camera.h"
#include "Surface.h"
#include "SolarSystem.h"
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
    Flight ship;ship.startOrbit(BodyId::Earth);OrbitCamera tracking;
    Vector initial=tracking.offset(ship).unit(),position=ship.position,velocity=ship.velocity;
    check(tracking.setMode(ExternalCameraMode::TargetRelative,ship,ship.reference),"Target-relative mode is available");
    check(dotp(initial,tracking.offset(ship).unit())>.999999999,"Switching tracking frames preserves viewing direction");
    Vector targetOffset=tracking.offset(ship);
    ship.align(-ship.right);check(tracking.offset(ship).dist(targetOffset)>1,"Target-relative camera follows vessel rotation");
    check(ship.position.dist(position)==0&&ship.velocity.dist(velocity)==0,"Camera changes do not modify flight state");
    check(tracking.setMode(ExternalCameraMode::AbsoluteDirection,ship,ship.reference),"Absolute-direction mode is available");
    auto absolute=tracking.pose(ship);Vector beforeRoll=ship.right;ship.right=ship.up;ship.up=-beforeRoll;
    check(tracking.offset(ship).dist(absolute.offset)<1e-9,"Absolute-direction position stays fixed while vessel rotates");
    check(tracking.pose(ship).up.dist(absolute.up)>.001,"Absolute-direction camera roll follows the vessel");
    check(tracking.setMode(ExternalCameraMode::GlobalFrame,ship,ship.reference),"Global-frame mode is available");
    auto global=tracking.pose(ship);ship.align(-ship.right);
    check(tracking.offset(ship).dist(global.offset)<1e-9&&tracking.pose(ship).up.dist(global.up)<1e-9,"Global-frame position and roll ignore vessel attitude");
    tracking.drag(0,400);auto inverted=tracking.pose(ship);
    check(std::isfinite(inverted.up.length())&&fabs(dotp(inverted.up,inverted.offset))<1e-9,"Global camera stays well-defined through full vertical rotation");
    check(tracking.setMode(ExternalCameraMode::TargetTo,ship,BodyId::Earth),"Target-to reference body is available");
    Vector toward=-ship.position.unit();check(dotp(-tracking.offset(ship).unit(),toward)>.999999,"Target-to points at the reference body");
    auto locked=tracking.offset(ship);tracking.drag(100,100);check(tracking.offset(ship).dist(locked)<1e-9,"Target-to direction stays locked while dragging");
    tracking.zoom(5);check(tracking.offset(ship).length()>locked.length(),"Target-to camera still zooms");
    tracking.setMode(ExternalCameraMode::TargetFrom,ship,BodyId::Earth);check(dotp(-tracking.offset(ship).unit(),toward)<-.999999,"Target-from looks away from the reference body");
    check(!tracking.setMode(ExternalCameraMode::TargetTo,ship,BodyId::Mars),"A distant reference requires ephemerides");
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    check(tracking.setMode(ExternalCameraMode::TargetTo,ship,BodyId::Mars),"Distant target-to reference is available with ephemerides");
    double date=ship.mjd+ship.elapsed/86400;Vector mars=(bodyState(BodyId::Mars,date).position-bodyState(ship.reference,date).position-ship.position).unit();
    check(dotp(-tracking.offset(ship).unit(),mars)>.999999,"Distant target-to follows ephemeris position");
    Flight shifted=ship;shifted.changeReference(BodyId::Sun);
    check(tracking.offset(shifted).dist(tracking.offset(ship))<1e-5,"Target-to view survives a gravity-reference change");
    Flight landed;landed.placeOnEarth(.3,-.8,.2);OrbitCamera ground;
    check(ground.setMode(ExternalCameraMode::GroundObserver,landed,BodyId::Earth),"Ground observer is available on a solid body");
    auto site=ground.offset(landed)+landed.position;double lat,lon;bodyCoordinates(BodyId::Earth,site,landed.mjd,landed.elapsed,lat,lon);
    check(fabs(lat-ground.groundLatitude)<1e-9&&fabs(remainder(lon-ground.groundLongitude,Pi2))<1e-9,"Ground observer sits at its chosen surface coordinates");
    landed.position+=landed.right*50;check((ground.offset(landed)+landed.position).dist(site)<1e-8,"Ground observer remains fixed when the ship moves");
    landed.elapsed+=30;site=ground.offset(landed)+landed.position;bodyCoordinates(BodyId::Earth,site,landed.mjd,landed.elapsed,lat,lon);
    check(fabs(lat-ground.groundLatitude)<1e-9&&fabs(remainder(lon-ground.groundLongitude,Pi2))<1e-9,"Ground observer rotates with its body");
    shifted=landed;shifted.changeReference(BodyId::Sun);
    check(ground.offset(shifted).dist(ground.offset(landed))<.01,"Ground observer remains attached when the ship changes reference body");
    double oldLat=ground.groundLatitude,oldLon=ground.groundLongitude,oldFov=ground.groundFov;ground.drag(10,10);ground.zoom(-20);
    check(ground.groundLatitude!=oldLat&&ground.groundLongitude!=oldLon&&ground.groundFov<oldFov,"Ground drag moves the site and scroll zooms the lens");
    Flight gas;gas.startOrbit(BodyId::Jupiter);check(!ground.setMode(ExternalCameraMode::GroundObserver,gas,BodyId::Jupiter),"Ground observer rejects bodies with no solid surface");
    std::cout<<checks<<" camera checks passed\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

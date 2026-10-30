#include "ISS.h"
#include "Flight.h"
#include "Mesh.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>

using namespace native;
int main() {
    Flight flight;
    flight.startISSApproach();
    const auto s=issState(flight.issOrbit,flight.mjd);
    const double altitude=s.position.length()-body(BodyId::Earth).radius;
    const double speed=s.velocity.length();
    auto check=[](bool value,const char *message){if(!value)throw std::runtime_error(message);};
    check(altitude>350000&&altitude<380000,"ISS altitude from original scenario");
    check(speed>7600.0&&speed<7800.0,"ISS orbital speed");
    auto t=issDockingTelemetry(flight,s,flight.issTargetPort);
    check(std::abs((flight.position-s.position).length()-50)<1e-7&&t.relativeVelocity.length()<1e-9,"50 metre synchronized approach setup");
    check(!issDockCapture(flight,t),"no distant capture");
    attachISS(flight,s,flight.issTargetPort);
    t=issDockingTelemetry(flight,s,flight.issTargetPort);
    check(t.distance<1e-7&&t.alignment<1e-6&&t.roll<1e-6,"original docking ports align");
    check(issDockCapture(flight,t),"capture at open aligned port");
    flight.glider.part(Part::Nose).position=0;check(!issDockCapture(flight,t),"closed nose prevents docking");
    flight.glider.part(Part::Nose).position=1;flight.velocity+=t.direction*2;
    check(!issDockCapture(flight,issDockingTelemetry(flight,s,flight.issTargetPort)),"fast approach is rejected");
    flight.velocity=s.velocity;flight.advance(.05);check(flight.issDocked,"automatic docking");
    for(int i=0;i<100;++i)flight.advance(.1);
    auto after=issState(flight.issOrbit,flight.mjd+flight.elapsed/86400.);
    check(issDockingTelemetry(flight,after,flight.issTargetPort).distance<1e-7,"docked vessel follows ISS");
    auto tmp=std::filesystem::temp_directory_path()/"orbiter-native-iss-test.scn";
    flight.save(tmp);Flight restored;restored.load(tmp);std::filesystem::remove(tmp);
    check(restored.issDocked&&restored.issTargetPort==flight.issTargetPort,"docking survives save and load");
    restored.undockISS();restored.advance(.1);check(!restored.issDocked,"undocking does not immediately recapture");
    Flight original;original.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/Docked at ISS.scn");
    check(original.issDocked&&original.issTargetPort==1,"original docked ISS scenario loads");
    auto root=std::filesystem::path(ORBITER_TEST_DATA);
    auto mesh=loadMesh(root/"Src/Vessel/ISS/Meshes/ProjectAlpha_ISS.msh");
    check(mesh.groups.size()==42&&mesh.textures.size()==36,"original ISS mesh");
    check(mesh.groups[0].vertices[0].u==1,"ISS UV coordinates");
    for(const auto &g:mesh.groups)for(const auto &v:g.vertices)
        check(std::isfinite(v.nx)&&std::isfinite(v.ny)&&std::isfinite(v.nz),"ISS normals");
    for(const auto &name:mesh.textures){
        auto file=std::filesystem::path(name).filename().string();
        std::transform(file.begin(),file.end(),file.begin(),[](unsigned char c){return std::tolower(c);});
        auto image=loadDDS(root/"Src/Vessel/ISS/Textures"/file);
        check(image.rgba.size()==size_t(image.width)*image.height*4,"ISS texture");
    }
    std::cout<<"ISS orbit: altitude "<<altitude<<" m, speed "<<speed<<" m/s\n";
    return 0;
}

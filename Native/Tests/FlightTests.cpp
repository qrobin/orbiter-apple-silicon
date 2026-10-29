#include "Flight.h"
#include "Mesh.h"
#include <iostream>
#include <algorithm>
#include <fstream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool b,const char *message) { ++checks; if(!b) throw std::runtime_error(message); }
int main() { try {
    auto root=std::filesystem::path(ORBITER_TEST_DATA);
    Flight flight; flight.load(root/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    check(flight.name=="GL-01","scenario focus"); check(flight.altitude()>100000&&flight.altitude()<800000,"scenario altitude");
    auto energy=[](const Flight &s){ return .5*s.velocity.length2()-Mu/s.position.length(); };
    double e0=energy(flight); Vector h0=crossp(flight.position,flight.velocity);
    auto e=flight.orbit(); double period=e.OrbitT(); Vector p0=flight.position,v0=flight.velocity;
    // Use warp to cover one complete orbit while keeping wall steps under .1 s.
    flight.load(root/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    flight.warp=100; double realStep=period/6000/100;
    for(int i=0;i<6000;++i) flight.advance(realStep);
    check(fabs(energy(flight)/e0-1)<1e-9,"coasting energy conservation");
    check((crossp(flight.position,flight.velocity)-h0).length()/h0.length()<1e-9,"coasting angular momentum conservation");
    check((flight.position-p0).length()<.1,"one orbital period position closure");
    check((flight.velocity-v0).length()<.001,"one orbital period velocity closure");
    flight.align(flight.velocity); flight.throttle=1; double fuel=flight.fuel;
    double before=energy(flight),burnStart=flight.elapsed; flight.advance(.1);
    check(fabs(fuel-flight.fuel-10*(flight.elapsed-burnStart))<1e-8,"Delta glider fuel flow is 10 kg per simulation second");
    check(energy(flight)>before,"prograde burn raises orbital energy");
    flight.paused=true; Vector old=flight.position; flight.advance(.1);
    check(flight.position.dist(old)==0,"pause freezes state"); flight.paused=false;
    flight.throttle=0; Input in; in.pitch=1; for(int i=0;i<100;++i) flight.advance(.01,in);
    check(fabs(flight.forward.length()-1)<1e-12&&fabs(dotp(flight.forward,flight.up))<1e-12,"attitude frame orthonormal");
    check(flight.rcs<RcsCapacity*.9,"attitude consumes RCS fuel");
    auto tmp=std::filesystem::temp_directory_path()/"orbiter-native-test.scn";
    flight.save(tmp); Flight roundtrip; roundtrip.load(tmp);
    check(roundtrip.position.dist(flight.position)<1e-7,"scenario state roundtrip");
    check(fabs(roundtrip.fuel-flight.fuel)<1e-9,"scenario fuel roundtrip");
    check(roundtrip.forward.dist(flight.forward)<1e-12&&roundtrip.up.dist(flight.up)<1e-12,"scenario attitude roundtrip");
    check(roundtrip.angularVelocity.dist(flight.angularVelocity)<1e-12,"scenario rotation rate roundtrip");
    std::ofstream(tmp)<<"BEGIN_FOCUS\n Ship no\nEND_FOCUS\nBEGIN_SHIPS\nno:DeltaGlider\n STATUS Landed Mars\nEND\nEND_SHIPS\n";
    bool rejected=false; try { roundtrip.load(tmp); } catch(...) { rejected=true; }
    check(rejected,"unsupported scenario rejected"); std::filesystem::remove(tmp);
    Flight circular; circular.position={EarthRadius+400000,0,0};
    circular.velocity={0,0,sqrt(Mu/circular.position.length())};
    double circularRadius=circular.position.length(); circular.warp=100;
    for(int i=0;i<1000;++i) circular.advance(.05);
    check(fabs(circular.position.length()-circularRadius)<.01,"circular orbit remains circular");
    Flight escape; escape.position={EarthRadius+400000,0,0};
    escape.velocity={0,0,sqrt(2*Mu/escape.position.length())*1.1};
    for(int i=0;i<100;++i) escape.advance(.05);
    check(std::isfinite(escape.position.length())&&escape.orbit().e>1,"hyperbolic escape remains finite");
    Flight parabolic; parabolic.position={EarthRadius+400000,0,0};
    parabolic.velocity={0,0,sqrt(2*Mu/parabolic.position.length())};
    for(int i=0;i<100;++i) parabolic.advance(.05);
    check(std::isfinite(parabolic.position.length())&&parabolic.altitude()>0,"parabolic boundary remains finite");
    Flight dry; dry.fuel=.0001; dry.align(dry.velocity); dry.throttle=1; dry.advance(.1);
    check(dry.fuel==0&&std::isfinite(dry.velocity.length()),"last partial fuel burn stays finite");
    auto mesh=loadMesh(root/"Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh");
    check(mesh.groups.size()==122&&mesh.textures.size()==10,"original Delta glider mesh parses");
    size_t triangles=0; for(const auto &g:mesh.groups) triangles+=g.indices.size()/3;
    check(triangles>10000,"complete mesh topology");
    for(auto &name:mesh.textures) {
        auto file=std::filesystem::path(name).filename().string();
        std::transform(file.begin(),file.end(),file.begin(),[](unsigned char c){return std::tolower(c);});
        auto tex=loadDDS(root/"Src/Vessel/DeltaGlider/Textures"/file);
        check(tex.rgba.size()==size_t(tex.width)*tex.height*4,"original DDS decodes");
    }
    std::cout<<"PASS: "<<checks<<" checks; "<<mesh.groups.size()<<" groups, "<<triangles<<" triangles\n";
    return 0;
} catch(const std::exception &e) { std::cerr<<"FAIL after "<<checks<<" checks: "<<e.what()<<'\n'; return 1; } }

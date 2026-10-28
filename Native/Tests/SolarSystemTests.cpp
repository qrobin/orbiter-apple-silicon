#include "Flight.h"
#include "SolarSystem.h"
#include "Surface.h"
#include "Exhaust.h"
#include <iostream>
#include <fstream>
#include <stdexcept>
using namespace native;
static int checks;
void check(bool ok,const std::string &label){++checks;if(!ok)throw std::runtime_error(label);}
int main(){try{
    auto root=std::filesystem::path(ORBITER_TEST_DATA);loadEphemerides(root/"Src/Celbody");
    check(BodyCount==33,"Original Sol catalogue contains 33 bodies");
    check(findBody("luna")==BodyId::Moon&&findBody("mArS")==BodyId::Mars,"Body lookup and alias");
    check(bodyAtmosphere(BodyId::Moon,0).rho==0&&bodyAtmosphere(BodyId::Mercury,0).p==0,"Airless bodies remain vacuum");
    check(bodyAtmosphere(BodyId::Mars,0).p<1000&&bodyAtmosphere(BodyId::Titan,0).rho>5,"Body-specific atmosphere");
    check(body(BodyId::Venus).spin().length()>0&&body(BodyId::Venus).period<0,"Retrograde Venus rotation");
    check(body(BodyId::Moon).mu()/(1738000.*1738000.)>1.6&&body(BodyId::Moon).mu()/(1738000.*1738000.)<1.7,"Lunar surface gravity");
    double date=51982.5292925579;
    auto tmp=std::filesystem::temp_directory_path()/"orbiter-native-solar-test.scn";
    for(const auto &b:bodies()){
        std::string label=b.name;check(b.mass>0&&b.radius>0&&std::isfinite(b.mu()),label+" physical data");
        double lat=.38,lon=-1.25,lat2,lon2;auto frame=bodySurface(b.id,lat,lon,date,123);
        bodyCoordinates(b.id,frame.up*b.radius,date,123,lat2,lon2);
        check(fabs(lat2-lat)<1e-12&&fabs(remainder(lon2-lon,Pi2))<1e-12,label+" rotating surface coordinate roundtrip");
        auto state=bodyState(b.id,date);check(std::isfinite(state.position.length2()+state.velocity.length2()),label+" ephemeris finite");
        if(b.id!=BodyId::Sun){auto a=bodyState(b.id,date-1./86400),c=bodyState(b.id,date+1./86400);double error=((c.position-a.position)*.5-state.velocity).length();check(error<1,label+" ephemeris derivative: "+std::to_string(error));}
        Flight f;f.startOrbit(b.id);check(f.reference==b.id&&f.altitude()>0,label+" orbit start");
        auto energy=[&](){return .5*f.velocity.length2()-b.mu()/f.position.length();};
        double before=energy();Vector momentum=crossp(f.position,f.velocity);f.warp=100;
        for(int i=0;i<30;++i)f.advance(.05);
        check(fabs(energy()/before-1)<1e-8,label+" coasting energy conservation");
        check((crossp(f.position,f.velocity)-momentum).length()/momentum.length()<1e-8,label+" coasting momentum conservation");
        f.save(tmp);Flight saved;saved.load(tmp);check(saved.reference==b.id&&saved.position.dist(f.position)<.01,label+" scenario body roundtrip");
    }
    auto moon=relativeBodyState(BodyId::Moon,date);check(moon.position.length()>3.5e8&&moon.position.length()<4.1e8,"ELP82 lunar distance");
    auto io=relativeBodyState(BodyId::Io,date);check(io.position.length()>4e8&&io.position.length()<4.4e8,"GALSAT Io distance");
    auto titan=relativeBodyState(BodyId::Titan,date);check(titan.position.length()>1.15e9&&titan.position.length()<1.3e9,"TASS17 Titan distance");
    auto earth=bodyState(BodyId::Earth,51544.5);check(earth.position.x<0&&earth.position.z>1.4e11&&earth.position.z<1.5e11,"VSOP87 Earth J2000 orientation and units");
    Flight f;f.startOrbit(BodyId::Earth);date=f.mjd;auto origin=bodyState(f.reference,date);Vector p=origin.position+f.position,v=origin.velocity+f.velocity;
    f.changeReference(BodyId::Sun);check((f.position-p).length()<.001&&(f.velocity-v).length()<1e-8,"Reference change preserves heliocentric position and velocity");
    f.changeReference(BodyId::Earth);auto lunar=relativeBodyState(BodyId::Moon,date);f.position=lunar.position+Vector(body(BodyId::Moon).radius+100000,0,0);f.velocity=lunar.velocity+Vector(0,0,1600);p=f.position;v=f.velocity;
    f.updateReference();check(f.reference==BodyId::Moon,"Lunar sphere-of-influence capture");
    check((f.position+lunar.position-p).length()<.001&&(f.velocity+lunar.velocity-v).length()<1e-6,"Lunar capture is continuous");
    f.position={sphereOfInfluence(BodyId::Moon,date)*1.1,0,0};f.updateReference();check(f.reference==BodyId::Earth,"Lunar escape returns to Earth reference");
    f.reference=BodyId::Moon;f.placeOnBody(.2,-.4,0);f.save(tmp);Flight landed;landed.load(tmp);check(landed.reference==BodyId::Moon&&landed.groundContact,"Landed Moon save/load");
    bool rejected=false;try{f.reference=BodyId::Jupiter;f.placeOnBody(0,0,0);}catch(...){rejected=true;}check(rejected,"Gas giants have no solid landing surface");
    f.startOrbit(BodyId::Moon);auto lunarPlume=plumeShape(f,ExhaustKind::Main);auto vacuumPlume=plumeShape(1000000,ExhaustKind::Main);check(fabs(lunarPlume.spread-vacuumPlume.spread)<1e-12,"Lunar plume uses vacuum pressure");
    for(BodyId id:{BodyId::Moon,BodyId::Mars}){Flight ground;ground.reference=id;ground.placeOnBody(.1,.2,0);ground.glider.parkingBrake=true;for(int i=0;i<500;++i)ground.advance(.01);check(!ground.impacted&&ground.altitude()>2.3&&ground.altitude()<2.7,std::string(body(id).name)+" body-specific resting ground contact");}
    std::filesystem::remove(tmp);std::cout<<checks<<" Solar System checks passed\n";
}catch(const std::exception &e){std::cerr<<"After "<<checks<<" checks: "<<e.what()<<'\n';return 1;}}

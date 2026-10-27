#include "Flight.h"
#include "Aerodynamics.h"
#include "Mesh.h"
#include "Cockpit.h"
#include <iostream>
#include <algorithm>
#include <sstream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool value,const char *message) { ++checks;if(!value) throw std::runtime_error(message); }
void run(Flight &f,double seconds,const Input &input={}) { for(int i=0;i<(int)(seconds*100);++i) f.advance(.01,input); }
int main() {try {
    check(cockpitZones().size()==25,"original cockpit click zones present");
    check(cockpitSwitches().size()==16,"mechanical cockpit switch animations present");
    const auto &zone=*std::find_if(cockpitZones().begin(),cockpitZones().end(),[](const CockpitZone &z){return z.action==0;});
    Vector center=(zone.corners[0]+zone.corners[3])*.5;
    Vector normal=crossp(zone.corners[1]-zone.corners[0],zone.corners[2]-zone.corners[0]).unit();
    check(pickCockpit(center-normal*.01,normal).action==0,"ray picks original gear lever quadrilateral");
    check(pickCockpit({100,100,100},{1,0,0}).action==-1,"missed cockpit ray has no action");
    Glider g;
    check(Glider::animations().size()==63,"all extracted animation components present");
    for(const auto &c:Glider::animations()) {
        check(c.end>c.start,"animation stage has positive duration");
        for(auto index:c.groups) check(index<(c.mesh?133:122),"animation addresses valid original mesh group");
    }
    g.toggle(Part::Airbrake);g.advance(2,0);check(g.part(Part::Airbrake).position==.5,"airbrake has original halfway stop");
    g.toggle(Part::Gear);g.advance(3,0);
    check(fabs(g.part(Part::Gear).position-.45)<1e-10,"gear uses original deployment speed");
    g.toggle(Part::Gear);g.advance(1,0);
    check(fabs(g.part(Part::Gear).position-.30)<1e-10,"gear reverses smoothly in motion");
    g.command(Part::Gear,1);g.advance(10,0);
    check(g.part(Part::Gear).open()&&!g.part(Part::Gear).moving(),"gear reaches endpoint without overshoot");
    check(!g.toggle(Part::Ladder),"ladder blocked until nose is fully open");
    g.toggle(Part::Nose);g.advance(20,0);check(g.part(Part::Nose).open(),"nose deploys in original 20 seconds");
    check(g.toggle(Part::Ladder),"ladder can deploy with nose open");g.advance(10,0);
    check(g.part(Part::Ladder).open(),"ladder reaches deployed position");
    g.command(Part::Nose,0);check(g.part(Part::Ladder).target==0,"closing nose retracts ladder");
    g.command(Part::Radiator,1);g.advance(25,0);
    check(fabs(g.part(Part::Radiator).position-.5)<1e-12,"radiator preserves 50-second sequence");
    auto neutral=Glider().transforms(122); g.part(Part::Gear).position=1;
    auto deployed=g.transforms(122);
    Vector sample(0,-2,8);
    check(neutral[97].point(sample).dist(deployed[97].point(sample))>1,"gear geometry visibly changes");
    for(double phase:{0.,.15,.3,.5,.7,.9,1.}) {
        Glider animated;for(auto &p:animated.parts)p.position=phase;
        for(int mesh:{0,1}) for(auto &t:animated.transforms(mesh?133:122,mesh)) {
            auto v=t.point({1,2,3});check(std::isfinite(v.length()),"staged transformations remain finite");
            check(fabs(t.direction({1,0,0}).length()-1)<1e-10,"animation rotation preserves lengths");
        }
    }
    Glider pressure;
    pressure.advance(100,0);check(fabs(pressure.cabinPressure-100000)<1e-8,"sealed cabin retains pressure");
    pressure.part(Part::OuterLock).position=pressure.part(Part::OuterLock).target=1;pressure.advance(2,0);
    check(pressure.lockPressure<1&&pressure.cabinPressure>99999,"outer door vents only isolated airlock");
    pressure.part(Part::OuterLock).position=pressure.part(Part::OuterLock).target=0;
    pressure.valves[2]=true;double total=pressure.cabinPressure*24+pressure.lockPressure*4;pressure.advance(100,0);
    check(fabs(pressure.cabinPressure*24+pressure.lockPressure*4-total)<1e-6,"equalization conserves pressure-volume total");
    check(fabs(pressure.cabinPressure-pressure.lockPressure)<500,"equalization reduces pressure difference");
    pressure.valves[0]=pressure.valves[4]=true;pressure.advance(10000,0);
    check(pressure.cabinPressure==100000&&pressure.lockPressure==100000,"supply valves restore target pressure");
    pressure.valves.fill(false);pressure.part(Part::Hatch).position=pressure.part(Part::Hatch).target=1;pressure.advance(2,0);
    check(pressure.cabinPressure<1000&&!pressure.warning().empty(),"hatch opening vents cabin and raises warning");
    Glider warm,cool;cool.part(Part::Radiator).position=cool.part(Part::Radiator).target=1;
    for(int i=0;i<1000;++i) {warm.advance(1,.5);cool.advance(1,.5);}
    check(cool.coolantTemperature<warm.coolantTemperature,"deployed pumped radiator rejects heat");
    Flight retro;retro.align(retro.velocity);retro.glider.retro=1;
    double fuel=retro.fuel;run(retro,1);check(retro.fuel==fuel,"closed retro covers inhibit fuel and thrust");
    retro.glider.part(Part::RetroCover).position=retro.glider.part(Part::RetroCover).target=1;
    auto energy=[](const Flight &s){return .5*s.velocity.length2()-Mu/s.position.length();};
    double energyBefore=energy(retro);run(retro,1);
    check(fuel-retro.fuel>1.69&&fuel-retro.fuel<1.71,"retro engine flow matches two 34 kN thrusters");
    check(energy(retro)<energyBefore,"retro burn reduces orbital energy");
    Flight hover;hover.glider.hover=1;fuel=hover.fuel;run(hover,1);
    check(fabs(fuel-hover.fuel-(140000+140000*3/4.55)/40000)<1e-6,"hover engine flow uses original three-thruster distribution");
    check(hover.acceleration>10,"hover engines produce real linear acceleration");
    Flight rotation; Input input;input.pitch=1;double rcs=rotation.rcs;run(rotation,1,input);
    check(fabs(rcs-rotation.rcs-.125)<1e-8,"RCS rotational fuel flow follows original thruster pair");
    check(rotation.angularVelocity.x>.1,"RCS torque changes angular rate");
    rotation.assist=Assist::KillRotation;double rate=rotation.angularVelocity.length();run(rotation,3);
    check(rotation.angularVelocity.length()<rate*.1,"kill rotation uses finite RCS torque");
    Flight noRCS;noRCS.glider.rcsMode=0;run(noRCS,1,input);check(noRCS.angularVelocity.length()==0,"RCS off disables manual jets");
    Flight empty;empty.rcs=0;run(empty,1,input);check(empty.angularVelocity.length()==0,"empty RCS tank cannot rotate ship");
    Flight gimbal;gimbal.throttle=.5;gimbal.glider.gimbalPitch=1;run(gimbal,.5);
    check(fabs(gimbal.angularVelocity.x)>.01,"gimbal force at engine mount produces torque");
    Flight balanced;balanced.throttle=.5;run(balanced,.5);
    check(balanced.angularVelocity.length()<1e-10,"balanced main engines do not induce torque");
    Flight asymmetric;asymmetric.throttle=.5;asymmetric.glider.mainBalance=1;run(asymmetric,.5);
    check(fabs(asymmetric.angularVelocity.y)>.005,"independent main engine balance induces yaw");
    Flight saved;saved.glider=g;saved.throttle=.25;saved.glider.hover=.3;saved.glider.retro=.6;saved.glider.navLights=true;saved.glider.trim=.2;
    auto path=std::filesystem::temp_directory_path()/"orbiter-glider-state-test.scn";
    saved.save(path);Flight restored;restored.load(path);std::filesystem::remove(path);
    check(fabs(restored.throttle-.25)<1e-12&&fabs(restored.glider.hover-.3)<1e-12,"engine throttle states persist");
    check(restored.glider.navLights&&restored.glider.trim==.2,"lights and trim persist");
    for(size_t i=0;i<PartCount;++i) {
        check(fabs(saved.glider.parts[i].position-restored.glider.parts[i].position)<1e-12,"mechanism position persists");
        check(fabs(saved.glider.parts[i].target-restored.glider.parts[i].target)<1e-12,"moving mechanism direction persists");
    }
    auto sea=earthAtmosphere(0);check(fabs(sea.p-101325)<.1&&fabs(sea.rho-1.225)<1e-6,"original legacy atmosphere sea-level reference");
    check(earthAtmosphere(300000).rho==0,"atmosphere stops beyond declared altitude limit");
    for(double a:{0.,11000.,25000.,47000.,79000.,105000.,150000.}) check(std::isfinite(earthAtmosphere(a).rho),"atmosphere layers stay finite");
    double cl,cm,cd;verticalLift(20*RAD,0,&cl,&cm,&cd);check(fabs(cl-1)<1e-12&&cd>0,"original glider lift coefficient table preserved");
    std::cout<<"PASS: "<<checks<<" glider checks, 63 original animation components\n";return 0;
}catch(const std::exception &e){std::cerr<<"FAIL after "<<checks<<": "<<e.what()<<'\n';return 1;}}

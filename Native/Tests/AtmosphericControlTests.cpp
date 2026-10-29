#include "Flight.h"
#include <cmath>
#include <filesystem>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool value,const char *message){if(!value)throw std::runtime_error(message);}
static void run(Flight &f,double seconds,const Input &input={}){for(int i=0;i<int(seconds/.05);++i)f.advance(.05,input);}
static Flight atlantic(){Flight f;f.load(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/Scenarios/Atlantic Ocean flight.scn");return f;}
int main(){try{
    check(loadEarthWeatherMap(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/earth-clouds.r8"),"Weather data loads");
    Flight f=atlantic();f.weatherPreset=3;
    for(int i=0;i<4;++i)f.captureAtmosphericTarget(i);
    double altitude=f.altitude()+500,speed=f.airRelativeVelocity().length(),rcs=f.rcs;
    check(f.setAtmosphericTarget(0,altitude)&&f.setAtmosphericTarget(3,Rad(110)),"Targets are accepted");
    check(f.setAtmosphericHold(0,true)&&f.setAtmosphericHold(1,true)&&f.setAtmosphericHold(3,true),"Atmospheric holds engage in flight");
    check(f.atmospheric.active[2],"Heading hold engages bank stabilization");
    run(f,120);
    std::cout<<"alt="<<f.altitude()<<" target="<<altitude<<" airspeed="<<f.airRelativeVelocity().length()<<" target="<<speed<<" heading="<<Deg(f.heading())<<" bank="<<Deg(f.bank())<<" throttle="<<f.throttle<<'\n';
    check(!f.impacted&&fabs(f.altitude()-altitude)<80,"Altitude hold approaches a new target in storm winds");
    check(fabs(f.airRelativeVelocity().length()-speed)<5,"Airspeed hold compensates for storm winds");
    check(fabs(std::remainder(f.heading()-Rad(110),Pi2))<Rad(3),"Heading hold turns toward its target");
    check(f.rcs==rcs,"Atmospheric stabilization uses aerodynamic controls, not RCS fuel");
    f.setMainThrottle(.2);check(!f.atmospheric.active[1]&&f.throttle==.2,"Manual throttle releases airspeed hold");
    check(f.setAtmosphericHold(1,true),"Airspeed hold can be reengaged");f.cutEngines();run(f,.1);
    check(!f.atmospheric.active[1]&&f.throttle==0,"Engine cutoff cannot be overridden by airspeed hold");
    Input pitch;pitch.pitch=.5;run(f,.1,pitch);check(!f.atmospheric.active[0],"Manual pitch releases altitude hold");
    Input roll;roll.roll=.5;run(f,.1,roll);check(!f.atmospheric.active[2]&&!f.atmospheric.active[3],"Manual roll releases bank and heading holds");
    Flight bank=atlantic();for(int i=0;i<4;++i)bank.captureAtmosphericTarget(i);
    check(bank.setAtmosphericTarget(2,Rad(15))&&bank.setAtmosphericHold(2,true)&&bank.setAtmosphericHold(0,true)&&bank.setAtmosphericHold(1,true),"Independent bank, altitude and speed holds engage");
    run(bank,40);check(fabs(bank.bank()-Rad(15))<Rad(2),"Bank hold reaches its target");
    check(bank.setAtmosphericTarget(2,Rad(-10))&&bank.setAtmosphericTarget(1,230),"Bank and speed targets can be changed while holding");
    run(bank,60);check(fabs(bank.bank()-Rad(-10))<Rad(2)&&fabs(bank.airRelativeVelocity().length()-230)<3,"Bank and airspeed follow updated targets");
    bank.setHoverThrottle(.1);check(!bank.atmospheric.engaged()&&!bank.setAtmosphericHold(0,true),"Hover thrust releases and prevents atmospheric holds");
    Flight o;for(int i=0;i<4;++i)o.captureAtmosphericTarget(i);check(!o.setAtmosphericHold(0,true),"Holds cannot engage in orbit");
    check(!f.setAtmosphericTarget(0,-1)&&!f.setAtmosphericTarget(1,NAN)&&!f.setAtmosphericTarget(2,Rad(70)),"Invalid targets are rejected");
    Flight manual=atlantic();for(int i=0;i<4;++i)manual.captureAtmosphericTarget(i);
    check(manual.setAtmosphericHold(0,true),"Altitude hold engages");manual.toggleAssist(Assist::Prograde);check(!manual.atmospheric.engaged(),"RCS nav program releases aerodynamic stabilization");
    std::cout<<"atmospheric control checks passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

#include "Flight.h"
#include "Surface.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool value,const char *message) {++checks;if(!value)throw std::runtime_error(message);}
void run(Flight &flight,double seconds,const Input &input={}) {
    for(int i=0;i<(int)ceil(seconds*120);++i)flight.advance(1./120,input);
}
Flight parked(double clearance=2.53) {
    Flight f;f.fuel=MainCapacity*.15;f.rcs=RcsCapacity*.5;
    f.glider.rcsMode=0;f.glider.parkingBrake=true;
    f.placeOnEarth(Rad(28.52257),Rad(-80.675645),Rad(153.89),clearance);return f;
}
int main() {try {
    for(double lat:{-89.,-45.,0.,28.52257,80.,90.})for(double lng:{-180.,-80.675645,0.,125.}) {
        auto frame=earthSurface(Rad(lat),Rad(lng),51982.5,1234);
        double a,b;earthCoordinates(frame.up*EarthRadius,51982.5,1234,a,b);
        check(fabs(a-Rad(lat))<1e-7,"surface latitude roundtrip");
        if(fabs(lat)<90)check(fabs(remainder(b-Rad(lng),Pi2))<1e-7,"surface longitude roundtrip");
        check(fabs(dotp(frame.up,frame.north))<1e-12,"surface basis orthogonal");
    }
    check(gliderContacts(true).size()==13&&gliderContacts(true)[0].position.y==-2.57,"original deployed touchdown points");
    check(!gliderContacts(false)[0].wheel&&gliderContacts(false)[0].position.y==-1.5,"original retracted touchdown points");
    Flight f=parked();double lat0,lng0;earthCoordinates(f.position,f.mjd,0,lat0,lng0);
    check(fabs(Deg(f.heading())-153.89)<1e-8&&fabs(f.pitch())<1e-10,"landed heading and level attitude");
    run(f,20);
    std::cout<<"settled alt="<<f.altitude()<<" gs="<<f.groundSpeed<<" wheels="<<f.wheelContacts<<" pitch="<<Deg(f.pitch())<<" crash="<<f.impacted<<'\n';
    check(!f.impacted,"parked glider does not crash");
    check(f.altitude()>2.3&&f.altitude()<2.7&&f.groundContact,"gear suspension supports weight");
    check(f.wheelContacts==3&&f.groundSpeed<.2,"three wheels settle without drift");
    double lat1,lng1;earthCoordinates(f.position,f.mjd,f.elapsed,lat1,lng1);
    check(fabs(lat1-lat0)<1e-5&&fabs(lng1-lng0)<1e-5,"parked glider follows Earth rotation");
    Flight coast=parked(),braked=parked();coast.glider.parkingBrake=braked.glider.parkingBrake=false;
    coast.velocity+=coast.forward*30;braked.velocity+=braked.forward*30;
    Input brake;brake.leftBrake=brake.rightBrake=1;
    run(coast,8);run(braked,8,brake);
    std::cout<<"rolling="<<coast.groundSpeed<<" braked="<<braked.groundSpeed<<" crash="<<braked.impacted<<'\n';
    check(!coast.impacted&&!braked.impacted,"ground roll remains stable");
    check(braked.groundSpeed<coast.groundSpeed*.2&&braked.groundSpeed<1,"wheel brakes stop forward motion");
    Flight taxi=parked();taxi.glider.parkingBrake=false;taxi.throttle=.05;run(taxi,8);
    check(!taxi.impacted&&taxi.groundSpeed>3&&taxi.groundContact,"main engines taxi on deployed wheels");
    Flight steer=parked();steer.glider.parkingBrake=false;steer.velocity+=steer.forward*8;
    double heading=steer.heading();Input turning;turning.yaw=.5;run(steer,5,turning);
    std::cout<<"steer heading delta="<<Deg(remainder(steer.heading()-heading,Pi2))<<" gs="<<steer.groundSpeed<<'\n';
    check(!steer.impacted&&fabs(remainder(steer.heading()-heading,Pi2))>Rad(3),"nose wheel steering changes heading");
    Flight hover=parked();hover.glider.hover=.95;run(hover,3);
    check(!hover.impacted&&hover.altitude()>10&&!hover.groundContact,"hover engines lift off from the ground");
    Flight soft=parked(4);soft.velocity-=soft.up;run(soft,15);
    check(!soft.impacted&&soft.groundContact&&soft.altitude()>2.3,"gentle landing settles onto suspension");
    Flight hard=parked(5);hard.velocity-=hard.up*30;run(hard,1);
    check(hard.impacted&&hard.paused,"hard impact is detected instead of tunneling through Earth");
    auto path=std::filesystem::temp_directory_path()/"orbiter-surface-test.scn";
    f.save(path);Flight restored;restored.load(path);std::filesystem::remove(path);
    check(restored.groundContact&&restored.glider.parkingBrake,"ground and parking brake state persist");
    check(restored.position.dist(f.position)<1e-6&&restored.velocity.dist(f.velocity)<1e-8,"landed Cartesian state persists");
    auto original=std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/Cape Canaveral.scn";
    Flight cape;cape.load(original);check(cape.groundContact&&cape.glider.part(Part::Gear).open(),"original Cape Canaveral scenario loads");
    run(cape,10);check(!cape.impacted&&cape.groundContact,"original Cape Canaveral scenario settles");
    std::cout<<"PASS: "<<checks<<" surface checks\n";return 0;
}catch(const std::exception &e){std::cerr<<"FAIL after "<<checks<<": "<<e.what()<<'\n';return 1;}}

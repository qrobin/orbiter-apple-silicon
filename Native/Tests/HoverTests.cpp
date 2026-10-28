#include "Flight.h"
#include "Surface.h"
#include "Cockpit.h"
#include "Mesh.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool value,const char *message){++checks;if(!value)throw std::runtime_error(message);}
void run(Flight &f,double seconds,double frame=.01,const Input &input={}) {
    for(int i=0;i<(int)std::round(seconds/frame);++i)f.advance(frame,input);
}
Flight cape(double height=2.53) {
    Flight f;f.fuel=MainCapacity*.15;f.rcs=RcsCapacity*.5;f.glider.rcsMode=0;
    f.placeOnEarth(Rad(28.52257),Rad(-80.675645),Rad(153.89),height);
    f.glider.parkingBrake=true;return f;
}
Vector rotate(Vector v,Vector axis,double angle) {
    return v*cos(angle)+crossp(axis,v)*sin(angle)+axis*dotp(axis,v)*(1-cos(angle));
}
void tilt(Flight &f,double pitch,double bank) {
    Vector axis=f.right;for(Vector *v:{&f.right,&f.up,&f.forward})*v=rotate(*v,axis,-pitch);
    axis=f.forward;for(Vector *v:{&f.right,&f.up,&f.forward})*v=rotate(*v,axis,-bank);
}
int main(){try {
    HoverControl h;h.attitudeMode=1;h.balance(.6,0,Rad(5),Rad(4),0,0);
    double total=140000*(h.levels[0]+(h.levels[1]+h.levels[2])*3/4.55*.5);
    check(fabs(total-.6*MaxHoverThrust)<1e-9,"attitude balancing preserves total thrust before saturation");
    check(3*140000*h.levels[0]<4.55*140000*3/4.55*.5*(h.levels[1]+h.levels[2]),"pitch-up error commands pitch-down torque");
    check(h.levels[2]>h.levels[1],"right bank error commands restoring roll torque");
    h.balance(.6,0,Rad(31),0,0,0);
    check(h.attitudeLimited&&h.levels[0]==.6&&h.levels[1]==.6&&h.levels[2]==.6,"outside original 30 degree envelope returns balanced thrust");
    h.balance(0,0,Rad(8),Rad(-5),0,0);
    check(h.levels[0]==0&&h.levels[1]==0&&h.levels[2]==0,"attitude controller cannot create thrust from zero throttle");
    h.attitudeMode=2;h.pitchTarget=Rad(10);h.bankTarget=Rad(-10);
    h.balance(.99,0,Rad(-29),Rad(29),-2,2);
    check(std::all_of(h.levels.begin(),h.levels.end(),[](double v){return v>=0&&v<=1;}),"saturated controller outputs are bounded");
    Flight launch=cape();double fuel=launch.fuel,rcs=launch.rcs;
    check(launch.setHoverHold(1,30)&&launch.glider.hoverControl.attitudeMode==1,"engaging hold enables automatic attitude when off");
    launch.warp=100;run(launch,60);
    std::cout<<"launch alt="<<launch.altitude()<<" vs="<<launch.surfaceVerticalSpeed()<<" pitch="<<Deg(launch.pitch())<<" bank="<<Deg(launch.bank())<<" fuel="<<launch.fuel<<'\n';
    check(!launch.impacted&&!launch.groundContact&&launch.warp==1,"altitude hold lifts off at real time");
    check(fabs(launch.altitude()-30)<.5&&fabs(launch.surfaceVerticalSpeed())<.1,"altitude hold settles within half a metre");
    check(fabs(launch.pitch())<Rad(1)&&fabs(launch.bank())<Rad(1),"hover attitude remains level without RCS");
    check(launch.fuel<fuel&&launch.rcs==rcs,"hold consumes main propellant and no RCS fuel");
    launch.setHoverHold(1,80);run(launch,60);
    check(fabs(launch.altitude()-80)<.5,"changing altitude target tracks the new height");
    launch.setHoverHold(1,0);run(launch,80);
    std::cout<<"landing alt="<<launch.altitude()<<" vs="<<launch.surfaceVerticalSpeed()<<" wheels="<<launch.wheelContacts<<'\n';
    check(!launch.impacted&&launch.groundContact&&launch.wheelContacts==3,"low target produces a gentle landing on the spherical surface");
    Flight disturbed=cape(100);disturbed.glider.hover=.56;tilt(disturbed,Rad(8),Rad(6));
    disturbed.setHoverHold(1,100);run(disturbed,60);
    std::cout<<"disturbed alt="<<disturbed.altitude()<<" pitch="<<Deg(disturbed.pitch())<<" bank="<<Deg(disturbed.bank())<<'\n';
    check(!disturbed.impacted&&fabs(disturbed.pitch())<Rad(1)&&fabs(disturbed.bank())<Rad(1),"attitude hold recovers a pitch and bank disturbance");
    check(fabs(disturbed.altitude()-100)<1,"height is recovered after the attitude disturbance");
    Flight manual=cape(100);manual.glider.hover=.56;manual.setHoverHold(1,100);
    auto &manualControl=manual.glider.hoverControl;manualControl.attitudeMode=2;
    manualControl.pitchTarget=Rad(3);manualControl.bankTarget=Rad(-2);run(manual,15);
    check(fabs(Deg(manual.pitch())-3)<.5&&fabs(Deg(manual.bank())+2)<.5,"manual hover attitude tracks pitch and bank targets");
    Flight keyboard=cape(100);keyboard.glider.hover=.56;keyboard.glider.rcsMode=1;keyboard.setHoverHold(1,100);
    Input command;command.pitch=-.5;command.roll=.3;double keyboardRCS=keyboard.rcs;run(keyboard,10,.01,command);
    check(fabs(Deg(keyboard.glider.hoverControl.pitchTarget)-5)<1e-10&&fabs(Deg(keyboard.glider.hoverControl.bankTarget)+3)<1e-10,"automatic hover accepts bounded manual tilt commands");
    check(keyboard.rcs==keyboardRCS,"hover tilt commands do not fire competing pitch and roll RCS jets");
    Flight varying=cape();varying.setHoverHold(1,30);
    for(int i=0;i<1000;++i)for(double dt:{.1,.003,.033,.01})varying.advance(dt);
    check(!varying.impacted&&fabs(varying.altitude()-30)<.5&&fabs(varying.surfaceVerticalSpeed())<.1,"hover feedback tolerates varying frame steps");
    Flight vertical=cape(50);vertical.glider.hover=.56;vertical.setHoverHold(2,2);run(vertical,25);
    std::cout<<"vs climb="<<vertical.surfaceVerticalSpeed()<<" alt="<<vertical.altitude()<<'\n';
    check(!vertical.impacted&&fabs(vertical.surfaceVerticalSpeed()-2)<.1,"vertical speed hold maintains a commanded climb");
    vertical.setHoverHold(2,-1);run(vertical,15);
    check(fabs(vertical.surfaceVerticalSpeed()+1)<.1,"vertical speed hold tracks a commanded descent");
    double level=vertical.glider.hover;vertical.glider.hoverControl.holdActive=false;
    run(vertical,.1);check(vertical.glider.hover==level,"disengagement leaves the existing throttle unchanged");
    vertical.setHoverHold(1,100);vertical.setHoverThrottle(.25);run(vertical,.1);
    check(!vertical.glider.hoverControl.holdActive&&vertical.glider.hover==.25,"manual hover override disengages hold");
    vertical.setHoverHold(1,100);vertical.cutEngines();run(vertical,.1);
    check(!vertical.glider.hoverControl.holdActive&&vertical.glider.hover==0&&vertical.glider.hoverLevel==0,"emergency cutoff cannot be overridden by hold");
    Flight heavy=cape();heavy.fuel=MainCapacity;heavy.rcs=RcsCapacity;heavy.setHoverHold(1,100);run(heavy,15);
    check(heavy.groundContact&&!heavy.impacted&&heavy.glider.hoverControl.thrustLimited,"overweight glider stays grounded and reports thrust saturation");
    Flight dry=cape(100);dry.fuel=.0001;dry.setHoverHold(1,100);run(dry,1);
    check(dry.fuel==0&&!dry.glider.hoverControl.holdActive&&dry.glider.hoverLevel==0,"fuel exhaustion disengages hold and removes thrust");
    Flight fast=cape();fast.setHoverHold(1,30);run(fast,60,.05);
    check(fabs(fast.altitude()-30)<.5,"hold is stable at a slower rendering cadence");
    Vector before=fast.position;double oldThrottle=fast.glider.hover;fast.paused=true;run(fast,1);
    check(fast.position.dist(before)==0&&fast.glider.hover==oldThrottle,"pause freezes the hover controller with flight state");
    Flight orbital;check(!orbital.setHoverHold(1,100),"orbital flight rejects surface-only hover hold");
    check(!fast.setHoverHold(2,21)&&!fast.setHoverHold(1,-1),"invalid target commands are rejected");
    auto path=std::filesystem::temp_directory_path()/"orbiter-hover-test.scn";
    fast.paused=false;fast.glider.hoverControl.attitudeMode=2;fast.glider.hoverControl.pitchTarget=Rad(2);fast.glider.hoverControl.bankTarget=Rad(-1);
    fast.save(path);Flight restored;restored.load(path);std::filesystem::remove(path);
    auto &r=restored.glider.hoverControl;
    check(r.holdActive&&r.holdMode==1&&r.altitudeTarget==30&&r.attitudeMode==2&&fabs(r.pitchTarget-Rad(2))<1e-14,"original hover scenario fields round-trip");
    restored.glider.hoverControl.attitudeMode=1;run(restored,10);
    check(fabs(restored.altitude()-30)<.5&&std::isfinite(restored.position.length()),"restored hold restarts derivative feedback cleanly");
    Glider original;check(original.parse("HOVERMODE 2 0.05 -0.03")&&original.parse("HOVERHOLD 1 2 100 -1")&&original.valid(),"original manual attitude and vertical speed keys load");
    Glider invalid;invalid.parse("HOVERMODE 4");check(!invalid.valid(),"out-of-range hover mode is invalid");
    invalid=Glider();invalid.parse("HOVERHOLD 1 1 -1 0");check(!invalid.valid(),"negative altitude target is invalid");
    auto root=std::filesystem::path(ORBITER_TEST_DATA);
    auto cockpit=loadMesh(root/"Src/Vessel/DeltaGlider/Meshes/deltaglider_vc.msh");
    for(const auto &control:cockpitSwitches())
        check(control.group>=0&&size_t(control.group)<cockpit.groups.size()&&control.first>=0&&size_t(control.first+control.count)<=cockpit.groups[control.group].vertices.size(),"cockpit control addresses a valid original vertex range");
    Vector eye(0,1.467,6.782);
    for(const auto &zone:cockpitZones())if(zone.action>=40) {
        Vector center=(zone.corners[0]+zone.corners[3])*.5;
        check(pickCockpit(eye,(center-eye).unit()).action==zone.action,"original hover quadrilateral is reachable from the pilot eye");
    }
    for(const auto &sphere:cockpitSpheres())
        check(pickCockpit(eye,(sphere.center-eye).unit()).action==sphere.action,"original spherical hover button is reachable from the pilot eye");
    auto readout=loadDDS(root/"Src/Vessel/DeltaGlider/Textures/blittgt1.dds");
    auto glyphs=loadDDS(root/"Src/Vessel/DeltaGlider/Textures/blitsrc1.dds");auto originalReadout=readout.rgba;
    HoverControl indicator;indicator.holdActive=true;indicator.altitudeTarget=100;
    check(paintHoverReadout(readout,glyphs,indicator)&&readout.rgba!=originalReadout,"original hover numeric display updates from live controller state");
    auto altitudeReadout=readout.rgba;indicator.holdMode=2;indicator.holdActive=false;indicator.verticalSpeedTarget=-1.5;
    check(paintHoverReadout(readout,glyphs,indicator)&&readout.rgba!=altitudeReadout,"hover readout changes mode, target and engagement indication");
    bool outsideUnchanged=true;
    for(size_t y=0;y<readout.height;++y)for(size_t x=0;x<readout.width;++x)if(x<314||x>=394||y<2||y>=23)
        for(int channel=0;channel<4;++channel)outsideUnchanged&=readout.rgba[(y*readout.width+x)*4+channel]==originalReadout[(y*readout.width+x)*4+channel];
    check(outsideUnchanged,"live hover blits preserve unrelated original cockpit texture regions");
    Flight practice;practice.load(root/"Native/Assets/Scenarios/Cape Canaveral hover.scn");run(practice,60);
    check(!practice.impacted&&practice.glider.hoverControl.holdActive&&fabs(practice.altitude()-100)<.5,"bundled practice flight launches and holds 100 metres");
    std::cout<<"PASS: "<<checks<<" hover checks\n";return 0;
}catch(const std::exception &e){std::cerr<<"FAIL after "<<checks<<": "<<e.what()<<'\n';return 1;}}

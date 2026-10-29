#include "Flight.h"
#include "Cockpit.h"
#include "Mesh.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static int checks=0;
static void check(bool ok,const char *message){++checks;if(!ok)throw std::runtime_error(message);}
static void run(Flight &f,double seconds){for(int i=0;i<int(seconds*100);++i)f.advance(.01);}
static Flight orbit(){
    Flight f;f.position={EarthRadius+400000,0,0};f.velocity={0,0,sqrt(Mu/f.position.length())};
    f.align(f.velocity);f.angularVelocity={};f.assist=Assist::Free;return f;
}
int main(){try{
    Flight mode=orbit();mode.warp=10;mode.toggleAssist(Assist::Prograde);
    check(mode.assistActive(Assist::Prograde),"Selecting a nav program engages it");
    mode.toggleAssist(Assist::Prograde);check(mode.assist==Assist::Free,"Selecting an active program turns it off");
    mode.toggleAssist(Assist::HorizonLevel);mode.toggleAssist(Assist::KillRotation);
    check(mode.assistActive(Assist::HorizonLevel)&&mode.assistActive(Assist::KillRotation),"Kill rotation can coexist with horizon level");
    mode.toggleAssist(Assist::Normal);check(mode.assistActive(Assist::Normal)&&mode.assistActive(Assist::HorizonLevel)&&!mode.assistActive(Assist::KillRotation),"Pointing replaces kill rotation while retaining horizon level");
    mode.toggleAssist(Assist::HorizonLevel);check(mode.assistActive(Assist::Normal)&&!mode.assistActive(Assist::HorizonLevel),"Disabling horizon level preserves the pointing program");
    mode.toggleAssist(Assist::HorizonLevel);mode.toggleAssist(Assist::Normal);
    check(mode.assistActive(Assist::HorizonLevel)&&mode.assist==Assist::HorizonLevel,"Disabling a pointing program preserves horizon level");
    mode.toggleAssist(Assist::KillRotation);mode.toggleAssist(Assist::KillRotation);
    check(mode.assistActive(Assist::HorizonLevel)&&!mode.assistActive(Assist::KillRotation),"Kill rotation can be toggled off without releasing horizon level");
    mode.toggleAssist(Assist::KillRotation);mode.toggleAssist(Assist::HorizonLevel);
    check(mode.assist==Assist::KillRotation&&!mode.assistActive(Assist::HorizonLevel),"Horizon level can be toggled off while retaining kill rotation");
    for(auto program:{Assist::Prograde,Assist::Retrograde,Assist::Normal,Assist::AntiNormal}){
        Flight f=orbit();double fuel=f.rcs;f.toggleAssist(program);run(f,100);
        Vector normal=crossp(f.velocity,f.position).unit();
        Vector target=program==Assist::Prograde?f.velocity.unit():program==Assist::Retrograde?-f.velocity.unit():program==Assist::Normal?normal:-normal;
        check(dotp(f.forward,target)>.995,"Nav program points the nose at its moving target");
        check(f.rcs<fuel&&f.throttle==0,"Nav alignment uses RCS fuel and leaves main engines alone");
        if(program==Assist::Prograde||program==Assist::Retrograde){
            double planetRight=dotp(f.right,-f.position.unit());
            check(program==Assist::Prograde?planetRight<-.98:planetRight>.98,"Planet is left in prograde and right in retrograde");
        }
    }
    for(auto program:{Assist::Prograde,Assist::Retrograde,Assist::Normal,Assist::AntiNormal}){
        Flight f=orbit();f.toggleAssist(program);f.toggleAssist(Assist::HorizonLevel);run(f,120);
        Vector radial=f.position.unit(),normal=crossp(f.velocity,f.position).unit();
        Vector target=program==Assist::Prograde?f.velocity.unit():program==Assist::Retrograde?-f.velocity.unit():program==Assist::Normal?normal:-normal;
        check(f.assistActive(program)&&f.assistActive(Assist::HorizonLevel)&&dotp(f.forward,target)>.995,"Horizon level retains the selected pointing direction");
        Vector expected=(radial-f.forward*dotp(radial,f.forward)).unit();
        check(dotp(f.up,expected)>.98,"Horizon level aligns the remaining roll axis to local up");
    }
    Flight planned=orbit();planned.maneuverDirection=(planned.velocity.unit()+planned.position.unit()*.4).unit();planned.assist=Assist::Maneuver;
    planned.toggleAssist(Assist::HorizonLevel);run(planned,120);
    check(dotp(planned.forward,planned.maneuverDirection)>.995&&planned.assistActive(Assist::HorizonLevel),"Horizon level combines with planned maneuver pointing");
    Vector planUp=(planned.position.unit()-planned.forward*dotp(planned.position.unit(),planned.forward)).unit();
    check(dotp(planned.up,planUp)>.98,"Planned maneuver uses horizon-level roll");
    Flight level=orbit();Vector radial=level.position.unit();level.forward=(radial+level.velocity.unit()).unit();
    level.right=crossp(radial,level.forward).unit();level.up=crossp(level.forward,level.right).unit();
    level.toggleAssist(Assist::HorizonLevel);run(level,90);
    check(fabs(level.pitch())<.03&&fabs(level.bank())<.03,"Horizon level removes pitch and bank");
    Flight stop=orbit();stop.angularVelocity={.2,-.1,.15};stop.toggleAssist(Assist::KillRotation);run(stop,20);
    check(stop.angularVelocity.length()<1e-4&&stop.assist==Assist::Free,"Kill rotation damps and releases after stopping");
    Flight dry=orbit();dry.rcs=0;Vector old=dry.forward;dry.toggleAssist(Assist::Retrograde);run(dry,5);
    check(dry.rcs==0&&dry.forward.dist(old)<1e-12,"An empty RCS supply cannot rotate the craft");
    for(auto program:{Assist::Prograde,Assist::Retrograde,Assist::Normal,Assist::AntiNormal})for(int radial=0;radial<2;++radial){
        Flight f=orbit();f.velocity=radial?f.position.unit()*20:Vector{};f.toggleAssist(program);run(f,2);
        check(std::isfinite(f.forward.length())&&std::isfinite(f.up.length())&&std::isfinite(f.rcs),"Stationary and radial motion never produce an undefined nav attitude");
    }
    Flight manualOff=orbit();manualOff.glider.rcsMode=0;manualOff.toggleAssist(Assist::Prograde);double fuel=manualOff.rcs;run(manualOff,5);
    check(manualOff.rcs<fuel,"The navigation computer works with the manual RCS dial off");
    Flight accelerated=orbit();accelerated.toggleAssist(Assist::Retrograde);accelerated.warp=10;old=accelerated.forward;fuel=accelerated.rcs;run(accelerated,1);
    check(accelerated.forward.dist(old)<1e-12&&accelerated.rcs==fuel,"Time acceleration does not teleport attitude or consume phantom RCS");
    const double vcX[]={.119,.373,.373,.627,.627,.881},vcY[]={.24,.24,.76,.24,.76,.24};
    const double panelX[]={1142,1179,1179,1216,1216,1253},panelY[]={98,98,74,98,74,98};
    for(int i=0;i<6;++i){
        check(cockpitNavButton(vcX[i],vcY[i])==i,"3D cockpit nav hit targets map to the original buttons");
        check(panelNavButton(panelX[i],panelY[i])==i&&pickPanel2D(panelX[i],panelY[i]).action==400+i,"2D panel nav targets match the 3D cockpit");
        Vector eye{0,1.467,6.782},point{.10191+vcX[i]*.07618,1.25710+vcY[i]*.02930,7.26800};auto hit=pickCockpit(eye,(point-eye).unit());
        check(hit.action==60&&cockpitNavButton(hit.u,hit.v)==i,"Pilot's ray reaches the corresponding original VC button");
    }
    check(cockpitNavButton(.1,.8)==6&&panelNavButton(1140,74)==6,"Both panels expose the planned-burn RCS button");
    check(cockpitNavButton(.9,.8)==-1&&panelNavButton(1250,74)==-1,"The remaining empty cells do not activate navigation programs");
    auto burnButton=maneuverButtonArtwork(false),litBurnButton=maneuverButtonArtwork(true);
    check(burnButton.width==128&&burnButton.height==64&&burnButton.rgba!=litBurnButton.rgba,"The burn button has visible inactive and active artwork");
    check(cockpitNavButton(42./169,.2)==-1,"The gaps between 3D buttons are inactive");
    Hud hud;hud.select(3);hud.adjustBrightness(-.63);hud.cycleColour();
    check(hud.mode==3&&fabs(hud.brightness-.37)<1e-9&&hud.colour==1,"HUD mode, brightness and colour respond independently");
    hud.adjustBrightness(-10);check(hud.brightness==0,"HUD brightness clamps to zero");hud.adjustBrightness(10);check(hud.brightness==1,"HUD brightness clamps to one");
    Flight saved=orbit();saved.hud=hud;saved.hud.select(2);auto path=std::filesystem::temp_directory_path()/"orbiter-nav-hud-test.scn";saved.save(path);Flight loaded;loaded.load(path);std::filesystem::remove(path);
    check(loaded.hud.mode==2&&loaded.hud.colour==1&&loaded.hud.brightness==1,"HUD settings survive scenario save and reload");
    std::cout<<checks<<" navigation program checks passed\n";
}catch(const std::exception &e){std::cerr<<"After "<<checks<<" checks: "<<e.what()<<'\n';return 1;}}

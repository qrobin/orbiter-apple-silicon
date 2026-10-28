#include "Exhaust.h"
#include <iostream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool ok,const char *name){++checks;if(!ok)throw std::runtime_error(name);}
int main(){try {
    Flight f;check(gliderExhaust(f).empty(),"No jets at idle");
    f.glider.mainLevel=.7;f.glider.mainBalance=.3;f.glider.gimbalPitch=.8;
    auto e=gliderExhaust(f);check(e.size()==2,"Two main engines");check(fabs(e[0].level-.49)<1e-10,"Main engine balance");check(e[0].direction.y<0,"Exhaust opposes gimbal thrust");
    f.cutEngines();f.glider.hoverControl.levels={.2,.4,.8};e=gliderExhaust(f);check(e.size()==3,"Three independent hover engines");check(e[2].level==.8,"Actual hover mixer output");
    f.cutEngines();
    for(int axis=0;axis<3;++axis)for(double sign:{-1.,1.}) {
        f.glider.rcsRotation={};f.glider.rcsTranslation={};f.glider.rcsRotation(axis)=sign;
        e=gliderExhaust(f);check(!e.empty(),"Both signs of every rotation axis emit");Vector force,torque;
        for(auto &j:e){check(fabs(j.direction.length()-1)<1e-10,"Unit nozzle direction");auto thrust=-j.direction*j.level;force+=thrust;torque+=crossp(j.position,thrust);}
        check(torque(axis)*sign>0,"RCS plume torque matches flight torque");
        f.glider.rcsRotation={};f.glider.rcsTranslation(axis)=sign;e=gliderExhaust(f);force={};
        for(auto &j:e)force-=j.direction*j.level;
        check(force(axis)*sign>0,"RCS plume force matches translation");
    }
    f.glider.rcsMode=0;check(gliderExhaust(f).empty(),"RCS-off suppresses all jets");
    f.glider.rcsMode=1;f.rcs=0;f.advance(.01,Input{1,1,1});check(gliderExhaust(f).empty(),"Empty RCS tank suppresses jets");
    auto ground=plumeShape(0,ExhaustKind::Main),space=plumeShape(200000,ExhaustKind::Main);
    check(space.spread>ground.spread,"Exhaust expands in vacuum");check(space.lifetime>ground.lifetime,"Vacuum plume persists longer");
    std::cout<<checks<<" exhaust checks passed\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

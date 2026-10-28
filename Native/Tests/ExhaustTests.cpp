#include "Exhaust.h"
#include "Mesh.h"
#include "SolarSystem.h"
#include <algorithm>
#include <limits>
#include <iostream>
#include <stdexcept>
using namespace native;
int checks=0;
void check(bool ok,const char *name){++checks;if(!ok)throw std::runtime_error(name);}
int main(){try {
    Flight f;check(gliderExhaust(f).empty(),"No jets at idle");
    f.glider.mainLevel=.7;f.glider.mainBalance=.3;f.glider.gimbalPitch=.8;
    auto e=gliderExhaust(f);check(e.size()==2,"Two main engines");check(fabs(e[0].level-.49)<1e-10,"Main engine balance");check(e[0].direction.y<0,"Exhaust opposes gimbal thrust");
    check(e[0].id==0&&e[1].id==1,"Main nozzles have stable identities");
    f.glider.mainBalance=1;auto one=gliderExhaust(f);check(one.size()==1&&one[0].id==1,"A nozzle keeps its identity when another stops");f.glider.mainBalance=.3;
    const auto mesh=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh");
    for(const auto &nozzle:e){
        double lip=std::numeric_limits<double>::infinity();
        for(const auto &group:mesh.groups)for(const auto &v:group.vertices)
            if(fabs(v.x-nozzle.position.x)<.8&&fabs(v.y)<.8&&v.z<-7.6)lip=std::min(lip,double(v.z));
        check(std::isfinite(lip),"Main nozzle rim exists in original mesh");
        check(fabs(nozzle.position.z-lip)<.002,"Visual exhaust starts at original nozzle lip, not interior thrust point");
    }
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
    f.assist=Assist::Normal;check(!gliderExhaust(f).empty(),"RCS navigation jets remain visible with the manual RCS dial off");f.clearAssist();
    f.glider.rcsMode=1;f.rcs=0;f.advance(.01,Input{1,1,1});check(gliderExhaust(f).empty(),"Empty RCS tank suppresses jets");
    auto ground=plumeShape(0,ExhaustKind::Main),space=plumeShape(200000,ExhaustKind::Main);
    check(space.spread>ground.spread,"Exhaust expands in vacuum");check(space.lifetime>ground.lifetime,"Vacuum plume persists longer");
    Flight aircraft;aircraft.position={EarthRadius+5000,0,0};aircraft.velocity={0,0,250};aircraft.glider.mainLevel=1;
    ExhaustTrail trail;for(int i=0;i<1200;++i){aircraft.position+=aircraft.velocity*.1;trail.update(aircraft,.1);}
    check(trail.puffs().size()>1000&&trail.puffs().size()<ExhaustTrail::capacity,"Atmospheric engines leave a bounded continuous trail");
    double length=0;for(const auto &p:trail.puffs())length=std::max(length,p.position.dist(aircraft.position));
    check(length>20000,"A moving craft leaves many kilometres of world-anchored trail");
    check(trail.puffs().front().age>100&&trail.puffs().back().age<1,"Old puffs persist and new puffs are emitted");
    auto young=trail.puffs().front();young.age=0;auto old=young;old.age=120;
    check(exhaustTrailRadius(old)>exhaustTrailRadius(young)+20,"Smoke broadens as it disperses in the atmosphere");
    aircraft.glider.mainLevel=0;size_t beforeCut=trail.puffs().size();Vector oldPuff=trail.puffs().front().position;aircraft.position+=Vector(10000,0,0);trail.update(aircraft,.1);
    check(!trail.puffs().empty()&&trail.puffs().size()<=beforeCut&&trail.puffs().front().position.dist(oldPuff)<100,"Engine cutoff retains the existing world-anchored trail");
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");aircraft.changeReference(BodyId::Sun);trail.update(aircraft,.1);
    check(!trail.puffs().empty()&&trail.puffs().front().body==BodyId::Earth,"Smoke remains attached to its emitting body after a reference change");
    trail.update(aircraft,241);check(trail.puffs().empty(),"Trail disperses after shutdown rather than following the ship forever");
    aircraft.reference=BodyId::Earth;aircraft.velocity={0,0,250};
    aircraft.position={EarthRadius+400000,0,0};aircraft.glider.mainLevel=1;trail.reset();
    for(int i=0;i<120;++i){aircraft.position+=aircraft.velocity*.1;trail.update(aircraft,.1);}
    check(!trail.puffs().empty()&&std::all_of(trail.puffs().begin(),trail.puffs().end(),[](const auto &p){return p.vacuum;}),"Vacuum produces a thin expanding gas plume rather than atmospheric smoke");
    auto gas=trail.puffs().front();gas.age=10;check(exhaustTrailRadius(gas)>100,"Rarefied gas expands into a broad plume");
    length=0;for(const auto &p:trail.puffs())length=std::max(length,p.position.dist(aircraft.position));check(length>10000,"Vacuum exhaust expands for many kilometres behind a sustained burn");
    aircraft.glider.mainLevel=0;trail.update(aircraft,25);check(trail.puffs().empty(),"The vacuum plume fades after engine shutdown");
    aircraft.glider.mainLevel=1;
    double low=0,high=150000;for(int i=0;i<40;++i){double mid=(low+high)*.5;if(earthAtmosphere(mid).p/101325.>3e-4)low=mid;else high=mid;}
    aircraft.position={EarthRadius+(low+high)*.5,0,0};trail.reset();trail.update(aircraft,.2);
    bool hasAir=false,hasGas=false;for(const auto &p:trail.puffs()){hasGas|=p.vacuum;hasAir|=!p.vacuum;}
    check(hasAir&&hasGas,"Atmospheric and rarefied plumes overlap smoothly during ascent");
    aircraft.position={EarthRadius+5000,0,0};trail.reset();ExhaustTrail fine;
    Flight coarseFlight=aircraft,fineFlight=aircraft;
    for(int i=0;i<120;++i){coarseFlight.position+=coarseFlight.velocity*.1;trail.update(coarseFlight,.1);}
    for(int i=0;i<1200;++i){fineFlight.position+=fineFlight.velocity*.01;fine.update(fineFlight,.01);}
    check(std::abs((int)trail.puffs().size()-(int)fine.puffs().size())<=2,"Trail emission is independent of frame rate");
    check(trail.puffs().front().position.dist(fine.puffs().front().position)<30,"Trail positions interpolate across frames");
    fine.reset();check(fine.puffs().empty(),"Scenario reset clears the old trail");
    std::cout<<checks<<" exhaust checks passed\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

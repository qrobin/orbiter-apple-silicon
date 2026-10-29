#include "Exhaust.h"
#include "Mesh.h"
#include "SolarSystem.h"
#include <algorithm>
#include <limits>
#include <set>
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
    auto segments=trail.segments(aircraft);check(segments.size()>1000,"Exhaust samples form continuous per-nozzle volumes");
    for(const auto &s:segments)check(s.stream>0&&s.nozzle<2&&s.start.radius>0&&s.end.radius>0,"Every segment retains its nozzle and valid physical volume");
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
    segments=trail.segments(aircraft);Vector nozzle=aircraft.position+aircraft.forward*(-8.043);
    for(const auto &s:segments){
        check(dotp(s.start.position-nozzle,aircraft.forward)<.1&&dotp(s.end.position-nozzle,aircraft.forward)<.1,"Vacuum plume geometry cannot extend ahead of the nozzle");
        check(dotp((s.end.position-s.start.position).unit(),aircraft.forward)>.98,"Neighbouring vacuum emissions follow a coherent nozzle path");
    }
    auto gas=trail.puffs().front();gas.age=10;check(exhaustTrailRadius(gas)>100,"Rarefied gas expands into a broad plume");
    length=0;for(const auto &p:trail.puffs())length=std::max(length,p.position.dist(aircraft.position));check(length>10000,"Vacuum exhaust expands for many kilometres behind a sustained burn");
    aircraft.glider.mainLevel=0;for(int i=0;i<10;++i){aircraft.position+=aircraft.velocity*.1;trail.update(aircraft,.1);}
    aircraft.glider.mainLevel=1;for(int i=0;i<20;++i){aircraft.position+=aircraft.velocity*.1;trail.update(aircraft,.1);}
    segments=trail.segments(aircraft);std::set<uint64_t> streams;double longest=0;
    for(const auto &s:segments){streams.insert(s.stream);longest=std::max(longest,s.start.position.dist(s.end.position));}
    check(streams.size()==4&&longest<400,"Cutting and restarting the engines never bridges the gap between burns");
    Flight turning;turning.position={EarthRadius+400000,0,0};turning.velocity={0,0,250};turning.align({0,0,1});turning.glider.mainLevel=1;
    ExhaustTrail turnTrail;turnTrail.update(turning,.1);turning.align({1,0,0});turnTrail.update(turning,.3);
    std::vector<Vector> directions;for(const auto &p:turnTrail.puffs())if(p.nozzle==0&&p.vacuum)directions.push_back((p.velocity-turning.velocity).unit());
    check(directions.size()>=2&&dotp(directions[0],directions[1])<.98,"Emissions interpolate the nozzle direction as the spacecraft turns");
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
    Flight weather;weather.position={EarthRadius+5000,0,0};weather.velocity={0,0,250};weather.glider.mainLevel=1;
    ExhaustTrail changing;for(int i=0;i<200;++i){weather.position+=weather.velocity;changing.update(weather,1,i>=20&&i<30?0:1);}
    double widest=0;for(const auto &s:changing.segments(weather))widest=std::max(widest,s.start.position.dist(s.end.position));
    check(widest<200,"Expired samples cannot create a false bridge across a gap in the trail");
    Flight io;io.reference=BodyId::Io;io.position={io.centralBody().radius+113000,0,0};io.velocity={0,0,1487};io.align(io.velocity);io.clearAssist();io.throttle=1;
    ExhaustTrail ioTrail;for(int i=0;i<250;++i){io.advance(.1);ioTrail.update(io,.1);}
    auto ioSegments=ioTrail.segments(io);check(ioSegments.size()>100,"An Io engine burn creates connected vacuum volumes");
    for(const auto &s:ioSegments){Vector tip=io.position-io.forward*8.043;check(dotp(s.start.position-tip,io.forward)<1&&dotp(s.end.position-tip,io.forward)<1,"Io burn leaves no spurious volume in front of the ship");}
    // Existing exhaust must evolve identically even if its source moves, turns or accelerates.
    Flight source;source.reference=BodyId::Io;source.position={source.centralBody().radius+113000,0,0};source.velocity={0,0,1487};source.align(source.velocity);source.glider.mainLevel=1;
    ExhaustTrail released;for(int i=0;i<20;++i){source.position+=source.velocity*.1;released.update(source,.1);}
    size_t previousCount=released.puffs().size();Vector priorPosition=released.puffs().front().position;ExhaustTrail control=released;Flight moved=source,unmoved=source;
    moved.position+=Vector(12000,-7000,3000);moved.velocity+=Vector(-3000,2000,5000);moved.align({1,0,0});
    released.update(moved,.1);control.update(unmoved,.1);
    for(size_t i=0;i<previousCount;++i){
        check(released.puffs()[i].position.dist(control.puffs()[i].position)<1e-8,"Released exhaust position ignores subsequent source motion and rotation");
        check(released.puffs()[i].velocity.dist(control.puffs()[i].velocity)<1e-8,"Released exhaust velocity ignores subsequent source acceleration");
    }
    check(released.puffs().front().position.dist(priorPosition)>1,"Released exhaust still drifts naturally through space");
    Vector cameraOffset{60,35,-120},beforeCamera,afterCamera,changedReferenceCamera;
    ExhaustCameraFrame beforeFrame(source,cameraOffset),afterFrame(moved,cameraOffset+source.position-moved.position);
    const auto &worldPoint=released.puffs().front();
    check(beforeFrame.relative(worldPoint.body,worldPoint.position,beforeCamera)&&afterFrame.relative(worldPoint.body,worldPoint.position,afterCamera)&&beforeCamera.dist(afterCamera)<1e-8,"A fixed camera sees the same smoke when the vessel moves and turns");
    Flight changedReference=source;changedReference.changeReference(BodyId::Sun);ExhaustCameraFrame changedFrame(changedReference,cameraOffset);
    check(changedFrame.relative(worldPoint.body,worldPoint.position,changedReferenceCamera)&&beforeCamera.dist(changedReferenceCamera)<.001,"A reference-body change leaves the smoke in the same world position");
    Flight spin;spin.reference=BodyId::Io;spin.position={spin.centralBody().radius+113000,0,0};spin.velocity={0,0,0};spin.align({0,0,1});
    spin.angularVelocity={0,1,0};spin.glider.mainLevel=1;ExhaustTrail spinning;spinning.update(spin,.15);
    auto nozzleJet=gliderExhaust(spin).front();auto world=[&](Vector v){return spin.right*v.x+spin.up*v.y+spin.forward*v.z;};
    Vector expected=spin.velocity+crossp(world(spin.angularVelocity),world(nozzleJet.position))+world(nozzleJet.direction)*1600;
    check(!spinning.puffs().empty()&&spinning.puffs().front().velocity.dist(expected)<1e-8,"New exhaust inherits the nozzle's rotation only at release");
    std::cout<<checks<<" exhaust checks passed\n";
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

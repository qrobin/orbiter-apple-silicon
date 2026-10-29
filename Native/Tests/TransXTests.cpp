#include "Session.h"
#include "Flight.h"
#include "SolarSystem.h"
#include "orbitelements.h"
#include "Cockpit.h"
#include "Mesh.h"
#include "mfd.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace native;
static int checks;
static void check(bool ok,const std::string&why){++checks;if(!ok)throw std::runtime_error(why);}
static std::string words(const transx::Frame&frame){std::string s;for(auto&c:frame.commands)if(c.kind==oapi::DrawCommand::Text)s+=c.text+'\n';return s;}
static std::vector<int> geometry(const transx::Frame &frame){std::vector<int> out;for(const auto &c:frame.commands){if(c.kind==oapi::DrawCommand::Text)continue;
    out.insert(out.end(),{int(c.kind),c.x,c.y,c.x2,c.y2});for(auto p:c.points){out.push_back(p.x);out.push_back(p.y);}}
    return out;}
int main(){try{
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    Flight f;f.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    transx::Session session(f);for(int i=0;i<100;++i)session.tick();
    auto first=session.frame(0);std::cout<<words(first);check(first.ready,"Original TransX MFD initializes");
    check(!first.commands.empty()&&!first.variables.empty(),"Original MFD plots and variables are available");
    check(first.stage==1&&first.view==2,"Original initial stage and setup view");
    check(words(first).find("Earth")!=std::string::npos,"TransX is bound to native Earth flight");
    auto rightBefore=session.frame(1),beforeRotation=session.frame(0);Vector position=f.position,velocity=f.velocity;
    session.rotateGraph(0,95,65);auto rotated=session.frame(0);
    check(geometry(rotated)!=geometry(beforeRotation),"Dragging rotates the 3D TransX orbit geometry");
    check(words(rotated)==words(beforeRotation),"Graph rotation leaves original values and labels unchanged");
    check(geometry(session.frame(1))==geometry(rightBefore),"Graph viewpoints are independent between MFDs");
    check(f.position.dist(position)==0&&f.velocity.dist(velocity)==0,"Graph rotation does not change the flight state");
    session.resetGraph(0);check(geometry(session.frame(0))==geometry(beforeRotation),"Reset restores the original TransX projection");
    VECTOR3 p,v;oapiGetRelativePos(oapiGetFocusObject(),oapiGetGbodyByName("Earth"),&p);oapiGetRelativeVel(oapiGetFocusObject(),oapiGetGbodyByName("Earth"),&v);
    check(Vector(p.x,p.y,p.z).dist(f.position)<1e-8&&Vector(v.x,v.y,v.z).dist(f.velocity)<1e-8,"Host exposes exact local spacecraft state");
    session.selectVariable(0,"Select Target");session.button(0,9);auto escape=session.frame(0);std::cout<<words(escape);
    check(escape.selected=="Select Target"&&words(escape).find("Escape")!=std::string::npos,"Variable selection uses original handler");
    session.button(0,1);for(int i=0;i<50;++i)session.tick();auto next=session.frame(0);std::cout<<words(next);
    check(next.stage==2&&words(next).find("Sun")!=std::string::npos,"Original forward control creates heliocentric stage");
    check(session.enterValue(0,"Mars"),"Native typed target selects a legal original TransX body");
    next=session.frame(0);check(words(next).find("Mars")!=std::string::npos,"Original target orbit uses native Mars ephemeris");
    check(!session.enterValue(0,"Europa"),"Reject a body belonging to a different stage");
    auto second=session.frame(1);check(second.stage==1,"Second MFD keeps its independent original view state");
    session.button(0,3);check(session.frame(0).view!=next.view,"Original view control changes view");
    auto file=(std::filesystem::temp_directory_path()/"orbiter-native-transx-plan.scn").string();
    session.save(file);check(std::filesystem::file_size(file)>50,"Original TransX scenario serialization");
    session.load(file);check(session.frame(0).ready&&words(session.frame(0)).find("Mars")!=std::string::npos,"Original TransX scenario restoration preserves target");
    std::ifstream planInput(file);std::string planText((std::istreambuf_iterator<char>(planInput)),{});planInput.close();f.save(file);
    {std::ofstream embedded(file,std::ios::app);embedded<<"\nBEGIN_MFD Left\n TYPE TransX\n"<<planText<<"END_MFD\n";}
    session.load(file);check(words(session.frame(0)).find("Mars")!=std::string::npos,"TransX status restored from a full native scenario");std::filesystem::remove(file);
    session.button(0,2);auto maneuver=session.frame(0);
    for(int i=0;i<5&&maneuver.view!=4;++i){session.button(0,3);maneuver=session.frame(0);}
    check(maneuver.stage==1&&maneuver.view==4,"Original maneuver view on the departure stage");
    session.selectVariable(0,"Manoeuvre mode");session.button(0,8);session.frame(0);
    session.selectVariable(0,"Prograde vel.");check(session.enterValue(0,"500"),"Original maneuver numeric entry");
    session.frame(0);check(!session.enterValue(0,"nan"),"Nonfinite native numeric entry rejected");
    check(session.enterValue(0,"0"),"Native numeric entry accepts literal zero");session.frame(0);
    check(session.enterValue(0,"500"),"Original maneuver value restored");session.frame(0);VECTOR3 direction;
    check(session.maneuverDirection(0,direction)&&std::isfinite(length(direction)),"RCS alignment direction comes from the original Target-view vector");
    check(session.selectVariable(0,"Man. date")&&session.enterValue(0,"2001-04-10 12:34:56"),"TransX accepts a UTC calendar maneuver date");
    auto dateFrame=session.frame(0);check(words(dateFrame).find("2001-04-10 12:34:56")!=std::string::npos,"The MFD displays the calendar date");
    transx::StageInfo info;double calendar=0;check(transx::parseCalendarUTC("2001-04-10 12:34:56",calendar)&&
        session.stageInfo(1,info)&&fabs(info.maneuver.date-calendar)<1e-9,"Calendar entry updates the original MJD maneuver value");
    check(!session.enterValue(0,"2001-02-29 12:34:56"),"Invalid calendar dates are rejected");
    check(session.enterValue(0,"52000.5")&&session.stageInfo(1,info)&&fabs(info.maneuver.date-52000.5)<1e-9,
          "Original numeric MJD entry remains supported");
    check(session.maneuverDirection(0,direction),"A maneuver direction remains available after changing the date");
    for(int i=0;i<5&&session.frame(0).view!=1;++i)session.button(0,3);
    auto targetBefore=session.frame(0);session.rotateGraph(0,80,50);auto targetAfter=session.frame(0);VECTOR3 rotatedDirection;
    check(targetBefore.view==1&&geometry(targetBefore)==geometry(targetAfter),"Graph rotation does not rotate the Target steering cue");
    check(session.maneuverDirection(0,rotatedDirection)&&length(rotatedDirection-direction)<1e-12,"Graph rotation does not affect the burn direction");
    check(f.throttle==0&&f.fuel==MainCapacity*.553,"Planning never commands the main engines");
    double main=f.fuel,rcs=f.rcs;f.maneuverDirection={direction.x,direction.y,direction.z};f.assist=Assist::Maneuver;f.glider.rcsMode=1;
    for(int i=0;i<4000;++i)f.advance(.01);
    check(dotp(f.forward,f.maneuverDirection)>.999,"TransX target converges through finite native RCS torque");
    check(f.rcs<rcs&&f.fuel==main&&f.throttle==0,"TransX alignment consumes RCS only, with manual main engines");
    auto local=GetRotationToTarget(oapiGetFocusInterface(),VECTOR3{f.forward.x,f.forward.y,f.forward.z});
    check(length(local-VECTOR3{0,0,1})<1e-10,"Original Target-view rotation matches the native attitude frame");
    double radius=7000000,mu=f.gravityMu(),speed=sqrt(mu/radius),dt=333;
    OrbitElements original(VECTOR3{radius,0,0},VECTOR3{0,0,speed},mu);original.timetovectors(dt,&p,&v);
    double angle=dt*speed/radius;check(Vector(p.x,p.y,p.z).dist(Vector(radius*cos(angle),0,radius*sin(angle)))<1,"Original TransX propagation agrees with circular analytic orbit");
    check(std::isfinite(original.getpedistance())&&fabs(original.getpedistance()-radius)<.01,"Original periapsis calculation");
    check(cockpitMfdZones().size()==24,"Original two-column six-button cockpit layout on both MFDs");
    for(const auto &zone:cockpitMfdZones()){Vector center=(zone.corners[0]+zone.corners[1]+zone.corners[2]+zone.corners[3])*.25,eye(0,1.467,6.782);
        check(pickCockpit(eye,(center-eye).unit()).action==zone.action,"Original MFD cockpit button ray hit");}
    for(const auto &screen:cockpitMfdScreens()){Vector center=(screen.corners[0]+screen.corners[3])*.5,eye(0,1.467,6.782);
        check(pickCockpit(eye,(center-eye).unit()).action==screen.action,"Cockpit MFD screen can receive graph drag");}
    check(pickPanel2D(180,101).action==100&&pickPanel2D(1090,306).action==123,"2D panel uses original TransX button regions");
    check(pickPanel2D(360,207).action==200&&pickPanel2D(920,207).action==201,"2D MFD displays use original mesh positions");
    check(pickPanel2D(20,200).action==300&&pickPanel2D(20,350).action==301,"2D panel uses original throttle regions");
    auto cockpit=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_vc.msh");
    check(cockpit.groups[62].texture==8&&!visibleCockpitGroup(62)&&!visibleCockpitGroup(83)&&!visibleCockpitGroup(84),"Pilot body, head and visor are hidden in the cockpit");
    check(visibleCockpitGroup(88)&&visibleCockpitGroup(89),"Cockpit MFDs remain visible");
    auto atlas=loadDDS(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Textures/dg_vc4.dds");Image labelled;
    check(paintMfdButtonLabels(labelled,atlas,{true,false})&&labelled.rgba!=atlas.rgba,"TransX button labels use the original VC atlas");
    std::cout<<checks<<" original TransX checks passed\n";
}catch(const std::exception&e){std::cerr<<"After "<<checks<<" checks: "<<e.what()<<'\n';return 1;}}

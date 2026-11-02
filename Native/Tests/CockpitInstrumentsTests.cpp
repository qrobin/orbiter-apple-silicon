#include "CockpitInstruments.h"
#include "Vecmat.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
void check(bool value,const char *message){if(!value)throw std::runtime_error(message);}
int main(){try{
    auto mesh=loadMesh(std::string(ORBITER_TEST_DATA)+"/Src/Vessel/DeltaGlider/Meshes/deltaglider_vc.msh");
    check(mesh.groups[86].label.find("HORIZON")!=std::string::npos&&mesh.groups[123].label.find("VC_INSTR")!=std::string::npos,"instrument groups match original mesh");
    auto horizon=mesh.groups[86].vertices,tapes=mesh.groups[123].vertices;
    updateHorizon(horizon,0,0,0,100,50);auto level=horizon;
    updateHorizon(horizon,Rad(20),Rad(30),Rad(90),1200,250);
    check(horizon[0].x!=level[0].x&&horizon[0].v<level[0].v,"horizon follows bank and pitch");
    check(horizon[12].v<level[12].v&&horizon[68].u!=level[68].u,"heading ribbon and digits follow heading");
    bool altChanged=false,speedChanged=false;for(int i=0;i<24;++i){altChanged|=horizon[16+i].u!=level[16+i].u;speedChanged|=horizon[40+i].u!=level[40+i].u;}
    check(altChanged&&speedChanged,"altitude and airspeed digits update");
    updateFlightTapes(tapes,0,0);auto zero=tapes;
    updateFlightTapes(tapes,Rad(15),25);
    check(tapes[2].v<zero[2].v&&tapes[8].u==zero[8].u&&tapes[12].v!=zero[12].v,"AOA tape and digits update");
    check(tapes[24].v<zero[24].v&&tapes[32].v!=zero[32].v,"vertical speed tape and digits update on climb");
    updateFlightTapes(tapes,Rad(-45),-70);
    check(tapes[24].v>zero[24].v&&tapes[28].v!=zero[28].v,"vertical speed responds to descent");
    auto original=loadDDS(std::string(ORBITER_TEST_DATA)+"/Src/Vessel/DeltaGlider/Textures/dg_instr.dds");Image scale;
    check(paintVerticalSpeedScale(scale,original,125),"original instrument atlas accepts VS labels");
    check(scale.rgba!=original.rgba,"VS labels are painted into the original atlas");
    auto positive=scale.rgba;check(paintVerticalSpeedScale(scale,original,-125)&&scale.rgba!=positive,"VS labels change for descent");
    std::cout<<"Cockpit instruments passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

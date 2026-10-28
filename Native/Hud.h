#pragma once
#include <algorithm>
#include <cmath>
namespace native {
// Delta-glider HUD mode, brightness and the original four Orbiter colors.
struct Hud {
    int mode=1,colour=0; // 1 orbit, 2 surface, 3 docking; green/orange/yellow/cyan
    double brightness=1;
    void select(int value){if(value>=1&&value<=3)mode=value;}
    void cycleMode(){mode=mode%3+1;}
    void cycleColour(){colour=(colour+1)%4;}
    void adjustBrightness(double delta){if(std::isfinite(delta))brightness=std::clamp(brightness+delta,0.,1.);}
    bool valid()const{return mode>=1&&mode<=3&&colour>=0&&colour<4&&std::isfinite(brightness)&&brightness>=0&&brightness<=1;}
};
}

#pragma once
// Delta-glider main-engine gimbal control, based on MainRetroSubsys.cpp (MIT).
#include <algorithm>
#include <array>
#include <cmath>
namespace native {
struct MainGimbal {
    static constexpr double pitchRange = 0.087488663525924; // tan(5 degrees)
    static constexpr double yawRange = 1.0/7.7;
    int mode=0; // 0 off, 1 automatic, 2 manual
    std::array<double,2> pitch{},yaw{},pitchCommand{},yawCommand{}; // tangents
    void command(bool pitchAxis,int engines,double direction,double dt) {
        if(mode!=2)return;
        auto &values=pitchAxis?pitchCommand:yawCommand;
        double range=pitchAxis?pitchRange:yawRange;
        for(int i=0;i<2;++i)if(engines&(1<<i))values[i]=std::clamp(values[i]+direction*dt*.5*range,-range,range);
    }
    void setBoth(bool pitchAxis,double value) {
        mode=2;auto &values=pitchAxis?pitchCommand:yawCommand;
        values.fill(std::clamp(value,-1.,1.)*(pitchAxis?pitchRange:yawRange));
    }
    void advance(double dt,double pitchInput,double yawInput,double rollInput,double left,double right) {
        if(mode==1) {
            double p[2]={pitchInput-rollInput,pitchInput+rollInput};
            double scale=std::max({1.,std::abs(p[0]),std::abs(p[1])});
            for(int i=0;i<2;++i)pitchCommand[i]=p[i]/scale*pitchRange;
            double balance=left+right>0?(left-right)/(left+right):0;
            yawCommand.fill(std::clamp(balance-yawInput,-1.,1.)*yawRange);
        }
        auto track=[dt](double &value,double target){value+=std::clamp(target-value,-.06*dt,.06*dt);};
        for(int i=0;i<2;++i){track(pitch[i],pitchCommand[i]);track(yaw[i],yawCommand[i]);}
    }
    bool valid() const {
        if(mode<0||mode>2)return false;
        for(auto values:{pitch,pitchCommand,yaw,yawCommand})for(double value:values)if(!std::isfinite(value))return false;
        for(int i=0;i<2;++i)if(std::abs(pitch[i])>pitchRange||std::abs(pitchCommand[i])>pitchRange||std::abs(yaw[i])>yawRange||std::abs(yawCommand[i])>yawRange)return false;
        return true;
    }
};
}

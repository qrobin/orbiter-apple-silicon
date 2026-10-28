// Adapted from DeltaGlider/HoverSubsys.cpp and Vessel::HoverHoldAltitude.
// Original controller algorithms: Copyright (c) Martin Schweiger, MIT License.
#include "Hover.h"
#include <algorithm>
#include <cmath>
#include <istream>
#include <ostream>
#include <sstream>
#include <stdexcept>
namespace native {
static constexpr double Range=10*3.141592653589793/180,Limit=3*Range,BackScale=3./4.55;
void HoverControl::resetFeedback() {sampled=false;thrustLimited=false;}
void HoverControl::updateHold(double dt,double altitude,double vs,double maxAcceleration,double &throttle) {
    if(!holdActive||dt<=0||maxAcceleration<=0) {resetFeedback();return;}
    // Original altitude loop requests 0.1 * height error, limited to 20 m/s.
    double target=holdMode==1?std::clamp((altitudeTarget-altitude)*.1,-20.,20.):verticalSpeedTarget;
    double measuredAcceleration=sampled?(vs-previousVerticalSpeed)/previousDt:0;
    sampled=true;previousVerticalSpeed=vs;previousDt=dt;
    double delta=(target-vs-measuredAcceleration)/maxAcceleration;
    throttle=std::clamp(throttle+std::clamp(delta,-dt,dt),0.,1.);
    thrustLimited=throttle>.999&&target-vs>.5;
}
void HoverControl::balance(double throttle,double manualBalance,double pitch,double bank,double pitchRate,double bankRate,
                           double pitchInput,double rollInput) {
    attitudeLimited=attitudeMode!=0&&(fabs(pitch)>Limit||fabs(bank)>Limit);
    levels={throttle*std::clamp(1+manualBalance,0.,1.),throttle*std::clamp(1-manualBalance,0.,1.),throttle*std::clamp(1-manualBalance,0.,1.)};
    if(!attitudeMode||throttle<=0)return;
    if(attitudeMode==1){pitchTarget=-std::clamp(pitchInput,-1.,1.)*Range;bankTarget=-std::clamp(rollInput,-1.,1.)*Range;}
    levels.fill(throttle);if(attitudeLimited)return;
    // Original gains and weighted-thrust preservation. Rates use native horizon
    // signs; the roll mix is reversed for the native right-handed r x F torque.
    double fb=-.2*(pitch-pitchTarget)-.6*pitchRate;
    double lr=.2*(bank-bankTarget)+.6*bankRate;
    double front=throttle+fb,back=throttle-fb;
    double correction=(front-throttle+(back-throttle)*BackScale)/(1+BackScale);
    front-=correction;back-=correction;
    double low=std::min(front,back),high=std::max(front,back);
    if(low<0){if(front<0){front=0;back+=low/BackScale;}else{back=0;front+=low*BackScale;}}
    if(high>1){if(front>1){front=1;back+=(high-1)/BackScale;}else{back=1;front+=(high-1)*BackScale;}}
    double left=back-lr,right=back+lr;low=std::min(left,right);high=std::max(left,right);
    if(low<0){if(left<0){left=0;right+=low;}else{right=0;left+=low;}}
    if(high>1){if(left>1){left=1;right+=high-1;}else{right=1;left+=high-1;}}
    levels={std::clamp(front,0.,1.),std::clamp(left,0.,1.),std::clamp(right,0.,1.)};
}
bool HoverControl::parse(const std::string &line) {
    std::istringstream s(line);std::string key;s>>key;
    if(key=="HOVERMODE") {
        if(!(s>>attitudeMode))throw std::runtime_error("Invalid hover attitude mode.");
        if(attitudeMode==2&&!(s>>pitchTarget>>bankTarget))throw std::runtime_error("Invalid hover attitude targets.");
        return true;
    }
    if(key=="HOVERHOLD") {
        if(!(s>>holdActive>>holdMode>>altitudeTarget>>verticalSpeedTarget))throw std::runtime_error("Invalid hover hold state.");
        resetFeedback();return true;
    }
    return false;
}
void HoverControl::save(std::ostream &out) const {
    out<<"  HOVERMODE "<<attitudeMode;
    if(attitudeMode==2)out<<' '<<pitchTarget<<' '<<bankTarget;
    out<<"\n  HOVERHOLD "<<holdActive<<' '<<holdMode<<' '<<altitudeTarget<<' '<<verticalSpeedTarget<<'\n';
}
bool HoverControl::valid() const {
    return attitudeMode>=0&&attitudeMode<=2&&holdMode>=0&&holdMode<=2&&(!holdActive||holdMode>0)&&
        std::isfinite(pitchTarget)&&std::isfinite(bankTarget)&&fabs(pitchTarget)<=Range+1e-9&&fabs(bankTarget)<=Range+1e-9&&
        std::isfinite(altitudeTarget)&&altitudeTarget>=0&&altitudeTarget<=1e7&&
        std::isfinite(verticalSpeedTarget)&&fabs(verticalSpeedTarget)<=1000;
}
}

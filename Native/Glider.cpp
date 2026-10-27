// Native Delta-glider systems. Original parameters and animation definitions:
// Copyright (c) Martin Schweiger. Licensed under the MIT License.
#include "Glider.h"
#include <algorithm>
#include <cmath>
#include <istream>
#include <ostream>
#include <sstream>
#include <stdexcept>
namespace native {
static constexpr const char *keys[]={"GEAR","NOSECONE","LADDER","AIRLOCK","IAIRLOCK","HATCH","RADIATOR","RCOVER","AIRBRAKE"};
static constexpr const char *names[]={"Landing gear","Nose cone","Escape ladder","Outer airlock","Inner airlock","Top hatch","Radiator","Retro covers","Airbrake"};
void Actuator::advance(double dt) {
    double change=rate*dt;
    position=position<target?std::min(target,position+change):std::max(target,position-change);
}
void RigidTransform::append(const RigidTransform &other) {
    translation=other.point(translation); rotation=other.rotation*rotation;
}
Glider::Glider() {
    const double rates[]={.15,.05,.1,.1,.1,.15,.02,.3,.3};
    for(size_t i=0;i<PartCount;++i) parts[i].rate=rates[i];
}
const char *Glider::name(Part p) { return names[static_cast<size_t>(p)]; }
void Glider::command(Part p,double target) {
    target=std::clamp(target,0.,1.);
    if(p==Part::Ladder&&target>0&&!part(Part::Nose).open()) return;
    if(p==Part::Nose&&target==0) part(Part::Ladder).target=0;
    part(p).target=target;
}
bool Glider::toggle(Part p) {
    double target=part(p).target>.5?0:1;
    if(p==Part::Airbrake) target=part(p).target<.49?.5:part(p).target<.99?1:0;
    if(p==Part::Ladder&&target>0&&!part(Part::Nose).open()) return false;
    command(p,target); return true;
}
void Glider::advance(double dt,double mainThrottle,double externalPressure) {
    for(auto &a:parts) a.advance(dt);
    mainLevel=mainThrottle;
    retroLevel=part(Part::RetroCover).open()&&part(Part::RetroCover).target==1?retro:0;
    hoverLevel=hover;
    // Continuous solution to PressureSubsys.cpp's volume/conductance equations.
    double hatchConductance=(valves[1]?2e-4:0)+.1*part(Part::Hatch).position;
    double outerConductance=(valves[3]?2e-4:0)+part(Part::OuterLock).position;
    cabinPressure=externalPressure+(cabinPressure-externalPressure)*exp(-hatchConductance*1000*dt/24);
    lockPressure=externalPressure+(lockPressure-externalPressure)*exp(-outerConductance*1000*dt/4);
    double exchange=(valves[2]?2e-4:0)+part(Part::InnerLock).position;
    double mean=(cabinPressure*24+lockPressure*4)/28;
    double difference=(cabinPressure-lockPressure)*exp(-exchange*1000*dt*(1./24+1./4));
    cabinPressure=mean+difference*4/28; lockPressure=mean-difference*24/28;
    if(valves[0]&&cabinPressure<100000) cabinPressure=std::min(100000.,400000-(400000-cabinPressure)*exp(-.05*dt/24));
    if(valves[4]&&lockPressure<100000) lockPressure=std::min(100000.,400000-(400000-lockPressure)*exp(-.05*dt/4));
    // Reduced thermal model: energy storage, engine heat, pumped radiator rejection.
    // This is not the original multi-node ThermalSubsystem solver.
    double load=900+2500*mainLevel+1800*hoverLevel+500*retroLevel;
    double radiator=part(Part::Radiator).position;
    double rejection=(coolantPump?1.:.12)*radiator*5.67e-8*18*.9*(pow(coolantTemperature,4)-pow(180.,4));
    coolantTemperature=std::clamp(coolantTemperature+(load-rejection)*dt/4e6,150.,1000.);
    cabinTemperature+=(coolantTemperature-cabinTemperature)*(1-exp(-dt/2400));
}
std::string Glider::warning() const {
    if(cabinPressure<60000) return "CABIN PRESSURE LOW — close hatch/airlock and open cabin supply";
    if(part(Part::OuterLock).position>.01&&part(Part::InnerLock).position>.01) return "BOTH AIRLOCK DOORS OPEN — cabin venting";
    if(retro>.01&&!part(Part::RetroCover).open()) return "RETRO INHIBITED — open retro covers";
    if(coolantTemperature>330) return "COOLANT HOT — deploy radiator and enable coolant pump";
    return {};
}
double Glider::channel(Channel c) const {
    switch(c) {
#define PART_CHANNEL(c,p) case Channel::c:return part(Part::p).position;
    PART_CHANNEL(Gear,Gear) PART_CHANNEL(Nose,Nose) PART_CHANNEL(Ladder,Ladder)
    PART_CHANNEL(OuterLock,OuterLock) PART_CHANNEL(InnerLock,InnerLock) PART_CHANNEL(Hatch,Hatch)
    PART_CHANNEL(Radiator,Radiator) PART_CHANNEL(RetroCover,RetroCover) PART_CHANNEL(Airbrake,Airbrake)
#undef PART_CHANNEL
    case Channel::Rudder:return .5+.5*rudder;
    case Channel::Elevator:return .5+.5*elevator;
    case Channel::Trim:return .5+.5*trim;
    case Channel::LeftAileron:case Channel::RightAileron:return .5+.5*aileron;
    case Channel::MainLever:return .4+.6*mainLevel-.4*retro;
    case Channel::HoverLever:return hover;
    }
    return 0;
}
const std::vector<AnimationComponent> &Glider::animations() {
    static const std::vector<AnimationComponent> components={
#include "GliderAnimations.inc"
    };
    return components;
}
std::vector<RigidTransform> Glider::transforms(size_t groupCount,int mesh) const {
    std::vector<RigidTransform> transforms(groupCount);
    for(const auto &c:animations()) {
        if(c.mesh!=mesh) continue;
        double fraction=(std::clamp(channel(c.channel),c.start,c.end)-std::clamp(c.baseline,c.start,c.end))/(c.end-c.start);
        if(fabs(fraction)<1e-14) continue;
        RigidTransform t;
        if(c.translation) t.translation=c.axis*fraction;
        else {
            Vector a=c.axis.unit(); double angle=c.amount*fraction,co=cos(angle),si=sin(angle),om=1-co;
            t.rotation.Set(co+om*a.x*a.x,om*a.x*a.y-si*a.z,om*a.x*a.z+si*a.y,
                           om*a.y*a.x+si*a.z,co+om*a.y*a.y,om*a.y*a.z-si*a.x,
                           om*a.z*a.x-si*a.y,om*a.z*a.y+si*a.x,co+om*a.z*a.z);
            t.translation=c.pivot-mul(t.rotation,c.pivot);
        }
        for(size_t index:c.groups) if(index<groupCount) transforms[index].append(t);
    }
    return transforms;
}
bool Glider::parse(const std::string &line) {
    std::istringstream s(line); std::string key; s>>key;
    for(size_t i=0;i<PartCount;++i) if(key==keys[i]) {
        double p=0,v=0; if(!(s>>p>>v)) throw std::runtime_error("Invalid mechanism state.");
        parts[i].position=p; parts[i].target=v>0?1:v<0?0:p; return true;
    }
    if(key=="DGTARGETS") { for(auto &a:parts) if(!(s>>a.target)) throw std::runtime_error("Invalid mechanism target.");return true; }
    if(key=="DGENGINES") { if(!(s>>hover>>retro>>mainBalance>>gimbalPitch>>gimbalYaw>>hoverBalance)) throw std::runtime_error("Invalid engine controls."); return true; }
    if(key=="DGCONTROLS") { if(!(s>>rcsMode>>trim)) throw std::runtime_error("Invalid flight controls."); return true; }
    if(key=="DGPRESSURE") { if(!(s>>cabinPressure>>lockPressure)) throw std::runtime_error("Invalid pressure state."); for(auto &v:valves) {int n=0;if(!(s>>n)) throw std::runtime_error("Invalid valve state.");v=n!=0;} return true; }
    if(key=="DGTHERMAL") { if(!(s>>coolantTemperature>>cabinTemperature>>coolantPump)) throw std::runtime_error("Invalid thermal state."); return true; }
    if(key=="DGLIGHTS") { if(!(s>>navLights>>beacons>>strobes>>landingLight>>instrumentLights)) throw std::runtime_error("Invalid light state.");return true; }
    return false;
}
void Glider::save(std::ostream &o) const {
    for(size_t i=0;i<PartCount;++i) {
        auto &a=parts[i]; double speed=a.moving()?copysign(a.rate,a.target-a.position):0;
        o<<"  "<<keys[i]<<' '<<a.position<<' '<<speed<<'\n';
    }
    o<<"  DGTARGETS"; for(const auto &a:parts)o<<' '<<a.target;o<<'\n';
    o<<"  DGENGINES "<<hover<<' '<<retro<<' '<<mainBalance<<' '<<gimbalPitch<<' '<<gimbalYaw<<' '<<hoverBalance
     <<"\n  DGCONTROLS "<<rcsMode<<' '<<trim<<"\n  DGPRESSURE "<<cabinPressure<<' '<<lockPressure;
    for(bool v:valves) o<<' '<<v;
    o<<"\n  DGTHERMAL "<<coolantTemperature<<' '<<cabinTemperature<<' '<<coolantPump
     <<"\n  DGLIGHTS "<<navLights<<' '<<beacons<<' '<<strobes<<' '<<landingLight<<' '<<instrumentLights<<'\n';
}
bool Glider::valid() const {
    for(const auto &a:parts) if(!std::isfinite(a.position)||!std::isfinite(a.target)||a.position<0||a.position>1||a.target<0||a.target>1) return false;
    for(double n:{hover,retro,mainBalance,gimbalPitch,gimbalYaw,hoverBalance,trim,cabinPressure,lockPressure,coolantTemperature,cabinTemperature}) if(!std::isfinite(n)) return false;
    return hover>=0&&hover<=1&&retro>=0&&retro<=1&&fabs(mainBalance)<=1&&fabs(gimbalPitch)<=1&&fabs(gimbalYaw)<=1&&fabs(hoverBalance)<=1&&fabs(trim)<=1&&rcsMode>=0&&rcsMode<=2&&cabinPressure>=0&&cabinPressure<=400000&&lockPressure>=0&&lockPressure<=400000&&coolantTemperature>=100&&coolantTemperature<=1000&&cabinTemperature>=100&&cabinTemperature<=1000;
}
}

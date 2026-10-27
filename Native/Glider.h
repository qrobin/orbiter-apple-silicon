#pragma once
#include "Vecmat.h"
#include <array>
#include <iosfwd>
#include <string>
#include <vector>
namespace native {
enum class Part { Gear, Nose, Ladder, OuterLock, InnerLock, Hatch, Radiator, RetroCover, Airbrake, Count };
constexpr size_t PartCount=static_cast<size_t>(Part::Count);
struct Actuator {
    double position=0,target=0,rate=.1;
    bool moving() const { return fabs(position-target)>1e-9; }
    bool open() const { return position>=1-1e-9; }
    void advance(double dt);
};
enum class Channel { Gear,Nose,Ladder,OuterLock,InnerLock,Hatch,Radiator,RetroCover,Airbrake,
                     Rudder,Elevator,Trim,LeftAileron,RightAileron,MainLever,HoverLever };
struct AnimationComponent {
    Channel channel; int mesh; std::vector<size_t> groups;
    Vector pivot,axis; double amount,start,end,baseline; bool translation;
};
struct RigidTransform {
    Matrix rotation; Vector translation;
    RigidTransform():rotation(IMatrix()){}
    Vector point(const Vector &v) const { return mul(rotation,v)+translation; }
    Vector direction(const Vector &v) const { return mul(rotation,v); }
    void append(const RigidTransform &other);
};
class Glider {
public:
    std::array<Actuator,PartCount> parts;
    double hover=0,retro=0,mainBalance=0,gimbalPitch=0,gimbalYaw=0,hoverBalance=0;
    double elevator=0,rudder=0,aileron=0,trim=0;
    double cabinPressure=100000,lockPressure=100000,coolantTemperature=293,cabinTemperature=293;
    bool parkingBrake=false;
    bool coolantPump=true,navLights=false,beacons=false,strobes=false,landingLight=false,instrumentLights=true;
    std::array<bool,5> valves{};
    int rcsMode=1; // 0 off, 1 rotation, 2 translation
    double mainLevel=0,retroLevel=0,hoverLevel=0;
    Vector rcsRotation,rcsTranslation;
    Glider();
    Actuator &part(Part p) { return parts[static_cast<size_t>(p)]; }
    const Actuator &part(Part p) const { return parts[static_cast<size_t>(p)]; }
    bool toggle(Part p);
    void command(Part p,double target);
    void advance(double dt,double mainThrottle,double externalPressure=0);
    bool parse(const std::string &line);
    void save(std::ostream &out) const;
    bool valid() const;
    std::string warning() const;
    double channel(Channel c) const;
    std::vector<RigidTransform> transforms(size_t groupCount,int mesh=0) const;
    static const std::vector<AnimationComponent> &animations();
    static const char *name(Part p);
};
}

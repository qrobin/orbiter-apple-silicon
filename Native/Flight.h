#pragma once
#include "Element.h"
#include <string>
#include <filesystem>
namespace native {
constexpr double EarthMass = 5.973698968e24;
constexpr double EarthRadius = 6.37101e6;
inline const double Mu = Ggrav*EarthMass;
constexpr double MainCapacity = 12900.0;
constexpr double RcsCapacity = 600.0;
constexpr double EmptyMass = 11000.0;
constexpr double ExhaustVelocity = 40000.0;
struct Input { double pitch=0, yaw=0, roll=0, translate=0; };
enum class Assist { Free, Prograde, Retrograde, KillRotation };
class Flight {
public:
    Vector position, velocity, right{1,0,0}, up{0,1,0}, forward{0,0,1}, angularVelocity;
    double mjd=51982.5292925579, elapsed=0, fuel=MainCapacity*.553, rcs=RcsCapacity*.9;
    double throttle=0, warp=1, acceleration=0;
    bool paused=false, impacted=false;
    Assist assist=Assist::Free;
    std::string name="GL-01";
    Flight();
    void load(const std::filesystem::path &path);
    void save(const std::filesystem::path &path) const;
    void advance(double realSeconds, const Input &input={});
    Elements orbit() const;
    double altitude() const { return position.length()-EarthRadius; }
    double mass() const { return EmptyMass+fuel+rcs; }
    double radialSpeed() const { return dotp(position,velocity)/position.length(); }
    void align(const Vector &direction);
private:
    void coast(double dt);
    void step(double dt,const Input &input);
};
}

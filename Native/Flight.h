#pragma once
#include "Element.h"
#include "Body.h"
#include "Glider.h"
#include "Hud.h"
#include "Weather.h"
#include <array>
#include <string>
#include <filesystem>
namespace native {
constexpr double MainCapacity = 12900.0;
constexpr double RcsCapacity = 600.0;
constexpr double EmptyMass = 11000.0;
constexpr double ExhaustVelocity = 40000.0;
struct Input { double pitch=0, yaw=0, roll=0, translate=0, lateral=0, vertical=0, leftBrake=0, rightBrake=0; };
enum class Assist { Free, Prograde, Retrograde, Normal, AntiNormal, HorizonLevel, KillRotation, Maneuver };
// Physical button order in the original VC: KILL-R, RET-G, PRO-G, NML−, NML+, HRLVL.
Assist navButtonMode(int button);
// Targets: altitude (m), airspeed (m/s), bank and heading (radians).
struct AtmosphericControl {
    std::array<bool,4> active{};
    std::array<double,4> target{};
    bool targetsInitialized=false,speedInitialized=false;
    double previousSpeed=0;
    bool engaged() const {return active[0]||active[1]||active[2]||active[3];}
    void cancel() {active.fill(false);speedInitialized=false;}
};
class Flight {
public:
    Glider glider;
    Hud hud;
    AtmosphericControl atmospheric;
    BodyId reference=BodyId::Earth;
    bool automaticReferenceChanges=false;
    int weatherPreset=0;
    const CelestialBody &centralBody()const{return body(reference);}
    double gravityMu()const{return centralBody().mu();}
    void startOrbit(BodyId body);
    void placeOnBody(double latitude,double longitude,double heading,double clearance=2.53);
    void changeReference(BodyId body);
    void updateReference();
    Vector position, velocity, right{1,0,0}, up{0,1,0}, forward{0,0,1}, angularVelocity;
    double mjd=51982.5292925579, elapsed=0, fuel=MainCapacity*.553, rcs=RcsCapacity*.9;
    double throttle=0, warp=1, acceleration=0, dynamicPressure=0, mach=0, angleOfAttack=0;
    bool paused=false, impacted=false,groundContact=false;
    int wheelContacts=0;
    double groundSpeed=0,contactLoad=0;
    Assist assist=Assist::Free;
    bool killRotationWithLevel=false,horizonWithAssist=false;
    Vector maneuverDirection{0,0,1};
    std::string name="GL-01";
    Flight();
    void load(const std::filesystem::path &path);
    void save(const std::filesystem::path &path) const;
    void advance(double realSeconds, const Input &input={});
    bool setHoverHold(int mode,double target);
    void setHoverThrottle(double level);
    void setMainThrottle(double level);
    bool atmosphericAvailable() const;
    void captureAtmosphericTarget(int channel);
    bool setAtmosphericTarget(int channel,double target);
    bool setAtmosphericHold(int channel,bool enabled);
    void cutEngines();
    void toggleAssist(Assist mode);
    void clearAssist();
    bool assistActive(Assist mode) const;
    Elements orbit() const;
    void placeOnEarth(double latitude,double longitude,double heading,double clearance=2.53);
    double pitch() const;
    double bank() const;
    double heading() const;
    double surfaceVerticalSpeed() const;
    double altitude() const { return position.length()-centralBody().radius; }
    double mass() const { return EmptyMass+fuel+rcs; }
    double radialSpeed() const { return dotp(position,velocity)/position.length(); }
    WeatherSample currentWeather() const {return reference==BodyId::Earth?earthWeather(position,mjd+elapsed/86400.,weatherPreset):WeatherSample{};}
    Vector airRelativeVelocity() const {return velocity-crossp(centralBody().spin(),position)-(reference==BodyId::Earth?earthWeather(position,mjd+elapsed/86400.,weatherPreset,false).wind:Vector());}
    void align(const Vector &direction);
private:
    void coast(double dt);
    void step(double dt,const Input &input);
    void updateAtmosphericControl(double dt);
};
}

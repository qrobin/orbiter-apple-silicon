#pragma once
#include "Flight.h"
#include <array>
#include <cstdint>
#include <vector>
namespace native {
enum class ExhaustKind { Main,Retro,Hover,Rcs };
struct ExhaustEmitter { Vector position,direction; double level,radius; ExhaustKind kind; unsigned id; };
// Body-frame nozzle positions in metres, with directions pointing out of the nozzle.
std::vector<ExhaustEmitter> gliderExhaust(const Flight &flight);
struct PlumeShape { double speed,lifetime,spread; };
PlumeShape plumeShape(double altitude,ExhaustKind kind);
PlumeShape plumeShape(const Flight &flight,ExhaustKind kind);
struct ExhaustTrailPuff {
    BodyId body; Vector position,velocity,axis;
    double age,lifetime,radius,opacity,halfLength,seed;
    bool vacuum;
};
double exhaustTrailRadius(const ExhaustTrailPuff &puff);
// Long-lived atmospheric exhaust, stored in the emitting body's inertial frame.
class ExhaustTrail {
public:
    static constexpr size_t capacity=16384;
    void update(const Flight &flight,double simulationSeconds,double humidity=.5);
    void reset();
    const std::vector<ExhaustTrailPuff>& puffs()const{return particles;}
private:
    struct EmitterHistory {Vector position;double remainder=0;bool active=false;};
    std::array<EmitterHistory,32> history{};
    BodyId previousBody=BodyId::Earth;
    bool haveBody=false;
    uint32_t serial=0;
    std::vector<ExhaustTrailPuff> particles;
};
}

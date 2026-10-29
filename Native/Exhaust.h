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
    BodyId body; Vector position,velocity;
    double age,lifetime,radius,opacity;
    uint64_t stream,sequence;
    unsigned nozzle;
    bool vacuum;
};
double exhaustTrailRadius(const ExhaustTrailPuff &puff);
double exhaustTrailOpacity(const ExhaustTrailPuff &puff);
struct ExhaustTrailPoint {Vector position;double radius,opacity,age;};
struct ExhaustTrailSegment {
    BodyId body; ExhaustTrailPoint start,end;
    uint64_t stream; unsigned nozzle; bool vacuum;
};
// Emission samples remain in the emitting body's inertial frame as they disperse.
class ExhaustTrail {
public:
    static constexpr size_t capacity=16384;
    void update(const Flight &flight,double simulationSeconds,double humidity=.5);
    void reset();
    const std::vector<ExhaustTrailPuff>& puffs()const{return particles;}
    std::vector<ExhaustTrailSegment> segments(const Flight &flight)const;
private:
    struct EmitterHistory {
        Vector position,direction,velocity;
        double remainder=0;bool active=false;
        std::array<bool,2> mediumActive{};
        std::array<uint64_t,2> stream{};
        std::array<uint64_t,2> sequence{};
    };
    std::array<EmitterHistory,32> history{};
    BodyId previousBody=BodyId::Earth;
    bool haveBody=false;
    uint64_t nextStream=0;
    std::vector<ExhaustTrailPuff> particles;
};
}

#pragma once
#include "Flight.h"
#include <vector>
namespace native {
enum class ExhaustKind { Main,Retro,Hover,Rcs };
struct ExhaustEmitter { Vector position,direction; double level,radius; ExhaustKind kind; };
// Body-frame nozzle positions in metres, with directions pointing out of the nozzle.
std::vector<ExhaustEmitter> gliderExhaust(const Flight &flight);
struct PlumeShape { double speed,lifetime,spread; };
PlumeShape plumeShape(double altitude,ExhaustKind kind);
PlumeShape plumeShape(const Flight &flight,ExhaustKind kind);
}

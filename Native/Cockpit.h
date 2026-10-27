#pragma once
#include "Vecmat.h"
#include <array>
#include <vector>
namespace native {
struct CockpitZone { int action; std::array<Vector,4> corners; };
struct CockpitSwitch { int action,group,first,count; Vector pivot,axis; };
const std::vector<CockpitSwitch> &cockpitSwitches();
struct CockpitHit { int action=-1; double u=0,v=0; };
const std::vector<CockpitZone> &cockpitZones();
CockpitHit pickCockpit(const Vector &origin,const Vector &direction);
}

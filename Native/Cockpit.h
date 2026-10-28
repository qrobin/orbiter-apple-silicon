#pragma once
#include "Vecmat.h"
#include <array>
#include <vector>
namespace native {
struct Image;
struct HoverControl;
bool paintHoverReadout(Image &target,const Image &glyphs,const HoverControl &hover);
struct CockpitZone { int action; std::array<Vector,4> corners; };
struct CockpitSwitch { int action,group,first,count; Vector pivot,axis; int motion=0; };
struct CockpitSphere { int action;Vector center;double radius; };
const std::vector<CockpitSphere> &cockpitSpheres();
const std::vector<CockpitSwitch> &cockpitSwitches();
// u follows corners 0->1, v follows 0->2; some upstream switch quads are transposed.
struct CockpitHit { int action=-1; double u=0,v=0; };
const std::vector<CockpitZone> &cockpitZones();
CockpitHit pickCockpit(const Vector &origin,const Vector &direction);
}

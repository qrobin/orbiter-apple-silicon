#pragma once
#include "Mesh.h"
namespace native {
// Original Delta-glider VC instruments: update copies of mesh groups 86 and 123.
void updateHorizon(std::vector<Vertex> &vertices,double pitch,double bank,double heading,double altitude,double airspeed);
void updateFlightTapes(std::vector<Vertex> &vertices,double aoa,double verticalSpeed);
bool paintVerticalSpeedScale(Image &target,const Image &original,double verticalSpeed);
}

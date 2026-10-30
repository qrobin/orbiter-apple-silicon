#pragma once
#include "Body.h"
#include <filesystem>
namespace native {
struct BodyState {Vector position,velocity;};
void loadEphemerides(const std::filesystem::path &directory);
bool ephemeridesReady();
BodyState relativeBodyState(BodyId id,double mjd);
BodyState bodyState(BodyId id,double mjd);
double sphereOfInfluence(BodyId id,double mjd);
double solarIrradiance(double distance);
double solarDiscVisibility(double sunRadius,double occluderRadius,double separation);
}

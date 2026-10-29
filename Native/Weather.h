#pragma once
#include "Body.h"
#include <filesystem>
namespace native {
// Satellite cloud coverage is historical; winds and storms are procedural.
struct WeatherSample {double cloud=0,storm=0,rain=0;Vector wind,lightning;double flash=0;};
bool loadEarthWeatherMap(const std::filesystem::path &path);
WeatherSample earthWeather(const Vector &position,double mjd,int preset,bool effects=true);
double updateGlassWetness(double wetness,double rain,double airspeed,double dt);
Vector glassRunoffVelocity(const Vector &airRelative,const Vector &radial,const Vector &right,const Vector &up,const Vector &forward);
}

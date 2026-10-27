#pragma once
#include <cmath>
// Constants retained from Orbitersdk/include/OrbiterAPI.h, without Win32 types.
constexpr double PI = 3.14159265358979323846;
constexpr double PI05 = PI/2.0;
constexpr double AU = 299792458.0 * 499.004783806;
constexpr double RAD = PI/180.0;
constexpr double DEG = 180.0/PI;
inline double posangle(double a) { a = std::fmod(a, 2*PI); return a < 0 ? a+2*PI : a; }

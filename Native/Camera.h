#pragma once
#include "Flight.h"
namespace native {
// Orbit controls and camera reference frame match Native/macOS/App.mm.
struct OrbitCamera {
    double yaw=25*RAD,pitch=17*RAD,distance=43;
    void drag(double horizontalPoints,double verticalPoints);
    void zoom(double scrollPoints);
    Vector offset(const Flight &flight) const;
};
}

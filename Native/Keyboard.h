#pragma once
#include "Flight.h"
#include <array>
namespace native {
// macOS hardware key codes. W/S and A/D control pitch and yaw; arrows
// retain the forward/back and side translation inputs previously on WASD.
inline Input flightKeyboardInput(const std::array<bool,256> &held){
    Input input;
    input.pitch=(held[13]?1.:0)-(held[1]?1.:0); // W nose down, S nose up
    input.yaw=(held[2]?1.:0)-(held[0]?1.:0); // D right, A left
    input.roll=(held[12]?1.:0)-(held[14]?1.:0);
    input.translate=(held[126]?1.:0)-(held[125]?1.:0);
    input.lateral=(held[124]?1.:0)-(held[123]?1.:0);
    input.vertical=(held[6]?1.:0)-(held[38]?1.:0);
    input.leftBrake=held[43]?1:0;input.rightBrake=held[47]?1:0;
    return input;
}
}

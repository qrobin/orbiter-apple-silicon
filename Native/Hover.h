#pragma once
#include <array>
#include <iosfwd>
#include <string>
namespace native {
constexpr double MaxHoverThrust=140000*(1+3./4.55);
struct HoverControl {
    int attitudeMode=0; // Original modes: 0 off, 1 automatic, 2 manual attitude targets.
    int holdMode=1;     // Original modes: 1 altitude, 2 vertical speed.
    bool holdActive=false,attitudeLimited=false,thrustLimited=false;
    double pitchTarget=0,bankTarget=0,altitudeTarget=100,verticalSpeedTarget=0;
    std::array<double,3> levels{}; // Actual front, rear-left, rear-right engine levels.
    void resetFeedback();
    void updateHold(double dt,double altitude,double verticalSpeed,double maxAcceleration,double &throttle);
    void balance(double throttle,double manualBalance,double pitch,double bank,double pitchRate,double bankRate,
                 double pitchInput=0,double rollInput=0);
    bool parse(const std::string &line);
    void save(std::ostream &out) const;
    bool valid() const;
private:
    bool sampled=false;
    double previousVerticalSpeed=0,previousDt=0;
};
}

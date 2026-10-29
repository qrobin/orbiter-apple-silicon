#pragma once
#include "Session.h"
#include <cstddef>
#include <string>

namespace native { class Flight; }
namespace native::transx {

// Advance through the ordinary flight model toward the selected maneuver.
// The work is bounded per frame so the UI remains responsive and cancellable.
class BurnSkip {
public:
    enum class State { Idle, Running, Reached, Cancelled, PlanChanged, FlightStopped };
    bool begin(Flight &flight,Session &session,std::string &error);
    void advance(Flight &flight,Session &session,size_t maxSteps=256,double budgetSeconds=.006);
    void cancel(Flight &flight);
    void reset();
    State state() const {return state_;}
    bool running() const {return state_==State::Running;}
private:
    bool samePlan(Session &session) const;
    void stop(Flight &flight,State state);
    State state_=State::Idle;
    BodyId reference_=BodyId::Earth;
    RouteValues maneuver_;
    std::uintptr_t stageToken_=0;
    double epoch_=0;
};
}

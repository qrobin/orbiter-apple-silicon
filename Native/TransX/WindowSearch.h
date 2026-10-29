#pragma once
#include "Session.h"
#include <memory>
#include <optional>

class OrbitElements;
namespace native {class Flight;}
namespace native::transx {
struct WindowSolution {
    RouteValues transfer,burn;
    double arrivalMJD=0,departureDV=0,captureDV=0;
    bool hasTransfer=false;
};

// Bounded, incremental search over the same conics used by TransX. It returns
// a sampled low-fuel candidate; the caller validates and applies it to TransX.
class WindowSearch {
public:
    WindowSearch(const Flight &flight,BodyId target,bool eject,
                 const OrbitElements &origin,const OrbitElements &destination);
    ~WindowSearch();
    void step(size_t budget);
    bool running() const;
    double progress() const;
    const std::optional<WindowSolution> &result() const;
    const std::string &error() const;
private:
    struct Impl;std::unique_ptr<Impl> impl;
};
}

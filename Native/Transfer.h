#pragma once
#include "Flight.h"
#include "SolarSystem.h"
#include <optional>
#include <vector>

namespace native {
// SI units, MJD dates, and the same inertial axes as the flight simulation.
struct LambertSolution { Vector departure,arrival; double residualSeconds=0; };
std::optional<LambertSolution> solveLambert(const Vector &r1,const Vector &r2,double seconds,double mu,
                                         const Vector &normal=Vector(0,-1,0));
BodyState propagateConic(const BodyState &state,double seconds,double mu);
std::optional<Vector> escapeVelocity(const Vector &position,const Vector &excess,double mu);
BodyId departureSystem(BodyId reference);
double nominalTransferDays(BodyId origin,BodyId target,double mjd,double solarRadius=0);
double defaultParkingAltitude(BodyId id);
double navigationAtmosphereLimit(BodyId id);

struct ParkingOrbit {
    BodyId reference=BodyId::Earth;
    BodyState state;
    double mjd=0;
};
ParkingOrbit parkingOrbit(const Flight &flight);
struct TransferRequest {
    BodyId origin=BodyId::Earth,target=BodyId::Mars;
    double departureMJD=51982.5292925579,flightDays=260;
    double departureAltitude=200000,arrivalAltitude=200000;
    std::optional<ParkingOrbit> parking;
};
struct TransferPlan {
    TransferRequest request;
    double departureMJD=0,arrivalMJD=0,departureDV=0,captureDV=0;
    BodyState start,end;
    LambertSolution trajectory;
    Vector departureExcess,arrivalExcess,burnVector,burnPosition,burnVelocityBefore;
    bool guidedDeparture=false;
    double totalDV()const{return departureDV+captureDV;}
};
// Zero-revolution, prograde heliocentric Lambert transfer. Parking-orbit burns
// are impulsive patched-conic estimates. Refinement includes the live orbit's
// plane and selects a nearby ejection opportunity; it never fires an engine.
TransferPlan planTransfer(const TransferRequest &request,bool refineParking=true);
struct BurnGuidance {
    bool valid=false,live=false;
    Vector deltaVelocity;
    double secondsToBurn=0,alignmentDegrees=0,prograde=0,normal=0,radial=0;
    double propellant=0,burnSeconds=0,availableDV=0;
};
BurnGuidance transferGuidance(const TransferPlan &plan,const Flight &flight);
void coastToDeparture(Flight &flight,const TransferPlan &plan,double leadSeconds=300);

class TransferSearch {
public:
    void begin(const TransferRequest &request,double spanDays);
    void step(size_t budget=12);
    void cancel(){running=false;}
    bool active()const{return running;}
    double progress()const;
    const std::optional<TransferPlan>& result()const{return best;}
private:
    TransferRequest base;
    std::vector<std::pair<double,double>> samples;
    size_t cursor=0,done=0;
    int stage=0;
    bool running=false;
    double span=0,departureStep=0,durationStep=0;
    std::optional<TransferPlan> best;
    void refine();
};
}

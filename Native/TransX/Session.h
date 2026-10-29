#pragma once
#include "SDK.h"
#include "Body.h"
#include <memory>
namespace native {class Flight;}
namespace native::transx {
struct Frame {
    std::vector<oapi::DrawCommand> commands;
    std::vector<std::string> variables;
    std::string selected,help;
    int stage=1,view=2;
    bool ready=false;
};
struct RouteLeg { BodyId center, next; int stage; bool escape; };
struct Route {
    BodyId origin=BodyId::Sun, destination=BodyId::Sun;
    std::vector<RouteLeg> legs;
    std::vector<BodyId> waypoints;
    int targetStage=0, ejectStage=0;
};
struct RouteValues { double date=0, prograde=0, outward=0, plane=0; };
struct StageInfo {
    BodyId reference=BodyId::Sun;
    RouteValues maneuver;
    bool enabled=false;
};
struct BurnTiming {
    double secondsToBurn=0,duration=0,deltaV=0,propellant=0;
    bool sufficientFuel=false;
};
enum class SearchState { Idle,Running,Complete,Failed };
struct SearchStatus {
    SearchState state=SearchState::Idle;
    double progress=0,arrivalMJD=0,departureDV=0,captureDV=0,missDistance=0;
    std::string message;
};
struct Approach {
    double distance=0, relativeSpeed=0, mjd=0;
    int source=0; // 1: TransX plan, 2: manoeuvre, 3: current orbit
};
class Session {
public:
    static constexpr int RouteDisplay=2;
    explicit Session(Flight &flight);
    ~Session();
    void tick();
    Frame frame(int display);
    void rotateGraph(int display,double horizontalPoints,double verticalPoints);
    void resetGraph(int display);
    void button(int display,int index,bool held=false);
    bool selectVariable(int display,const std::string &name);
    bool enterValue(int display,const std::string &value);
    void save(const std::string &path);
    void load(const std::string &path);
    bool maneuverDirection(int display,VECTOR3 &direction);
    bool maneuverDirectionForStage(int stage,VECTOR3 &direction);
    int stageCount();
    int selectedStage();
    bool selectStage(int stage);
    bool stageInfo(int stage,StageInfo &info);
    bool setStageManeuver(int stage,const RouteValues &values);
    bool stageTiming(int stage,BurnTiming &timing);
    bool alignStage(int stage);
    bool beginWindowSearch(const Route &route,std::string &error);
    void stepWindowSearch(size_t budget=16);
    void cancelWindowSearch();
    SearchStatus windowSearchStatus() const;
    bool createRoute(BodyId destination,Route &route,std::string &error);
    bool createRoute(const std::vector<BodyId> &waypoints,Route &route,std::string &error);
    bool currentRoute(Route &route);
    bool routeMatches(const Route &route);
    bool routeView(int stage,int mode);
    bool routeValues(const Route &route,bool departure,RouteValues &values);
    bool setRouteValues(const Route &route,bool departure,const RouteValues &values);
    bool routeApproach(const Route &route,Approach &approach);
    bool routeHohmann(const Route &route,double &dv);
private:
    bool displayView(int display,int stage,int mode);
    struct Impl;std::unique_ptr<Impl> impl;
};
}

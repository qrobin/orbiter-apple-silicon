#include "Cockpit.h"
#include <limits>
namespace native {
const std::vector<CockpitZone> &cockpitZones() {
    static const std::vector<CockpitZone> zones={
#include "CockpitZones.inc"
    };return zones;
}
const std::vector<CockpitSwitch> &cockpitSwitches() {
    static const std::vector<CockpitSwitch> switches={
#include "CockpitSwitches.inc"
    };return switches;
}
CockpitHit pickCockpit(const Vector &origin,const Vector &direction) {
    CockpitHit hit;double nearest=std::numeric_limits<double>::max();
    for(const auto &z:cockpitZones()) {
        Vector a=z.corners[1]-z.corners[0],b=z.corners[2]-z.corners[0],normal=crossp(a,b);
        double den=dotp(normal,direction);if(fabs(den)<1e-14) continue;
        double t=dotp(normal,z.corners[0]-origin)/den;if(t<=0||t>=nearest)continue;
        Vector delta=origin+direction*t-z.corners[0];
        double aa=dotp(a,a),bb=dotp(b,b),ab=dotp(a,b),det=aa*bb-ab*ab;
        if(det<1e-20)continue;
        double u=(dotp(delta,a)*bb-dotp(delta,b)*ab)/det;
        double v=(dotp(delta,b)*aa-dotp(delta,a)*ab)/det;
        if(u>=0&&u<=1&&v>=0&&v<=1) {nearest=t;hit={z.action,u,v};}
    }return hit;
}
}

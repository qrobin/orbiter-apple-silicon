#include "Cockpit.h"
#include "Mesh.h"
#include "Hover.h"
#include <algorithm>
#include <cstdio>
#include <limits>
namespace native {
bool paintHoverReadout(Image &target,const Image &glyphs,const HoverControl &hover) {
    // Original HoverHoldAltIndicator atlas coordinates and 8x11 glyph cells.
    if(target.width<394||target.height<23||glyphs.width<136||glyphs.height<22||
       target.rgba.size()!=size_t(target.width)*target.height*4||glyphs.rgba.size()!=size_t(glyphs.width)*glyphs.height*4)return false;
    auto blit=[&](int dx,int dy,int sx,int sy,int width,int height) {
        for(int row=0;row<height;++row)
            std::copy_n(glyphs.rgba.data()+((sy+row)*glyphs.width+sx)*4,width*4,
                        target.rgba.data()+((dy+row)*target.width+dx)*4);
    };
    blit(314,2,hover.holdMode==2?25:0,14,25,8);
    blit(348,2,hover.holdActive?51:78,14,27,8);
    double value=hover.holdMode==2?hover.verticalSpeedTarget:hover.altitudeTarget,scale=1;char suffix=' ';
    if(fabs(value)>=1e9){scale=1e9;suffix='G';}else if(fabs(value)>=1e6){scale=1e6;suffix='M';}else if(fabs(value)>=1e3){scale=1e3;suffix='k';}
    char buffer[32];std::snprintf(buffer,sizeof(buffer),hover.holdMode==2?"%+7.2f%c":"%7.1f%c",value/scale,suffix);
    std::string text(buffer);text.resize(10,' ');
    for(int i=0;i<10;++i) {
        char c=text[i];int column=c>='0'&&c<='9'?c-'0':c=='.'?10:c=='+'?11:c=='-'?12:c=='k'?13:c=='M'?14:c=='G'?15:16;
        blit(314+i*8,12,column*8,0,8,11);
    }
    return true;
}
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
const std::vector<CockpitSphere> &cockpitSpheres() {
    static const std::vector<CockpitSphere> spheres={
#include "CockpitSpheres.inc"
    };return spheres;
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
    }
    double a=direction.length2();if(a<1e-20)return hit;
    for(const auto &sphere:cockpitSpheres()) {
        Vector d=origin-sphere.center;double b=dotp(d,direction),c=d.length2()-sphere.radius*sphere.radius,disc=b*b-a*c;
        if(disc<0)continue;
        double t=(-b-sqrt(disc))/a;if(t<=0)t=(-b+sqrt(disc))/a;
        if(t>0&&t<nearest){nearest=t;hit={sphere.action,0,0};}
    }
    return hit;
}
}

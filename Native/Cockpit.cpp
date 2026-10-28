#include "Cockpit.h"
#include "Mesh.h"
#include "Hover.h"
#include <algorithm>
#include <cmath>
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
const std::vector<CockpitZone> &cockpitMfdZones(){
    // Original MfdSubsystem::clbkLoadVC quads and ProcessMouseVC button spacing.
    static const auto zones=[](){std::vector<CockpitZone> z;
        for(int d=0;d<2;++d)for(int side=0;side<2;++side){double x=(d? .0616:-.2684)+side*.1900;
            Vector p(x,1.2155,7.2751),across(.0168,0,0),down(0,1.0963-1.2155,7.2317-7.2751);
            for(int b=0;b<6;++b){auto top=p+down*(b*4./23),bottom=p+down*((b+.75)*4./23);
                z.push_back({100+d*12+side*6+b,{top,top+across,bottom,bottom+across}});
            }
        }
        return z;
    }();return zones;
}
const std::vector<CockpitZone> &cockpitMfdScreens(){
    // Display quads from the original deltaglider_vc.msh groups 88 and 89.
    static const std::vector<CockpitZone> screens={
        {200,{{{-0.245,1.07624,7.23827},{-0.085,1.07624,7.23827},{-0.245,1.22659,7.29299},{-0.085,1.22659,7.29299}}}},
        {201,{{{ 0.085,1.07624,7.23827},{ 0.245,1.07624,7.23827},{ 0.085,1.22659,7.29299},{ 0.245,1.22659,7.29299}}}}
    };return screens;
}
bool visibleCockpitGroup(size_t group){
    // Original VC pilot body, head and visor; group 132 is the HUD overlay.
    return group!=62&&group!=83&&group!=84&&group!=132;
}
int cockpitNavButton(double u,double v){
    if(!std::isfinite(u)||!std::isfinite(v)||u<0||u>=1||v<0||v>=1)return -1;
    // Directly mirrors RcsProgButtons::ProcessMouseVC's 169 x 63 grid.
    int x=int(u*169),y=int(v*63),column=x/43,row=y/33;
    if(column>3||row>1||x%43>=40||y%33>=30)return -1;
    static const int buttons[2][4]={{0,1,3,5},{-1,2,4,-1}};
    return buttons[row][column];
}
int panelNavButton(double x,double y){
    if(!std::isfinite(x)||!std::isfinite(y)||x<1124||x>=1272||y<62||y>=110)return -1;
    int column=int(x-1124)/37,row=int(y-62)/24;
    static const int buttons[2][4]={{-1,2,4,-1},{0,1,3,5}};
    return buttons[row][column];
}
CockpitHit pickPanel2D(double x,double y){
    if(!std::isfinite(x)||!std::isfinite(y))return {};
    for(int d=0;d<2;++d){
        double offset=d?736:173;
        for(int side=0;side<2;++side){double left=offset+side*348;
            if(x>=left&&x<left+25&&y>=100&&y<323){
                int row=int((y-100)/41);if(row<6&&int(y-100)%41<18)return {100+d*12+side*6+row,0,0};
            }
        }
        double left=d?778:216;
        if(x>=left&&x<left+288&&y>=63&&y<351)return {200+d,(x-left)/288,(y-63)/288};
    }
    auto inside=[&](double x0,double y0,double x1,double y1){return x>=x0&&x<x1&&y>=y0&&y<y1;};
    int navButton=panelNavButton(x,y);if(navButton>=0)return {400+navButton,0,0};
    if(inside(15,18,122,33)){
        int column=int(x-15)/29;
        if(column<=3&&int(x-15)%29<20)return {500+column,0,y-18};
    }
    if(inside(4,122,57,297))return {300,0,y};
    if(inside(4,304,57,444))return {301,0,y};
    if(inside(93,373,125,572))return {302,0,y};
    if(inside(1221,359,1260,473))return {303,0,y};
    if(inside(138,299,158,359))return {304,0,y};
    if(inside(100,69,140,113))return {305,x,0};
    if(inside(87,299,107,359))return {306,0,y};
    if(inside(356,426,396,470))return {307,x,0};
    if(inside(491,415,533,445))return {308,0,0};
    return {};
}
bool paintMfdButtonLabels(Image &target,const Image &original,const std::array<bool,2>&enabled){
    if(original.width<660||original.height<1024||original.rgba.size()!=size_t(original.width)*original.height*4)return false;
    target=original;
    // Glyphs and atlas layout from original MfdButtonCol::RedrawVC.
    const int x[]={81,90,100,110,120,129,138,150,159,164,173,183,192,203,213,224,233,243,253,263,271,281,291,305,314,324};
    const int w[]={9,9,9,9,8,8,10,8,4,7,8,7,10,9,10,8,9,9,8,9,9,9,12,8,9,8};
    const char *labels[]={"HLP","FWD","BCK","VW","VAR","-VR","ADJ","-AJ","++","--","EXE","ENT"};
    auto blit=[&](int dx,int dy,int sx,int sy,int width,int height){for(int row=0;row<height;++row)for(int col=0;col<width;++col)for(int c=0;c<4;++c)
        target.rgba[(size_t(dy+row)*target.width+dx+col)*4+c]=original.rgba[(size_t(sy+row)*original.width+sx+col)*4+c];};
    auto glyph=[&](char c){return c=='+'?std::pair<int,int>{333,6}:c=='-'?std::pair<int,int>{342,6}:std::pair<int,int>{x[c-'A'],w[c-'A']};};
    for(int d=0;d<2;++d)for(int side=0;side<2;++side)for(int b=0;b<6;++b){int y=14+side*41+d*82,center=148+b*40;
        blit(center-16,y,0,128,32,12);if(!enabled[d])continue;
        const char *s=labels[side*6+b];int width=0;for(auto p=s;*p;++p)width+=glyph(*p).second;
        int dx=center-width/2;for(auto p=s;*p;++p){auto [sx,gw]=glyph(*p);blit(dx,y,sx,1012,gw,12);dx+=gw;}
    }
    return true;
}
CockpitHit pickCockpit(const Vector &origin,const Vector &direction) {
    CockpitHit hit;double nearest=std::numeric_limits<double>::max();
    auto testQuad=[&](const CockpitZone &z) {
        Vector a=z.corners[1]-z.corners[0],b=z.corners[2]-z.corners[0],normal=crossp(a,b);
        double den=dotp(normal,direction);if(fabs(den)<1e-14) return;
        double t=dotp(normal,z.corners[0]-origin)/den;if(t<=0||t>=nearest)return;
        Vector delta=origin+direction*t-z.corners[0];
        double aa=dotp(a,a),bb=dotp(b,b),ab=dotp(a,b),det=aa*bb-ab*ab;
        if(det<1e-20)return;
        double u=(dotp(delta,a)*bb-dotp(delta,b)*ab)/det;
        double v=(dotp(delta,b)*aa-dotp(delta,a)*ab)/det;
        if(u>=0&&u<=1&&v>=0&&v<=1) {nearest=t;hit={z.action,u,v};}
    };
    for(const auto &z:cockpitZones())testQuad(z);
    for(const auto &z:cockpitMfdZones())testQuad(z);
    for(const auto &z:cockpitMfdScreens())testQuad(z);
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

// Adapted from the MIT-licensed Delta-glider Horizon.cpp, InstrAoa.cpp and InstrVs.cpp.
#include "CockpitInstruments.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>
namespace native {
namespace {
constexpr double pi=3.14159265358979323846, rad=pi/180, w=512, h=1024;
std::string display(double d){
    char s[64];double a=fabs(d),scale=1;int precision=1;char suffix=' ';
    if(a>=1e12)return "--.-- ";
    if(a>=1e9){scale=1e9;suffix='G';}else if(a>=1e6){scale=1e6;suffix='M';}else if(a>=1e3){scale=1e3;suffix='k';}
    if(scale>1){double n=a/scale;precision=n<10?3:n<100?2:1;std::snprintf(s,sizeof(s),"% .*f%c",precision,d/scale,suffix);}
    else std::snprintf(s,sizeof(s),"% 6.1f ",d);
    return std::string(s+1);
}
void digits(std::vector<Vertex>&v,int offset,int count,const char *s){
    std::string text(s);text.resize(count,' ');
    for(int i=0;i<count;++i){char c=text[i];double dx=0,dy=0;
        if(c>='0'&&c<='9')dy=(c-'0')*17.;
        else {dx=10;dy=c=='.'?0:c=='-'?34:c=='+'?51:c=='k'?68:17;}
        for(int j=0;j<4;++j){v[offset+4*i+j].u=(335.+dx+(j%2)*10)/w;v[offset+4*i+j].v=(600.5+((j<2)?19:0)+dy)/h;}
    }
}
}
void updateHorizon(std::vector<Vertex>&v,double pitch,double bank,double heading,double altitude,double airspeed){
    if(v.size()<80)return;
    const double xp[12]={-108,-54,54,108,-108,-54,54,108,-6,6,-6,6};
    const double yp[12]={54,108,108,54,-54,-108,-108,-54,49,49,37,37};
    double dy=315./(h*2),cnt=(h-450)/h,tv[8]={cnt-dy/2,cnt-dy,cnt-dy,cnt-dy/2,cnt+dy/2,cnt+dy,cnt+dy,cnt+dy/2};
    double bsin=sin(bank),bcos=cos(bank),tilt=20*rad,scale=.055/108;
    for(int i=0;i<12;++i){double x=(bcos*xp[i]+bsin*yp[i])*scale,y=(-bsin*xp[i]+bcos*yp[i])*scale,z=i<8?-.0005:-.001;
        v[i].x=x;v[i].y=1.189+y*cos(tilt)-z*sin(tilt);v[i].z=7.285+y*sin(tilt)+z*cos(tilt);
        if(i<8)v[i].v=tv[i]-pitch*315/(h*(pi/2));
    }
    heading=fmod(heading,2*pi);if(heading<0)heading+=2*pi;
    for(int i=0;i<4;++i)v[12+i].v=1-(i%2?121./h:0)-heading*864/(h*2*pi);
    char head[8];std::snprintf(head,sizeof(head),"%03d",int(heading/rad+.5));
    std::string strings[]={display(altitude),display(airspeed),head};int offsets[]={16,40,64},counts[]={6,6,3};
    for(int k=0;k<3;++k){strings[k].resize(counts[k],' ');for(int i=0;i<counts[k];++i){char c=strings[k][i];double x=c>='0'&&c<='9'?201+(c-'0')*10:c=='.'?301:c=='k'?316:c=='M'?327:c=='G'?337:307.5;
        for(int j=0;j<4;++j)v[offsets[k]+i*4+j].u=(x+(j%2)*10)/w;
    }}
}
void updateFlightTapes(std::vector<Vertex>&v,double aoa,double verticalSpeed){
    if(v.size()<48)return;
    aoa=std::clamp(aoa,-45*rad,45*rad);double a=fabs(aoa)/rad;
    double dy=a<=5?-aoa/rad*12:(a-5)*5+60;if(a>5&&aoa>=0)dy=-dy;
    double y0=std::max(-256.,dy-50),y1=std::min(256.,dy+50);
    double tv0=(y0+517)/h,tv1=(y1+517)/h;
    double low=1.09597-.069540024/2,high=1.09597+.069540024/2;
    double vy0=dy+50>256?high-.069540024*(y1-y0)/100:low;
    double vy1=dy-50< -256?low+.069540024*(y1-y0)/100:high;
    for(int i:{2,3,4,5}){auto &p=v[i];p.y=i<4?vy1:vy0;p.v=i<4?tv0:tv1;p.z=v[6].z+(v[0].z-v[6].z)*(p.y-v[6].y)/(v[0].y-v[6].y);}
    char text[64];std::snprintf(text,sizeof(text),a<10?"%+0.1f":"%+0.0f",aoa/rad);digits(v,8,4,text);
    double vs=verticalSpeed*.1,fraction=vs-floor(vs),center=412;
    if(fabs(vs)<=4)center-=vs*15;else center+=(vs>0?-(5+fraction):(5-fraction))*15;
    v[24].v=v[25].v=(center-50)/h;v[26].v=v[27].v=(center+50)/h;
    if(fabs(vs)<1e3)std::snprintf(text,sizeof(text),fabs(vs)<10?"%+0.1f":"%+0.0f",vs*10);
    else if(fabs(vs)<1e6)std::snprintf(text,sizeof(text),"%+3.0fk",vs>0?floor(vs*.01):ceil(vs*.01));
    else std::snprintf(text,sizeof(text),"----");
    digits(v,28,5,text);
}
bool paintVerticalSpeedScale(Image &target,const Image &original,double verticalSpeed){
    if(original.width!=512||original.height!=1024||original.rgba.size()!=size_t(512*1024*4)||!std::isfinite(verticalSpeed))return false;
    target=original;double vs=verticalSpeed*.1;bool centered=fabs(vs)<=4;
    // Avoid integer overflow on pathological scenario values.
    vs=std::clamp(vs,-1e6,1e6);int vmin=int(floor(vs))-3;
    for(int i=vmin;i<=vmin+7;++i){if(centered&&i==0)continue;int iy=centered?412-i*15-5:i>0?412-(2+i-vmin)*15-5:412+(8-i+vmin)*15-5;
        std::string s=std::to_string(abs((i%1000)*10));
        for(int j=0;j<4;++j){int sy=596+(j<(int)s.size()?(s[j]-'0')*8:80)+(i<0?88:0);
            if(iy<0||iy+8>1024)continue;
            for(int row=0;row<8;++row)std::copy_n(original.rgba.data()+((sy+row)*512+328)*4,24,target.rgba.data()+((iy+row)*512+327+j*6)*4);
        }
    }
    return true;
}
}

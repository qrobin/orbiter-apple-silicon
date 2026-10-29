#include "Weather.h"
#include "Surface.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <fstream>
#include <vector>
namespace native {
namespace {
constexpr size_t Width=2048,Height=1024;
std::vector<unsigned char> cloudMap;
double smooth(double low,double high,double x){double t=std::clamp((x-low)/(high-low),0.,1.);return t*t*(3-2*t);}
double coverage(double lat,double lon){
    if(cloudMap.size()!=Width*Height)return .35;
    double x=(lon/Pi2+.5)*Width-.5,y=(.5-lat/Pi)*Height-.5;
    long ix=(long)floor(x),iy=(long)floor(y);double fx=x-ix,fy=y-iy;
    auto sample=[](long a,long b){a=(a%(long)Width+(long)Width)%Width;b=std::clamp(b,0L,(long)Height-1);return cloudMap[(size_t)b*Width+(size_t)a]/255.;};
    return (sample(ix,iy)*(1-fx)+sample(ix+1,iy)*fx)*(1-fy)+(sample(ix,iy+1)*(1-fx)+sample(ix+1,iy+1)*fx)*fy;
}
double hash(int x,int y,int t){unsigned n=(unsigned)x*0x9e3779b9u^(unsigned)y*0x85ebca6bu^(unsigned)t*0xc2b2ae35u;n^=n>>16;n*=0x7feb352du;n^=n>>15;n*=0x846ca68bu;n^=n>>16;return (n&0xffffffu)/16777216.;}
}
bool loadEarthWeatherMap(const std::filesystem::path &path){
    std::ifstream f(path,std::ios::binary);if(!f)return false;
    std::vector<unsigned char> bytes(Width*Height);f.read((char*)bytes.data(),bytes.size());
    if((size_t)f.gcount()!=bytes.size()||f.peek()!=std::char_traits<char>::eof())return false;
    cloudMap=std::move(bytes);return true;
}
WeatherSample earthWeather(const Vector &position,double mjd,int preset,bool effects){
    WeatherSample result;if(preset<=0||!std::isfinite(mjd)||position.length2()<1)return result;
    double lat,lon;bodyCoordinates(BodyId::Earth,position,mjd,0,lat,lon);
    double altitude=position.length()-body(BodyId::Earth).radius;
    result.cloud=coverage(lat,lon);double clouds=smooth(.06,.78,result.cloud);
    if(preset==3)result.storm=.65+.35*clouds;
    else if(preset==4)result.storm=smooth(.72,.97,result.cloud);
    else if(preset==2)result.storm=.25*smooth(.60,.95,result.cloud);
    double atmosphere=1-smooth(12000,30000,std::max(0.,altitude));
    double rainHeight=1-smooth(7000,10500,std::max(0.,altitude));
    result.rain=result.storm*rainHeight;
    auto frame=bodySurface(BodyId::Earth,lat,lon,mjd);
    double seconds=(mjd-51544.5)*86400.;
    double zonal=(cos(3*lat)>0?-1:1)*(5+9*fabs(sin(2*lat))+24*result.storm);
    double north=4*sin(lon*2+lat*3)+8*result.storm*sin(lon*5-lat*2);
    double gust=result.storm*(3*sin(seconds*.31+lon*12)+2*sin(seconds*.77+lat*19));
    result.wind=(frame.east*(zonal+gust)+frame.north*(north+gust*.35))*atmosphere;
    if(!effects||result.storm<.45||rainHeight<=0)return result;
    // Stable world-space lightning cells: brief repeated flashes, not attached to the vessel.
    int ix=(int)floor((lon+Pi)*400),iy=(int)floor((lat+Pi*.5)*400);
    double period=19.,clock=fmod(seconds,period*1000000.);int cycle=(int)floor(clock/period);double phase=clock-cycle*period;
    double t=phase-(2+hash(ix,iy,cycle)*14);
    double pulse=(t>=0&&t<.45)?std::max(exp(-t*22),.65*exp(-fabs(t-.18)*35)):0;
    result.flash=pulse*smooth(.45,.75,result.storm)*rainHeight;
    double flashLat=std::clamp((iy+.5)/400-Pi*.5+(.5-hash(ix,iy,cycle+17))*.001,-Pi*.5,Pi*.5);
    double flashLon=(ix+.5)/400-Pi+(.5-hash(ix,iy,cycle+39))*.001;
    result.lightning=bodySurface(BodyId::Earth,flashLat,flashLon,mjd).up*(body(BodyId::Earth).radius+30);
    return result;
}
}

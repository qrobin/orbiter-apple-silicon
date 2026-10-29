#include "Weather.h"
#include "Flight.h"
#include "Surface.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool condition,const char *message){if(!condition)throw std::runtime_error(message);}
int main(){try{
    check(loadEarthWeatherMap(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/earth-clouds.r8"),"Load satellite weather map");
    constexpr double date=51982.5292925579;
    auto position=[&](double lat,double lon,double altitude){return bodySurface(BodyId::Earth,Rad(lat),Rad(lon),date).up*(EarthRadius+altitude);};
    Vector dryPosition,cloudyPosition;double minimum=2,maximum=-1;
    for(int lat=-60;lat<=60;lat+=10)for(int lon=-180;lon<180;lon+=10){
        Vector p=position(lat,lon,2000);double c=earthWeather(p,date,4,false).cloud;
        if(c<minimum){minimum=c;dryPosition=p;}if(c>maximum){maximum=c;cloudyPosition=p;}
    }
    auto dry=earthWeather(dryPosition,date,4),cloudy=earthWeather(cloudyPosition,date,4);
    check(cloudy.cloud>dry.cloud+.3&&cloudy.storm>dry.storm+.3,"Regional weather differs between satellite cloud systems");
    auto storm=earthWeather(dryPosition,date,3),clear=earthWeather(dryPosition,date,0);
    check(storm.rain>.5&&storm.wind.length()>15&&clear.rain==0&&clear.wind.length()==0,"Storm has rain and strong winds; clear is calm");
    double wet=updateGlassWetness(0,1,100,5),drying=updateGlassWetness(wet,0,100,5);
    check(wet>.5&&drying>0&&drying<wet,"Cockpit glass gets wet in rain and dries gradually afterwards");
    check(updateGlassWetness(wet,0,100,0)==wet&&updateGlassWetness(wet,0,250,5)<drying,"Paused wetness is stable and faster airflow clears water sooner");
    check(updateGlassWetness(0,1,250,30)<updateGlassWetness(0,1,0,30)*.5,"Fast flight reduces water accumulation even in continuing rain");
    check(fabs(dotp(storm.wind,dryPosition.unit()))<1e-8,"Weather wind follows the local surface");
    bool sawLightning=false;
    for(int i=0;i<3800;++i){
        double now=date+i*.01/86400.;
        Vector here=bodySurface(BodyId::Earth,Rad(10),Rad(-100),now).up*(EarthRadius+2000);
        auto sample=earthWeather(here,now,3);
        if(sample.flash>.1){sawLightning=true;check(sample.lightning.dist(here)<35000,"Lightning stays in the local storm cell");}
    }
    check(sawLightning,"Storms produce brief lightning flashes");
    auto high=earthWeather(position(0,0,50000),date,3);
    check(high.rain==0&&high.wind.length()==0,"Rain and wind fade out above the atmosphere");
    check(!loadEarthWeatherMap("/not/a/weather/map")&&earthWeather(cloudyPosition,date,4).cloud==cloudy.cloud,"A missing map does not replace existing weather data");
    Flight a;a.load(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/Scenarios/Atlantic Ocean flight.scn");Flight b=a;
    a.weatherPreset=0;b.weatherPreset=3;check((a.airRelativeVelocity()-b.airRelativeVelocity()).length()>15,"Regional wind affects air-relative velocity");
    for(int i=0;i<120;++i){a.advance(1./120);b.advance(1./120);}
    check(a.velocity.dist(b.velocity)>.01,"Wind affects aerodynamic flight forces");
    std::cout<<"regional weather checks passed\n";
}catch(const std::exception &error){std::cerr<<error.what()<<'\n';return 1;}}

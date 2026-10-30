#include "Flight.h"
#include "SolarSystem.h"
#include "Surface.h"
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
struct Scenario {const char *file;double latitude,longitude,height;int weather;};
int main(){try{
    auto root=std::filesystem::path(ORBITER_TEST_DATA);
    loadEphemerides(root/"Src/Celbody");
    check(loadEarthWeatherMap(root/"Native/Assets/earth-clouds.r8"),"Load the weather map");
    const Scenario cases[]={
        {"Atlantic Ocean flight.scn",20,-40,5000,4},
        {"Hawaii sunset.scn",20.5,-156.5,4000,1},
        {"Gulf of Mexico storm.scn",25,-90,2500,3},
        {"Mediterranean clear flight.scn",35,18,5000,0},
        {"France low flight.scn",46,2,400,0}
    };
    for(auto &scenario:cases){
        Flight f;f.load(root/"Native/Assets/Scenarios"/scenario.file);
        double lat,lon;bodyCoordinates(BodyId::Earth,f.position,f.mjd,0,lat,lon);
        check(f.reference==BodyId::Earth&&!f.groundContact&&!bodyRotationsPaused(),"Scenario starts airborne with normal Earth rotation");
        check(fabs(Deg(lat)-scenario.latitude)<.001&&fabs(Deg(lon)-scenario.longitude)<.001,"Scenario starts at its named location");
        check(fabs(f.altitude()-scenario.height)<.1&&fabs(f.airRelativeVelocity().length()-250)<.1,"Scenario starts at its intended altitude and airspeed");
        check(f.weatherPreset==scenario.weather&&dotp(f.forward,f.airRelativeVelocity().unit())>.999,"Weather loads and aircraft faces the airflow");
        check(f.atmosphericAvailable(),"Flight stabilization is available");
        check(f.atmospheric.active[0]&&f.atmospheric.active[1]&&f.atmospheric.active[2],"Preset begins with altitude, airspeed and level-bank holds engaged");
        if(scenario.weather==3)check(f.currentWeather().rain>.5&&f.currentWeather().wind.length()>15,"Storm produces rain and strong wind");
        if(scenario.latitude==20.5){
            auto sun=[&](double date){return (-bodyState(BodyId::Earth,date).position-bodySurface(BodyId::Earth,lat,lon,date).up*(EarthRadius+scenario.height)).unit();};
            auto frame=bodySurface(BodyId::Earth,lat,lon,f.mjd);
            double elevation=asin(dotp(frame.up,sun(f.mjd)));
            auto later=bodySurface(BodyId::Earth,lat,lon,f.mjd+120./86400.);
            check(fabs(Deg(elevation)-4)<.1&&dotp(later.up,sun(f.mjd+120./86400.))<sin(elevation),"Hawaii starts at a descending sunset");
            check(dotp(f.forward,sun(f.mjd))>.99,"Sunset is visible ahead of the cockpit");
        }
        for(int i=0;i<1200;++i)f.advance(.05);
        std::cout<<scenario.file<<": after 60s altitude="<<f.altitude()<<" speed="<<f.airRelativeVelocity().length()<<'\n';
        check(!f.impacted&&fabs(f.altitude()-scenario.height)<100&&fabs(f.airRelativeVelocity().length()-250)<10,"Each cruise start remains stable for a minute");
    }
    Flight storm;storm.load(root/"Native/Assets/Scenarios/Gulf of Mexico storm.scn");
    auto save=std::filesystem::temp_directory_path()/"orbiter-atmospheric-weather-test.scn";storm.save(save);
    Flight restored;restored.load(save);check(restored.weatherPreset==3,"Saved weather survives reopening");
    check(restored.atmospheric.active[0]&&restored.atmospheric.active[1]&&restored.atmospheric.active[2]&&fabs(restored.atmospheric.target[0]-2500)<.01,"Saved atmospheric holds survive reopening");
    std::ofstream(save)<<"BEGIN_ENVIRONMENT\n NATIVE_WEATHER 7\nEND_ENVIRONMENT\n";
    bool rejected=false;try{restored.load(save);}catch(const std::exception &){rejected=true;}
    check(rejected&&restored.weatherPreset==3,"Invalid weather is rejected without changing the flight");std::filesystem::remove(save);
    Flight legacy;legacy.weatherPreset=2;legacy.load(root/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    check(legacy.weatherPreset==2,"Original scenarios preserve the selected weather");
    std::cout<<"atmospheric scenario checks passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}

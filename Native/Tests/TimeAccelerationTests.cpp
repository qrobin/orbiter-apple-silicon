#include "Flight.h"
#include "TimeAcceleration.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){try{
    double rate=1;
    for(double expected:TimeAccelerationRates){
        check(rate==expected,"Increasing selects each acceleration rate in order");
        rate=stepTimeAcceleration(rate,true);
    }
    check(rate==MaximumTimeAcceleration,"Increasing stops at the highest supported rate");
    for(auto it=TimeAccelerationRates.rbegin();it!=TimeAccelerationRates.rend();++it){
        check(rate==*it,"Decreasing selects each acceleration rate in order");
        rate=stepTimeAcceleration(rate,false);
    }
    check(rate==1,"Decreasing stops at normal time");
    check(stepTimeAcceleration(7,true)==10&&stepTimeAcceleration(7,false)==5,"Rates between steps select their nearest neighbor");
    for(double speed:TimeAccelerationRates){
        Flight flight;double radius=EarthRadius+400000;
        flight.position={radius,0,0};flight.velocity={0,0,sqrt(Mu/radius)};
        flight.warp=speed;flight.advance(.01);
        check(fabs(flight.elapsed-.01*speed)<1e-9,"Selected rate advances the requested simulation time");
        check(fabs(flight.position.length()-radius)<.1,"Accelerated coasting retains the circular orbit");
    }
    std::cout<<TimeAccelerationRates.size()<<" acceleration rates verified\n";
}catch(const std::exception &error){std::cerr<<error.what()<<'\n';return 1;}}

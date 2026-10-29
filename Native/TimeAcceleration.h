#pragma once
#include <algorithm>
#include <array>
#include <cmath>

namespace native {
inline constexpr std::array<double,16> TimeAccelerationRates={
    1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000,100000
};
inline constexpr double MaximumTimeAcceleration=TimeAccelerationRates.back();

inline double stepTimeAcceleration(double current,bool increase) {
    if(!std::isfinite(current))return 1;
    if(increase){
        auto next=std::upper_bound(TimeAccelerationRates.begin(),TimeAccelerationRates.end(),current);
        return next==TimeAccelerationRates.end()?TimeAccelerationRates.back():*next;
    }
    auto next=std::lower_bound(TimeAccelerationRates.begin(),TimeAccelerationRates.end(),current);
    return next==TimeAccelerationRates.begin()?TimeAccelerationRates.front():*--next;
}
}

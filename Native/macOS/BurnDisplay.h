#pragma once
#import <Cocoa/Cocoa.h>
#include "TransX/Session.h"

static NSString *burnDuration(double seconds) {
    if(!std::isfinite(seconds)||seconds<0)return @"—";
    unsigned long long n=(unsigned long long)std::min(std::ceil(seconds),1e12);
    unsigned long long days=n/86400,hours=(n/3600)%24,minutes=(n/60)%60,secs=n%60;
    return days?[NSString stringWithFormat:@"%llud %02llu:%02llu:%02llu",days,hours,minutes,secs]:[NSString stringWithFormat:@"%02llu:%02llu:%02llu",hours,minutes,secs];
}
static NSString *burnTimingText(int stage,const native::transx::BurnTiming &timing) {
    double ignition=timing.secondsToBurn-timing.duration*.5;
    return [NSString stringWithFormat:@"STEP %d  IGN T%@%@  ·  BURN ~%@%@",stage,ignition>=0?@"−":@"+",burnDuration(fabs(ignition)),burnDuration(timing.duration),timing.sufficientFuel?@"":@" · LOW FUEL"];
}

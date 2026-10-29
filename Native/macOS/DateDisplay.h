#pragma once
#import <Cocoa/Cocoa.h>
#include "TransX/SDK.h"

// Both the native panels and TransX use the same UTC Gregorian conversion.
static NSString *simulationDate(double mjd) {
    char date[32];
    return native::transx::formatCalendarUTC(mjd,date,sizeof(date))?[NSString stringWithUTF8String:date]:@"—";
}
static bool parseSimulationDate(NSString *text,double &mjd) {
    NSString *value=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return native::transx::parseCalendarUTC(value.UTF8String,mjd);
}

#import <Cocoa/Cocoa.h>
#include "Flight.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
using namespace native;
@class GliderPanel;
@interface FlightView : NSView {
@public
    Flight flight;
    NSString *status;
}
@property(nonatomic,strong) GliderPanel *systemsPanel;
- (void)clearInput;
- (void)toggleHoverHold:(id)sender;
@end
@implementation FlightView
- (void)clearInput {}
- (void)toggleHoverHold:(id)sender {}
@end
#include "../macOS/GliderPanel.inc"
@interface GliderPanel (TestActions)
- (void)changeAirTarget:(NSTextField *)sender;
- (void)captureAirTarget:(NSButton *)sender;
- (void)toggleAirHold:(NSButton *)sender;
- (void)changeEngine:(NSSlider *)sender;
@end
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    [NSApplication sharedApplication];
    FlightView *view=[[FlightView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    view->flight.load(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/Scenarios/Atlantic Ocean flight.scn");
    GliderPanel *panel=[[GliderPanel alloc] initWithFlightView:view];
    NSArray<NSTextField *> *targets=[panel valueForKey:@"airTargets"];
    NSArray<NSButton *> *holds=[panel valueForKey:@"airHolds"];
    check(targets.count==4&&holds.count==4,"Panel exposes all four atmospheric holds");
    check(fabs(targets[0].doubleValue-5000)<1&&fabs(targets[1].doubleValue-250)<.1,"Panel starts with current flight targets");
    targets[0].doubleValue=5300;[panel changeAirTarget:targets[0]];
    holds[0].state=NSControlStateValueOn;[panel toggleAirHold:holds[0]];
    check(view->flight.atmospheric.active[0]&&view->flight.atmospheric.target[0]==5300,"Panel altitude target and hold operate flight controller");
    holds[1].state=NSControlStateValueOn;[panel toggleAirHold:holds[1]];check(view->flight.atmospheric.active[1],"Panel engages airspeed hold");
    NSArray<NSSlider *> *sliders=[panel valueForKey:@"engineSliders"];sliders[0].doubleValue=.3;[panel changeEngine:sliders[0]];
    check(!view->flight.atmospheric.active[1]&&fabs(view->flight.throttle-.3)<1e-9,"Panel throttle releases airspeed hold");
    targets[3].doubleValue=110;[panel changeAirTarget:targets[3]];holds[3].state=NSControlStateValueOn;[panel toggleAirHold:holds[3]];
    check(view->flight.atmospheric.active[3]&&view->flight.atmospheric.active[2]&&!targets[2].enabled,"Heading hold controls the bank target");
    [[panel valueForKey:@"refreshTimer"] invalidate];[panel close];
    std::cout<<"atmospheric panel checks passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

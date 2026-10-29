#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include "Flight.h"
#include "SolarSystem.h"
#import "TransXDrawing.h"
#include <array>
#include <iostream>
#include <stdexcept>
using namespace native;
@class RoutePanel;

@interface TransXPanel : NSWindowController
- (void)refresh;
@end
@implementation TransXPanel
- (void)refresh {}
@end
@interface FlightView : NSView {
@public
    Flight flight;
    std::unique_ptr<native::transx::Session> transxSession;
    std::array<native::transx::Frame,3> transxFrames;
    int transxAlignDisplay;
}
@property(nonatomic,strong) TransXPanel *navigationPanel;
@property(nonatomic,strong) RoutePanel *routePanel;
- (void)ensureTransX;
- (void)clearInput;
- (void)showNavigation:(id)sender;
@end
@implementation FlightView
- (void)ensureTransX {if(!transxSession)transxSession=std::make_unique<native::transx::Session>(flight);}
- (void)clearInput {}
- (void)showNavigation:(id)sender {}
@end
@interface FlippedGliderDocument : NSView
@end
@implementation FlippedGliderDocument
- (BOOL)isFlipped{return YES;}
@end
@interface TransXCanvas : NSView
@property(nonatomic,weak) FlightView *flightView;
@property(nonatomic) int display;
@end
@implementation TransXCanvas
- (BOOL)isFlipped{return YES;}
- (void)drawRect:(NSRect)dirty {if(self.flightView)paintTransX(self.flightView->transxFrames[self.display],self.bounds);}
@end
@interface RoutePanel : NSWindowController
- (instancetype)initWithFlightView:(FlightView *)view;
- (void)refresh;
- (void)updateControls;
- (void)createRoute:(id)sender;
- (void)applyTransfer:(id)sender;
- (void)applyBurn:(id)sender;
- (void)align:(id)sender;
- (void)release:(id)sender;
- (void)estimate:(id)sender;
- (void)setTime:(NSButton *)sender;
- (void)controlTextDidChange:(NSNotification *)notification;
@end
@interface FlightView (RouteControls)
- (void)showRoutePlanner:(id)sender;
@end
#include "../macOS/RoutePanel.inc"

static int checks=0;
static void check(bool ok,const char *message){++checks;if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool {try{
    [NSApplication sharedApplication];
    loadEphemerides(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Celbody");
    FlightView *view=[[FlightView alloc] initWithFrame:NSMakeRect(0,0,800,600)];
    view->flight.load(std::filesystem::path(ORBITER_TEST_DATA)/"Scenarios/Delta-glider/DG Mk4 in orbit.scn");
    [view ensureTransX];for(int i=0;i<100;++i)view->transxSession->tick();
    RoutePanel *panel=[[RoutePanel alloc] initWithFlightView:view];
    NSScrollView *scroll=(NSScrollView *)panel.window.contentView;NSView *doc=scroll.documentView;
    NSPopUpButton *destination=nil;NSMutableArray<NSTextField *> *fields=[NSMutableArray arrayWithCapacity:8];
    for(int i=0;i<8;++i)[fields addObject:(NSTextField *)[NSNull null]];
    NSMutableArray<NSView *> *interactive=[NSMutableArray new];
    for(NSView *item in doc.subviews){
        check(NSContainsRect(doc.bounds,item.frame),"Control fits inside the route document");
        if([item isKindOfClass:NSPopUpButton.class]&&[item.accessibilityLabel isEqualToString:@"Route destination"])destination=(NSPopUpButton *)item;
        if([item isKindOfClass:NSTextField.class]&&[(NSTextField *)item isEditable]&&item.tag>=0&&item.tag<8)fields[item.tag]=(NSTextField *)item;
        if([item isKindOfClass:NSButton.class]||[item isKindOfClass:NSPopUpButton.class]||
           ([item isKindOfClass:NSTextField.class]&&[(NSTextField *)item isEditable]))[interactive addObject:item];
    }
    for(NSUInteger i=0;i<interactive.count;++i)for(NSUInteger j=i+1;j<interactive.count;++j)
        check(!NSIntersectsRect(interactive[i].frame,interactive[j].frame),"Interactive controls do not overlap");
    check(destination!=nil,"Destination selector exists");
    check(destination.selectedItem.tag==(NSInteger)BodyId::Mars,"Mars is the default destination from Earth");
    for(id field in fields)check(field!=NSNull.null,"A numeric route field exists");
    [panel updateControls];check(!fields[1].enabled&&!fields[5].enabled,"Fields are disabled before a route exists");
    [destination selectItemWithTag:(NSInteger)BodyId::Mars];[panel createRoute:nil];[panel updateControls];
    transx::Route route;check(view->transxSession->currentRoute(route)&&route.destination==BodyId::Mars,"Create route drives the original TransX state");
    check(fields[1].enabled&&fields[5].enabled,"Transfer and burn fields are enabled for Mars");
    transx::RouteValues values;check(view->transxSession->routeValues(route,false,values),"Initial ejection values are available");
    [panel estimate:nil];check(fields[1].doubleValue>1000&&values.prograde==0,"Estimate fills a draft without changing the TransX plan");
    NSButton *time=[NSButton buttonWithTitle:@"In 1 h" target:nil action:nullptr];time.tag=1;[panel setTime:time];
    check(fabs(fields[4].doubleValue-(view->flight.mjd+view->flight.elapsed/86400.+1./24.))<1e-6,"Time shortcut uses the simulation clock");
    fields[1].stringValue=@"3000";
    [panel controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:fields[1]]];
    [panel updateControls];check([fields[1].stringValue isEqualToString:@"3000"],"Refresh preserves an unapplied edit");
    [panel applyTransfer:nil];[panel updateControls];
    check(view->transxSession->routeValues(route,false,values)&&fabs(values.prograde-3000)<.001,"Transfer is applied to TransX");
    fields[5].stringValue=@"nan";[panel applyBurn:nil];
    check(view->transxSession->routeValues(route,true,values)&&values.prograde==0,"Invalid input does not alter the burn");
    fields[5].stringValue=@"3500";
    [panel controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:fields[5]]];
    [panel applyBurn:nil];[panel updateControls];
    check(view->transxSession->routeValues(route,true,values)&&fabs(values.prograde-3500)<.001,"Burn is applied to the original maneuver");
    double fuel=view->flight.fuel,throttle=view->flight.throttle;[panel align:nil];
    check(view->flight.assist==Assist::Maneuver&&view->transxAlignDisplay==transx::Session::RouteDisplay,"Align engages departure RCS guidance");
    check(view->flight.fuel==fuel&&view->flight.throttle==throttle,"The planner never commands the main engines");
    [panel release:nil];check(view->flight.assist==Assist::Free,"Release turns off maneuver alignment");
    NSString *preview=NSProcessInfo.processInfo.environment[@"ORBITER_ROUTE_PREVIEW"];
    if(preview.length){
        [panel updateControls];[doc layoutSubtreeIfNeeded];
        [panel.window setFrameOrigin:NSMakePoint(-10000,-10000)];[panel.window orderFront:nil];[panel.window display];
        NSBitmapImageRep *image=[doc bitmapImageRepForCachingDisplayInRect:doc.bounds];
        [doc cacheDisplayInRect:doc.bounds toBitmapImageRep:image];
        CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(nullptr,image.pixelsWide,image.pixelsHigh,8,0,colors,kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(context,.12,.12,.12,1);CGContextFillRect(context,CGRectMake(0,0,image.pixelsWide,image.pixelsHigh));
        CGContextDrawImage(context,CGRectMake(0,0,image.pixelsWide,image.pixelsHigh),image.CGImage);
        CGImageRef rendered=CGBitmapContextCreateImage(context);
        NSBitmapImageRep *composite=[[NSBitmapImageRep alloc] initWithCGImage:rendered];
        [[composite representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:preview atomically:YES];
        CGImageRelease(rendered);CGContextRelease(context);CGColorSpaceRelease(colors);
        [panel.window orderOut:nil];
    }
    std::cout<<checks<<" route panel checks passed\n";
}catch(const std::exception &error){std::cerr<<"After "<<checks<<" checks: "<<error.what()<<'\n';return 1;}return 0;}}

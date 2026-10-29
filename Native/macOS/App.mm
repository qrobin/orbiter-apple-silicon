#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include "Flight.h"
#include "TimeAcceleration.h"
#include "TransX/BurnSkip.h"
#include "Mesh.h"
#include "Cockpit.h"
#include "Surface.h"
#include "Base.h"
#include "Camera.h"
#import "NativeVisuals.h"
#import "SolarRenderer.h"
#include "SolarSystem.h"
#import "TransXDrawing.h"
#import "BurnDisplay.h"
#import "DateDisplay.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <fstream>
#include <numeric>
#include <vector>
using namespace native;
static NSString *resource(NSString *p) { return [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:p]; }
static simd_float4 f4(const Vector &v,float w=0) { return {(float)v.x,(float)v.y,(float)v.z,w}; }
static simd_float4x4 projection(float aspect,float t) {
    // Reversed infinite depth preserves centimetre-scale ground overlays even
    // when the visible Earth surface is kilometres from the camera.
    float n=.2f; simd_float4x4 m={};
    m.columns[0]={1/(aspect*t),0,0,0}; m.columns[1]={0,1/t,0,0};
    m.columns[2]={0,0,0,-1}; m.columns[3]={0,0,n,0}; return m;
}
struct SwitchUniforms { simd_float4 pivotAngle,axisStart,range; };
struct ObjectUniforms { simd_float4x4 model; simd_float4 color,options; };
struct GpuGroup { id<MTLBuffer> vertices,indices; NSUInteger count; size_t material,texture,index; int mesh; };
@class FlightView;
@class GliderPanel;
@class TransXPanel;
@interface RoutePanel : NSWindowController
- (instancetype)initWithFlightView:(FlightView *)view;
- (void)refresh;
- (void)updateControls;
@end
@interface Panel2DView : NSView
@property(nonatomic,weak) FlightView *flightView;
- (void)setDisplayImage:(NSBitmapImageRep *)image index:(int)display;
- (NSRect)panelRect;
- (void)tick;
- (void)cancelInteraction;
@end
@interface FlightHUD : NSView
@property(nonatomic,weak) FlightView *flightView;
- (void)paint:(NSRect)bounds;
@end
@interface FlightView : MTKView<MTKViewDelegate> {
@public
    Flight flight;
    std::array<bool,256> held;
    double fps,cpuMs,gpuMs,cockpitYaw,cockpitPitch;
    OrbitCamera externalCamera;
    CockpitCamera cockpitCamera;
    bool helpVisible,cockpit,panelView,orbitVisible,demoLadderQueued;
    NSString *status,*navigationStatus;
    NSInteger navigationTarget;
    std::unique_ptr<native::transx::Session> transxSession;
    native::transx::BurnSkip burnSkip;
    std::array<native::transx::Frame,3> transxFrames;
    std::array<bool,2> transxMfd;
    int transxAlignDisplay;
    BodyId transxAlignBody;
    double transxRefresh;
@private
    id<MTLCommandQueue> queue;
    NativeVisuals *visuals;
    SolarRenderer *solar;
    NSInteger restartBody;
    BodyId lastBody;
    bool rcsDemo;
    NSPoint lastDragPoint;
    bool haveDragPoint;
    id<MTLRenderPipelineState> meshPipeline,skyPipeline;
    id<MTLDepthStencilState> depthState,skyDepth,transparentDepth;
    std::array<size_t,2> meshCounts;
    std::vector<GpuGroup> groups;
    std::vector<Material> materials;
    NSMutableArray<id<MTLTexture>> *textures;
    id<MTLTexture> earthTexture,whiteTexture;
    id<MTLTexture> hoverReadoutTexture,mfdLabelTexture;
    std::array<id<MTLTexture>,2> maneuverButtonTextures;
    Image mfdLabelImage,mfdLabelOriginal;
    std::array<bool,2> lastMfdLabels;
    Image hoverReadoutImage,hoverGlyphs;
    std::array<id<MTLTexture>,2> instrumentTextures;
    int activeCockpitControl;
    double activeCockpitDirection;
    CFTimeInterval previous,begin,lastHud;
    NSUInteger frameCount,smokeFrames;
    double cpuSum,gpuSum;
    std::vector<double> intervals;
    NSString *capturePath,*reportPath,*restartScenario;
    SurfaceBase surfaceBase;
    dispatch_semaphore_t inflight;
}
@property(nonatomic,strong) FlightHUD *hud;
@property(nonatomic,strong) GliderPanel *systemsPanel;
@property(nonatomic,strong) TransXPanel *navigationPanel;
@property(nonatomic,strong) RoutePanel *routePanel;
@property(nonatomic,strong) Panel2DView *panel2D;
- (void)resetFlight:(id)sender;
- (void)demonstrateGlider:(id)sender;
- (void)startSurface:(id)sender;
- (void)startOrbit:(id)sender;
- (void)startHoverPractice:(id)sender;
- (void)toggleHoverHold:(id)sender;
- (void)toggleHoverAttitude:(id)sender;
- (void)holdCurrentAltitude:(id)sender;
- (void)holdZeroVerticalSpeed:(id)sender;
- (void)toggleParkingBrake:(id)sender;
- (void)openScenario:(id)sender;
- (void)saveScenario:(id)sender;
- (void)pauseFlight:(id)sender;
- (void)skipToBurn:(id)sender;
- (void)toggleHelp:(id)sender;
- (void)clearInput;
- (void)cycleWeather:(id)sender;
- (void)startBodyOrbit:(NSMenuItem *)sender;
- (void)setWeather:(NSMenuItem *)sender;
- (void)updateCockpitDisplays;
- (void)setViewMode:(int)mode;
- (void)cycleView:(id)sender;
- (void)chooseView:(NSMenuItem *)sender;
- (void)selectNavButton:(int)button;
- (void)chooseNavProgram:(NSMenuItem *)sender;
- (void)chooseHudMode:(NSMenuItem *)sender;
- (void)cycleHudColour:(id)sender;
- (void)adjustHudBrightness:(NSMenuItem *)sender;
- (void)chooseExternalCamera:(NSMenuItem *)sender;
- (void)chooseCameraReference:(NSMenuItem *)sender;
- (void)cycleExternalCamera:(id)sender;
- (void)applyExternalCamera:(ExternalCameraMode)mode reference:(BodyId)reference;
@end
@interface FlightView (NavigationControls)
- (void)showNavigation:(id)sender;
- (void)updateNavigation;
- (void)resetNavigation;
- (NSDictionary *)navigationReport;
- (void)prepareNavigation:(BodyId)targetId;
- (void)ensureTransX;
- (void)showTransXGuide:(id)sender;
- (void)operateTransXButton:(int)button display:(int)display;
- (void)rotateTransXGraph:(int)display horizontal:(double)dx vertical:(double)dy;
- (void)resetTransXGraph:(int)display;
- (void)toggleTransXMFD:(NSMenuItem *)sender;
- (void)loadTransXScenario:(NSString *)path;
- (void)saveTransXScenario:(NSString *)path;
@end
@interface FlightView (RouteControls)
- (void)showRoutePlanner:(id)sender;
@end
@interface FlightView (GliderControls)
- (void)showSystems:(id)sender;
- (void)toggleMechanism:(id)sender;
@end

static NSString *burnCountdown(FlightView *view) {
    if(!view||!view->transxSession)return nil;
    auto &session=*view->transxSession;int stage=session.selectedStage();native::transx::BurnTiming timing;
    if(!stage||!session.stageTiming(stage,timing))return nil;
    return burnTimingText(stage,timing);
}

@implementation FlightHUD
- (BOOL)isOpaque { return NO; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel { return @"Flight instruments"; }
- (id)accessibilityValue {
    FlightView *v=self.flightView; if(!v) return @"Loading";
    auto &f=v->flight;
    auto &hover=f.glider.hoverControl;
    NSString *holdState=hover.holdActive?[NSString stringWithFormat:@"%@ %.1f",hover.holdMode==1?@"altitude hold":@"vertical speed hold",hover.holdMode==1?hover.altitudeTarget:hover.verticalSpeedTarget]:@"off";
    NSString *clock=burnCountdown(v)?:@"No planned burn";
    NSString *date=simulationDate(f.mjd+f.elapsed/86400.);
    if(f.altitude()<std::min(120000.,f.centralBody().radius*.02)) return [NSString stringWithFormat:@"%@, altitude %.1f metres, ground speed %.2f metres per second, vertical speed %+.1f, heading %.1f degrees, main throttle %.0f percent, hover %.0f percent, parking brake %@, fuel %.1f kg, hold %@, controls %@, %@ UTC, %@",
        f.paused?@"Paused":f.groundContact?@"On the ground":@"Flying",f.altitude(),f.groundSpeed,f.surfaceVerticalSpeed(),Deg(f.heading()),f.throttle*100,f.glider.hover*100,f.glider.parkingBrake?@"set":@"released",f.fuel,holdState,v->helpVisible?@"visible":@"hidden",date,clock];
    return [NSString stringWithFormat:@"%@, altitude %.2f km, speed %.2f m/s, throttle %.0f percent, fuel %.1f kg, time acceleration %.0f, controls %@, %@ UTC, %@",
        v->flight.paused?@"Paused":v->flight.groundContact?@"On the ground":@"Flying",v->flight.altitude()/1000,v->flight.altitude()<std::min(120000.,v->flight.centralBody().radius*.02)?v->flight.groundSpeed:v->flight.velocity.length(),v->flight.throttle*100,v->flight.fuel,v->flight.warp,v->helpVisible?@"visible":@"hidden",date,clock];
}
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (void)drawRect:(NSRect)rect { [self paint:self.bounds]; }
static void text(NSString *s,CGFloat x,CGFloat y,CGFloat size,NSColor *color,BOOL mono=NO) {
    NSFont *font=mono?[NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightRegular]:[NSFont systemFontOfSize:size weight:NSFontWeightMedium];
    [s drawAtPoint:NSMakePoint(x,y) withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}];
}
static void line(CGFloat x,CGFloat y,CGFloat x2,CGFloat y2,NSColor *color,CGFloat width=1) {
    [color setStroke]; NSBezierPath *p=[NSBezierPath bezierPath]; p.lineWidth=width;
    [p moveToPoint:NSMakePoint(x,y)]; [p lineToPoint:NSMakePoint(x2,y2)]; [p stroke];
}
- (void)paint:(NSRect)b {
    FlightView *v=self.flightView; if(!v) return;
    Flight &f=v->flight;double radius=f.centralBody().radius;NSString *bodyName=[NSString stringWithUTF8String:f.centralBody().name]; CGFloat w=b.size.width,h=b.size.height;
    NSColor *ink=[NSColor colorWithRed:.76 green:.94 blue:.79 alpha:1];
    NSColor *muted=[NSColor colorWithRed:.60 green:.72 blue:.66 alpha:1];
    NSColor *white=[NSColor colorWithWhite:.95 alpha:1];
    NSColor *panel=[NSColor colorWithRed:.025 green:.045 blue:.04 alpha:.91];
    NSString *mode=@"MANUAL";
    switch(f.assist) { case Assist::Prograde: mode=@"PROGRADE";break; case Assist::Retrograde:mode=@"RETROGRADE";break;case Assist::Normal:mode=@"NORMAL";break;case Assist::AntiNormal:mode=@"ANTI-NORMAL";break;case Assist::HorizonLevel:mode=@"HORIZON LEVEL";break;case Assist::KillRotation:mode=@"KILL ROTATION";break;case Assist::Maneuver:mode=@"MANEUVER ALIGN";break;default:break; }
    auto warning=f.glider.warning();
    NSString *burn=burnCountdown(v);
    bool parkingNotice=f.glider.parkingBrake&&f.altitude()<1000;
    CGFloat headerHeight=parkingNotice?154:!warning.empty()?132:v->status.length?110:78;
    headerHeight=std::max(headerHeight,burn?128.:104.);
    [panel setFill];NSRectFill(NSMakeRect(0,h-headerHeight,w,headerHeight));
    NSRectFill(NSMakeRect(0,0,w,28));
    text(@"Orbiter",26,h-44,22,white);
    text([NSString stringWithFormat:@"Delta-glider  /  %s  /  %@",f.name.c_str(),bodyName],26,h-66,12,muted);
    text(v->burnSkip.running()?[NSString stringWithFormat:@"SKIPPING   ·   T+ %.0f s",f.elapsed]:[NSString stringWithFormat:@"%@   ·   %.0f×   ·   T+ %.0f s",f.paused?@"PAUSED":@"FLIGHT",f.warp,f.elapsed],w-320,h-37,12,ink,YES);
    text([NSString stringWithFormat:@"Metal  ·  ARM64  ·  %.0f fps",v->fps],w-320,h-57,11,muted,YES);
    text([simulationDate(f.mjd+f.elapsed/86400.) stringByAppendingString:@" UTC"],w-320,h-80,11,muted,YES);
    if(burn)text(burn,w-320,h-103,11,ink,YES);
    if(v->navigationStatus.length)text(v->navigationStatus,26,h-93,12,ink);
    else if(v->status.length) text(v->status,26,h-93,12,ink);
    if(!warning.empty()) text([NSString stringWithUTF8String:warning.c_str()],26,h-116,12,[NSColor colorWithRed:1 green:.72 blue:.36 alpha:1]);
    if(f.glider.parkingBrake && f.altitude()<1000) text(@"PARKING BRAKE SET · Shift-W releases · , / . wheel brakes",26,h-139,12,[NSColor colorWithRed:1 green:.78 blue:.43 alpha:1]);
    if(f.impacted) {
        text(@"Hard impact — press R to restart",w*.5-170,h*.63,18,[NSColor orangeColor]);
    }
    // Restrained flight symbology, leaving the view unobstructed.
    CGFloat cx=w*.5,cy=v->panelView?std::min(h-95.,[v.panel2D panelRect].size.height+55.):h*.5;
    const double colours[4][3]={{0,1,0},{1,.27,0},{1,1,.50},{0,.64,.80}};
    auto &hud=f.hud;const auto &rgb=colours[hud.colour];
    NSColor *hudInk=[NSColor colorWithRed:rgb[0]*hud.brightness green:rgb[1]*hud.brightness blue:rgb[2]*hud.brightness alpha:1];
    line(cx-22,cy,cx-7,cy,hudInk); line(cx+7,cy,cx+22,cy,hudInk); line(cx,cy-7,cx,cy+7,hudInk);
    if(v->cockpit&&hud.brightness>0) {
        NSString *readout=hud.mode==1?[NSString stringWithFormat:@"ORBIT  ALT %.1f km  V %.0f m/s",f.altitude()/1000,f.velocity.length()]:hud.mode==2?[NSString stringWithFormat:@"SURFACE  ALT %.0f m  V/S %+.1f m/s  HDG %03.0f°",f.altitude(),f.surfaceVerticalSpeed(),Deg(f.heading())]:@"DOCKING  ·  NO TARGET";
        NSDictionary *attributes=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],NSForegroundColorAttributeName:hudInk};
        NSSize size=[readout sizeWithAttributes:attributes];[readout drawAtPoint:NSMakePoint(cx-size.width*.5,cy-24) withAttributes:attributes];
    }
    NSString *viewName=v->panelView?@"2D PANEL":v->cockpit?@"VIRTUAL COCKPIT":[NSString stringWithFormat:@"EXTERNAL · %s",externalCameraModeName(v->externalCamera.mode)];
    text(viewName,cx-53,h-34,10,muted);
    if(!v->cockpit) {
    CGFloat left=26,bottom=35,pw=252,ph=194;
    [panel setFill]; NSRectFill(NSMakeRect(left,bottom,pw,ph));
    bool surface=f.altitude()<std::min(120000.,f.centralBody().radius*.02);
    Elements orbit=surface?Elements():f.orbit();
    if(surface) {
        text([NSString stringWithFormat:@"SURFACE / %@",bodyName.uppercaseString],left+14,bottom+ph-27,11,ink);
        NSArray *rows=@[[NSString stringWithFormat:@"Altitude       %9.1f m",f.altitude()],
            [NSString stringWithFormat:@"Ground speed   %9.2f m/s",f.groundSpeed],
            [NSString stringWithFormat:@"Vertical       %+9.2f m/s",f.surfaceVerticalSpeed()],
            [NSString stringWithFormat:@"Heading        %9.1f°",Deg(f.heading())],
            [NSString stringWithFormat:@"Pitch          %+9.1f°",Deg(f.pitch())],
            [NSString stringWithFormat:@"Bank           %+9.1f°",Deg(f.bank())]];
        for(NSUInteger i=0;i<rows.count;++i) text(rows[i],left+14,bottom+ph-53-i*22,12,i<3?white:ink,YES);
    } else {
        text([NSString stringWithFormat:@"ORBIT / %@",bodyName.uppercaseString],left+14,bottom+ph-27,11,ink);
        text([NSString stringWithFormat:@"Altitude       %9.2f km",f.altitude()/1000],left+14,bottom+ph-53,12,white,YES);
        text([NSString stringWithFormat:@"Speed          %9.2f m/s",f.velocity.length()],left+14,bottom+ph-74,12,white,YES);
        text([NSString stringWithFormat:@"Vertical       %+9.2f m/s",f.radialSpeed()],left+14,bottom+ph-95,12,white,YES);
        text(orbit.e<1?[NSString stringWithFormat:@"Apoapsis       %9.2f km",(orbit.ApDist()-radius)/1000]:@"Apoapsis          ESCAPE",left+14,bottom+ph-123,12,ink,YES);
        text([NSString stringWithFormat:@"Periapsis      %9.2f km",(orbit.PeDist()-radius)/1000],left+14,bottom+ph-144,12,ink,YES);
        text([NSString stringWithFormat:@"Eccentricity   %9.5f",orbit.e],left+14,bottom+ph-165,12,muted,YES);
    }
    CGFloat rx=w-278;
    [panel setFill]; NSRectFill(NSMakeRect(rx,bottom,pw,ph));
    text([NSString stringWithFormat:@"ENGINES  M %.0f / H %.0f / R %.0f %%",f.throttle*100,f.glider.hover*100,f.glider.retro*100],rx+14,bottom+ph-27,10,ink);
    bool hoverPrimary=f.glider.hover>f.throttle;
    double engineLevel=hoverPrimary?f.glider.hover:f.throttle;
    text([NSString stringWithFormat:@"%@       %3.0f %%",hoverPrimary?@"Hover engines":@"Main engines ",engineLevel*100],rx+14,bottom+ph-53,12,white,YES);
    [ink setFill]; NSRectFill(NSMakeRect(rx+14,bottom+ph-68,224*engineLevel,3));
    text([NSString stringWithFormat:@"Fuel             %6.0f kg",f.fuel],rx+14,bottom+ph-96,12,white,YES);
    text([NSString stringWithFormat:@"RCS              %6.0f kg",f.rcs],rx+14,bottom+ph-117,12,white,YES);
    text([NSString stringWithFormat:@"Load             %6.2f g",f.acceleration/9.80665],rx+14,bottom+ph-138,12,muted,YES);
    auto &hover=f.glider.hoverControl;
    NSString *holdStatus=hover.holdActive?[NSString stringWithFormat:@"%@ %+.1f %@",hover.holdMode==1?@"ALT HOLD":@"VS HOLD",hover.holdMode==1?hover.altitudeTarget:hover.verticalSpeedTarget,hover.holdMode==1?@"m":@"m/s"]:nil;
    text(holdStatus?holdStatus:f.groundContact?[NSString stringWithFormat:@"%d WHEELS · %@",f.wheelContacts,f.glider.parkingBrake?@"PARK BRAKE":@"BRAKES RELEASED"]:mode,rx+14,bottom+15,12,ink);
    if(v->orbitVisible&&w>950&&surface) {
        CGFloat ox=w*.5,oy=bottom+87,r=64;
        [panel setFill];NSRectFill(NSMakeRect(ox-120,bottom,240,ph));
        text(@"SURFACE ATTITUDE",ox-100,bottom+ph-27,11,ink);
        [NSGraphicsContext saveGraphicsState];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox-r,oy-r,2*r,2*r)] addClip];
        NSAffineTransform *t=[NSAffineTransform transform];[t translateXBy:ox yBy:oy];[t rotateByDegrees:Deg(f.bank())];[t translateXBy:0 yBy:-Deg(f.pitch())*2];[t concat];
        [[NSColor colorWithRed:.12 green:.29 blue:.43 alpha:1] setFill];NSRectFill(NSMakeRect(-300,0,600,600));
        [[NSColor colorWithRed:.27 green:.23 blue:.16 alpha:1] setFill];NSRectFill(NSMakeRect(-300,-600,600,600));
        line(-200,0,200,0,ink);
        for(int angle=-30;angle<=30;angle+=10) if(angle) {line(-18,angle*2,18,angle*2,ink);text([NSString stringWithFormat:@"%d",abs(angle)],23,angle*2-5,9,ink,YES);}
        [NSGraphicsContext restoreGraphicsState];
        line(ox-30,oy,ox-8,oy,white,2);line(ox+8,oy,ox+30,oy,white,2);line(ox,oy-6,ox,oy+5,white,2);
        text([NSString stringWithFormat:@"HDG %05.1f°",Deg(f.heading())],ox-42,bottom+10,11,ink,YES);
    }
    if(v->orbitVisible&&w>950&&!surface) {
        CGFloat ox=w*.5,oy=bottom+95,scale=70/std::max(radius,orbit.e<1?orbit.ApDist():f.position.length());
        [panel setFill]; NSRectFill(NSMakeRect(ox-120,bottom,240,ph));
        text(@"OSCULATING ORBIT",ox-100,bottom+ph-27,11,ink);
        [[NSColor colorWithRed:.08 green:.22 blue:.31 alpha:1] setFill];
        CGFloat discRadius=radius*scale;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox-discRadius,oy-discRadius,2*discRadius,2*discRadius)] fill];
        if(orbit.e<1) {
            [ink setStroke]; NSBezierPath *p=[NSBezierPath bezierPath];
            for(int j=0;j<=180;++j) { double a=j*Pi2/180, r=orbit.Rdist(a)*scale;
                NSPoint point=NSMakePoint(ox+r*cos(a),oy+r*sin(a)); if(!j) [p moveToPoint:point]; else [p lineToPoint:point]; }
            [p stroke];
            double a=orbit.TrueAnm(),r=orbit.Radius()*scale;
            [white setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox+r*cos(a)-3,oy+r*sin(a)-3,6,6)] fill];
        }
    }
    }
    text(@"+ / − Throttle    X Cut engines    M Systems    F4 TransX    V View    Space Pause    F1 Controls",26,12,11,muted);
    if(v->helpVisible) {
        CGFloat bw=620,bh=534,x=(w-bw)/2,y=(h-bh)/2;
        [panel setFill]; NSRectFill(NSMakeRect(x,y,bw,bh));
        text(@"Flight controls",x+24,y+bh-44,23,white);
        NSArray<NSString *> *rows=@[@"+ / −      Increase / decrease main throttle",@"X          Cut main, hover and retro engines",@"↑ ↓ ← →    Pitch and yaw    ·    Q / E  Roll",@"W/S A/D Z/J   RCS forward/side/vertical",@"P / O      Prograde / retrograde assist",@"; / '      Normal / anti-normal    ·    Shift-L  Horizon level",@"K / N      Kill rotation / manual control",@"Ctrl-H / Option-H   Cycle HUD mode / colour",@"T / Y      Increase / decrease time acceleration",@"[ / ]      Decrease / increase hover throttle",@", / .      Hold left / right wheel brake",@"Shift-W    Toggle parking brake",@"F5/F6/F7   Hover attitude / hold altitude / zero climb",@"M / V      Glider systems / cycle camera views",@"F8         Cycle external tracking frames",@"F4         Original TransX MFD / navigation controls",@"G C F B    Gear / nose / radiator / airbrake",@"H L U I    Hatch / ladder / retro covers / airlock",@"Drag       Look around / rotate TransX graph    ·    Scroll  Zoom",@"Space      Pause    ·    R  Restart    ·    F2  Diagram",@"⌘O / ⌘S    Open / save scenario    ·    F1  Close help"];
        for(NSUInteger i=0;i<rows.count;++i) text(rows[i],x+24,y+bh-81-i*20,13,ink,YES);
    }
}
@end
@implementation FlightView
- (instancetype)initWithFrame:(NSRect)frame {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device) @throw [NSException exceptionWithName:@"Metal unavailable" reason:@"A Metal-capable Mac is required." userInfo:nil];
    self=[super initWithFrame:frame device:device]; if(!self) return nil;
    activeCockpitControl=-1;cockpitPitch=-.25;restartBody=-1;lastBody=BodyId::Earth;
    held.fill(false);lastMfdLabels.fill(false);transxMfd.fill(false);transxAlignDisplay=-1;transxAlignBody=flight.reference;transxRefresh=0; externalCamera.yaw=-.55; externalCamera.pitch=.32; externalCamera.distance=43; helpVisible=false; orbitVisible=true;
    self.colorPixelFormat=MTLPixelFormatBGRA8Unorm_sRGB; self.depthStencilPixelFormat=MTLPixelFormatDepth32Float;
    self.sampleCount=[device supportsTextureSampleCount:4]?4:1;self.clearDepth=0;
    self.preferredFramesPerSecond=120; self.framebufferOnly=NO; self.clearColor=MTLClearColorMake(0,0,0,1);
    self.delegate=self; inflight=dispatch_semaphore_create(3); queue=[device newCommandQueue];
    NSError *error=nil; NSString *source=[NSString stringWithContentsOfFile:resource(@"Shaders.metal") encoding:NSUTF8StringEncoding error:&error];
    NSString *types=[NSString stringWithContentsOfFile:resource(@"VisualTypes.h") encoding:NSUTF8StringEncoding error:&error];
    NSString *effects=[NSString stringWithContentsOfFile:resource(@"NativeVisuals.metal") encoding:NSUTF8StringEncoding error:&error];
    NSString *solarSource=[NSString stringWithContentsOfFile:resource(@"SolarSystem.metal") encoding:NSUTF8StringEncoding error:&error];
    if(!source||!types||!effects||!solarSource)@throw [NSException exceptionWithName:@"Missing Metal source" reason:error.localizedDescription userInfo:nil];
    source=[NSString stringWithFormat:@"%@\n%@\n%@\n%@",types,effects,source,solarSource];
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library) @throw [NSException exceptionWithName:@"Metal shader error" reason:error.localizedDescription userInfo:nil];
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA16Float; pd.depthAttachmentPixelFormat=self.depthStencilPixelFormat; pd.rasterSampleCount=self.sampleCount;
    pd.vertexFunction=[library newFunctionWithName:@"skyVertex"]; pd.fragmentFunction=[library newFunctionWithName:@"skyFragment"];
    skyPipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];
    pd.vertexFunction=[library newFunctionWithName:@"meshVertex"]; pd.fragmentFunction=[library newFunctionWithName:@"meshFragment"];
    pd.colorAttachments[0].blendingEnabled=YES;
    pd.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;
    pd.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    pd.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
    pd.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    meshPipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];
    if(!meshPipeline||!skyPipeline) @throw [NSException exceptionWithName:@"Metal pipeline error" reason:error.localizedDescription userInfo:nil];
    MTLDepthStencilDescriptor *dd=[MTLDepthStencilDescriptor new]; dd.depthCompareFunction=MTLCompareFunctionGreater; dd.depthWriteEnabled=YES;
    depthState=[device newDepthStencilStateWithDescriptor:dd]; dd.depthCompareFunction=MTLCompareFunctionAlways; dd.depthWriteEnabled=NO;
    dd.depthWriteEnabled=YES;skyDepth=[device newDepthStencilStateWithDescriptor:dd];
    dd.depthWriteEnabled=NO;dd.depthCompareFunction=MTLCompareFunctionGreater; transparentDepth=[device newDepthStencilStateWithDescriptor:dd];
    visuals=[[NativeVisuals alloc] initWithDevice:device library:library queue:queue samples:self.sampleCount];
    textures=[NSMutableArray new];
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:1 height:1 mipmapped:NO];
    whiteTexture=[device newTextureWithDescriptor:td]; uint32_t white=0xffffffff;
    [whiteTexture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&white bytesPerRow:4]; [textures addObject:whiteTexture];
    for(int i=0;i<2;++i){auto art=maneuverButtonArtwork(i!=0);
        MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:art.width height:art.height mipmapped:NO];
        maneuverButtonTextures[i]=[device newTextureWithDescriptor:desc];
        [maneuverButtonTextures[i] replaceRegion:MTLRegionMake2D(0,0,art.width,art.height) mipmapLevel:0 withBytes:art.rgba.data() bytesPerRow:art.width*4];
    }
    surfaceBase=loadSurfaceBase(resource(@"Bases/Canaveral.cfg").fileSystemRepresentation,resource(@"Meshes").fileSystemRepresentation);
    for(int meshIndex=0;meshIndex<3;++meshIndex) {
        auto mesh=meshIndex==2?surfaceBase.mesh:loadMesh(resource(meshIndex?@"Meshes/deltaglider_vc.msh":@"Meshes/deltaglider_ns.msh").fileSystemRepresentation);
        size_t materialBase=materials.size(),textureBase=textures.count-1;
        materials.insert(materials.end(),mesh.materials.begin(),mesh.materials.end());
        if(meshIndex<2) meshCounts[meshIndex]=mesh.groups.size();
        for(auto name:mesh.textures) {
            std::transform(name.begin(),name.end(),name.begin(),[](unsigned char c){ return std::tolower(c); });
            if(name.rfind("dg/",0)==0) name="DG/"+name.substr(3);
            auto image=loadDDS(resource([(meshIndex==2?@"Textures/Base/":@"Textures/") stringByAppendingString:[NSString stringWithUTF8String:name.c_str()]]).fileSystemRepresentation);
            MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:image.width height:image.height mipmapped:YES];
            id<MTLTexture> tex=[device newTextureWithDescriptor:desc];
            if(meshIndex==1&&name=="DG/dg_vc4.dds"){mfdLabelTexture=tex;mfdLabelOriginal=image;mfdLabelImage=image;}
            [tex replaceRegion:MTLRegionMake2D(0,0,image.width,image.height) mipmapLevel:0 withBytes:image.rgba.data() bytesPerRow:image.width*4];
            id<MTLCommandBuffer> cb=[queue commandBuffer]; id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder]; [blit generateMipmapsForTexture:tex]; [blit endEncoding]; [cb commit];
            [textures addObject:tex];
            if(meshIndex==1&&name=="DG/blittgt1.dds"){hoverReadoutTexture=tex;hoverReadoutImage=image;}
        }
        for(size_t i=0;i<mesh.groups.size();++i) {
            const auto &g=mesh.groups[i]; GpuGroup group;
            group.vertices=[device newBufferWithBytes:g.vertices.data() length:g.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];
            group.indices=[device newBufferWithBytes:g.indices.data() length:g.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
            group.count=g.indices.size(); group.material=materialBase+g.material;
            group.texture=g.texture?textureBase+g.texture:0; group.index=i; group.mesh=meshIndex; groups.push_back(group);
        }
    }
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    hoverGlyphs=loadDDS(resource(@"Textures/DG/blitsrc1.dds").fileSystemRepresentation);
    earthTexture=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:resource(@"earth-8k.jpg")] options:@{MTKTextureLoaderOptionSRGB:@YES,MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];
    if(!earthTexture) @throw [NSException exceptionWithName:@"Earth texture error" reason:error.localizedDescription userInfo:nil];
    solar=[[SolarRenderer alloc] initWithDevice:device library:library samples:self.sampleCount earth:earthTexture];
    loadEphemerides(resource(@"Ephemeris").fileSystemRepresentation);
    for(auto &tex:instrumentTextures) {
        MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:512 height:512 mipmapped:NO];
        tex=[device newTextureWithDescriptor:desc];
    }
    [self resetFlight:nil];
    bool warmHover=false;NSInteger lookAt=-1;navigationTarget=-1;
    NSArray<NSString *> *args=NSProcessInfo.processInfo.arguments;
    for(NSUInteger i=1;i<args.count;++i) {
        if([args[i] isEqual:@"--frames"]&&i+1<args.count) smokeFrames=[args[++i] integerValue];
        else if([args[i] isEqual:@"--capture"]&&i+1<args.count) capturePath=args[++i];
        else if([args[i] isEqual:@"--body"]&&i+1<args.count){restartBody=(NSInteger)findBody(args[++i].UTF8String);[self resetFlight:nil];externalCamera.pitch=flight.centralBody().solid?.32:1.35;warmHover=false;}
        else if([args[i] isEqual:@"--look-at"]&&i+1<args.count)lookAt=(NSInteger)findBody(args[++i].UTF8String);
        else if([args[i] isEqual:@"--transx-target"]&&i+1<args.count)navigationTarget=(NSInteger)findBody(args[++i].UTF8String);
        else if([args[i] isEqual:@"--weather"]&&i+1<args.count)visuals.weather=[args[++i] integerValue];
        else if([args[i] isEqual:@"--throttle"]&&i+1<args.count)flight.throttle=std::clamp([args[++i] doubleValue],0.,1.);
        else if([args[i] isEqual:@"--altitude"]&&i+1<args.count){double lat,lon;bodyCoordinates(flight.reference,flight.position,flight.mjd,flight.elapsed,lat,lon);flight.placeOnBody(lat,lon,flight.heading(),std::clamp([args[++i] doubleValue],2.53,1000000.));flight.groundContact=false;flight.wheelContacts=0;}
        else if([args[i] isEqual:@"--paused"])flight.paused=true;
        else if([args[i] isEqual:@"--rcs-demo"])rcsDemo=true;
        else if([args[i] isEqual:@"--camera-yaw"]&&i+1<args.count)externalCamera.yaw=[args[++i] doubleValue]*RAD;
        else if([args[i] isEqual:@"--camera-pitch"]&&i+1<args.count)externalCamera.pitch=std::clamp([args[++i] doubleValue]*RAD,-1.35,1.35);
        else if([args[i] isEqual:@"--camera-distance"]&&i+1<args.count)externalCamera.distance=std::clamp([args[++i] doubleValue],14.,MaxExternalCameraDistance);
        else if([args[i] isEqual:@"--surface"]) {[self startSurface:nil];warmHover=false;}
        else if([args[i] isEqual:@"--hover-demo"]) {[self startHoverPractice:nil];warmHover=true;}
        else if([args[i] isEqual:@"--cockpit"]) cockpit=true;
        else if([args[i] isEqual:@"--panel2d"]) {cockpit=true;panelView=true;}
        else if([args[i] isEqual:@"--glider-demo"]) {
            for(Part p:{Part::Gear,Part::Nose,Part::Radiator,Part::RetroCover,Part::Airbrake}) { flight.glider.part(p).position=1;flight.glider.part(p).target=1; }
            flight.glider.navLights=flight.glider.beacons=flight.glider.strobes=true;
        }
        else if([args[i] isEqual:@"--prograde"]) { flight.assist=Assist::Prograde; flight.align(flight.velocity); }
        else if([args[i] isEqual:@"--report"]&&i+1<args.count) reportPath=args[++i];
        else if([args[i] isEqual:@"--scenario"]&&i+1<args.count) { restartBody=-1;restartScenario=args[++i]; [self resetFlight:nil];warmHover=false; }
    }
    if(warmHover)for(int i=0;i<6000;++i)flight.advance(.01);
    if(lookAt>=0){
        double date=flight.mjd+flight.elapsed/86400;Vector direction=bodyState((BodyId)lookAt,date).position-bodyState(flight.reference,date).position-flight.position;
        Vector radial=flight.position.unit(),tangent=flight.velocity-radial*dotp(flight.velocity,radial);if(tangent.length2()<1)tangent=flight.forward;tangent.unify();Vector lateral=crossp(radial,tangent).unit(),out=-direction.unit();
        externalCamera.pitch=std::clamp(asin(std::clamp(dotp(out,radial),-1.,1.)),-1.35,1.35);externalCamera.yaw=atan2(dotp(out,lateral),-dotp(out,tangent));
    }
    [self updateCockpitDisplays];previous=begin=CACurrentMediaTime(); return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)clearInput { held.fill(false);haveDragPoint=false;activeCockpitControl=-1;activeCockpitDirection=0;[self.panel2D cancelInteraction]; }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self.window makeFirstResponder:self]; }
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
    CFTimeInterval start=CACurrentMediaTime(),dt=start-previous; previous=start;
    if(dt<=0) return;
    Input input; input.pitch=(held[125]?1.:0)-(held[126]?1.:0); input.yaw=(held[124]?1.:0)-(held[123]?1.:0);
    input.roll=(held[12]?1.:0)-(held[14]?1.:0); input.translate=(held[13]?1.:0)-(held[1]?1.:0);
    input.lateral=(held[2]?1.:0)-(held[0]?1.:0); input.vertical=(held[6]?1.:0)-(held[38]?1.:0);
    input.leftBrake=held[43]?1:0;input.rightBrake=held[47]?1:0;
    if(burnSkip.running()&&(input.pitch||input.yaw||input.roll||input.translate||input.lateral||input.vertical||
       held[30]||held[33]||held[24]||held[27]||held[69]||held[78])){
        burnSkip.cancel(flight);status=@"Skip cancelled by manual control · paused";
    }
    if(held[30]) flight.setHoverThrottle(flight.glider.hover+dt*.35);
    if(held[33]) flight.setHoverThrottle(flight.glider.hover-dt*.35);
    if(held[24]||held[69]) flight.throttle=std::min(1.,flight.throttle+dt*.4);
    if(held[27]||held[78]) flight.throttle=std::max(0.,flight.throttle-dt*.4);
    if((input.pitch||input.yaw||input.roll)&&flight.glider.rcsMode!=2) flight.clearAssist();
    if(smokeFrames&&rcsDemo){input.pitch=.3;input.yaw=-.15;input.roll=.2;flight.clearAssist();}
    if(activeCockpitControl==62){flight.hud.adjustBrightness(activeCockpitDirection*dt*.3);self.hud.needsDisplay=YES;}
    if(activeCockpitControl>=100&&activeCockpitControl<124&&transxSession){int id=activeCockpitControl-100,b=id%12;if(b==8||b==9)transxSession->button(id/12,b,true);}
    if(panelView)[self.panel2D tick];
    [self updateNavigation];
    if(burnSkip.running()){
        burnSkip.advance(flight,*transxSession);
        using SkipState=native::transx::BurnSkip::State;
        switch(burnSkip.state()){
            case SkipState::Reached:status=@"One day before estimated ignition · paused";break;
            case SkipState::PlanChanged:status=@"Skip stopped because the selected burn changed · paused";break;
            case SkipState::FlightStopped:status=@"Skip stopped because the flight paused or ended";break;
            case SkipState::Cancelled:status=@"Skip cancelled · paused";break;
            default:break;
        }
    }else flight.advance(dt,input);
    if(demoLadderQueued&&flight.glider.part(Part::Nose).open()) { flight.glider.command(Part::Ladder,1);demoLadderQueued=false; }
    dispatch_semaphore_wait(inflight,DISPATCH_TIME_FOREVER);
    id<CAMetalDrawable> drawable=self.currentDrawable;
    if(!drawable) { dispatch_semaphore_signal(inflight); return; }
    auto cameraPose=externalCamera.pose(flight);
    Vector offset=cameraPose.offset;
    Vector dir=(-offset).unit(),up=cameraPose.up;
    if(cockpit) { offset=flight.up*1.467+flight.forward*6.782; dir=panelView?flight.forward:(flight.forward*(cos(cockpitYaw)*cos(cockpitPitch))+flight.right*(sin(cockpitYaw)*cos(cockpitPitch))+flight.up*sin(cockpitPitch)).unit(); up=flight.up; }
    Vector cameraRight=crossp(up,dir).unit(),cameraUp=crossp(dir,cameraRight).unit();
    float aspect=self.drawableSize.width/std::max(1.,self.drawableSize.height),tanHalf=cockpit?(panelView?tan(50*RAD*.5):cockpitCamera.tanHalfFov()):externalCamera.tanHalfFov();
    FrameUniforms uniforms{}; uniforms.projection=projection(aspect,tanHalf);
    uniforms.right=f4(cameraRight); uniforms.up=f4(cameraUp); uniforms.forward=f4(dir);
    uniforms.position=f4((flight.position+offset)/flight.centralBody().radius);
    uniforms.screen={(float)self.drawableSize.width,(float)self.drawableSize.height,tanHalf,0};
    uniforms.environment={0,(float)flight.altitude(),0,(float)fmod(flight.elapsed,86400.)};
    if(lastBody!=flight.reference){[visuals resetForReferenceChange];lastBody=flight.reference;}
    [solar updateFrame:&uniforms flight:flight offset:offset];
    [visuals prepare:&uniforms width:drawable.texture.width height:drawable.texture.height];
    ObjectUniforms object={};
    object.model.columns[0]=f4(flight.right); object.model.columns[1]=f4(flight.up); object.model.columns[2]=f4(flight.forward); object.model.columns[3]=f4(-offset,1);
    id<MTLCommandBuffer> cb=[queue commandBuffer]; cb.label=@"Orbiter native flight";
    [visuals encodeShadows:cb frame:uniforms];
    id<MTLRenderCommandEncoder> encoder=[cb renderCommandEncoderWithDescriptor:visuals.scenePass];
    [encoder setRenderPipelineState:skyPipeline]; [encoder setDepthStencilState:skyDepth];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1]; [encoder setFragmentTexture:[solar textureForBody:flight.reference] atIndex:0];
    [encoder setFragmentTexture:solar.rings atIndex:2];
    [encoder setFragmentTexture:visuals.cloudShadows atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder setDepthStencilState:depthState];
    [solar encodeBodies:encoder frame:uniforms flight:flight offset:offset];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
    [encoder setFragmentTexture:visuals.cloudShadows atIndex:1];
    {
        [encoder setRenderPipelineState:meshPipeline]; [encoder setDepthStencilState:depthState]; [encoder setCullMode:MTLCullModeNone];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        std::vector<SwitchUniforms> switchData;
        for(const auto &sw:cockpitSwitches()) {
            auto &g=flight.glider;bool enabled=false;
            if(sw.action<9) enabled=g.part(static_cast<Part>(sw.action)).target>.5;
            else if(sw.action>=10&&sw.action<=20) {
                bool values[]={g.valves[0],g.valves[1],g.valves[2],g.valves[3],g.valves[4],g.coolantPump,g.navLights,g.beacons,g.strobes,g.landingLight,g.instrumentLights};
                enabled=values[sw.action-10];
            }
            auto &hover=g.hoverControl;double amount=(enabled?1:-1)*28*RAD;bool lit=false;Vector axis=sw.axis;
            if(sw.action==30)amount=(1-g.rcsMode)*50*RAD;
            else if(sw.action==40)amount=(1-hover.attitudeMode)*50*RAD;
            else if(sw.action>=41&&sw.action<=43)amount=activeCockpitControl==sw.action?activeCockpitDirection*15*RAD:0;
            else if(sw.action==45)amount=activeCockpitControl==45?.004:0;
            else if(sw.action>=46&&sw.action<=48) {
                lit=sw.action==46?hover.holdActive:hover.holdMode==sw.action-46;
                bool pressed=activeCockpitControl==sw.action||(activeCockpitControl==44&&sw.action==47+(activeCockpitDirection>0));
                amount=pressed?.0065:lit?.005:0;
            }
            else if(sw.action==62)amount=-280*RAD*flight.hud.brightness;
            else if(sw.action==63)amount=activeCockpitControl==63?.004:0;
            else if(sw.action>=70&&sw.action<=75){lit=flight.assistActive(navButtonMode(sw.action-70));amount=activeCockpitControl==sw.action?.0065:lit?.005:0;}
            else if(sw.action>=80&&sw.action<=82){lit=flight.hud.mode==sw.action-79;amount=activeCockpitControl==sw.action?.0065:lit?.005:0;}
            else if(sw.action==50||sw.action==51) {
                double p=hover.attitudeMode?(sw.action==50?flight.pitch():hover.pitchTarget):0;
                double b=hover.attitudeMode?(sw.action==50?flight.bank():hover.bankTarget):0;
                double dx=-std::clamp(b,-10*RAD,10*RAD)*(.0103/(10*RAD)),dy=-std::clamp(p,-10*RAD,10*RAD)*(.0103/(10*RAD));
                axis={dx,dy*cos(.622165),dy*sin(.622165)};amount=1;
            }
            switchData.push_back({f4(sw.pivot,amount),f4(axis,(float)sw.first),simd_make_float4((float)sw.count,(float)sw.group,(float)sw.motion,lit?1.f:0.f)});
        }
        [encoder setVertexBytes:switchData.data() length:switchData.size()*sizeof(SwitchUniforms) atIndex:3];
        simd_float4x4 vesselModel=object.model;
        auto baseFrame=earthSurface(surfaceBase.latitude,surfaceBase.longitude,flight.mjd,flight.elapsed);
        Vector basePosition=baseFrame.up*EarthRadius-flight.position;
        if(flight.reference==BodyId::Earth&&basePosition.length()<80000 && flight.altitude()<50000) {
            object.model.columns[0]=f4(-baseFrame.north);object.model.columns[1]=f4(baseFrame.up);object.model.columns[2]=f4(baseFrame.east);object.model.columns[3]=f4(basePosition-offset,1);
            object.options={0,0,0,0};
            for(const auto &g:groups) if(g.mesh==2) {
                const auto &m=materials[g.material];object.color={m.diffuse[0],m.diffuse[1],m.diffuse[2],m.diffuse[3]};
                [encoder setVertexBuffer:g.vertices offset:0 atIndex:0];[encoder setVertexBytes:&object length:sizeof(object) atIndex:2];[encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
                [encoder setFragmentTexture:textures[g.texture] atIndex:0];[encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:g.count indexType:MTLIndexTypeUInt32 indexBuffer:g.indices indexBufferOffset:0];
            }
        }
        if(cockpit&&!panelView){
            static const Vertex button[]={
                {.103f,1.273f,7.265f,0,0,-1,0,1},{.119f,1.273f,7.265f,0,0,-1,1,1},{.119f,1.285f,7.265f,0,0,-1,1,0},
                {.103f,1.273f,7.265f,0,0,-1,0,1},{.119f,1.285f,7.265f,0,0,-1,1,0},{.103f,1.285f,7.265f,0,0,-1,0,0}
            };
            object.model=vesselModel;object.color={1,1,1,1};object.options={3,0,0,0};
            [encoder setDepthStencilState:depthState];[encoder setVertexBytes:button length:sizeof(button) atIndex:0];
            [encoder setVertexBytes:&object length:sizeof(object) atIndex:2];[encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
            [encoder setFragmentTexture:maneuverButtonTextures[flight.assist==Assist::Maneuver?1:0] atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        }
        object.model=vesselModel;
        auto transforms=flight.glider.transforms(meshCounts[cockpit?1:0],cockpit?1:0);
        for(int transparent=0;transparent<2;++transparent) {
            [encoder setDepthStencilState:transparent?transparentDepth:depthState];
            for(const auto &g:groups) {
                if(panelView||g.mesh!=(cockpit?1:0)) continue;
                if(cockpit&&!visibleCockpitGroup(g.index)) continue;
                const auto &mat=materials[g.material]; bool label=cockpit&&g.index==129;
                if((label||mat.diffuse[3]<.99)!=(transparent==1)) continue;
                const auto &t=transforms[g.index]; simd_float4x4 local;
                local.columns[0]=f4({t.rotation.m11,t.rotation.m21,t.rotation.m31});
                local.columns[1]=f4({t.rotation.m12,t.rotation.m22,t.rotation.m32});
                local.columns[2]=f4({t.rotation.m13,t.rotation.m23,t.rotation.m33}); local.columns[3]=f4(t.translation,1);
                object.model=simd_mul(vesselModel,local); object.options={0,cockpit&&flight.glider.instrumentLights?.20f:0.f,(float)g.index,cockpit?(float)switchData.size():0.f};
                object.color={mat.diffuse[0],mat.diffuse[1],mat.diffuse[2],mat.diffuse[3]};
                if(label){object.color={1,1,1,1};object.options.x=4;}
                [encoder setVertexBuffer:g.vertices offset:0 atIndex:0];
                [encoder setVertexBytes:&object length:sizeof(object) atIndex:2];
                [encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
                if(cockpit&&(g.index==88||g.index==89)) {
                    object.color={1,1,1,1};object.options.x=3;
                    [encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
                    [encoder setFragmentTexture:instrumentTextures[g.index-88] atIndex:0];
                } else [encoder setFragmentTexture:textures[g.texture] atIndex:0];
                [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:g.count indexType:MTLIndexTypeUInt32 indexBuffer:g.indices indexBufferOffset:0];
            }
        }
        object.model=vesselModel;
        [encoder setDepthStencilState:transparentDepth]; [encoder setFragmentTexture:whiteTexture atIndex:0];
        auto drawEffect=[&](const std::vector<Vertex> &vertices,simd_float4 color,float type) {
            object.color=color; object.options={type,0,0,0};
            [encoder setVertexBytes:vertices.data() length:vertices.size()*sizeof(Vertex) atIndex:0];
            [encoder setVertexBytes:&object length:sizeof(object) atIndex:2];
            [encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
        };
        auto &dg=flight.glider;
        Vector cr(dotp(cameraRight,flight.right),dotp(cameraRight,flight.up),dotp(cameraRight,flight.forward));
        Vector cu(dotp(cameraUp,flight.right),dotp(cameraUp,flight.up),dotp(cameraUp,flight.forward));
        auto beacon=[&](Vector p,simd_float4 color,double size) {
            std::vector<Vertex> vertices;
            for(auto uv:std::array<std::array<float,2>,6>{{{-1,-1},{1,-1},{1,1},{-1,-1},{1,1},{-1,1}}}) {
                Vector q=p+(cr*uv[0]+cu*uv[1])*size;
                vertices.push_back({(float)q.x,(float)q.y,(float)q.z,0,1,0,uv[0],uv[1]});
            }
            drawEffect(vertices,color,2);
        };
        if(dg.navLights) { beacon({-8.6,0,-3.3},simd_make_float4(1,.18,.13,1),.4); beacon({8.6,0,-3.3},simd_make_float4(.12,1,.2,1),.4); beacon({0,.5,-7.5},simd_make_float4(1,1,1,1),.35); }
        if(dg.beacons&&fmod(flight.elapsed,2)<.15) { beacon({0,2.2,2},simd_make_float4(1,.18,.12,1),.7); beacon({0,-1.4,2},simd_make_float4(1,.18,.12,1),.7); }
        if(dg.strobes&&fmod(flight.elapsed,1.13)<.08) for(double x:{-8.9,8.9}) beacon({x,2.5,-5.4},simd_make_float4(1,1,1,1),.8);
        if(dg.landingLight) beacon({2.5,-.5,6.5},simd_make_float4(1,.95,.75,1),.5);
    }
    [encoder endEncoding];
    [visuals encodeWeather:cb frame:uniforms];
    [visuals encodeExhaust:cb frame:uniforms flight:flight offset:offset];
    [visuals encodePresent:cb drawable:drawable];
    [cb presentDrawable:drawable];
    __weak FlightView *weakSelf=self; dispatch_semaphore_t semaphore=inflight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        double ms=(completed.GPUEndTime-completed.GPUStartTime)*1000;
        dispatch_async(dispatch_get_main_queue(),^{ FlightView *v=weakSelf; if(v&&ms>0) { v->gpuMs=ms; v->gpuSum+=ms; } });
        dispatch_semaphore_signal(semaphore);
    }];
    [cb commit];
    cpuMs=(CACurrentMediaTime()-start)*1000; cpuSum+=cpuMs; ++frameCount;
    if(frameCount>30) intervals.push_back(dt*1000);
    if(start-lastHud>.1) { [self updateCockpitDisplays]; fps=1/dt; self.hud.needsDisplay=YES; lastHud=start; }
    if(smokeFrames&&frameCount>=smokeFrames) {
        self.paused=YES; [cb waitUntilCompleted];
        if(cb.error){fprintf(stderr,"Metal frame failed: %s\n",cb.error.localizedDescription.UTF8String);exit(2);}
        if(capturePath) [self captureTexture:drawable.texture to:capturePath];
        [self writeReport]; dispatch_async(dispatch_get_main_queue(),^{[NSApp terminate:nil];});
    }
    }
}
- (void)captureTexture:(id<MTLTexture>)texture to:(NSString *)path {
    NSUInteger w=texture.width,h=texture.height; std::vector<uint8_t> pixels(w*h*4);
    [texture getBytes:pixels.data() bytesPerRow:w*4 fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
    for(size_t i=0;i<w*h;++i) std::swap(pixels[4*i],pixels[4*i+2]);
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:w*4 bitsPerPixel:32];
    memcpy(rep.bitmapData,pixels.data(),pixels.size());
    // Composite the exact same HUD used by the live view over the rendered frame.
    [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    CGFloat scale=w/self.bounds.size.width; NSAffineTransform *transform=[NSAffineTransform transform]; [transform scaleBy:scale]; [transform concat];
    [self.hud paint:self.bounds];
    if(panelView&&self.panel2D){
        NSBitmapImageRep *panel=[self.panel2D bitmapImageRepForCachingDisplayInRect:self.panel2D.bounds];
        [self.panel2D cacheDisplayInRect:self.panel2D.bounds toBitmapImageRep:panel];
        NSRect r=[self.panel2D panelRect];r.origin.y=self.bounds.size.height-NSMaxY(r);
        [NSGraphicsContext saveGraphicsState];NSRectClip(r);[panel drawInRect:self.bounds];[NSGraphicsContext restoreGraphicsState];
    }
    [NSGraphicsContext restoreGraphicsState];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
- (void)writeReport {
    if(!reportPath) return;
    auto sorted=intervals; std::sort(sorted.begin(),sorted.end());
    double mean=sorted.empty()?0:std::accumulate(sorted.begin(),sorted.end(),0.)/sorted.size();
    double p95=sorted.empty()?0:sorted[(sorted.size()-1)*95/100];
    NSDictionary *report=@{@"architecture":@"arm64",@"renderer":@"Metal",@"body":[NSString stringWithUTF8String:flight.centralBody().name],@"bodyRadius":@(flight.centralBody().radius),@"bodyMu":@(flight.gravityMu()),@"solarSystemBodies":@(BodyCount),@"device":self.device.name,
        @"frames":@(frameCount),@"drawableWidth":@(self.drawableSize.width),@"drawableHeight":@(self.drawableSize.height),
        @"screenMaximumFPS":@(self.window.screen.maximumFramesPerSecond),@"requestedFPS":@(self.preferredFramesPerSecond),@"sampleCount":@(self.sampleCount),@"weather":flight.reference==BodyId::Earth?[visuals weatherName]:@"Not applicable",@"cloudWidth":@(visuals.cloudWidth),@"cloudHeight":@(visuals.cloudHeight),@"hdr":@YES,
        @"exhaustEmitters":@(visuals.emitterCount),@"exhaustTrailPuffs":@([visuals liveTrailPuffCount]),@"cameraDistance":@(externalCamera.distance),@"forwardLength":@(flight.forward.length()),@"rightLength":@(flight.right.length()),@"meanFrameMs":@(mean),@"p95FrameMs":@(p95),@"meanFPS":@(mean?1000/mean:0),
        @"meanCPUEncodeMs":@(cpuSum/frameCount),@"lastGPUFrameMs":@(gpuMs),@"scenarioElapsed":@(flight.elapsed),
        @"altitudeMeters":@(flight.altitude()),@"meshGroups":@(groups.size()),
        @"groundSpeed":@(flight.groundSpeed),@"wheelContacts":@(flight.wheelContacts),@"parkingBrake":@(flight.glider.parkingBrake),@"impacted":@(flight.impacted),
        @"hoverHoldActive":@(flight.glider.hoverControl.holdActive),@"hoverHoldMode":@(flight.glider.hoverControl.holdMode),
        @"hoverAltitudeTarget":@(flight.glider.hoverControl.altitudeTarget),@"verticalSpeed":@(flight.surfaceVerticalSpeed()),@"pitchDegrees":@(Deg(flight.pitch())),@"bankDegrees":@(Deg(flight.bank())),
        @"hoverFront":@(flight.glider.hoverControl.levels[0]),@"hoverLeft":@(flight.glider.hoverControl.levels[1]),@"hoverRight":@(flight.glider.hoverControl.levels[2]),
        @"surfacePads":@(flight.reference==BodyId::Earth?surfaceBase.pads:0),@"surfaceBuildings":@(flight.reference==BodyId::Earth?surfaceBase.buildings:0),@"surfaceRunways":@(flight.reference==BodyId::Earth?surfaceBase.runways:0)};
    NSMutableDictionary *full=[report mutableCopy];full[@"transx"]=[self navigationReport];
    [[NSJSONSerialization dataWithJSONObject:full options:NSJSONWritingPrettyPrinted error:nil] writeToFile:reportPath atomically:YES];
}
- (void)updateCockpitDisplays {
    NSString *bodyName=[NSString stringWithUTF8String:flight.centralBody().name];double radius=flight.centralBody().radius;
    bool surface=flight.altitude()<std::min(120000.,flight.centralBody().radius*.02);Elements orbit=surface?Elements():flight.orbit();
    NSColor *green=[NSColor colorWithRed:.52 green:1 blue:.58 alpha:1];
    for(int display=0;display<2;++display) {
        NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:512 pixelsHigh:512 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:2048 bitsPerPixel:32];
        [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [[NSColor blackColor] setFill];NSRectFill(NSMakeRect(0,0,512,512));
        if(transxSession&&transxMfd[display])paintTransX(transxFrames[display],NSMakeRect(0,0,512,512));
        else {
        NSArray<NSString *> *rows;
        if(!display&&surface) rows=@[[NSString stringWithFormat:@"SURFACE / %@",bodyName.uppercaseString],[NSString stringWithFormat:@"ALT   %.1f m",flight.altitude()],
            [NSString stringWithFormat:@"GS    %.2f m/s",flight.groundSpeed],[NSString stringWithFormat:@"VS    %+.2f m/s",flight.surfaceVerticalSpeed()],
            [NSString stringWithFormat:@"HDG   %.1f deg",Deg(flight.heading())],[NSString stringWithFormat:@"PITCH %+.1f deg",Deg(flight.pitch())],
            [NSString stringWithFormat:@"BANK  %+.1f deg",Deg(flight.bank())],flight.glider.parkingBrake?@"PARK BRAKE SET":@"BRAKES RELEASED"];
        else if(!display) rows=@[[NSString stringWithFormat:@"ORBIT / %@",bodyName.uppercaseString],[NSString stringWithFormat:@"ALT   %.2f km",flight.altitude()/1000],
            [NSString stringWithFormat:@"VEL   %.1f m/s",flight.velocity.length()],
            orbit.e<1?[NSString stringWithFormat:@"ApA   %.1f km",(orbit.ApDist()-radius)/1000]:@"ApA   ESCAPE",
            [NSString stringWithFormat:@"PeA   %.1f km",(orbit.PeDist()-radius)/1000],
            [NSString stringWithFormat:@"ECC   %.5f",orbit.e],[NSString stringWithFormat:@"VS    %+.1f m/s",flight.radialSpeed()]];
        else if(flight.glider.hoverControl.attitudeMode||flight.glider.hoverControl.holdActive) {
            auto &hover=flight.glider.hoverControl;
            rows=@[hover.holdActive?(hover.holdMode==1?@"HOVER / ALT HOLD":@"HOVER / VS HOLD"):@"HOVER / HOLD OFF",
                [NSString stringWithFormat:@"TGT %.1f %@",hover.holdMode==2?hover.verticalSpeedTarget:hover.altitudeTarget,hover.holdMode==2?@"m/s":@"m"],
                [NSString stringWithFormat:@"VS  %+.2f m/s",flight.surfaceVerticalSpeed()],
                [NSString stringWithFormat:@"P %+.1f  B %+.1f deg",Deg(flight.pitch()),Deg(flight.bank())],
                [NSString stringWithFormat:@"FRONT %.0f %%",hover.levels[0]*100],
                [NSString stringWithFormat:@"L %.0f %%  R %.0f %%",hover.levels[1]*100,hover.levels[2]*100],
                [NSString stringWithFormat:@"FUEL %.0f kg",flight.fuel],hover.attitudeLimited?@"ATTITUDE LIMIT":hover.thrustLimited?@"THRUST LIMIT":@"M: HOVER CONTROLS"];
        }
        else rows=@[@"GLIDER SYSTEMS",[NSString stringWithFormat:@"MAIN  %.0f %%",flight.throttle*100],
            [NSString stringWithFormat:@"HOVR  %.0f %%",flight.glider.hover*100],[NSString stringWithFormat:@"RETR  %.0f %%",flight.glider.retro*100],
            [NSString stringWithFormat:@"FUEL  %.0f kg",flight.fuel],[NSString stringWithFormat:@"RCS   %.0f kg",flight.rcs],
            [NSString stringWithFormat:@"CAB   %.1f kPa",flight.glider.cabinPressure/1000],@"M: SYSTEMS PANEL"];
        for(NSUInteger i=0;i<rows.count;++i) text(rows[i],24,450-i*54,26,green,YES);
        }
        [NSGraphicsContext restoreGraphicsState];
        [self.panel2D setDisplayImage:rep index:display];
        id<MTLBuffer> upload=[self.device newBufferWithBytes:rep.bitmapData length:512*2048 options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        [blit copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:2048 sourceBytesPerImage:512*2048 sourceSize:MTLSizeMake(512,512,1) toTexture:instrumentTextures[display] destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];[cb commit];
    }
    if(mfdLabelTexture&&lastMfdLabels!=transxMfd&&paintMfdButtonLabels(mfdLabelImage,mfdLabelOriginal,transxMfd)){
        lastMfdLabels=transxMfd;auto &image=mfdLabelImage;
        id<MTLBuffer> upload=[self.device newBufferWithBytes:image.rgba.data() length:image.rgba.size() options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        [blit copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:image.width*4 sourceBytesPerImage:image.rgba.size() sourceSize:MTLSizeMake(image.width,image.height,1) toTexture:mfdLabelTexture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit generateMipmapsForTexture:mfdLabelTexture];[blit endEncoding];[cb commit];
    }
    if(hoverReadoutTexture&&paintHoverReadout(hoverReadoutImage,hoverGlyphs,flight.glider.hoverControl)) {
        auto &image=hoverReadoutImage;
        id<MTLBuffer> upload=[self.device newBufferWithBytes:image.rgba.data() length:image.rgba.size() options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        [blit copyFromBuffer:upload sourceOffset:0 sourceBytesPerRow:image.width*4 sourceBytesPerImage:image.rgba.size() sourceSize:MTLSizeMake(image.width,image.height,1) toTexture:hoverReadoutTexture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit generateMipmapsForTexture:hoverReadoutTexture];[blit endEncoding];[cb commit];
    }
}
- (void)resetFlight:(id)sender {
    [self clearInput];[visuals reset];demoLadderQueued=false;
    if(restartBody>=0)flight.startOrbit((BodyId)restartBody);
    else {if(!restartScenario)restartScenario=resource(@"Scenarios/DG Mk4 in orbit.scn");flight.load(restartScenario.fileSystemRepresentation);}
    flight.automaticReferenceChanges=true;[self resetNavigation];if(restartBody<0&&restartScenario)[self loadTransXScenario:restartScenario];
    status=[NSString stringWithFormat:@"%s %@ · Press F1 for controls",flight.centralBody().name,flight.groundContact?@"surface flight":@"orbit"];

}
- (void)startSurface:(id)sender {
    restartBody=-1;restartScenario=resource(@"Scenarios/Cape Canaveral native.scn");[self resetFlight:nil];
    externalCamera.setMode(ExternalCameraMode::OrbitalChase,flight,flight.reference);externalCamera.yaw=-.55;externalCamera.pitch=.22;externalCamera.distance=43;[self setViewMode:0];
}
- (void)startOrbit:(id)sender {restartBody=-1;restartScenario=resource(@"Scenarios/DG Mk4 in orbit.scn");[self resetFlight:nil];}
- (void)startHoverPractice:(id)sender {
    restartBody=-1;restartScenario=resource(@"Scenarios/Cape Canaveral hover.scn");[self resetFlight:nil];
    externalCamera.setMode(ExternalCameraMode::OrbitalChase,flight,flight.reference);externalCamera.yaw=-.55;externalCamera.pitch=.22;externalCamera.distance=43;[self setViewMode:0];status=@"Hover practice · climbing to 100 m · X disengages hold and cuts engines";
}
- (void)toggleHoverHold:(id)sender {
    auto &h=flight.glider.hoverControl;
    if(h.holdActive){h.holdActive=false;h.resetFeedback();status=@"Hover hold disengaged · throttle retained";}
    else if(!flight.setHoverHold(h.holdMode==2?2:1,h.holdMode==2?h.verticalSpeedTarget:h.altitudeTarget))status=@"Hover hold requires fuel and a solid body below 120 km";
    else status=@"Hover hold engaged · manual hover throttle or X disengages hold";
}
- (void)toggleHoverAttitude:(id)sender {auto &h=flight.glider.hoverControl;h.attitudeMode=h.attitudeMode==1?0:1;status=h.attitudeMode?@"Hover auto attitude · pitch/roll keys command up to 10° tilt":@"Hover attitude control off";}
- (void)holdCurrentAltitude:(id)sender {
    auto &h=flight.glider.hoverControl;
    if(h.holdActive&&h.holdMode==1){[self toggleHoverHold:nil];return;}
    if(flight.setHoverHold(1,std::max(0.,flight.altitude())))status=@"Holding current altitude · X cuts engines";
    else status=@"Hover hold requires fuel and a solid body below 120 km";
}
- (void)holdZeroVerticalSpeed:(id)sender {
    auto &h=flight.glider.hoverControl;
    if(h.holdActive&&h.holdMode==2){[self toggleHoverHold:nil];return;}
    if(flight.setHoverHold(2,0))status=@"Holding zero vertical speed · X cuts engines";
    else status=@"Hover hold requires fuel and a solid body below 120 km";
}
- (void)toggleParkingBrake:(id)sender {flight.glider.parkingBrake=!flight.glider.parkingBrake;self.hud.needsDisplay=YES;}
- (void)demonstrateGlider:(id)sender {
    [self startOrbit:nil];[self setViewMode:0];flight.align(flight.velocity);flight.assist=Assist::Prograde;flight.warp=10;
    for(Part p:{Part::Gear,Part::Nose,Part::Radiator,Part::RetroCover,Part::Airbrake}) flight.glider.command(p,1);
    flight.glider.navLights=flight.glider.beacons=flight.glider.strobes=true;demoLadderQueued=true;
    status=@"Mechanism demonstration · original deployment timing at 10× · R restarts";
}
- (void)pauseFlight:(id)sender {
    if(burnSkip.running()){burnSkip.cancel(flight);status=@"Skip cancelled · paused";}
    else flight.paused=!flight.paused;
    [self clearInput];self.hud.needsDisplay=YES;
}
- (void)skipToBurn:(id)sender {
    if(burnSkip.running()){burnSkip.cancel(flight);status=@"Skip cancelled · paused";}
    else if(!transxSession)status=@"No planned burn. Configure a maneuver first.";
    else{
        std::string error;
        if(!burnSkip.begin(flight,*transxSession,error))status=transxString(error);
        else{[self clearInput];status=@"Skipping to one day before estimated ignition · Space cancels";}
    }
    self.hud.needsDisplay=YES;[self.routePanel refresh];
}
- (void)toggleHelp:(id)sender { helpVisible=!helpVisible; self.hud.needsDisplay=YES; }
- (void)showError:(const char *)message { NSAlert *a=[NSAlert new]; a.messageText=@"Unable to load flight"; a.informativeText=[NSString stringWithUTF8String:message]; [a runModal]; }
- (void)openScenario:(id)sender {
    [self clearInput]; BOOL wasPaused=flight.paused; flight.paused=true;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"scn"]]; panel.message=@"Choose a Solar System scenario focused on a standard DeltaGlider.";
    if([panel runModal]==NSModalResponseOK) { try { flight.load(panel.URL.fileSystemRepresentation);[self resetNavigation];[self loadTransXScenario:panel.URL.path]; restartBody=-1;restartScenario=panel.URL.path;status=panel.URL.lastPathComponent; }
        catch(const std::exception &e) { [self showError:e.what()]; flight.paused=wasPaused; } }
    else flight.paused=wasPaused;
    previous=CACurrentMediaTime();
}
- (void)saveScenario:(id)sender {
    [self clearInput]; BOOL wasPaused=flight.paused; flight.paused=true;
    NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"Native flight.scn"; panel.allowedContentTypes=@[[UTType typeWithFilenameExtension:@"scn"]];
    if([panel runModal]==NSModalResponseOK) { try { flight.save(panel.URL.fileSystemRepresentation);[self saveTransXScenario:panel.URL.path]; status=@"Flight saved"; } catch(const std::exception &e) { [self showError:e.what()]; } }
    flight.paused=wasPaused; previous=CACurrentMediaTime();
}
- (void)keyDown:(NSEvent *)event {
    if(smokeFrames) return;
    if(event.modifierFlags&NSEventModifierFlagCommand) { [super keyDown:event]; return; }
    unsigned code=event.keyCode; if(code<held.size()) held[code]=true;
    if(code==13&&(event.modifierFlags&NSEventModifierFlagShift)) {held[code]=false;if(!event.isARepeat)[self toggleParkingBrake:nil];return;}
    if(event.isARepeat) return;
    switch(code) {
        case 49:[self pauseFlight:nil];break;
        case 7:flight.cutEngines();break; // X
        case 15:[self resetFlight:nil];break;
        case 35:[self selectNavButton:2];break;
        case 31:[self selectNavButton:1];break;
        case 40:[self selectNavButton:0];break;
        case 41:[self selectNavButton:4];break;
        case 39:[self selectNavButton:3];break;
        case 45:flight.clearAssist();transxAlignDisplay=-1;break;
        case 17:if(burnSkip.running())burnSkip.cancel(flight);flight.warp=stepTimeAcceleration(flight.warp,true);status=[NSString stringWithFormat:@"Time acceleration %.0f×",flight.warp];break;
        case 16:if(burnSkip.running())burnSkip.cancel(flight);flight.warp=stepTimeAcceleration(flight.warp,false);status=[NSString stringWithFormat:@"Time acceleration %.0f×",flight.warp];break;
        case 9:[self cycleView:nil];break;
        case 46:[self showSystems:nil];break;
        case 5:flight.glider.toggle(Part::Gear);break;
        case 8:flight.glider.toggle(Part::Nose);break;
        case 11:if(event.modifierFlags&NSEventModifierFlagShift) flight.glider.command(Part::Airbrake,std::max(0.,flight.glider.part(Part::Airbrake).target-.5)); else flight.glider.command(Part::Airbrake,std::min(1.,flight.glider.part(Part::Airbrake).target+.5));break;
        case 4:if(event.modifierFlags&NSEventModifierFlagOption)[self cycleHudColour:nil];else if(event.modifierFlags&NSEventModifierFlagControl)flight.hud.cycleMode();else flight.glider.toggle(Part::Hatch);break;
        case 3:flight.glider.toggle(Part::Radiator);break;
        case 37:if(event.modifierFlags&NSEventModifierFlagShift)[self selectNavButton:5];else if(!flight.glider.toggle(Part::Ladder)) status=@"Open the nose cone fully before extending the ladder";break;
        case 34:flight.glider.toggle(event.modifierFlags&NSEventModifierFlagShift?Part::InnerLock:Part::OuterLock);break;
        case 32:flight.glider.toggle(Part::RetroCover);break;
        case 96:[self toggleHoverAttitude:nil];break;
        case 97:[self holdCurrentAltitude:nil];break;
        case 98:[self holdZeroVerticalSpeed:nil];break;
        case 100:[self cycleExternalCamera:nil];break;
        case 99:[self cycleWeather:nil];break;
        case 118:[self showNavigation:nil];break;
        case 122:[self toggleHelp:nil];break;
        case 120:orbitVisible=!orbitVisible;break;
    }
}
- (void)startBodyOrbit:(NSMenuItem *)sender {
    restartBody=sender.tag;[self resetFlight:nil];externalCamera.setMode(ExternalCameraMode::OrbitalChase,flight,flight.reference);externalCamera.yaw=-.55;externalCamera.pitch=flight.centralBody().solid?.32:1.35;externalCamera.distance=43;[self setViewMode:0];self.hud.needsDisplay=YES;
}
- (void)setViewMode:(int)mode {
    cockpit=mode!=0;panelView=mode==2;self.panel2D.hidden=!panelView;[self clearInput];
    if(panelView)[self updateCockpitDisplays];self.hud.needsDisplay=YES;
}
- (void)cycleView:(id)sender {[self setViewMode:!cockpit?1:panelView?0:2];}
- (void)chooseView:(NSMenuItem *)sender {[self setViewMode:(int)sender.tag];[self.window makeFirstResponder:self];}
- (void)selectNavButton:(int)button {
    if(button==6){
        if(flight.assist==Assist::Maneuver&&transxAlignDisplay==native::transx::Session::RouteDisplay){
            flight.clearAssist();transxAlignDisplay=-1;status=@"Planned burn alignment released";
        }else if(!transxSession)status=@"No planned burn. Configure a maneuver in TransX or Route Planner.";
        else {int stage=transxSession->selectedStage();
            if(stage!=1)status=@"Select the current stage before aligning; this maneuver is for a later stage.";
            else if(flight.rcs<=0)status=@"RCS fuel depleted · cannot align to the planned burn";
            else if(transxSession->alignStage(stage)){transxAlignDisplay=native::transx::Session::RouteDisplay;transxAlignBody=flight.reference;status=@"RCS aligning to the selected burn · main engine is manual";}
            else status=@"No applicable maneuver vector. Set a nonzero burn for the current stage.";
        }
        self.hud.needsDisplay=YES;self.panel2D.needsDisplay=YES;return;
    }
    Assist mode=navButtonMode(button);if(mode==Assist::Free)return;
    flight.toggleAssist(mode);transxAlignDisplay=-1;
    if(flight.rcs<=0&&flight.assistActive(mode))status=@"RCS fuel depleted · attitude program cannot fire";
    self.hud.needsDisplay=YES;self.panel2D.needsDisplay=YES;
}
- (void)chooseNavProgram:(NSMenuItem *)sender {[self selectNavButton:(int)sender.tag];[self.window makeFirstResponder:self];}
- (void)chooseHudMode:(NSMenuItem *)sender {flight.hud.select((int)sender.tag);self.hud.needsDisplay=YES;self.panel2D.needsDisplay=YES;[self.window makeFirstResponder:self];}
- (void)cycleHudColour:(id)sender {flight.hud.cycleColour();self.hud.needsDisplay=YES;}
- (void)adjustHudBrightness:(NSMenuItem *)sender {flight.hud.adjustBrightness(sender.tag*.1);self.hud.needsDisplay=YES;}
- (void)applyExternalCamera:(ExternalCameraMode)mode reference:(BodyId)reference {
    if(!externalCamera.setMode(mode,flight,reference)){status=@"This camera mode requires a solid reference body";self.hud.needsDisplay=YES;return;}
    [self setViewMode:0];
    if(mode==ExternalCameraMode::TargetTo||mode==ExternalCameraMode::TargetFrom)status=[NSString stringWithFormat:@"Camera: %s %s",externalCameraModeName(mode),body(reference).name];
    else if(mode==ExternalCameraMode::GroundObserver)status=@"Ground observer · drag to move the site · scroll to zoom";
    else status=[NSString stringWithFormat:@"Camera: %s",externalCameraModeName(mode)];
    self.hud.needsDisplay=YES;[self.window makeFirstResponder:self];
}
- (void)chooseExternalCamera:(NSMenuItem *)sender {[self applyExternalCamera:(ExternalCameraMode)sender.tag reference:flight.reference];}
- (void)chooseCameraReference:(NSMenuItem *)sender {
    bool to=sender.tag<200;int index=(int)sender.tag-(to?100:200);
    if(index>=0&&index<(int)BodyCount)[self applyExternalCamera:to?ExternalCameraMode::TargetTo:ExternalCameraMode::TargetFrom reference:(BodyId)index];
}
- (void)cycleExternalCamera:(id)sender {
    auto mode=externalCamera.mode;
    auto next=mode==ExternalCameraMode::TargetRelative?ExternalCameraMode::AbsoluteDirection:mode==ExternalCameraMode::AbsoluteDirection?ExternalCameraMode::GlobalFrame:ExternalCameraMode::TargetRelative;
    [self applyExternalCamera:next reference:flight.reference];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if(item.action==@selector(chooseNavProgram:)){item.state=(item.tag==6?flight.assist==Assist::Maneuver&&transxAlignDisplay==native::transx::Session::RouteDisplay:flight.assistActive(navButtonMode((int)item.tag)))?NSControlStateValueOn:NSControlStateValueOff;return YES;}
    if(item.action==@selector(chooseHudMode:)){item.state=flight.hud.mode==item.tag?NSControlStateValueOn:NSControlStateValueOff;return YES;}
    if(item.action==@selector(chooseExternalCamera:)){item.state=(NSInteger)externalCamera.mode==item.tag?NSControlStateValueOn:NSControlStateValueOff;return item.tag!=(NSInteger)ExternalCameraMode::GroundObserver||flight.centralBody().solid;}
    if(item.action==@selector(chooseCameraReference:)){bool to=item.tag<200;int index=(int)item.tag-(to?100:200);item.state=externalCamera.mode==(to?ExternalCameraMode::TargetTo:ExternalCameraMode::TargetFrom)&&(int)externalCamera.target==index?NSControlStateValueOn:NSControlStateValueOff;return YES;}
    if(item.action==@selector(toggleTransXMFD:)){item.state=transxMfd[std::clamp((int)item.tag,0,1)]?NSControlStateValueOn:NSControlStateValueOff;return YES;}
    if(item.action==@selector(setWeather:))return flight.reference==BodyId::Earth;
    return YES;
}
- (void)cycleWeather:(id)sender {visuals.weather=(visuals.weather+1)%4;status=[NSString stringWithFormat:@"Weather: %@ · F3 changes cloud coverage",[visuals weatherName]];self.hud.needsDisplay=YES;}
- (void)setWeather:(NSMenuItem *)sender {visuals.weather=sender.tag;status=[NSString stringWithFormat:@"Weather: %@",[visuals weatherName]];self.hud.needsDisplay=YES;}
- (void)keyUp:(NSEvent *)event { if(event.keyCode<held.size()) held[event.keyCode]=false; }
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];activeCockpitControl=-1;lastDragPoint=event.locationInWindow;haveDragPoint=true;
    if(!cockpit||smokeFrames)return;
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];
    double aspect=self.bounds.size.width/self.bounds.size.height;
    Vector ray=cockpitCamera.ray(cockpitYaw,cockpitPitch,p.x/self.bounds.size.width*2-1,p.y/self.bounds.size.height*2-1,aspect);
    auto hit=pickCockpit({0,1.467,6.782},ray);auto &g=flight.glider;
    if(hit.action>=200&&hit.action<202){int display=hit.action-200;
        if(transxSession&&transxMfd[display]){if(event.clickCount>=2)[self resetTransXGraph:display];else activeCockpitControl=hit.action;}
        return;
    }
    if(hit.action>=100&&hit.action<124){int id=hit.action-100;[self operateTransXButton:id%12 display:id/12];activeCockpitControl=hit.action;return;}
    if(hit.action<0)return;
    if(hit.action<9) g.toggle(static_cast<Part>(hit.action));
    else if(hit.action>=10&&hit.action<=20) {
        bool *values[]={&g.valves[0],&g.valves[1],&g.valves[2],&g.valves[3],&g.valves[4],&g.coolantPump,&g.navLights,&g.beacons,&g.strobes,&g.landingLight,&g.instrumentLights};
        *values[hit.action-10]=!*values[hit.action-10];
    } else if(hit.action==30) g.rcsMode=std::clamp(g.rcsMode+(hit.u>.5?1:-1),0,2);
    else if(hit.action==31) g.trim=std::clamp(g.trim+(hit.v>.5?.1:-.1),-1.,1.);
    else if(hit.action==32) g.gimbalPitch=std::clamp(g.gimbalPitch+(hit.v>.5?.1:-.1),-1.,1.);
    else if(hit.action==33) g.gimbalYaw=std::clamp(g.gimbalYaw+(hit.v>.5?.1:-.1),-1.,1.);
    else if(hit.action==34) {flight.throttle=std::clamp(1-hit.v,0.,1.);activeCockpitControl=34;}
    else if(hit.action==35) {flight.setHoverThrottle(std::clamp(hit.v,0.,1.));activeCockpitControl=35;}
    else if(hit.action==40) {g.hoverControl.attitudeMode=std::clamp(g.hoverControl.attitudeMode+(hit.u>.5?1:-1),0,2);}
    else if(hit.action>=41&&hit.action<=43) {
        activeCockpitControl=hit.action;activeCockpitDirection=hit.v>.5?1:-1;auto &h=g.hoverControl;
        if(hit.action==43) {if(h.holdMode==2)h.verticalSpeedTarget=std::clamp(h.verticalSpeedTarget+activeCockpitDirection*.1,-20.,20.);else h.altitudeTarget=std::clamp(h.altitudeTarget+activeCockpitDirection*.5,0.,120000.);}
        else if(h.attitudeMode==2) {double &target=hit.action==41?h.pitchTarget:h.bankTarget;target=std::clamp(target+activeCockpitDirection*RAD,-10*RAD,10*RAD);}
    }
    else if(hit.action==44) {
        auto &h=g.hoverControl;int mode=hit.u>.5?2:1;activeCockpitControl=44;activeCockpitDirection=hit.u>.5?1:-1;
        if(h.holdActive&&mode!=h.holdMode)flight.setHoverHold(mode,mode==1?std::max(0.,flight.altitude()):std::clamp(flight.surfaceVerticalSpeed(),-20.,20.));else h.holdMode=mode;
    }
    else if(hit.action==45) {activeCockpitControl=45;auto &h=g.hoverControl;if(h.holdMode==2)h.verticalSpeedTarget=0;else h.altitudeTarget=std::clamp(flight.altitude(),0.,120000.);}
    else if(hit.action==46) {activeCockpitControl=46;[self toggleHoverHold:nil];}
    else if(hit.action==60){int button=cockpitNavButton(hit.u,hit.v);if(button>=0){[self selectNavButton:button];activeCockpitControl=70+button;}return;}
    else if(hit.action==61){int x=int(hit.u*126),button=x/43;if(button<3&&x%43<40){flight.hud.select(button+1);activeCockpitControl=80+button;self.hud.needsDisplay=YES;}return;}
    else if(hit.action==62){activeCockpitControl=62;activeCockpitDirection=hit.u>.5?1:-1;flight.hud.adjustBrightness(activeCockpitDirection*.04);self.hud.needsDisplay=YES;return;}
    else if(hit.action==63){activeCockpitControl=63;[self cycleHudColour:nil];return;}
    status=@"Cockpit control operated · M opens the complete systems panel";
}
- (void)mouseUp:(NSEvent *)event { activeCockpitControl=-1;haveDragPoint=false; }
- (void)mouseDragged:(NSEvent *)event {
    if(smokeFrames) return;
    double deltaX=event.deltaX,deltaY=event.deltaY;NSPoint point=event.locationInWindow;
    if(!deltaX&&!deltaY&&haveDragPoint){deltaX=point.x-lastDragPoint.x;deltaY=lastDragPoint.y-point.y;}
    lastDragPoint=point;haveDragPoint=true;
    if(activeCockpitControl>=200&&activeCockpitControl<202){[self rotateTransXGraph:activeCockpitControl-200 horizontal:deltaX vertical:deltaY];return;}
    if(activeCockpitControl>=100)return;
    if(activeCockpitControl==34||activeCockpitControl==35) {
        double &level=activeCockpitControl==34?flight.throttle:flight.glider.hover;
        double value=std::clamp(level-deltaY*.01,0.,1.);
        if(activeCockpitControl==35)flight.setHoverThrottle(value);else level=value;return;
    }
    if(activeCockpitControl>=40) {
        auto &h=flight.glider.hoverControl;
        if(activeCockpitControl==41&&h.attitudeMode==2)h.pitchTarget=std::clamp(h.pitchTarget-deltaY*.2*RAD,-10*RAD,10*RAD);
        if(activeCockpitControl==42&&h.attitudeMode==2)h.bankTarget=std::clamp(h.bankTarget+deltaX*.2*RAD,-10*RAD,10*RAD);
        if(activeCockpitControl==43) {if(h.holdMode==2)h.verticalSpeedTarget=std::clamp(h.verticalSpeedTarget+deltaX*.1,-20.,20.);else h.altitudeTarget=std::clamp(h.altitudeTarget+deltaX,0.,120000.);}
        return;
    }
    if(cockpit) { cockpitYaw=std::clamp(cockpitYaw+deltaX*.006,-2.5,2.5); cockpitPitch=std::clamp(cockpitPitch-deltaY*.006,-1.1,1.1); }
    else externalCamera.drag(deltaX,deltaY);
}
- (void)scrollWheel:(NSEvent *)event {
    if(smokeFrames)return;
    if(cockpit)cockpitCamera.zoom(event.scrollingDeltaY);
    else externalCamera.zoom(event.scrollingDeltaY);
}
@end
#include "GliderPanel.inc"
#include "TransXPanel.inc"
#include "RoutePanel.inc"
#include "Panel2D.inc"

@interface AppDelegate : NSObject<NSApplicationDelegate,NSWindowDelegate>
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) FlightView *view;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try { try {
        NSRect rect=NSMakeRect(0,0,1280,800);
        self.window=[[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.window.title=[NSString stringWithFormat:@"Orbiter Native %@ — Delta-glider",[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]; self.window.minSize=NSMakeSize(900,600); self.window.delegate=self;
        self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.view=[[FlightView alloc] initWithFrame:rect]; self.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        NSView *root=[[NSView alloc] initWithFrame:rect]; [root addSubview:self.view];
        FlightHUD *hud=[[FlightHUD alloc] initWithFrame:rect]; hud.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; hud.flightView=self.view;
        [root addSubview:hud]; self.view.hud=hud;
        Panel2DView *panel=[[Panel2DView alloc] initWithFrame:rect];panel.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;panel.flightView=self.view;panel.hidden=!self.view->panelView;[root addSubview:panel];self.view.panel2D=panel;
        self.window.contentView=root;
        NSMenu *main=[NSMenu new]; NSMenuItem *appItem=[NSMenuItem new]; [main addItem:appItem];
        NSMenu *app=[NSMenu new]; [app addItemWithTitle:@"Quit Orbiter" action:@selector(terminate:) keyEquivalent:@"q"]; appItem.submenu=app;
        NSMenuItem *fileItem=[NSMenuItem new]; fileItem.title=@"File"; [main addItem:fileItem]; NSMenu *file=[NSMenu new]; fileItem.submenu=file;
        NSMenuItem *open=[file addItemWithTitle:@"Open Scenario…" action:@selector(openScenario:) keyEquivalent:@"o"]; open.target=self.view;
        NSMenuItem *save=[file addItemWithTitle:@"Save Scenario…" action:@selector(saveScenario:) keyEquivalent:@"s"]; save.target=self.view;
        NSMenuItem *flightItem=[NSMenuItem new]; flightItem.title=@"Flight"; [main addItem:flightItem]; NSMenu *fm=[NSMenu new]; flightItem.submenu=fm;
        NSMenuItem *pause=[fm addItemWithTitle:@"Pause / Resume" action:@selector(pauseFlight:) keyEquivalent:@""]; pause.target=self.view;
        NSMenuItem *systems=[fm addItemWithTitle:@"Glider Systems…" action:@selector(showSystems:) keyEquivalent:@""]; systems.target=self.view;
        NSArray *viewTitles=@[@"External View",@"3D Cockpit View",@"2D Instrument Panel View"];
        for(int i=0;i<3;++i){NSMenuItem *item=[fm addItemWithTitle:viewTitles[i] action:@selector(chooseView:) keyEquivalent:@""];item.target=self.view;item.tag=i;}
        NSMenuItem *surface=[fm addItemWithTitle:@"Cape Canaveral — Surface Flight" action:@selector(startSurface:) keyEquivalent:@""];surface.target=self.view;
        NSMenuItem *practice=[fm addItemWithTitle:@"Cape Canaveral — Hover Practice" action:@selector(startHoverPractice:) keyEquivalent:@""];practice.target=self.view;
        NSMenuItem *hoverAtt=[fm addItemWithTitle:@"Toggle Hover Auto Attitude (F5)" action:@selector(toggleHoverAttitude:) keyEquivalent:@""];hoverAtt.target=self.view;
        NSMenuItem *holdAlt=[fm addItemWithTitle:@"Hold Current Altitude (F6)" action:@selector(holdCurrentAltitude:) keyEquivalent:@""];holdAlt.target=self.view;
        NSMenuItem *holdVS=[fm addItemWithTitle:@"Hold Zero Vertical Speed (F7)" action:@selector(holdZeroVerticalSpeed:) keyEquivalent:@""];holdVS.target=self.view;
        NSMenuItem *orbit=[fm addItemWithTitle:@"Earth Orbit" action:@selector(startOrbit:) keyEquivalent:@""];orbit.target=self.view;
        NSMenuItem *park=[fm addItemWithTitle:@"Toggle Parking Brake" action:@selector(toggleParkingBrake:) keyEquivalent:@""];park.target=self.view;
        NSMenuItem *demo=[fm addItemWithTitle:@"Mechanism Demonstration" action:@selector(demonstrateGlider:) keyEquivalent:@""];demo.target=self.view;
        NSMenuItem *reset=[fm addItemWithTitle:@"Restart Flight" action:@selector(resetFlight:) keyEquivalent:@""]; reset.target=self.view;
        NSMenuItem *help=[fm addItemWithTitle:@"Flight Controls" action:@selector(toggleHelp:) keyEquivalent:@"?"]; help.target=self.view;
        NSMenuItem *cameraItem=[NSMenuItem new];cameraItem.title=@"Camera";[main addItem:cameraItem];NSMenu *cameraMenu=[NSMenu new];cameraItem.submenu=cameraMenu;
        NSArray<NSString *> *cameraNames=@[@"Orbital Chase",@"Target-relative (F8)",@"Absolute Direction (F8)",@"Global Frame (F8)"];
        for(int i=0;i<4;++i){NSMenuItem *item=[cameraMenu addItemWithTitle:cameraNames[i] action:@selector(chooseExternalCamera:) keyEquivalent:@""];item.target=self.view;item.tag=i;}
        for(int to:{1,0}){NSMenuItem *parent=[cameraMenu addItemWithTitle:to?@"Target to…":@"Target from…" action:nil keyEquivalent:@""];NSMenu *refs=[NSMenu new];parent.submenu=refs;
            for(const auto &b:bodies()){NSMenuItem *item=[refs addItemWithTitle:[NSString stringWithUTF8String:b.name] action:@selector(chooseCameraReference:) keyEquivalent:@""];item.target=self.view;item.tag=(to?100:200)+(NSInteger)b.id;}}
        NSMenuItem *ground=[cameraMenu addItemWithTitle:@"Ground Observer" action:@selector(chooseExternalCamera:) keyEquivalent:@""];ground.target=self.view;ground.tag=(NSInteger)ExternalCameraMode::GroundObserver;
        NSMenuItem *navItem=[NSMenuItem new];navItem.title=@"Navigation";[main addItem:navItem];NSMenu *nav=[NSMenu new];navItem.submenu=nav;
        NSMenuItem *programs=[nav addItemWithTitle:@"RCS Programs" action:nil keyEquivalent:@""];NSMenu *programMenu=[NSMenu new];programs.submenu=programMenu;
        NSArray<NSString *> *programNames=@[@"Kill Rotation (K)",@"Retrograde (O)",@"Prograde (P)",@"Anti-normal (')",@"Normal (;)",@"Horizon Level (Shift-L)",@"Align Selected Burn"];
        for(int i=0;i<7;++i){NSMenuItem *item=[programMenu addItemWithTitle:programNames[i] action:@selector(chooseNavProgram:) keyEquivalent:@""];item.target=self.view;item.tag=i;}
        NSMenuItem *hudMenuItem=[nav addItemWithTitle:@"HUD Mode" action:nil keyEquivalent:@""];NSMenu *hudMenu=[NSMenu new];hudMenuItem.submenu=hudMenu;
        NSArray<NSString *> *hudNames=@[@"Orbit",@"Surface",@"Docking"];
        for(int i=0;i<3;++i){NSMenuItem *item=[hudMenu addItemWithTitle:hudNames[i] action:@selector(chooseHudMode:) keyEquivalent:@""];item.target=self.view;item.tag=i+1;}
        NSMenuItem *colour=[hudMenu addItemWithTitle:@"Cycle HUD Colour (Option-H)" action:@selector(cycleHudColour:) keyEquivalent:@""];colour.target=self.view;
        for(int sign:{-1,1}){NSMenuItem *item=[hudMenu addItemWithTitle:sign<0?@"Decrease Brightness":@"Increase Brightness" action:@selector(adjustHudBrightness:) keyEquivalent:@""];item.target=self.view;item.tag=sign;}
        NSMenuItem *planner=[nav addItemWithTitle:@"TransX… (F4)" action:@selector(showNavigation:) keyEquivalent:@"t"];planner.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;planner.target=self.view;
        NSMenuItem *routePlanner=[nav addItemWithTitle:@"Route Planner…" action:@selector(showRoutePlanner:) keyEquivalent:@"r"];routePlanner.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;routePlanner.target=self.view;
        NSMenuItem *skip=[nav addItemWithTitle:@"Skip to 1 Day Before Burn" action:@selector(skipToBurn:) keyEquivalent:@""];skip.target=self.view;
        for(int d=0;d<2;++d){NSMenuItem *item=[nav addItemWithTitle:d?@"TransX on Right MFD":@"TransX on Left MFD" action:@selector(toggleTransXMFD:) keyEquivalent:@""];item.target=self.view;item.tag=d;}
        NSMenuItem *guide=[nav addItemWithTitle:@"TransX Quickstart…" action:@selector(showTransXGuide:) keyEquivalent:@""];guide.target=self.view;
        NSMenuItem *solarItem=[NSMenuItem new];solarItem.title=@"Solar System";[main addItem:solarItem];NSMenu *system=[NSMenu new];solarItem.submenu=system;
        for(const auto &b:bodies())if(b.id==BodyId::Sun||b.parent==BodyId::Sun){
            NSMenuItem *parent=[system addItemWithTitle:[NSString stringWithUTF8String:b.name] action:nil keyEquivalent:@""];NSMenu *children=[NSMenu new];parent.submenu=children;
            NSMenuItem *orbit=[children addItemWithTitle:[NSString stringWithFormat:@"%s Orbit",b.name] action:@selector(startBodyOrbit:) keyEquivalent:@""];orbit.target=self.view;orbit.tag=(NSInteger)b.id;
            for(const auto &moon:bodies())if(b.id!=BodyId::Sun&&moon.id!=b.id&&moon.parent==b.id){NSMenuItem *item=[children addItemWithTitle:[NSString stringWithFormat:@"%s Orbit",moon.name] action:@selector(startBodyOrbit:) keyEquivalent:@""];item.target=self.view;item.tag=(NSInteger)moon.id;}
        }
        NSMenuItem *weatherItem=[NSMenuItem new];weatherItem.title=@"Weather";[main addItem:weatherItem];NSMenu *weather=[NSMenu new];weatherItem.submenu=weather;
        NSArray *presets=@[@"Clear",@"Scattered",@"Overcast",@"Storm"];
        for(NSInteger i=0;i<4;++i){NSMenuItem *item=[weather addItemWithTitle:presets[i] action:@selector(setWeather:) keyEquivalent:@""];item.target=self.view;item.tag=i;}
        if([NSProcessInfo.processInfo.arguments containsObject:@"--transx"])[self.view ensureTransX];
        if(self.view->navigationTarget>=0)[self.view prepareNavigation:(BodyId)self.view->navigationTarget];
        NSApp.mainMenu=main; [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        if([NSProcessInfo.processInfo.arguments containsObject:@"--transx-preview"])[self.view showNavigation:nil];
    } catch(const std::exception &e) { [self fail:[NSString stringWithUTF8String:e.what()]]; } }
    @catch(NSException *e) { [self fail:e.reason]; }
}
- (void)fail:(NSString *)message { fprintf(stderr,"Orbiter Native: %s\n",message.UTF8String); if([NSProcessInfo.processInfo.arguments containsObject:@"--frames"]) exit(1); NSAlert *a=[NSAlert new]; a.messageText=@"Orbiter could not start"; a.informativeText=message; [a runModal]; [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)windowDidResignKey:(NSNotification *)note { [self.view clearInput]; }
- (void)applicationDidResignActive:(NSNotification *)note { [self.view clearInput]; }
@end
int main(int argc,const char **argv) { @autoreleasepool {
    NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    AppDelegate *delegate=[AppDelegate new]; app.delegate=delegate; [app run]; return 0;
} }

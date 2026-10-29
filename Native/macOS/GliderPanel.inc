// Native controls for the standard Delta-glider. Included after FlightView.
@interface FlippedGliderDocument : NSView
@end
@implementation FlippedGliderDocument
- (BOOL)isFlipped { return YES; }
@end
@interface GliderPanel : NSWindowController {
    __weak FlightView *flightView;
    NSMutableArray<NSButton *> *mechanismButtons,*switches;
    NSMutableArray<NSTextField *> *mechanismValues,*engineValues;
    NSMutableArray<NSSlider *> *engineSliders;
    NSMutableArray<NSTextField *> *airTargets;
    NSMutableArray<NSButton *> *airHolds;
    NSTextField *airReadout;
    NSTextField *summary,*pressure,*thermal,*warning;
    NSButton *parkingBrake,*holdButton;
    NSSegmentedControl *hoverAttitude,*holdMode;
    NSSlider *hoverPitch,*hoverBank;
    NSTextField *hoverPitchLabel,*hoverBankLabel,*holdTarget,*holdTargetLabel,*hoverReadout;
    NSButton *captureHoldTarget;
    NSNumberFormatter *holdFormatter;
    NSSegmentedControl *rcsSelector;
    NSTimer *refreshTimer;
}
- (instancetype)initWithFlightView:(FlightView *)view;
- (void)refresh:(id)sender;
@end
@implementation GliderPanel
- (instancetype)initWithFlightView:(FlightView *)view {
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,440,690) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:panel]; if(!self) return nil;
    flightView=view; panel.title=@"Delta-glider Systems"; panel.floatingPanel=YES;
    panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    panel.releasedWhenClosed=NO;
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,440,690)];
    scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES;
    FlippedGliderDocument *doc=[[FlippedGliderDocument alloc] initWithFrame:NSMakeRect(0,0,420,2126)];
    scroll.documentView=doc; panel.contentView=scroll;
    mechanismButtons=[NSMutableArray new]; mechanismValues=[NSMutableArray new];
    engineSliders=[NSMutableArray new]; engineValues=[NSMutableArray new]; switches=[NSMutableArray new];
    auto label=[&](NSString *value,CGFloat x,CGFloat y,CGFloat width,CGFloat size=12) {
        NSTextField *field=[NSTextField labelWithString:value]; field.frame=NSMakeRect(x,y,width,24);
        field.font=[NSFont systemFontOfSize:size weight:NSFontWeightRegular]; [doc addSubview:field]; return field;
    };
    auto section=[&](NSString *value,CGFloat y) { auto f=label(value,18,y,380,15);f.font=[NSFont boldSystemFontOfSize:15]; };
    summary=label(@"",18,14,390);
    section(@"Mechanisms",48);
    for(size_t i=0;i<PartCount;++i) {
        CGFloat y=82+i*34;
        label([NSString stringWithUTF8String:Glider::name(static_cast<Part>(i))],18,y+3,140);
        NSTextField *value=label(@"",162,y+3,124); [mechanismValues addObject:value];
        NSButton *button=[NSButton buttonWithTitle:@"Deploy" target:self action:@selector(togglePart:)];
        button.frame=NSMakeRect(302,y,104,28);button.tag=i;
        [button setAccessibilityLabel:[NSString stringWithUTF8String:Glider::name(static_cast<Part>(i))]];
        [doc addSubview:button]; [mechanismButtons addObject:button];
    }
    section(@"Engines and flight controls",404);
    NSArray *titles=@[@"Main throttle",@"Hover throttle",@"Retro throttle",@"Main L/R balance",@"Main pitch gimbal",@"Main yaw gimbal",@"Hover fore/aft",@"Elevator trim"];
    for(NSUInteger i=0;i<titles.count;++i) {
        CGFloat y=438+i*47; label(titles[i],18,y,240);
        NSTextField *value=label(@"",304,y,96);[engineValues addObject:value];
        NSSlider *slider=[NSSlider sliderWithValue:0 minValue:i<3?0:-1 maxValue:1 target:self action:@selector(changeEngine:)];
        slider.frame=NSMakeRect(18,y+20,384,20);slider.tag=i;slider.continuous=YES;
        [slider setAccessibilityLabel:titles[i]]; [doc addSubview:slider];[engineSliders addObject:slider];
    }
    label(@"RCS mode",18,820,100);
    rcsSelector=[NSSegmentedControl segmentedControlWithLabels:@[@"Off",@"Rotation",@"Translation"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeRCS:)];
    rcsSelector.frame=NSMakeRect(132,816,270,28); [doc addSubview:rcsSelector];
    NSButton *cut=[NSButton buttonWithTitle:@"Cut main, hover and retro" target:self action:@selector(cutEngines:)];
    cut.frame=NSMakeRect(18,854,384,28); [doc addSubview:cut];
    section(@"Cabin and airlock",906);
    pressure=label(@"",18,936,390);
    NSArray *switchTitles=@[@"Cabin pressure supply",@"Cabin vent",@"Cabin–airlock equalization",@"Airlock vent",@"Airlock pressure supply",@"Coolant pump",@"Navigation lights",@"Red beacons",@"White strobes",@"Landing / docking light",@"Cockpit illumination"];
    for(NSUInteger i=0;i<switchTitles.count;++i) {
        CGFloat y=i<5?966+i*27:1168+(i-5)*27;
        NSButton *button=[NSButton checkboxWithTitle:switchTitles[i] target:self action:@selector(changeSwitch:)];
        button.frame=NSMakeRect(18,y,384,24);button.tag=i;[doc addSubview:button];[switches addObject:button];
    }
    section(@"Cooling and lighting",1112); thermal=label(@"",18,1142,390);
    warning=label(@"",18,1340,386,11);warning.frame=NSMakeRect(18,1340,386,58);warning.maximumNumberOfLines=3;
    warning.textColor=[NSColor colorWithRed:1 green:.72 blue:.36 alpha:1];
    label(@"Mechanisms follow simulation time. M opens this panel.",18,1402,390,11);
    for(NSView *item in doc.subviews) if(item!=summary) {NSRect frame=item.frame;frame.origin.y+=424;item.frame=frame;}
    parkingBrake=[NSButton checkboxWithTitle:@"Parking brake  (Option-W)" target:self action:@selector(changeParkingBrake:)];
    parkingBrake.frame=NSMakeRect(18,43,384,24);[doc addSubview:parkingBrake];
    label(@"Hold , / . for left/right brakes. [ / ] changes hover thrust.",18,76,390,11);
    section(@"Hover control",112);
    hoverAttitude=[NSSegmentedControl segmentedControlWithLabels:@[@"Off",@"Auto attitude",@"Manual targets"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeHoverAttitude:)];
    hoverAttitude.frame=NSMakeRect(18,141,384,28);[hoverAttitude setAccessibilityLabel:@"Hover attitude mode"];[doc addSubview:hoverAttitude];
    hoverPitchLabel=label(@"Pitch target",18,181,184);hoverBankLabel=label(@"Bank target",218,181,184);
    hoverPitch=[NSSlider sliderWithValue:0 minValue:-10 maxValue:10 target:self action:@selector(changeHoverAngle:)];
    hoverBank=[NSSlider sliderWithValue:0 minValue:-10 maxValue:10 target:self action:@selector(changeHoverAngle:)];hoverBank.tag=1;hoverPitch.continuous=hoverBank.continuous=YES;
    hoverPitch.frame=NSMakeRect(18,205,180,20);hoverBank.frame=NSMakeRect(218,205,180,20);
    [hoverPitch setAccessibilityLabel:@"Hover pitch target in degrees"];[hoverBank setAccessibilityLabel:@"Hover bank target in degrees"];
    [doc addSubview:hoverPitch];[doc addSubview:hoverBank];
    holdMode=[NSSegmentedControl segmentedControlWithLabels:@[@"Altitude hold",@"Vertical speed hold"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeHoldMode:)];
    holdMode.frame=NSMakeRect(18,244,384,28);[holdMode setAccessibilityLabel:@"Hover hold mode"];[doc addSubview:holdMode];
    holdTargetLabel=label(@"Target (m)",18,284,110);
    holdTarget=[NSTextField textFieldWithString:@"100.0"];holdTarget.frame=NSMakeRect(126,280,100,26);
    holdFormatter=[NSNumberFormatter new];holdFormatter.numberStyle=NSNumberFormatterDecimalStyle;holdFormatter.maximumFractionDigits=1;
    holdFormatter.minimum=@0;holdFormatter.maximum=@120000;holdTarget.formatter=holdFormatter;holdTarget.target=self;holdTarget.action=@selector(changeHoldTarget:);[doc addSubview:holdTarget];
    captureHoldTarget=[NSButton buttonWithTitle:@"Use current altitude" target:self action:@selector(captureHoverTarget:)];
    captureHoldTarget.frame=NSMakeRect(237,278,165,28);[doc addSubview:captureHoldTarget];
    holdButton=[NSButton buttonWithTitle:@"Engage Altitude Hold" target:self action:@selector(toggleHoverHold:)];
    holdButton.frame=NSMakeRect(18,322,384,30);[doc addSubview:holdButton];
    hoverReadout=label(@"",18,365,384,11);hoverReadout.frame=NSMakeRect(18,365,384,64);hoverReadout.maximumNumberOfLines=3;
    // Keep atmospheric controls at the top of the common systems window so
    // they are reachable from all three camera views.
    for(NSView *item in doc.subviews)if(item!=summary){NSRect frame=item.frame;frame.origin.y+=260;item.frame=frame;}
    section(@"Atmospheric stabilization",44);
    airTargets=[NSMutableArray new];airHolds=[NSMutableArray new];
    NSArray *airLabels=@[@"Altitude (m)",@"Airspeed (m/s)",@"Bank (°)",@"Heading (°)"];
    for(int i=0;i<4;++i){
        CGFloat y=77+i*39;label(airLabels[i],18,y+4,106);
        NSTextField *field=[NSTextField textFieldWithString:@"0"];field.frame=NSMakeRect(124,y,87,26);field.tag=i;field.target=self;field.action=@selector(changeAirTarget:);
        NSNumberFormatter *formatter=[NSNumberFormatter new];formatter.numberStyle=NSNumberFormatterDecimalStyle;formatter.maximumFractionDigits=1;
        formatter.minimum=i==0?@50:i==1?@80:i==2?@(-60):@0;formatter.maximum=i==0?@100000:i==1?@2000:i==2?@60:@360;
        field.formatter=formatter;[field setAccessibilityLabel:[NSString stringWithFormat:@"%@ target",airLabels[i]]];[doc addSubview:field];[airTargets addObject:field];
        NSButton *hold=[NSButton checkboxWithTitle:@"Hold" target:self action:@selector(toggleAirHold:)];hold.frame=NSMakeRect(220,y,67,26);hold.tag=i;[hold setAccessibilityLabel:[NSString stringWithFormat:@"Hold %@",airLabels[i]]];[doc addSubview:hold];[airHolds addObject:hold];
        NSButton *capture=[NSButton buttonWithTitle:@"Use current" target:self action:@selector(captureAirTarget:)];capture.frame=NSMakeRect(292,y,110,26);capture.tag=i;[capture setAccessibilityLabel:[NSString stringWithFormat:@"Capture current %@",airLabels[i]]];[doc addSubview:capture];
    }
    airReadout=label(@"",18,237,384,11);airReadout.frame=NSMakeRect(18,237,384,61);airReadout.maximumNumberOfLines=3;
    [self refresh:nil];
    refreshTimer=[NSTimer scheduledTimerWithTimeInterval:.2 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
    [panel center]; return self;
}
- (void)refresh:(id)sender {
    FlightView *view=flightView; if(!view) return; auto &f=view->flight;auto &g=f.glider;
    summary.stringValue=f.paused?@"Paused — resume flight to move mechanisms":f.groundContact?[NSString stringWithFormat:@"Ground %.1f m/s · %d wheels in contact",f.groundSpeed,f.wheelContacts]:@"Systems active · standard Delta-glider";
    parkingBrake.state=g.parkingBrake?NSControlStateValueOn:NSControlStateValueOff;
    for(size_t i=0;i<PartCount;++i) {
        auto &a=g.parts[i];
        mechanismValues[i].stringValue=[NSString stringWithFormat:@"%@ %.0f%%",a.moving()?(a.target>a.position?@"Opening":@"Closing"):(a.position>.99?@"Open":a.position<.01?@"Closed":@"Stopped"),a.position*100];
        mechanismButtons[i].title=a.target>.5?@"Retract":@"Deploy";
    }
    double values[]={f.throttle,g.hover,g.retro,g.mainBalance,g.gimbalPitch,g.gimbalYaw,g.hoverBalance,g.trim};
    for(size_t i=0;i<8;++i) { engineSliders[i].doubleValue=values[i]; engineValues[i].stringValue=[NSString stringWithFormat:@"%+.0f%%",values[i]*100]; }
    auto &ap=f.atmospheric;
    if(!ap.targetsInitialized){for(int i=0;i<4;++i)f.captureAtmosphericTarget(i);ap.targetsInitialized=true;}
    bool available=f.atmosphericAvailable();
    for(int i=0;i<4;++i){
        if(!airTargets[i].currentEditor)airTargets[i].doubleValue=i>=2?Deg(ap.target[i]):ap.target[i];
        airHolds[i].state=ap.active[i]?NSControlStateValueOn:NSControlStateValueOff;
        airHolds[i].enabled=ap.active[i]||(available&&(i!=1||f.fuel>0));
        airTargets[i].enabled=!(i==2&&ap.active[3]);
    }
    airReadout.stringValue=[NSString stringWithFormat:@"Now: %.0f m · %.0f m/s airspeed · %.0f° bank · %.0f° heading\n%@",f.altitude(),f.airRelativeVelocity().length(),Deg(f.bank()),Deg(f.heading()),available?@"Manual pitch/roll/yaw or throttle releases the related hold.":@"Requires airspeed above 80 m/s, sufficient air density, and hover engines off."];
    auto &h=g.hoverControl;
    hoverAttitude.selectedSegment=h.attitudeMode;
    hoverPitch.enabled=hoverBank.enabled=h.attitudeMode==2;
    hoverPitch.doubleValue=Deg(h.pitchTarget);hoverBank.doubleValue=Deg(h.bankTarget);
    hoverPitchLabel.stringValue=[NSString stringWithFormat:@"Pitch target %+.1f°",Deg(h.pitchTarget)];
    hoverBankLabel.stringValue=[NSString stringWithFormat:@"Bank target %+.1f°",Deg(h.bankTarget)];
    engineSliders[6].enabled=h.attitudeMode==0;
    engineSliders[6].toolTip=@"Fore/aft balance is controlled automatically while hover attitude control is enabled.";
    bool altitudeMode=h.holdMode!=2;holdMode.selectedSegment=altitudeMode?0:1;
    holdTargetLabel.stringValue=altitudeMode?@"Target (m)":@"Target (m/s)";
    holdFormatter.minimum=altitudeMode?@0:@(-20);holdFormatter.maximum=altitudeMode?@120000:@20;
    if(!holdTarget.currentEditor)holdTarget.doubleValue=altitudeMode?h.altitudeTarget:h.verticalSpeedTarget;
    [holdTarget setAccessibilityLabel:altitudeMode?@"Hover altitude target in metres":@"Hover vertical speed target in metres per second"];
    captureHoldTarget.title=altitudeMode?@"Use current altitude":@"Set zero climb";
    holdButton.title=[NSString stringWithFormat:@"%@ %@ Hold",h.holdActive?@"Disengage":@"Engage",altitudeMode?@"Altitude":@"Vertical Speed"];
    holdButton.enabled=h.holdActive||(f.altitude()<120000&&f.fuel>0&&!f.impacted);
    holdButton.toolTip=@"Requires main propellant and flight over a solid body below 120 km. Manual hover throttle or Cut Engines disengages hold.";
    hoverReadout.stringValue=[NSString stringWithFormat:@"Pitch %+.1f°  Bank %+.1f°  Vertical %+.2f m/s\nEngines F %.0f%%  L %.0f%%  R %.0f%%\n%@",Deg(f.pitch()),Deg(f.bank()),f.surfaceVerticalSpeed(),h.levels[0]*100,h.levels[1]*100,h.levels[2]*100,h.attitudeLimited?@"Attitude outside 30° control range":h.thrustLimited?@"Thrust at limit — target may be unreachable":h.holdActive?@"Hold engaged · X cuts engines":@"Hold off · manual hover throttle"];
    hoverReadout.textColor=(h.attitudeLimited||h.thrustLimited)?[NSColor colorWithRed:1 green:.72 blue:.36 alpha:1]:NSColor.labelColor;
    rcsSelector.selectedSegment=g.rcsMode;
    pressure.stringValue=[NSString stringWithFormat:@"Cabin %.1f kPa    Airlock %.1f kPa",g.cabinPressure/1000,g.lockPressure/1000];
    thermal.stringValue=[NSString stringWithFormat:@"Coolant %.1f K    Cabin %.1f K",g.coolantTemperature,g.cabinTemperature];
    bool states[]={g.valves[0],g.valves[1],g.valves[2],g.valves[3],g.valves[4],g.coolantPump,g.navLights,g.beacons,g.strobes,g.landingLight,g.instrumentLights};
    for(size_t i=0;i<11;++i) switches[i].state=states[i]?NSControlStateValueOn:NSControlStateValueOff;
    auto message=g.warning();warning.stringValue=message.empty()?@"Opening the hatch or both airlock doors vents cabin air.":[NSString stringWithUTF8String:message.c_str()];
}
- (void)togglePart:(NSButton *)sender {
    if(!flightView->flight.glider.toggle(static_cast<Part>(sender.tag))) flightView->status=@"Open the nose cone fully before extending the escape ladder";
    [self refresh:nil];
}
- (void)changeEngine:(NSSlider *)sender {
    auto &f=flightView->flight; auto &g=f.glider;
    double *values[]={&f.throttle,&g.hover,&g.retro,&g.mainBalance,&g.gimbalPitch,&g.gimbalYaw,&g.hoverBalance,&g.trim};
    if(sender.tag==0)f.setMainThrottle(sender.doubleValue);else if(sender.tag==1)f.setHoverThrottle(sender.doubleValue);else *values[sender.tag]=sender.doubleValue; [self refresh:nil];
}
- (void)changeAirTarget:(NSTextField *)sender {
    auto &f=flightView->flight;int channel=(int)sender.tag;double value=sender.doubleValue;
    if(channel>=2)value=Rad(value);if(channel==3&&value>=Pi2)value=0;
    if(!f.setAtmosphericTarget(channel,value))flightView->status=@"Invalid atmospheric hold target";
    [self refresh:nil];
}
- (void)captureAirTarget:(NSButton *)sender {flightView->flight.captureAtmosphericTarget((int)sender.tag);[self refresh:nil];}
- (void)toggleAirHold:(NSButton *)sender {
    auto &f=flightView->flight;int channel=(int)sender.tag;bool enabled=sender.state==NSControlStateValueOn;
    if(enabled){double value=airTargets[channel].doubleValue;if(channel>=2)value=Rad(value);if(channel==3&&value>=Pi2)value=0;
        if(!f.setAtmosphericTarget(channel,value)){flightView->status=@"Invalid atmospheric hold target";[self refresh:nil];return;}}
    if(!f.setAtmosphericHold(channel,enabled))flightView->status=@"Atmospheric hold requires a valid target, airspeed and atmosphere, with hover engines off";
    [self refresh:nil];
}
- (void)changeHoverAttitude:(NSSegmentedControl *)sender {flightView->flight.glider.hoverControl.attitudeMode=(int)sender.selectedSegment;[self refresh:nil];}
- (void)changeHoverAngle:(NSSlider *)sender {
    auto &h=flightView->flight.glider.hoverControl;
    (sender.tag?h.bankTarget:h.pitchTarget)=Rad(sender.doubleValue);[self refresh:nil];
}
- (void)changeHoldMode:(NSSegmentedControl *)sender {
    auto &f=flightView->flight;auto &h=f.glider.hoverControl;int mode=(int)sender.selectedSegment+1;
    if(h.holdActive&&mode!=h.holdMode)f.setHoverHold(mode,mode==1?std::max(0.,f.altitude()):std::clamp(f.surfaceVerticalSpeed(),-20.,20.));
    else h.holdMode=mode;
    [self refresh:nil];
}
- (void)changeHoldTarget:(NSTextField *)sender {
    auto &h=flightView->flight.glider.hoverControl;
    if(h.holdMode==2)h.verticalSpeedTarget=std::clamp(sender.doubleValue,-20.,20.);else h.altitudeTarget=std::clamp(sender.doubleValue,0.,120000.);
    [self refresh:nil];
}
- (void)captureHoverTarget:(id)sender {
    auto &f=flightView->flight;auto &h=f.glider.hoverControl;
    if(h.holdMode==2)h.verticalSpeedTarget=0;else h.altitudeTarget=std::clamp(f.altitude(),0.,120000.);
    [self refresh:nil];
}
- (void)toggleHoverHold:(id)sender {[flightView toggleHoverHold:nil];[self refresh:nil];}
- (void)changeParkingBrake:(NSButton *)sender {flightView->flight.glider.parkingBrake=sender.state==NSControlStateValueOn;}
- (void)changeRCS:(NSSegmentedControl *)sender { flightView->flight.glider.rcsMode=(int)sender.selectedSegment; }
- (void)changeSwitch:(NSButton *)sender {
    auto &g=flightView->flight.glider;
    bool *values[]={&g.valves[0],&g.valves[1],&g.valves[2],&g.valves[3],&g.valves[4],&g.coolantPump,&g.navLights,&g.beacons,&g.strobes,&g.landingLight,&g.instrumentLights};
    *values[sender.tag]=sender.state==NSControlStateValueOn;
}
- (void)cutEngines:(id)sender { flightView->flight.cutEngines();[self refresh:nil]; }
@end
@implementation FlightView (GliderControls)
- (void)showSystems:(id)sender {
    if(!self.systemsPanel) self.systemsPanel=[[GliderPanel alloc] initWithFlightView:self];
    [self clearInput]; [self.systemsPanel refresh:nil]; [self.systemsPanel showWindow:nil];
}
- (void)toggleMechanism:(NSMenuItem *)sender { flight.glider.toggle(static_cast<Part>(sender.tag)); }
@end

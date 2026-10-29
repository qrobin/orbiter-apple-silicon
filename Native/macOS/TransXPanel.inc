// Native host for the original TransX MFD. Button actions and plots are supplied
// by Src/Plugin/TransX; the host adds readable labels and direct value entry.
@interface TransXCanvas : NSView
@property(nonatomic,weak) FlightView *flightView;
@property(nonatomic) int display;
@end
@implementation TransXCanvas
- (BOOL)acceptsFirstResponder{return YES;}
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    if(event.clickCount>=2)[self.flightView resetTransXGraph:self.display];
}
- (void)mouseDragged:(NSEvent *)event {
    [self.flightView rotateTransXGraph:self.display horizontal:event.deltaX vertical:event.deltaY];
}
- (void)keyDown:(NSEvent *)event {
    if(self.display==native::transx::Session::RouteDisplay){[super keyDown:event];return;}
    NSString *key=event.charactersIgnoringModifiers.lowercaseString;if(!key.length)return;
    unichar c=[key characterAtIndex:0];const char *keys="hfrw.,[]=-xe";int button=-1;
    for(int i=0;i<12;++i)if(c==keys[i])button=i;if(c=='+')button=8;
    if(button>=0)[self.flightView operateTransXButton:button display:self.display];else[super keyDown:event];
}
- (BOOL)isFlipped{return YES;}
- (BOOL)isOpaque{return YES;}
- (void)drawRect:(NSRect)dirty {FlightView *v=self.flightView;if(v)paintTransX(v->transxFrames[self.display],self.bounds);}
- (BOOL)isAccessibilityElement{return YES;}
- (NSString *)accessibilityLabel{return @"Original TransX MFD display";}
- (id)accessibilityValue {FlightView *v=self.flightView;if(!v)return @"Loading";NSMutableString *s=[NSMutableString new];for(auto &c:v->transxFrames[self.display].commands)if(c.kind==oapi::DrawCommand::Text)[s appendFormat:@"%@\n",transxString(c.text)];return s;}
@end
@interface TransXPanel : NSWindowController {
    __weak FlightView *flightView;
    TransXCanvas *canvas;
    NSSegmentedControl *displaySelector;
    NSPopUpButton *variables;
    NSTextField *entry,*help,*message;
    NSButton *align,*release;
    int display;
    std::string lastSelected;
    std::vector<std::string> lastVariables;
}
- (instancetype)initWithFlightView:(FlightView *)view;
- (void)refresh;
- (void)requestEntryForDisplay:(int)display;
@end
@implementation TransXPanel
- (instancetype)initWithFlightView:(FlightView *)view {
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,816,706) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:panel];if(!self)return nil;flightView=view;panel.title=@"TransX";panel.floatingPanel=YES;panel.releasedWhenClosed=NO;
    panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,816,706)];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    FlippedGliderDocument *doc=[[FlippedGliderDocument alloc] initWithFrame:NSMakeRect(0,0,800,710)];scroll.documentView=doc;panel.contentView=scroll;
    displaySelector=[NSSegmentedControl segmentedControlWithLabels:@[@"Left MFD",@"Right MFD"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeDisplay:)];
    displaySelector.frame=NSMakeRect(16,12,242,28);displaySelector.selectedSegment=0;[displaySelector setAccessibilityLabel:@"TransX display"];[doc addSubview:displaySelector];
    variables=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(278,12,360,28) pullsDown:NO];variables.target=self;variables.action=@selector(selectVariable:);[variables setAccessibilityLabel:@"TransX variable"];[doc addSubview:variables];
    canvas=[[TransXCanvas alloc] initWithFrame:NSMakeRect(144,54,512,512)];canvas.flightView=view;
    canvas.toolTip=@"Drag to rotate the orbit graph. Double-click to reset.";[doc addSubview:canvas];
    auto button=[&](NSString *name,SEL action,CGFloat x,CGFloat y,CGFloat width){auto b=[NSButton buttonWithTitle:name target:self action:action];b.frame=NSMakeRect(x,y,width,30);b.font=[NSFont systemFontOfSize:12];[doc addSubview:b];return b;};
    button(@"Reset graph",@selector(resetGraph:),650,12,134);
    NSArray *names=@[@"Help",@"Next stage",@"Previous stage",@"Change view",@"Next variable",@"Previous variable",@"Adjustment +",@"Adjustment −",@"Increase",@"Decrease",@"Execute",@"Enter value"];
    NSArray *labels=@[@"HLP",@"FWD",@"BCK",@"VW",@"VAR",@"−VR",@"ADJ",@"−AJ",@"++",@"−−",@"EXE",@"ENT"];
    for(int i=0;i<12;++i){auto b=button(names[i],@selector(pressButton:),i<6?12:668,104+(i%6)*70,120);b.tag=i;b.toolTip=[NSString stringWithFormat:@"TransX %@",labels[i]];
        if(i==8||i==9){b.continuous=YES;[b setPeriodicDelay:.35 interval:.06];}
    }
    help=[NSTextField wrappingLabelWithString:@""];help.frame=NSMakeRect(16,578,768,34);help.font=[NSFont systemFontOfSize:12];[doc addSubview:help];
    entry=[[NSTextField alloc] initWithFrame:NSMakeRect(16,618,400,24)];entry.placeholderString=@"Enter a value or a body name";entry.target=self;entry.action=@selector(applyValue:);[entry setAccessibilityLabel:@"Value for selected TransX variable"];[doc addSubview:entry];
    button(@"Apply value",@selector(applyValue:),422,614,112);
    align=button(@"Align with RCS",@selector(align:),540,614,128);release=button(@"Release",@selector(release:),674,614,110);
    message=[NSTextField wrappingLabelWithString:@"Drag the graph to rotate; double-click or use Reset graph to restore. Engine burns remain manual."];message.frame=NSMakeRect(16,660,610,38);message.font=[NSFont systemFontOfSize:11];message.textColor=NSColor.secondaryLabelColor;[doc addSubview:message];
    button(@"Return to flight",@selector(returnToFlight:),642,658,142);
    [self refresh];[panel center];return self;
}
- (void)refresh {
    FlightView *v=flightView;if(!v||!v->transxSession)return;
    auto &f=v->transxFrames[display];canvas.display=display;canvas.needsDisplay=YES;
    auto list=f.variables;std::sort(list.begin(),list.end());
    if(list!=lastVariables){[variables removeAllItems];for(auto &name:list)[variables addItemWithTitle:transxString(name)];lastVariables=list;}
    [variables selectItemWithTitle:transxString(f.selected)];help.stringValue=transxString(f.help);
    if(lastSelected!=f.selected){if(!entry.currentEditor)entry.stringValue=@"";lastSelected=f.selected;}
    VECTOR3 direction;align.enabled=v->flight.rcs>0&&v->transxSession->maneuverDirection(display,direction);release.enabled=v->flight.assist==Assist::Maneuver;
}
- (void)changeDisplay:(id)sender {display=(int)displaySelector.selectedSegment;flightView->transxMfd[display]=true;[self refresh];}
- (void)selectVariable:(id)sender {flightView->transxSession->selectVariable(display,variables.titleOfSelectedItem.UTF8String);[self updateFrame];}
- (void)pressButton:(NSButton *)sender {
    flightView->transxSession->button(display,(int)sender.tag);
    if(sender.tag==11){auto &input=native::transx::pendingInput();if(input.callback){entry.stringValue=transxString(input.initial);[self.window makeFirstResponder:entry];}}
    [self updateFrame];
}
- (void)updateFrame {flightView->transxFrames[display]=flightView->transxSession->frame(display);[self refresh];}
- (void)requestEntryForDisplay:(int)d {
    display=d;displaySelector.selectedSegment=d;[self refresh];auto &input=native::transx::pendingInput();
    if(input.callback){entry.stringValue=transxString(input.initial);[self.window makeFirstResponder:entry];}
}
- (void)applyValue:(id)sender {
    if(flightView->transxSession->enterValue(display,entry.stringValue.UTF8String))message.stringValue=@"Value applied by TransX. Engine burns remain manual.";
    else message.stringValue=@"Value not accepted. Use Increase / Decrease for choices; body names must belong to the current stage.";
    [self updateFrame];
}
- (void)align:(id)sender {
    FlightView *v=flightView;VECTOR3 direction;if(!v->transxSession->maneuverDirection(display,direction))return;
    v->flight.clearAssist();v->flight.maneuverDirection={direction.x,direction.y,direction.z};v->flight.assist=Assist::Maneuver;v->flight.glider.rcsMode=1;v->flight.warp=1;v->transxAlignDisplay=display;v->transxAlignBody=v->flight.reference;[self returnToFlight:nil];
}
- (void)release:(id)sender {if(flightView->flight.assist==Assist::Maneuver)flightView->flight.clearAssist();flightView->transxAlignDisplay=-1;[self refresh];}
- (void)resetGraph:(id)sender {[flightView resetTransXGraph:display];}
- (void)returnToFlight:(id)sender {[flightView clearInput];[flightView.window makeKeyAndOrderFront:nil];[flightView.window makeFirstResponder:flightView];}
@end

@implementation FlightView (NavigationControls)
- (void)ensureTransX {
    if(transxSession)return;transxSession=std::make_unique<native::transx::Session>(flight);transxMfd[0]=true;
    for(int d=0;d<3;++d)transxFrames[d]=transxSession->frame(d);
}
- (void)showNavigation:(id)sender {[self ensureTransX];if(!self.navigationPanel)self.navigationPanel=[[TransXPanel alloc] initWithFlightView:self];[self clearInput];[self.navigationPanel showWindow:nil];[self.navigationPanel.window makeKeyAndOrderFront:nil];}
- (void)updateNavigation {
    if(!transxSession)return;transxSession->tick();
    if(transxSession->windowSearchStatus().state==native::transx::SearchState::Running)transxSession->stepWindowSearch(12);
    if(flight.assist==Assist::Maneuver&&transxAlignDisplay>=0){VECTOR3 target;
        bool valid=flight.reference==transxAlignBody&&(transxAlignDisplay==native::transx::Session::RouteDisplay?transxSession->maneuverDirectionForStage(1,target):transxSession->maneuverDirection(transxAlignDisplay,target));
        if(valid)flight.maneuverDirection={target.x,target.y,target.z};else{flight.assist=Assist::Free;transxAlignDisplay=-1;}
    }
    double now=CACurrentMediaTime();if(now-transxRefresh>.1){for(int d=0;d<2;++d)transxFrames[d]=transxSession->frame(d);[self.navigationPanel refresh];[self.routePanel refresh];transxRefresh=now;}
}
- (void)resetNavigation {BOOL active=transxSession!=nullptr;auto previousMfd=transxMfd;burnSkip.reset();transxSession.reset();transxAlignDisplay=-1;navigationStatus=nil;if(active){[self ensureTransX];transxMfd=previousMfd;[self.navigationPanel refresh];[self.routePanel refresh];}}
- (void)operateTransXButton:(int)button display:(int)d {
    [self ensureTransX];transxMfd[d]=true;transxSession->button(d,button);transxFrames[d]=transxSession->frame(d);
    if(button==11){[self showNavigation:nil];[self.navigationPanel requestEntryForDisplay:d];}else[self.navigationPanel refresh];
}
- (void)rotateTransXGraph:(int)d horizontal:(double)dx vertical:(double)dy {
    if(!transxSession)return;transxSession->rotateGraph(d,dx,dy);transxFrames[d]=transxSession->frame(d);
    [self.navigationPanel refresh];if(cockpit)[self updateCockpitDisplays];
}
- (void)resetTransXGraph:(int)d {
    if(!transxSession)return;transxSession->resetGraph(d);transxFrames[d]=transxSession->frame(d);
    [self.navigationPanel refresh];if(cockpit)[self updateCockpitDisplays];
}
- (void)toggleTransXMFD:(NSMenuItem *)sender {auto priorMfd=transxMfd;[self ensureTransX];transxMfd=priorMfd;int d=std::clamp((int)sender.tag,0,1);transxMfd[d]=!priorMfd[d];[self updateCockpitDisplays];}
- (NSDictionary *)navigationReport {
    if(!transxSession)return @{@"active":@NO};NSMutableArray *displays=[NSMutableArray new];
    for(int d=0;d<2;++d){auto &f=transxFrames[d];[displays addObject:@{@"stage":@(f.stage),@"view":@(f.view),@"ready":@(f.ready),@"variable":transxString(f.selected),@"drawCommands":@(f.commands.size()),@"cockpit":@(transxMfd[d])}];}
    return @{@"active":@YES,@"module":@"Original Src/Plugin/TransX",@"engineControl":@"manual",@"displays":displays};
}
- (void)prepareNavigation:(BodyId)targetId {
    [self ensureTransX];
    // Development smoke-test setup through the original TransX controls.
    BodyId current=flight.reference;
    for(int i=0;i<4&&current!=BodyId::Sun;++i){transxSession->selectVariable(0,"Select Target");transxSession->enterValue(0,"Escape");transxSession->frame(0);transxSession->button(0,1);current=body(current).parent;}
    transxSession->selectVariable(0,"Select Target");transxSession->enterValue(0,body(targetId).name);
    for(int i=0;i<64;++i)transxSession->tick();transxFrames[0]=transxSession->frame(0);
}
- (void)loadTransXScenario:(NSString *)path {
    std::ifstream in(path.fileSystemRepresentation);std::string s((std::istreambuf_iterator<char>(in)),{});
    if(s.find("TYPE TransX")==std::string::npos&&s.find("TYPE Transx")==std::string::npos)return;
    [self ensureTransX];transxSession->load(path.fileSystemRepresentation);[self updateNavigation];
}
- (void)showTransXGuide:(id)sender {[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:resource(@"Docs/TransX/TransX quickstart.pdf")]];}
- (void)saveTransXScenario:(NSString *)path {
    if(!transxSession)return;
    auto tmp=std::filesystem::temp_directory_path()/std::string([NSUUID.UUID.UUIDString stringByAppendingString:@"-transx.scn"].UTF8String);transxSession->save(tmp.string());
    std::ifstream in(tmp);std::string s((std::istreambuf_iterator<char>(in)),{});std::filesystem::remove(tmp);
    std::ofstream out(path.fileSystemRepresentation,std::ios::app);out<<"\nBEGIN_MFD Left\n  TYPE TransX\n"<<s<<"END_MFD\n";out.flush();if(!out)throw std::runtime_error("Saving TransX status failed.");
}
@end

// A guided editor over the original TransX stages; all burns remain manual.
@implementation RoutePanel {
    __weak FlightView *flightView;
    native::transx::Route route;
    BOOL hasRoute,transferDirty,burnDirty;
    native::transx::SearchState lastSearchState;
    native::transx::BurnSkip::State lastSkipState;
    double lastValuesRefresh;
    NSPopUpButton *destination,*graphChoice,*steps;
    NSTextField *origin,*path,*message,*transferNote,*burnNote,*approach,*approachDetail;
    NSMutableArray<NSTextField *> *transferFields,*burnFields;
    NSMutableArray<NSNumber *> *draftStops;
    NSButton *addStop,*clearStops,*create,*findWindow,*applyTransfer,*estimate,*applyBurn,*align,*release,*skipBurn,*transferTime,*burnTime;
    TransXCanvas *canvas;
}
- (instancetype)initWithFlightView:(FlightView *)view {
    NSPanel *panel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,860,744)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskUtilityWindow
        backing:NSBackingStoreBuffered defer:NO];
    self=[super initWithWindow:panel];if(!self)return nil;
    flightView=view;draftStops=[NSMutableArray new];lastSearchState=native::transx::SearchState::Idle;lastSkipState=native::transx::BurnSkip::State::Idle;
    panel.title=@"Route Planner";panel.floatingPanel=YES;panel.releasedWhenClosed=NO;
    panel.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,860,744)];
    scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;
    FlippedGliderDocument *doc=[[FlippedGliderDocument alloc] initWithFrame:NSMakeRect(0,0,844,786)];
    scroll.documentView=doc;panel.contentView=scroll;
    auto label=[&](NSString *value,CGFloat x,CGFloat y,CGFloat width,CGFloat height=22,CGFloat size=12){
        auto f=[NSTextField wrappingLabelWithString:value];f.frame=NSMakeRect(x,y,width,height);
        f.font=[NSFont systemFontOfSize:size];[doc addSubview:f];return f;
    };
    auto heading=[&](NSString *value,CGFloat x,CGFloat y,CGFloat width){
        auto f=label(value,x,y,width,24,15);f.font=[NSFont boldSystemFontOfSize:15];return f;
    };
    auto button=[&](NSString *title,SEL action,CGFloat x,CGFloat y,CGFloat width){
        auto b=[NSButton buttonWithTitle:title target:self action:action];b.frame=NSMakeRect(x,y,width,30);
        b.font=[NSFont systemFontOfSize:12];[doc addSubview:b];return b;
    };
    heading(@"Route Planner",18,14,300);
    auto subtitle=label(@"An easier way to set up the original TransX plan. You control the engine burn.",18,42,800,22);
    subtitle.textColor=NSColor.secondaryLabelColor;
    origin=label(@"From",18,82,200);label(@"Destination",228,82,90);
    destination=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(318,77,170,28) pullsDown:NO];
    for(const auto &b:bodies()){
        [destination addItemWithTitle:transxString(b.name)];destination.lastItem.tag=(NSInteger)b.id;
    }
    [destination selectItemWithTag:(NSInteger)(view->flight.reference==BodyId::Mars?BodyId::Earth:BodyId::Mars)];
    [destination setAccessibilityLabel:@"Route destination"];[doc addSubview:destination];
    addStop=button(@"Add stop",@selector(addStop:),492,77,102);
    clearStops=button(@"Clear stops",@selector(clearStops:),596,77,108);
    create=button(@"Create route",@selector(createRoute:),706,77,120);
    path=label(@"Choose a destination to begin.",18,122,810,24,13);path.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    message=label(@"",18,150,810,36,12);message.textColor=NSColor.secondaryLabelColor;

    heading(@"Transfer",18,200,410);
    transferNote=label(@"Select a route to edit its transfer.",18,226,410,46,12);transferNote.textColor=NSColor.secondaryLabelColor;
    transferFields=[NSMutableArray new];burnFields=[NSMutableArray new];
    NSArray *labels=@[@"Ejection date (UTC)",@"Prograde (m/s)",@"Outward (m/s)",@"Plane change (m/s)"];
    for(int i=0;i<4;++i){
        CGFloat x=18+(i%2)*202,y=280+(i/2)*58;
        label(labels[i],x,y,i==0?128:190,20,11);
        auto field=[[NSTextField alloc] initWithFrame:NSMakeRect(x,y+21,188,24)];
        field.tag=i;field.delegate=(id<NSTextFieldDelegate>)self;[field setAccessibilityLabel:labels[i]];
        [doc addSubview:field];[transferFields addObject:field];
    }
    transferTime=button(@"In 1 h",@selector(setTime:),151,279,58);transferTime.frame=NSMakeRect(151,279,58,20);transferTime.tag=0;
    applyTransfer=button(@"Apply transfer",@selector(applyTransfer:),18,400,128);
    estimate=button(@"Hohmann estimate",@selector(estimate:),148,400,136);
    findWindow=button(@"Find 1st window",@selector(findWindow:),286,400,132);

    heading(@"Step burn",18,455,170);
    steps=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(195,451,221,28) pullsDown:NO];steps.target=self;steps.action=@selector(changeStep:);
    [steps setAccessibilityLabel:@"Selected maneuver step"];[doc addSubview:steps];
    burnNote=label(@"Choose a step, set its maneuver, and align using RCS. The main engines remain manual.",18,481,410,42,12);
    burnNote.textColor=NSColor.secondaryLabelColor;
    NSArray *burnLabels=@[@"Burn date (UTC)",@"Prograde (m/s)",@"Outward (m/s)",@"Plane change (m/s)"];
    for(int i=0;i<4;++i){
        CGFloat x=18+(i%2)*202,y=530+(i/2)*58;
        label(burnLabels[i],x,y,i==0?128:190,20,11);
        auto field=[[NSTextField alloc] initWithFrame:NSMakeRect(x,y+21,188,24)];
        field.tag=i+4;field.delegate=(id<NSTextFieldDelegate>)self;
        [field setAccessibilityLabel:[@"Burn " stringByAppendingString:burnLabels[i]]];
        [doc addSubview:field];[burnFields addObject:field];
    }
    burnTime=button(@"In 1 h",@selector(setTime:),151,529,58);burnTime.frame=NSMakeRect(151,529,58,20);burnTime.tag=1;
    applyBurn=button(@"Apply burn",@selector(applyBurn:),18,651,126);
    align=button(@"Align with RCS",@selector(align:),150,651,140);
    release=button(@"Release",@selector(release:),296,651,102);
    skipBurn=button(@"Skip to 1 day before burn",@selector(skipBurn:),18,690,210);
    skipBurn.toolTip=@"Fast-forward to one day before estimated ignition, then pause. Space cancels.";
    auto burnHelp=label(@"Window search matches the departure burn to the transfer. Manual edits may need further tuning.",18,729,410,48,11);
    burnHelp.textColor=NSColor.secondaryLabelColor;

    heading(@"TransX view",462,200,180);
    graphChoice=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(646,196,180,28) pullsDown:NO];
    [graphChoice addItemsWithTitles:@[@"Transfer orbit",@"Departure escape",@"Burn maneuver"]];
    graphChoice.target=self;graphChoice.action=@selector(changeGraph:);[graphChoice setAccessibilityLabel:@"Route graph view"];
    [doc addSubview:graphChoice];
    canvas=[[TransXCanvas alloc] initWithFrame:NSMakeRect(482,233,344,344)];canvas.flightView=view;
    canvas.display=native::transx::Session::RouteDisplay;canvas.toolTip=@"Drag to rotate. Double-click to reset.";[doc addSubview:canvas];
    approach=label(@"No encounter selected",462,589,364,23,13);approach.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    approachDetail=label(@"",462,615,364,67,12);approachDetail.textColor=NSColor.secondaryLabelColor;
    auto graphHelp=label(@"Drag the graph to rotate; double-click to reset.",462,682,364,20,11);graphHelp.textColor=NSColor.secondaryLabelColor;
    button(@"Open original TransX",@selector(openTransX:),462,710,184);
    button(@"Return to flight",@selector(returnToFlight:),662,710,164);
    [panel center];return self;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *field=notification.object;
    if(field.tag<4)transferDirty=YES;else burnDirty=YES;
}
- (void)fillFields:(NSArray<NSTextField *> *)fields values:(const native::transx::RouteValues &)v {
    double values[]={v.date,v.prograde,v.outward,v.plane};
    for(int i=0;i<4;++i)if(!fields[i].currentEditor)fields[i].stringValue=i==0?simulationDate(values[i]):[NSString stringWithFormat:@"%.12g",values[i]];
}
- (BOOL)readFields:(NSArray<NSTextField *> *)fields values:(native::transx::RouteValues &)v {
    double values[4];
    if(!parseSimulationDate(fields[0].stringValue,values[0]))return NO;
    for(int i=1;i<4;++i){
        NSString *s=[fields[i].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        const char *text=s.UTF8String;char *end=nullptr;values[i]=strtod(text,&end);
        if(!*text||end==text||*end||!std::isfinite(values[i]))return NO;
    }
    v={values[0],values[1],values[2],values[3]};return YES;
}
- (NSString *)routeName {
    NSMutableString *name=[NSMutableString stringWithUTF8String:body(route.origin).name];
    for(const auto &leg:route.legs)[name appendFormat:@"  →  %s",body(leg.next).name];
    return name;
}
- (void)refresh {if(self.window.isVisible)[self updateControls];}
- (void)updateControls {
    FlightView *v=flightView;if(!v||!v->transxSession)return;
    auto &session=*v->transxSession;
    origin.stringValue=[NSString stringWithFormat:@"From: %s",v->flight.centralBody().name];
    auto search=session.windowSearchStatus();BOOL searching=search.state==native::transx::SearchState::Running;
    BodyId previous=draftStops.count?(BodyId)draftStops.lastObject.integerValue:v->flight.reference;
    for(NSMenuItem *item in destination.itemArray)item.enabled=item.tag!=(NSInteger)previous;
    if(destination.selectedItem.tag==(NSInteger)previous){
        for(NSMenuItem *item in destination.itemArray)if(item.enabled){[destination selectItem:item];break;}
    }
    if(hasRoute&&!session.routeMatches(route)){
        hasRoute=NO;transferDirty=burnDirty=NO;
        message.stringValue=@"The shared TransX route changed. Select a destination to create a new route.";
    }
    if(!hasRoute){
        native::transx::Route recovered;
        if(session.currentRoute(recovered)){
            route=std::move(recovered);hasRoute=YES;transferDirty=burnDirty=NO;lastValuesRefresh=0;
            [destination selectItemWithTag:(NSInteger)route.destination];
            message.stringValue=@"This is the current shared TransX plan. Transfer and burn settings can be edited below.";
        }
    }
    int stage=session.selectedStage(),count=session.stageCount();
    bool rebuildSteps=steps.numberOfItems!=count;
    if(!rebuildSteps)for(int i=1;i<=count;++i){native::transx::StageInfo info;
        if(!session.stageInfo(i,info)||![[steps itemAtIndex:i-1].title isEqualToString:[NSString stringWithFormat:@"Step %d · %s",i,body(info.reference).name]]){rebuildSteps=true;break;}}
    if(rebuildSteps){[steps removeAllItems];for(int i=1;i<=count;++i){native::transx::StageInfo info;if(!session.stageInfo(i,info))continue;
        [steps addItemWithTitle:[NSString stringWithFormat:@"Step %d · %s",i,body(info.reference).name]];steps.lastItem.tag=i;}}
    if(stage>0)[steps selectItemWithTag:stage];steps.enabled=hasRoute&&count>0&&!searching;
    if(draftStops.count){
        NSMutableString *draft=[NSMutableString stringWithFormat:@"Draft: %s",v->flight.centralBody().name];
        for(NSNumber *stop in draftStops)[draft appendFormat:@"  →  %s",body((BodyId)stop.integerValue).name];
        [draft appendString:@"  →  choose destination"];path.stringValue=draft;
    }else path.stringValue=hasRoute?[self routeName]:@"Choose a destination to begin.";
    destination.enabled=addStop.enabled=create.enabled=!searching;clearStops.enabled=!searching&&draftStops.count>0;
    BOOL transferAvailable=hasRoute&&route.ejectStage>0&&!searching;
    for(NSTextField *field in transferFields)field.enabled=transferAvailable;
    for(NSTextField *field in burnFields)field.enabled=hasRoute&&!searching;
    applyTransfer.enabled=transferAvailable;transferTime.enabled=transferAvailable;applyBurn.enabled=hasRoute&&!searching;burnTime.enabled=hasRoute&&!searching;
    estimate.enabled=!searching&&hasRoute&&route.targetStage>0&&(route.ejectStage>0||(route.targetStage==1&&session.selectedStage()==1));
    findWindow.enabled=searching||(hasRoute&&route.targetStage>0&&!v->burnSkip.running());findWindow.title=searching?@"Cancel search":@"Find 1st window";
    if(searching)message.stringValue=[NSString stringWithFormat:@"Searching the first encounter for low fuel use… %.0f%%",search.progress*100];
    else if(search.state!=lastSearchState){
        if(search.state==native::transx::SearchState::Complete){
            session.selectStage(1);stage=1;[steps selectItemWithTag:1];transferDirty=burnDirty=NO;lastValuesRefresh=0;
            message.stringValue=[NSString stringWithFormat:@"First encounter applied · departure Δv %.0f m/s · estimated capture Δv %.0f m/s. Later steps need separate plans.",search.departureDV,search.captureDV];
        }else if(search.state==native::transx::SearchState::Failed)message.stringValue=transxString(search.message);
    }
    lastSearchState=search.state;
    auto skipState=v->burnSkip.state();
    if(skipState!=lastSkipState){
        using SkipState=native::transx::BurnSkip::State;
        switch(skipState){
            case SkipState::Running:message.stringValue=@"Skipping to one day before ignition. Engine and RCS settings are kept; Space cancels.";break;
            case SkipState::Reached:message.stringValue=@"Reached one day before estimated ignition. Flight paused.";break;
            case SkipState::Cancelled:message.stringValue=@"Skip cancelled. Flight paused.";break;
            case SkipState::PlanChanged:message.stringValue=@"Skip stopped because the selected burn changed. Flight paused.";break;
            case SkipState::FlightStopped:message.stringValue=@"Skip stopped because the flight paused or ended.";break;
            default:break;
        }
        lastSkipState=skipState;
    }
    graphChoice.enabled=hasRoute;canvas.hidden=!hasRoute;
    [graphChoice itemAtIndex:1].enabled=hasRoute&&route.legs.front().escape;
    if(![graphChoice itemAtIndex:graphChoice.indexOfSelectedItem].enabled)[graphChoice selectItemAtIndex:0];
    skipBurn.title=v->burnSkip.running()?@"Cancel skip":@"Skip to 1 day before burn";skipBurn.enabled=v->burnSkip.running();
    if(!hasRoute){transferNote.stringValue=@"Select a route to edit its transfer.";burnNote.stringValue=@"Choose a step and set its maneuver.";approach.stringValue=@"No encounter selected";approachDetail.stringValue=@"";align.enabled=NO;release.enabled=v->flight.assist==Assist::Maneuver;return;}
    if(transferAvailable){
        const auto &leg=*std::find_if(route.legs.begin(),route.legs.end(),[](const auto &item){return !item.escape;});
        transferNote.stringValue=[NSString stringWithFormat:@"Ejection velocity relative to the departing body; tune the first encounter with %s. This is not the engine burn.",body(leg.next).name];
    }else if(route.targetStage==1){
        transferNote.stringValue=@"This target is in your current system. Set the departure maneuver below to plan the transfer.";
    }else if(route.targetStage){
        transferNote.stringValue=@"This route has multiple escape stages. Adjust its advanced ejection plans in the original TransX window.";
    }else transferNote.stringValue=@"This route escapes into the parent system. Use the original TransX escape view to refine the departure.";

    double now=CACurrentMediaTime();
    if(now-lastValuesRefresh>.5){
        native::transx::RouteValues values;
        if(transferAvailable&&!transferDirty&&session.routeValues(route,false,values))[self fillFields:transferFields values:values];
        native::transx::StageInfo info;
        if(!burnDirty&&session.stageInfo(stage,info)){
            values=info.enabled?info.maneuver:native::transx::RouteValues{v->flight.mjd+v->flight.elapsed/86400.,0,0,0};
            [self fillFields:burnFields values:values];
        }
        lastValuesRefresh=now;
    }
    int graphStage=route.targetStage?route.targetStage:1,mode=route.targetStage?2:3;
    if(graphChoice.indexOfSelectedItem==1){graphStage=1;mode=3;}
    if(graphChoice.indexOfSelectedItem==2){graphStage=session.selectedStage();mode=4;}
    if(!session.routeView(graphStage,mode))session.routeView(graphStage,2);
    v->transxFrames[native::transx::Session::RouteDisplay]=session.frame(native::transx::Session::RouteDisplay);
    canvas.needsDisplay=YES;

    native::transx::Approach result;
    if(session.routeApproach(route,result)){
        const auto &leg=*std::find_if(route.legs.begin(),route.legs.end(),[](const auto &item){return !item.escape;});
        NSString *source=result.source==1?@"transfer plan":result.source==2?@"burn maneuver":@"inherited orbit";
        approach.stringValue=[NSString stringWithFormat:@"%s closest approach",body(leg.next).name];
        approachDetail.stringValue=[NSString stringWithFormat:@"%@ · %.0f km from center\n%@ UTC · relative speed %.0f m/s\nTransX estimate; tune and verify before burning.",source,result.distance/1000.,simulationDate(result.mjd),result.relativeSpeed];
    }else{
        approach.stringValue=route.targetStage?@"No encounter estimate yet":@"Escape to parent system";
        approachDetail.stringValue=route.targetStage?@"Apply transfer or burn settings to calculate an approach. The current route is not an automatic intercept.":@"There is no target encounter for this route.";
    }
    native::transx::BurnTiming timing;int selected=session.selectedStage();
    BOOL hasTiming=session.stageTiming(selected,timing);
    burnNote.stringValue=hasTiming?[NSString stringWithFormat:@"%@\nIgnition centers a full-thrust burn on the maneuver time.",burnTimingText(selected,timing)]:@"Set this step's maneuver to show the burn countdown and duration.";
    skipBurn.enabled=v->burnSkip.running()||(!searching&&hasTiming&&timing.deltaV>.1&&timing.secondsToBurn-timing.duration*.5>86400.);
    skipBurn.toolTip=hasTiming&&timing.secondsToBurn-timing.duration*.5<=86400.?@"The selected burn is already within one day.":@"Fast-forward to one day before estimated ignition, then pause. Space cancels.";
    VECTOR3 direction;align.enabled=!searching&&selected==1&&v->flight.rcs>0&&v->flight.assist!=Assist::Maneuver&&session.maneuverDirectionForStage(selected,direction);
    release.enabled=v->flight.assist==Assist::Maneuver;
}
- (void)addStop:(id)sender {
    if(!flightView)return;BodyId stop=(BodyId)destination.selectedItem.tag;
    BodyId previous=draftStops.count?(BodyId)draftStops.lastObject.integerValue:flightView->flight.reference;
    if(stop==previous){message.stringValue=@"Choose a different body for the next stop.";return;}
    [draftStops addObject:@((NSInteger)stop)];
    message.stringValue=@"Stop added. Choose another stop or the final destination, then create the route.";
    [self updateControls];
}
- (void)clearStops:(id)sender {
    [draftStops removeAllObjects];message.stringValue=@"Stops cleared. Choose a destination to create a route.";[self updateControls];
}
- (void)createRoute:(id)sender {
    FlightView *v=flightView;if(!v||!v->transxSession)return;
    native::transx::Route next;std::string error;
    std::vector<BodyId> waypoints;for(NSNumber *stop in draftStops)waypoints.push_back((BodyId)stop.integerValue);
    waypoints.push_back((BodyId)destination.selectedItem.tag);
    if(!v->transxSession->createRoute(waypoints,next,error)){
        message.stringValue=transxString(error);[self refresh];return;
    }
    if(v->burnSkip.running())[v skipToBurn:nil];
    if(v->flight.assist==Assist::Maneuver)v->flight.clearAssist();v->transxAlignDisplay=-1;
    v->transxSession->cancelWindowSearch();[draftStops removeAllObjects];
    route=std::move(next);hasRoute=YES;transferDirty=burnDirty=NO;lastValuesRefresh=0;
    [graphChoice selectItemAtIndex:0];
    message.stringValue=@"TransX stages created. Find the first window or edit each step; engine burns remain manual.";
    [self refresh];[v.navigationPanel refresh];
}
- (void)findWindow:(id)sender {
    FlightView *v=flightView;if(!v||!v->transxSession||!hasRoute)return;
    if(v->transxSession->windowSearchStatus().state==native::transx::SearchState::Running){
        v->transxSession->cancelWindowSearch();message.stringValue=@"Search cancelled; the existing TransX plan was kept.";
    }else{
        std::string error;
        if(!v->transxSession->beginWindowSearch(route,error)){message.stringValue=transxString(error);return;}
        if(v->flight.assist==Assist::Maneuver&&v->transxAlignDisplay==native::transx::Session::RouteDisplay){
            v->flight.clearAssist();v->transxAlignDisplay=-1;
        }
    }
    [self updateControls];
}
- (void)applyValues:(BOOL)departure {
    FlightView *v=flightView;if(!v||!hasRoute)return;
    native::transx::RouteValues values;
    if(![self readFields:departure?burnFields:transferFields values:values]){
        message.stringValue=@"Enter a UTC date as YYYY-MM-DD HH:MM:SS and a finite number in each velocity field.";return;
    }
    bool accepted=departure?v->transxSession->setStageManeuver(v->transxSession->selectedStage(),values):v->transxSession->setRouteValues(route,false,values);
    if(!accepted){
        message.stringValue=@"TransX did not accept these values. Check the date and velocity magnitudes, or recreate the route.";return;
    }
    if(departure&&v->burnSkip.running())[v skipToBurn:nil];
    if(departure)burnDirty=NO;else transferDirty=NO;
    lastValuesRefresh=0;message.stringValue=departure?@"Step maneuver applied. Align with RCS when it is current; fire the engine manually.":@"Transfer plan applied. Check the closest approach and tune the values.";
    [self refresh];[v.navigationPanel refresh];
}
- (void)applyTransfer:(id)sender {[self applyValues:NO];}
- (void)applyBurn:(id)sender {[self applyValues:YES];}
- (void)setTime:(NSButton *)sender {
    if(!flightView||!hasRoute)return;
    double mjd=flightView->flight.mjd+flightView->flight.elapsed/86400.+1./24.;
    if(sender.tag==0){transferFields[0].stringValue=simulationDate(mjd);transferDirty=YES;}
    else{burnFields[0].stringValue=simulationDate(mjd);burnDirty=YES;}
}
- (void)estimate:(id)sender {
    FlightView *v=flightView;double dv=0;if(!v||!hasRoute||!v->transxSession->routeHohmann(route,dv)){
        message.stringValue=@"The current TransX stage cannot provide a Hohmann estimate.";return;
    }
    BOOL transfer=route.ejectStage>0;NSArray<NSTextField *> *fields=transfer?transferFields:burnFields;
    fields[1].stringValue=[NSString stringWithFormat:@"%.8g",dv];if(transfer)transferDirty=YES;else burnDirty=YES;
    message.stringValue=@"Hohmann is a rough prograde starting estimate, not a solved encounter. Adjust the other values, then apply.";
}
- (void)changeGraph:(id)sender {[self refresh];}
- (void)changeStep:(id)sender {
    FlightView *v=flightView;if(!v||!v->transxSession)return;
    int requested=(int)steps.selectedItem.tag;
    if(v->burnSkip.running()){[v skipToBurn:nil];message.stringValue=@"Skip cancelled because the selected step changed.";}
    if(v->flight.assist==Assist::Maneuver&&v->transxAlignDisplay==native::transx::Session::RouteDisplay){v->flight.clearAssist();v->transxAlignDisplay=-1;}
    v->transxSession->selectStage(requested);burnDirty=NO;lastValuesRefresh=0;
    [self refresh];v.hud.needsDisplay=YES;
}
- (void)align:(id)sender {
    FlightView *v=flightView;if(!v||!hasRoute||!v->transxSession->routeMatches(route))return;
    [v selectNavButton:6];[self returnToFlight:nil];
}
- (void)release:(id)sender {
    if(flightView->flight.assist==Assist::Maneuver)flightView->flight.clearAssist();
    flightView->transxAlignDisplay=-1;[self refresh];
}
- (void)skipBurn:(id)sender {
    if(!flightView)return;[flightView skipToBurn:sender];
    message.stringValue=flightView->status?:@"";[self updateControls];
}
- (void)openTransX:(id)sender {[flightView showNavigation:nil];}
- (void)returnToFlight:(id)sender {[flightView clearInput];[flightView.window makeKeyAndOrderFront:nil];[flightView.window makeFirstResponder:flightView];}
@end

@implementation FlightView (RouteControls)
- (void)showRoutePlanner:(id)sender {
    [self ensureTransX];if(!self.routePanel)self.routePanel=[[RoutePanel alloc] initWithFlightView:self];
    [self clearInput];[self.routePanel showWindow:nil];[self.routePanel.window makeKeyAndOrderFront:nil];[self.routePanel refresh];
}
@end

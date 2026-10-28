// Original Delta-glider main panel atlas and MFD geometry, presented as a 2D view.
@implementation Panel2DView {
    NSImage *background;
    NSMutableArray<NSImage *> *displays;
    int activeAction;
}
- (instancetype)initWithFrame:(NSRect)frame {
    self=[super initWithFrame:frame];if(!self)return nil;
    auto atlas=loadDDS(resource(@"Textures/DG/dg_panel.dds").fileSystemRepresentation);
    if(atlas.width<1280||atlas.height<1024)throw std::runtime_error("Invalid Delta-glider 2D panel texture.");
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:1280 pixelsHigh:572 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:1280*4 bitsPerPixel:32];
    for(int y=0;y<572;++y)for(int x=0;x<1280;++x){
        const auto *source=atlas.rgba.data()+(size_t(y+452)*atlas.width+x)*4;
        auto *dest=rep.bitmapData+(size_t(y)*1280+x)*4;
        for(int c=0;c<3;++c)dest[c]=uint8_t((unsigned(source[c])*source[3]+127)/255);dest[3]=source[3];
    }
    background=[[NSImage alloc] initWithSize:NSMakeSize(1280,572)];[background addRepresentation:rep];
    displays=[NSMutableArray arrayWithObjects:[NSImage new],[NSImage new],nil];activeAction=-1;
    self.toolTip=@"Original Delta-glider panel. Drag a TransX display to rotate its graph; double-click to reset.";
    return self;
}
- (BOOL)isFlipped {return YES;}
- (BOOL)isOpaque {return NO;}
- (BOOL)isAccessibilityElement {return YES;}
- (NSString *)accessibilityLabel {return @"Delta-glider 2D instrument panel";}
- (NSRect)panelRect {
    double scale=std::min(self.bounds.size.width/1280.,self.bounds.size.height*.86/572.);
    return NSMakeRect((self.bounds.size.width-1280*scale)*.5,self.bounds.size.height-572*scale,1280*scale,572*scale);
}
- (NSView *)hitTest:(NSPoint)point {
    NSPoint local=[self convertPoint:point fromView:self.superview];
    return !self.hidden&&NSPointInRect(local,[self panelRect])?[super hitTest:point]:nil;
}
- (void)setDisplayImage:(NSBitmapImageRep *)rep index:(int)display {
    if(display<0||display>=2||!rep)return;
    NSImage *image=[[NSImage alloc] initWithSize:NSMakeSize(512,512)];[image addRepresentation:rep];displays[display]=image;
    if(!self.hidden)self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirty {
    FlightView *v=self.flightView;if(!v)return;
    NSRect rect=[self panelRect];double scale=rect.size.width/1280.;
    [NSGraphicsContext saveGraphicsState];NSAffineTransform *t=[NSAffineTransform transform];
    [t translateXBy:rect.origin.x yBy:rect.origin.y];[t scaleBy:scale];[t concat];
    // The original panel atlas is transparent over its separately drawn instruments.
    // Draw live attitude and heading beneath those cutouts, as Orbiter does.
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(533,42,216,216)] addClip];
    NSAffineTransform *horizon=[NSAffineTransform transform];[horizon translateXBy:641 yBy:150];
    [horizon rotateByDegrees:-Deg(v->flight.bank())];[horizon translateXBy:0 yBy:Deg(v->flight.pitch())*2];[horizon concat];
    [[NSColor colorWithRed:.18 green:.39 blue:.58 alpha:1] setFill];NSRectFill(NSMakeRect(-400,-400,800,400));
    [[NSColor colorWithRed:.35 green:.25 blue:.17 alpha:1] setFill];NSRectFill(NSMakeRect(-400,0,800,400));
    [[NSColor colorWithWhite:.9 alpha:1] setStroke];NSBezierPath *horizonLine=[NSBezierPath bezierPath];horizonLine.lineWidth=2;
    [horizonLine moveToPoint:NSMakePoint(-180,0)];[horizonLine lineToPoint:NSMakePoint(180,0)];[horizonLine stroke];
    [NSGraphicsContext restoreGraphicsState];
    [[NSColor colorWithRed:.025 green:.035 blue:.03 alpha:1] setFill];NSRectFill(NSMakeRect(563,395,156,154));
    NSString *heading=[NSString stringWithFormat:@"%03.0f°",Deg(v->flight.heading())];
    [heading drawAtPoint:NSMakePoint(616,450) withAttributes:@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightMedium],NSForegroundColorAttributeName:[NSColor colorWithRed:.6 green:1 blue:.65 alpha:1]}];
    [background drawInRect:NSMakeRect(0,0,1280,572) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    for(int d=0;d<2;++d){
        [displays[d] drawInRect:NSMakeRect(d?778:216,63,288,288) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        if(v->transxMfd[d]){
            NSString *labels[]={@"HLP",@"FWD",@"BCK",@"VW",@"VAR",@"−VR",@"ADJ",@"−AJ",@"++",@"−−",@"EXE",@"ENT"};
            for(int side=0;side<2;++side)for(int row=0;row<6;++row){
                NSString *label=labels[side*6+row];CGFloat left=(d?736:173)+side*348;
                NSDictionary *attr=@{NSFontAttributeName:[NSFont boldSystemFontOfSize:9],NSForegroundColorAttributeName:[NSColor colorWithRed:.55 green:1 blue:.6 alpha:1]};
                NSSize size=[label sizeWithAttributes:attr];[label drawAtPoint:NSMakePoint(left+(25-size.width)*.5,102+row*41) withAttributes:attr];
            }
        }
    }
    // Slider markers reflect the native flight state instead of static atlas art.
    auto marker=[](CGFloat x,CGFloat y,CGFloat w){[[NSColor colorWithCalibratedWhite:.72 alpha:1] setFill];NSRectFill(NSMakeRect(x,y-3,w,6));};
    double mainY=v->flight.glider.retro>0?256+v->flight.glider.retro*32:131+(1-v->flight.throttle)*108;
    marker(8,mainY,15);marker(35,mainY,15);marker(20,313+(1-v->flight.glider.hover)*116,15);
    [NSGraphicsContext restoreGraphicsState];
}
- (NSPoint)panelPoint:(NSEvent *)event {
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];NSRect r=[self panelRect];double scale=r.size.width/1280.;
    return NSMakePoint((p.x-r.origin.x)/scale,(p.y-r.origin.y)/scale);
}
- (void)applyThrottleAt:(NSPoint)p {
    Flight &f=self.flightView->flight;
    if(activeAction==300){double y=std::clamp(p.y-131.,0.,157.);f.throttle=y<=108?1-y/108:0;f.glider.retro=y>=125?(y-125)/32:0;}
    else if(activeAction==301)f.setHoverThrottle(1-std::clamp((p.y-313.)/116.,0.,1.));
    self.needsDisplay=YES;
}
- (void)mouseDown:(NSEvent *)event {
    FlightView *v=self.flightView;if(!v)return;[self.window makeFirstResponder:v];
    NSPoint p=[self panelPoint:event];auto hit=pickPanel2D(p.x,p.y);activeAction=hit.action;
    if(activeAction>=100&&activeAction<124){int id=activeAction-100;[v operateTransXButton:id%12 display:id/12];return;}
    if(activeAction>=200&&activeAction<202){int d=activeAction-200;
        if(!v->transxSession||!v->transxMfd[d])activeAction=-1;else if(event.clickCount>=2){[v resetTransXGraph:d];activeAction=-1;}return;
    }
    if(activeAction==300||activeAction==301){[self applyThrottleAt:p];return;}
    auto &g=v->flight.glider;
    if(activeAction==302){bool closed=g.part(Part::Gear).target<.5;if((closed&&p.y-373<151)||(!closed&&p.y-373>46))g.command(Part::Gear,closed?1:0);}
    else if(activeAction==303){bool closed=g.part(Part::Nose).target<.5;if((closed&&p.y-359<58)||(!closed&&p.y-359>36))g.command(Part::Nose,closed?1:0);}
    else if(activeAction==304)g.command(Part::Airbrake,p.y-299>30?1:0);
    else if(activeAction==305)g.rcsMode=std::clamp(g.rcsMode+(p.x<120?-1:1),0,2);
    else if(activeAction==306)g.trim=std::clamp(g.trim+(p.y<329?.1:-.1),-1.,1.);
    else if(activeAction==307)g.hoverControl.attitudeMode=std::clamp(g.hoverControl.attitudeMode+(p.x<376?-1:1),0,2);
    else if(activeAction==308)[v toggleHoverHold:nil];
    self.needsDisplay=YES;
}
- (void)mouseDragged:(NSEvent *)event {
    if(activeAction>=200&&activeAction<202)[self.flightView rotateTransXGraph:activeAction-200 horizontal:event.deltaX vertical:event.deltaY];
    else if(activeAction==300||activeAction==301)[self applyThrottleAt:[self panelPoint:event]];
}
- (void)mouseUp:(NSEvent *)event {activeAction=-1;}
- (void)cancelInteraction {activeAction=-1;}
- (void)scrollWheel:(NSEvent *)event {[self.flightView scrollWheel:event];}
- (void)tick {
    if(activeAction<100||activeAction>=124||!self.flightView->transxSession)return;
    int id=activeAction-100,button=id%12;
    if(button==8||button==9)self.flightView->transxSession->button(id/12,button,true);
}
@end

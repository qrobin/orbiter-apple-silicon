#import "TransXDrawing.h"
NSString *transxString(const std::string &s){
    NSString *text=[[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return text?:[[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSWindowsCP1252StringEncoding]?:@"";
}
void paintTransX(const native::transx::Frame &frame,NSRect rect){
    [NSGraphicsContext saveGraphicsState];
    auto *ctx=NSGraphicsContext.currentContext;
    // Original Sketchpad uses a downward Y axis, independently of the host.
    NSAffineTransform *t=[NSAffineTransform transform];
    if(ctx.isFlipped){[t translateXBy:rect.origin.x yBy:rect.origin.y];[t scaleXBy:rect.size.width/512 yBy:rect.size.height/512];}
    else{[t translateXBy:rect.origin.x yBy:rect.origin.y+rect.size.height];[t scaleXBy:rect.size.width/512 yBy:-rect.size.height/512];}
    [t concat];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:ctx.CGContext flipped:YES];
    [[NSColor blackColor] setFill];NSRectFill(NSMakeRect(0,0,512,512));NSRectClip(NSMakeRect(0,0,512,512));
    auto color=[](DWORD c){return [NSColor colorWithRed:(c&255)/255. green:((c>>8)&255)/255. blue:((c>>16)&255)/255. alpha:1];};
    NSFont *font=[NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    for(const auto &c:frame.commands){
        if(c.kind==oapi::DrawCommand::Text){
            [transxString(c.text) drawAtPoint:NSMakePoint(c.x,c.y) withAttributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color(c.color)}];continue;
        }
        NSBezierPath *p=[NSBezierPath bezierPath];p.lineWidth=std::max(1,c.width);
        if(c.dashed){CGFloat d[]={4,3};[p setLineDash:d count:2 phase:0];}
        if(c.kind==oapi::DrawCommand::Line){[p moveToPoint:NSMakePoint(c.x,c.y)];[p lineToPoint:NSMakePoint(c.x2,c.y2)];}
        else if(c.kind==oapi::DrawCommand::Polyline){if(c.points.empty())continue;[p moveToPoint:NSMakePoint(c.points[0].x,c.points[0].y)];for(size_t i=1;i<c.points.size();++i)[p lineToPoint:NSMakePoint(c.points[i].x,c.points[i].y)];}
        else {NSRect b=NSMakeRect(std::min(c.x,c.x2),std::min(c.y,c.y2),abs(c.x2-c.x),abs(c.y2-c.y));
            if(c.kind==oapi::DrawCommand::Ellipse)[p appendBezierPathWithOvalInRect:b];else[p appendBezierPathWithRect:b];
            if(c.filled){[color(c.fill) setFill];[p fill];}
        }
        [color(c.color) setStroke];[p stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
}

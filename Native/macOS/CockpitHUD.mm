#import "CockpitHUD.h"
#include <algorithm>
using namespace native;
NSBitmapImageRep *makeCockpitHud(const Flight &flight){
    constexpr int size=512;
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:size*4 bitsPerPixel:32];
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [[NSColor clearColor] setFill];NSRectFillUsingOperation(NSMakeRect(0,0,size,size),NSCompositingOperationCopy);
    NSColor *white=NSColor.whiteColor;[white setStroke];NSBezierPath *path=[NSBezierPath bezierPath];path.lineWidth=3;
    [path moveToPoint:NSMakePoint(182,275)];[path lineToPoint:NSMakePoint(235,275)];
    [path moveToPoint:NSMakePoint(277,275)];[path lineToPoint:NSMakePoint(330,275)];
    [path moveToPoint:NSMakePoint(256,257)];[path lineToPoint:NSMakePoint(256,293)];[path stroke];
    auto centered=[&](NSString *value,CGFloat y,CGFloat pointSize){
        NSDictionary *attributes=@{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:pointSize weight:NSFontWeightMedium],NSForegroundColorAttributeName:white};
        NSSize extent=[value sizeWithAttributes:attributes];[value drawAtPoint:NSMakePoint((size-extent.width)*.5,y) withAttributes:attributes];
    };
    if(flight.hud.mode==1){
        centered(@"ORBIT",345,23);
        centered([NSString stringWithFormat:@"ALT %.1f km",flight.altitude()/1000],185,24);
        centered([NSString stringWithFormat:@"VEL %.0f m/s",flight.velocity.length()],146,24);
    }else if(flight.hud.mode==2){
        centered(@"SURFACE",345,23);
        centered([NSString stringWithFormat:@"ALT %.0f m   GS %.0f m/s",flight.altitude(),flight.groundSpeed],185,22);
        centered([NSString stringWithFormat:@"V/S %+.1f m/s   HDG %03.0f°",flight.surfaceVerticalSpeed(),Deg(flight.heading())],146,22);
    }else{
        centered(@"DOCKING",345,23);centered(@"NO TARGET",170,24);
    }
    [NSGraphicsContext restoreGraphicsState];return rep;
}

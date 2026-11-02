#import "CockpitHUD.h"
#include <algorithm>
#include <cmath>
using namespace native;

// Coordinates and geometry follow the virtual-cockpit sketchpad HUD in
// Src/Orbiter/hud.cpp and the Delta-glider's registered HUD and eye positions.
namespace {
constexpr double size=512, cx=256, cy=256+(1.467-1.462)*size/.15;
constexpr double projection=(7.09-6.782)*size/.15, marker=26, ladderWidth=120;
struct Drawing {
    NSColor *ink=NSColor.whiteColor;
    void line(double x1,double y1,double x2,double y2) const {
        NSBezierPath *p=[NSBezierPath bezierPath];p.lineWidth=2;
        [p moveToPoint:NSMakePoint(x1,y1)];[p lineToPoint:NSMakePoint(x2,y2)];[p stroke];
    }
    void label(NSString *s,double x,double y,double fontSize=19,bool centered=false) const {
        NSDictionary *a=@{NSFontAttributeName:[NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightRegular],NSForegroundColorAttributeName:ink};
        NSSize extent=[s sizeWithAttributes:a];[s drawAtPoint:NSMakePoint(x-(centered?extent.width*.5:0),y) withAttributes:a];
    }
    void box(double x,double y,double w,double h) const {NSBezierPath *p=[NSBezierPath bezierPathWithRect:NSMakeRect(x,y,w,h)];p.lineWidth=2;[p stroke];}
    void circle(double x,double y,double r) const {NSBezierPath *p=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x-r,y-r,2*r,2*r)];p.lineWidth=2;[p stroke];}
    bool project(const Flight &f,const Vector &v,NSPoint &p) const {
        double z=dotp(v,f.forward);if(z<=1e-9)return false;
        p=NSMakePoint(cx+projection*dotp(v,f.right)/z,cy+projection*dotp(v,f.up)/z);
        return p.x>=0&&p.x<size&&p.y>=0&&p.y<size;
    }
    void direction(const Flight &f,const Vector &v,bool ring,NSString *name=nil,NSString *value=nil) const {
        if(v.length2()<1e-16)return;
        NSPoint p;bool visible=project(f,v,p),negative=false;
        if(!visible&&ring){visible=project(f,-v,p);negative=visible;}
        if(visible){
            if(ring&&!negative)circle(p.x,p.y,marker);
            if(!ring)box(p.x-marker,p.y-marker,2*marker,2*marker);
            else {line(p.x-marker,p.y,p.x+marker,p.y);line(p.x,p.y-marker,p.x,p.y+marker);}
        } else {
            double x=dotp(v,f.right),y=dotp(v,f.up),length=hypot(x,y);
            if(length<1e-9)return;
            x/=length;y/=length;double r=marker*.6;
            line(cx+10*r*x,cy+10*r*y,cx+7*r*x-r*y,cy+7*r*y+r*x);
            line(cx+10*r*x,cy+10*r*y,cx+7*r*x+r*y,cy+7*r*y-r*x);
            line(cx+7*r*x-r*y,cy+7*r*y+r*x,cx+7*r*x+r*y,cy+7*r*y-r*x);
            p=NSMakePoint(cx+8.5*r*x,cy+8.5*r*y);
        }
        if(name)label(negative?[@"-" stringByAppendingString:name]:name,p.x,p.y+marker+4,15,true);
        if(value)label(value,p.x,p.y-marker-20,15,true);
    }
    void center() const {
        constexpr double d=size/32;
        line(cx-2*d,cy,cx-d,cy);line(cx+d,cy,cx+2*d,cy);
        line(cx-d,cy-d,cx,cy);line(cx,cy,cx+d,cy-d);
    }
    void readout(double x,NSString *value,NSString *unit,bool left) const {
        box(x,424,105,25);label(value,x+52.5,426,20,true);
        label(unit,left?x-40:x+109,430,13);
    }
    void ladder(double pitch,double bank) const {
        // Orbiter spaces 10-degree bars by tan(10 deg), with broken negative bars.
        double degrees=Deg(pitch),c=cos(bank),s=sin(bank),step=projection*tan(Rad(10));
        for(int n=-18;n<=18;++n){
            double offset=(degrees-n*10)*step/10.;if(fabs(offset)>250)continue;
            int labelValue=n;bool reverse=false;if(labelValue>9){labelValue=18-labelValue;reverse=true;}else if(labelValue< -9){labelValue=-18-labelValue;reverse=true;}
            double width=ladderWidth*(labelValue==0?1.4:1.0);
            auto point=[&](double along,double vertical){return NSMakePoint(cx+along*c-vertical*s,cy-along*s-vertical*c);};
            auto segment=[&](double a,double b,double h1,double h2){NSPoint p=point(a,offset+h1),q=point(b,offset+h2);line(p.x,p.y,q.x,q.y);};
            if(abs(labelValue)!=9){
                double inner=labelValue<0?.75:.25;
                segment(-width,-width*inner,0,0);segment(width*inner,width,0,0);
                if(labelValue<0){segment(-width*.5,-width*.25,0,0);segment(width*.25,width*.5,0,0);}
                if(labelValue){double hook=(labelValue<0?-1:1)*(reverse?-1:1)*width*.1;segment(-width,-width,0,hook);segment(width,width,0,hook);}
            }else {segment(-width*.5,-width*.25,0,0);segment(width*.25,width*.5,0,0);}
            NSPoint mid=point(0,offset);label([NSString stringWithFormat:@"%+d0",labelValue],mid.x,mid.y-9,16,true);
        }
    }
    void heading(double heading) const {
        line(cx-5,502,cx,497);line(cx,497,cx+6,503);
        double deg=Deg(heading);int base=(int)floor(deg/2);
        for(int tick=base-8;tick<=base+8;++tick){double x=cx+(tick*2-deg)*8;if(x<cx-size/5||x>cx+size/5)continue;
            int wrapped=((tick*2)%360+360)%360;bool major=wrapped%10==0;
            line(x,502,x,major?492:497);if(major)label([NSString stringWithFormat:@"%03d",wrapped],x,476,13,true);
        }
    }
    void azimuth(double phi,double bank) const {
        double deg=Deg(phi),step=projection*tan(Rad(2)),c=cos(bank),s=sin(bank);
        int base=(int)floor(deg/2);
        for(int tick=base-8;tick<=base+8;++tick){double d=(tick*2-deg)*step/2;if(fabs(d)>175)continue;
            int value=((tick*2)%360+360)%360;double x=cx+d*c,y=cy-d*s,mark=value%10?5.6:11.3;
            line(x-mark*s,y-mark*c,x+mark*s,y+mark*c);
            if(value%10==0)label([NSString stringWithFormat:@"%d",value],x+2*mark*s,y+2*mark*c,13,true);
        }
    }
};
NSString *number(double v) {
    if(!std::isfinite(v)||fabs(v)>=1e12)return @"----";
    if(fabs(v)>=1e9)return [NSString stringWithFormat:@"%.2fG",v/1e9];
    if(fabs(v)>=1e6)return [NSString stringWithFormat:@"%.2fM",v/1e6];
    if(fabs(v)>=1e4)return [NSString stringWithFormat:@"%.1fk",v/1e3];
    return [NSString stringWithFormat:fabs(v)<100?@"%.1f":@"%.0f",v];
}
}
NSBitmapImageRep *makeCockpitHud(const Flight &f){
    NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:size*4 bitsPerPixel:32];
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [[NSColor clearColor] setFill];NSRectFillUsingOperation(NSMakeRect(0,0,size,size),NSCompositingOperationCopy);
    Drawing d;[d.ink setStroke];d.center();
    NSString *body=[NSString stringWithUTF8String:f.centralBody().name];
    if(f.hud.mode==1){
        d.label([NSString stringWithFormat:@"ORBIT [%@]",body],10,487,19);
        d.readout(60,number(f.velocity.length()),@"OS",true);d.readout(347,number(f.position.length()),@"RAD",false);
        d.direction(f,f.velocity,true,@"PG");
        if(f.position.length2()>1e-12&&f.velocity.length2()>1e-12){
            Vector p=f.position.unit(),v=f.velocity.unit();
            Vector pr(dotp(p,f.right),dotp(p,f.up),dotp(p,f.forward));
            Vector vr(dotp(v,f.right),dotp(v,f.up),dotp(v,f.forward));
            Vector normal=-crossp(pr,vr);double length=normal.length();
            if(length>1e-9){double a=normal.x,b=normal.y,c=normal.z;
                double pitch=asin(std::clamp(c/length,-1.,1.)),bank=atan2(a,b);d.ladder(pitch,bank);
                Vector z(-c*a,-c*b,a*a+b*b);if(z.length2()>1e-12){z=z.unit();double phi=acos(std::clamp(dotp(vr,z),-1.,1.));if(dotp(z,crossp(vr,normal))>0)phi=Pi2-phi;d.azimuth(phi,bank);}
            }
        }
    }else if(f.hud.mode==2){
        d.label(@"SRFCE",10,487,19);
        bool radar=f.groundAltitude()<10000,air=bodyAtmosphere(f.reference,f.altitude()).p>1e-3;
        Vector ground=f.velocity-crossp(f.centralBody().spin(),f.position);
        d.readout(60,number(air?f.airRelativeVelocity().length():ground.length()),air?@"TAS":@"GS",true);
        d.readout(347,number(radar?f.groundAltitude():f.altitude()),radar?@"R ALT":@"ALT",false);
        if(ground.length()>1)d.direction(f,ground,true);
        d.heading(f.heading());d.ladder(f.pitch(),f.bank());
    }else{
        d.label(@"DOCK",10,487,19);
        if(f.reference==BodyId::Earth){
            ISSState station=issState(f.issOrbit,f.mjd+f.elapsed/86400.);auto t=issDockingTelemetry(f,station,f.issTargetPort);
            d.label([NSString stringWithFormat:@"[ISS PORT %d]",f.issTargetPort+1],110,487,19);
            d.direction(f,f.velocity-station.velocity,true,@"V[ISS]",number((f.velocity-station.velocity).length()));
            d.direction(f,station.position-f.position,false,@"ISS",number((station.position-f.position).length()));
            // Original approach gates: 14 x 10 m, every 50 m from the port.
            Vector eye=f.position+f.up*1.467+f.forward*6.782,axis=-t.direction,xdir=crossp(axis,t.up);
            for(int i=1;i<=10;++i){Vector center=t.target-eye-axis*(50.*i);NSPoint p[4];bool visible=true;
                for(int j=0;j<4;++j){Vector corner=center+t.up*(j<=1?5.:-5.)+xdir*((j==0||j==3)?7.:-7.);if(!d.project(f,corner,p[j])){visible=false;break;}}
                if(visible)for(int j=0;j<4;++j)d.line(p[j].x,p[j].y,p[(j+1)%4].x,p[(j+1)%4].y);
            }
        }else d.label(@"NO TARGET",10,460,17);
    }
    [NSGraphicsContext restoreGraphicsState];return rep;
}

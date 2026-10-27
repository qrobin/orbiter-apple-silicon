#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include "Flight.h"
#include "Mesh.h"
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
    float n=.2f,far=100000; simd_float4x4 m={};
    m.columns[0]={1/(aspect*t),0,0,0}; m.columns[1]={0,1/t,0,0};
    m.columns[2]={0,0,far/(n-far),-1}; m.columns[3]={0,0,n*far/(n-far),0}; return m;
}
struct FrameUniforms { simd_float4x4 projection; simd_float4 right,up,forward,position,sun,screen; };
struct ObjectUniforms { simd_float4x4 model; simd_float4 color,options; };
struct GpuGroup { id<MTLBuffer> vertices,indices; NSUInteger count; size_t material,texture; };
@class FlightView;
@interface FlightHUD : NSView
@property(nonatomic,weak) FlightView *flightView;
- (void)paint:(NSRect)bounds;
@end
@interface FlightView : MTKView<MTKViewDelegate> {
@public
    Flight flight;
    std::array<bool,256> held;
    double yaw,pitch,distance,fps,cpuMs,gpuMs;
    bool helpVisible,cockpit,orbitVisible;
    NSString *status;
@private
    id<MTLCommandQueue> queue;
    id<MTLRenderPipelineState> meshPipeline,skyPipeline;
    id<MTLDepthStencilState> depthState,skyDepth;
    std::vector<GpuGroup> groups;
    std::vector<Material> materials;
    NSMutableArray<id<MTLTexture>> *textures;
    id<MTLTexture> earthTexture,whiteTexture;
    CFTimeInterval previous,begin,lastHud;
    NSUInteger frameCount,smokeFrames;
    double cpuSum,gpuSum;
    std::vector<double> intervals;
    NSString *capturePath,*reportPath;
    dispatch_semaphore_t inflight;
}
@property(nonatomic,strong) FlightHUD *hud;
- (void)resetFlight:(id)sender;
- (void)openScenario:(id)sender;
- (void)saveScenario:(id)sender;
- (void)pauseFlight:(id)sender;
- (void)toggleHelp:(id)sender;
- (void)clearInput;
@end
@implementation FlightHUD
- (BOOL)isOpaque { return NO; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel { return @"Flight instruments"; }
- (id)accessibilityValue {
    FlightView *v=self.flightView; if(!v) return @"Loading";
    return [NSString stringWithFormat:@"%@, altitude %.2f km, speed %.2f m/s, throttle %.0f percent, fuel %.1f kg, time acceleration %.0f, controls %@",
        v->flight.paused?@"Paused":@"Flying",v->flight.altitude()/1000,v->flight.velocity.length(),v->flight.throttle*100,v->flight.fuel,v->flight.warp,v->helpVisible?@"visible":@"hidden"];
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
    Flight &f=v->flight; CGFloat w=b.size.width,h=b.size.height;
    NSColor *ink=[NSColor colorWithRed:.76 green:.94 blue:.79 alpha:1];
    NSColor *muted=[NSColor colorWithRed:.60 green:.72 blue:.66 alpha:1];
    NSColor *white=[NSColor colorWithWhite:.95 alpha:1];
    NSColor *panel=[NSColor colorWithRed:.025 green:.045 blue:.04 alpha:.91];
    NSString *mode=@"MANUAL";
    switch(f.assist) { case Assist::Prograde: mode=@"PROGRADE";break; case Assist::Retrograde:mode=@"RETROGRADE";break;case Assist::KillRotation:mode=@"KILL ROTATION";break;default:break; }
    text(@"Orbiter",26,h-44,22,white);
    text([NSString stringWithFormat:@"Delta-glider  /  %s",f.name.c_str()],26,h-66,12,muted);
    text([NSString stringWithFormat:@"%@   ·   %.0f×   ·   T+ %.0f s",f.paused?@"PAUSED":@"FLIGHT",f.warp,f.elapsed],w-320,h-37,12,ink,YES);
    text([NSString stringWithFormat:@"Metal  ·  ARM64  ·  %.0f fps",v->fps],w-320,h-57,11,muted,YES);
    if(v->status.length) text(v->status,26,h-93,12,ink);
    if(f.impacted) {
        text(@"Surface contact — press R to restart",w*.5-170,h*.63,18,[NSColor orangeColor]);
    }
    // Restrained flight symbology, leaving the view unobstructed.
    CGFloat cx=w*.5,cy=h*.5;
    line(cx-22,cy,cx-7,cy,ink); line(cx+7,cy,cx+22,cy,ink); line(cx,cy-7,cx,cy+7,ink);
    text(v->cockpit?@"FORWARD VIEW":@"EXTERNAL VIEW",cx-53,h-34,10,muted);
    CGFloat left=26,bottom=35,pw=252,ph=194;
    [panel setFill]; NSRectFill(NSMakeRect(left,bottom,pw,ph));
    text(@"ORBIT  /  EARTH",left+14,bottom+ph-27,11,ink);
    Elements orbit=f.orbit();
    text([NSString stringWithFormat:@"Altitude       %9.2f km",f.altitude()/1000],left+14,bottom+ph-53,12,white,YES);
    text([NSString stringWithFormat:@"Speed          %9.2f m/s",f.velocity.length()],left+14,bottom+ph-74,12,white,YES);
    text([NSString stringWithFormat:@"Vertical       %+9.2f m/s",f.radialSpeed()],left+14,bottom+ph-95,12,white,YES);
    text(orbit.e<1?[NSString stringWithFormat:@"Apoapsis       %9.2f km",(orbit.ApDist()-EarthRadius)/1000]:@"Apoapsis          ESCAPE",left+14,bottom+ph-123,12,ink,YES);
    text([NSString stringWithFormat:@"Periapsis      %9.2f km",(orbit.PeDist()-EarthRadius)/1000],left+14,bottom+ph-144,12,ink,YES);
    text([NSString stringWithFormat:@"Eccentricity   %9.5f",orbit.e],left+14,bottom+ph-165,12,muted,YES);
    CGFloat rx=w-278;
    [panel setFill]; NSRectFill(NSMakeRect(rx,bottom,pw,ph));
    text(@"PROPULSION",rx+14,bottom+ph-27,11,ink);
    text([NSString stringWithFormat:@"Main engine       %3.0f %%",f.throttle*100],rx+14,bottom+ph-53,12,white,YES);
    [ink setFill]; NSRectFill(NSMakeRect(rx+14,bottom+ph-68,224*f.throttle,3));
    text([NSString stringWithFormat:@"Fuel             %6.0f kg",f.fuel],rx+14,bottom+ph-96,12,white,YES);
    text([NSString stringWithFormat:@"RCS              %6.0f kg",f.rcs],rx+14,bottom+ph-117,12,white,YES);
    text([NSString stringWithFormat:@"Acceleration     %6.2f m/s²",f.acceleration],rx+14,bottom+ph-138,12,muted,YES);
    text(mode,rx+14,bottom+15,12,ink);
    if(v->orbitVisible&&w>950) {
        CGFloat ox=w*.5,oy=bottom+95,scale=70/std::max(EarthRadius,orbit.e<1?orbit.ApDist():f.position.length());
        [panel setFill]; NSRectFill(NSMakeRect(ox-120,bottom,240,ph));
        text(@"OSCULATING ORBIT",ox-100,bottom+ph-27,11,ink);
        [[NSColor colorWithRed:.08 green:.22 blue:.31 alpha:1] setFill];
        CGFloat radius=EarthRadius*scale;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox-radius,oy-radius,2*radius,2*radius)] fill];
        if(orbit.e<1) {
            [ink setStroke]; NSBezierPath *p=[NSBezierPath bezierPath];
            for(int j=0;j<=180;++j) { double a=j*Pi2/180, r=orbit.Rdist(a)*scale;
                NSPoint point=NSMakePoint(ox+r*cos(a),oy+r*sin(a)); if(!j) [p moveToPoint:point]; else [p lineToPoint:point]; }
            [p stroke];
            double a=orbit.TrueAnm(),r=orbit.Radius()*scale;
            [white setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(ox+r*cos(a)-3,oy+r*sin(a)-3,6,6)] fill];
        }
    }
    text(@"+ / − Throttle     X Cut engines     P Prograde     Space Pause     F1 Controls",26,12,11,muted);
    if(v->helpVisible) {
        CGFloat bw=570,bh=355,x=(w-bw)/2,y=(h-bh)/2;
        [panel setFill]; NSRectFill(NSMakeRect(x,y,bw,bh));
        text(@"Flight controls",x+24,y+bh-44,23,white);
        NSArray<NSString *> *rows=@[@"+ / −      Increase / decrease main throttle",@"X          Cut main engines",@"↑ ↓ ← →    Pitch and yaw    ·    Q / E  Roll",@"W / S      Forward / backward RCS translation",@"P / O      Prograde / retrograde assist",@"K / N      Kill rotation / manual control",@"T / Y      Increase / decrease time acceleration",@"V          Switch external / forward view",@"Drag       Orbit camera    ·    Scroll  Zoom",@"Space      Pause    ·    R  Restart    ·    F2  Orbit",@"⌘O / ⌘S    Open / save scenario    ·    F1  Close help"];
        for(NSUInteger i=0;i<rows.count;++i) text(rows[i],x+24,y+bh-81-i*23,13,ink,YES);
    }
}
@end
@implementation FlightView
- (instancetype)initWithFrame:(NSRect)frame {
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device) @throw [NSException exceptionWithName:@"Metal unavailable" reason:@"A Metal-capable Mac is required." userInfo:nil];
    self=[super initWithFrame:frame device:device]; if(!self) return nil;
    held.fill(false); yaw=-.55; pitch=.32; distance=43; helpVisible=false; orbitVisible=true;
    self.colorPixelFormat=MTLPixelFormatBGRA8Unorm_sRGB; self.depthStencilPixelFormat=MTLPixelFormatDepth32Float;
    self.sampleCount=[device supportsTextureSampleCount:4]?4:1;
    self.preferredFramesPerSecond=120; self.framebufferOnly=NO; self.clearColor=MTLClearColorMake(0,0,0,1);
    self.delegate=self; inflight=dispatch_semaphore_create(3); queue=[device newCommandQueue];
    NSError *error=nil; NSString *source=[NSString stringWithContentsOfFile:resource(@"Shaders.metal") encoding:NSUTF8StringEncoding error:&error];
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library) @throw [NSException exceptionWithName:@"Metal shader error" reason:error.localizedDescription userInfo:nil];
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
    pd.colorAttachments[0].pixelFormat=self.colorPixelFormat; pd.depthAttachmentPixelFormat=self.depthStencilPixelFormat; pd.rasterSampleCount=self.sampleCount;
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
    MTLDepthStencilDescriptor *dd=[MTLDepthStencilDescriptor new]; dd.depthCompareFunction=MTLCompareFunctionLess; dd.depthWriteEnabled=YES;
    depthState=[device newDepthStencilStateWithDescriptor:dd]; dd.depthCompareFunction=MTLCompareFunctionAlways; dd.depthWriteEnabled=NO;
    skyDepth=[device newDepthStencilStateWithDescriptor:dd];
    auto mesh=loadMesh(resource(@"Meshes/deltaglider_ns.msh").fileSystemRepresentation); materials=mesh.materials;
    textures=[NSMutableArray new];
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:1 height:1 mipmapped:NO];
    whiteTexture=[device newTextureWithDescriptor:td]; uint32_t white=0xffffffff;
    [whiteTexture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&white bytesPerRow:4]; [textures addObject:whiteTexture];
    for(auto &name:mesh.textures) {
        auto filename=std::filesystem::path(name).filename().string();
        std::transform(filename.begin(),filename.end(),filename.begin(),[](unsigned char c){ return std::tolower(c); });
        auto image=loadDDS(resource([@"Textures/DG/" stringByAppendingString:[NSString stringWithUTF8String:filename.c_str()]]).fileSystemRepresentation);
        MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:image.width height:image.height mipmapped:YES];
        id<MTLTexture> tex=[device newTextureWithDescriptor:desc];
        [tex replaceRegion:MTLRegionMake2D(0,0,image.width,image.height) mipmapLevel:0 withBytes:image.rgba.data() bytesPerRow:image.width*4];
        id<MTLCommandBuffer> cb=[queue commandBuffer]; id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder]; [blit generateMipmapsForTexture:tex]; [blit endEncoding]; [cb commit];
        [textures addObject:tex];
    }
    for(const auto &g:mesh.groups) {
        GpuGroup group;
        group.vertices=[device newBufferWithBytes:g.vertices.data() length:g.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];
        group.indices=[device newBufferWithBytes:g.indices.data() length:g.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
        group.count=g.indices.size(); group.material=g.material; group.texture=g.texture; groups.push_back(group);
    }
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    earthTexture=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:resource(@"earth.png")] options:@{MTKTextureLoaderOptionSRGB:@YES,MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];
    if(!earthTexture) @throw [NSException exceptionWithName:@"Earth texture error" reason:error.localizedDescription userInfo:nil];
    [self resetFlight:nil];
    NSArray<NSString *> *args=NSProcessInfo.processInfo.arguments;
    for(NSUInteger i=1;i<args.count;++i) {
        if([args[i] isEqual:@"--frames"]&&i+1<args.count) smokeFrames=[args[++i] integerValue];
        else if([args[i] isEqual:@"--capture"]&&i+1<args.count) capturePath=args[++i];
        else if([args[i] isEqual:@"--prograde"]) { flight.assist=Assist::Prograde; flight.align(flight.velocity); }
        else if([args[i] isEqual:@"--report"]&&i+1<args.count) reportPath=args[++i];
        else if([args[i] isEqual:@"--scenario"]&&i+1<args.count) flight.load(args[++i].fileSystemRepresentation);
    }
    previous=begin=CACurrentMediaTime(); return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)clearInput { held.fill(false); }
- (void)viewDidMoveToWindow { [super viewDidMoveToWindow]; [self.window makeFirstResponder:self]; }
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {}
- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
    CFTimeInterval start=CACurrentMediaTime(),dt=start-previous; previous=start;
    if(dt<=0) return;
    Input input; input.pitch=(held[125]?1.:0)-(held[126]?1.:0); input.yaw=(held[124]?1.:0)-(held[123]?1.:0);
    input.roll=(held[12]?1.:0)-(held[14]?1.:0); input.translate=(held[13]?1.:0)-(held[1]?1.:0);
    if(held[24]||held[69]) flight.throttle=std::min(1.,flight.throttle+dt*.4);
    if(held[27]||held[78]) flight.throttle=std::max(0.,flight.throttle-dt*.4);
    if(input.pitch||input.yaw||input.roll) flight.assist=Assist::Free;
    flight.advance(dt,input);
    dispatch_semaphore_wait(inflight,DISPATCH_TIME_FOREVER);
    MTLRenderPassDescriptor *pass=self.currentRenderPassDescriptor; id<CAMetalDrawable> drawable=self.currentDrawable;
    if(!pass||!drawable) { dispatch_semaphore_signal(inflight); return; }
    Vector radial=flight.position.unit(),tangent=(flight.velocity-radial*dotp(flight.velocity,radial)).unit();
    Vector lateral=crossp(radial,tangent).unit();
    Vector offset=(-tangent*(cos(yaw)*cos(pitch))+lateral*(sin(yaw)*cos(pitch))+radial*sin(pitch))*distance;
    Vector dir=(-offset).unit(),up=radial;
    if(cockpit) { offset=flight.right*-.414+flight.up*1.95+flight.forward*6.7; dir=flight.forward; up=flight.up; }
    Vector cameraRight=crossp(dir,up).unit(),cameraUp=crossp(cameraRight,dir).unit();
    float aspect=self.drawableSize.width/std::max(1.,self.drawableSize.height),tanHalf=tan(50*RAD*.5);
    FrameUniforms uniforms; uniforms.projection=projection(aspect,tanHalf);
    uniforms.right=f4(cameraRight); uniforms.up=f4(cameraUp); uniforms.forward=f4(dir);
    uniforms.position=f4((flight.position+offset)/EarthRadius);
    // Fixed initial solar direction for the single-body flight milestone.
    uniforms.sun=f4(Vector(.32,.84,-.44).unit());
    uniforms.screen={(float)self.drawableSize.width,(float)self.drawableSize.height,tanHalf,(float)fmod((flight.mjd+flight.elapsed/86400.-51544.5)*86400/86164.10132+4.88948754/Pi2,1.)};
    ObjectUniforms object={};
    object.model.columns[0]=f4(flight.right); object.model.columns[1]=f4(flight.up); object.model.columns[2]=f4(flight.forward); object.model.columns[3]=f4(-offset,1);
    id<MTLCommandBuffer> cb=[queue commandBuffer]; cb.label=@"Orbiter native flight";
    id<MTLRenderCommandEncoder> encoder=[cb renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:skyPipeline]; [encoder setDepthStencilState:skyDepth];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1]; [encoder setFragmentTexture:earthTexture atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    if(!cockpit) {
        [encoder setRenderPipelineState:meshPipeline]; [encoder setDepthStencilState:depthState]; [encoder setCullMode:MTLCullModeNone];
        [encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        // Opaque geometry first; transparent canopy last.
        for(int transparent=0;transparent<2;++transparent) for(const auto &g:groups) {
            const auto &mat=materials[g.material]; if((mat.diffuse[3]<.99)!=(transparent==1)) continue;
            object.color={mat.diffuse[0],mat.diffuse[1],mat.diffuse[2],mat.diffuse[3]};
            [encoder setVertexBuffer:g.vertices offset:0 atIndex:0];
            [encoder setVertexBytes:&object length:sizeof(object) atIndex:2];
            [encoder setFragmentBytes:&object length:sizeof(object) atIndex:2];
            [encoder setFragmentTexture:textures[g.texture] atIndex:0];
            [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:g.count indexType:MTLIndexTypeUInt32 indexBuffer:g.indices indexBufferOffset:0];
        }
    }
    [encoder endEncoding]; [cb presentDrawable:drawable];
    __weak FlightView *weakSelf=self; dispatch_semaphore_t semaphore=inflight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        double ms=(completed.GPUEndTime-completed.GPUStartTime)*1000;
        dispatch_async(dispatch_get_main_queue(),^{ FlightView *v=weakSelf; if(v&&ms>0) { v->gpuMs=ms; v->gpuSum+=ms; } });
        dispatch_semaphore_signal(semaphore);
    }];
    [cb commit];
    cpuMs=(CACurrentMediaTime()-start)*1000; cpuSum+=cpuMs; ++frameCount;
    if(frameCount>30) intervals.push_back(dt*1000);
    if(start-lastHud>.1) { fps=1/dt; self.hud.needsDisplay=YES; lastHud=start; }
    if(smokeFrames&&frameCount>=smokeFrames) {
        self.paused=YES; [cb waitUntilCompleted];
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
    [self.hud paint:self.bounds]; [NSGraphicsContext restoreGraphicsState];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
- (void)writeReport {
    if(!reportPath) return;
    auto sorted=intervals; std::sort(sorted.begin(),sorted.end());
    double mean=sorted.empty()?0:std::accumulate(sorted.begin(),sorted.end(),0.)/sorted.size();
    double p95=sorted.empty()?0:sorted[(sorted.size()-1)*95/100];
    NSDictionary *report=@{@"architecture":@"arm64",@"renderer":@"Metal",@"device":self.device.name,
        @"frames":@(frameCount),@"drawableWidth":@(self.drawableSize.width),@"drawableHeight":@(self.drawableSize.height),
        @"sampleCount":@(self.sampleCount),@"cameraDistance":@(distance),@"forwardLength":@(flight.forward.length()),@"rightLength":@(flight.right.length()),@"meanFrameMs":@(mean),@"p95FrameMs":@(p95),@"meanFPS":@(mean?1000/mean:0),
        @"meanCPUEncodeMs":@(cpuSum/frameCount),@"lastGPUFrameMs":@(gpuMs),@"scenarioElapsed":@(flight.elapsed),
        @"altitudeMeters":@(flight.altitude()),@"meshGroups":@(groups.size())};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:reportPath atomically:YES];
}
- (void)resetFlight:(id)sender { flight.load(resource(@"Scenarios/DG Mk4 in orbit.scn").fileSystemRepresentation); status=@"Earth orbit  ·  Press F1 for controls"; }
- (void)pauseFlight:(id)sender { flight.paused=!flight.paused; [self clearInput]; }
- (void)toggleHelp:(id)sender { helpVisible=!helpVisible; self.hud.needsDisplay=YES; }
- (void)showError:(const char *)message { NSAlert *a=[NSAlert new]; a.messageText=@"Unable to load flight"; a.informativeText=[NSString stringWithUTF8String:message]; [a runModal]; }
- (void)openScenario:(id)sender {
    [self clearInput]; BOOL wasPaused=flight.paused; flight.paused=true;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowedFileTypes=@[@"scn"]; panel.message=@"Choose an Earth-orbit scenario focused on a DeltaGlider.";
    if([panel runModal]==NSModalResponseOK) { try { flight.load(panel.URL.fileSystemRepresentation); status=panel.URL.lastPathComponent; }
        catch(const std::exception &e) { [self showError:e.what()]; flight.paused=wasPaused; } }
    else flight.paused=wasPaused;
    previous=CACurrentMediaTime();
}
- (void)saveScenario:(id)sender {
    [self clearInput]; BOOL wasPaused=flight.paused; flight.paused=true;
    NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"Native flight.scn"; panel.allowedFileTypes=@[@"scn"];
    if([panel runModal]==NSModalResponseOK) { try { flight.save(panel.URL.fileSystemRepresentation); status=@"Flight saved"; } catch(const std::exception &e) { [self showError:e.what()]; } }
    flight.paused=wasPaused; previous=CACurrentMediaTime();
}
- (void)keyDown:(NSEvent *)event {
    if(smokeFrames) return;
    if(event.modifierFlags&NSEventModifierFlagCommand) { [super keyDown:event]; return; }
    unsigned code=event.keyCode; if(code<held.size()) held[code]=true;
    if(event.isARepeat) return;
    switch(code) {
        case 49:[self pauseFlight:nil];break;
        case 7:flight.throttle=0;break; // X
        case 15:[self resetFlight:nil];break;
        case 35:flight.assist=Assist::Prograde;flight.angularVelocity={};break;
        case 31:flight.assist=Assist::Retrograde;flight.angularVelocity={};break;
        case 40:flight.assist=Assist::KillRotation;break;
        case 45:flight.assist=Assist::Free;break;
        case 17:flight.warp=std::min(1000.,flight.warp*10);status=@"Time acceleration returns to 1× during maneuvers";break;
        case 16:flight.warp=std::max(1.,flight.warp/10);break;
        case 9:cockpit=!cockpit;break;
        case 122:[self toggleHelp:nil];break;
        case 120:orbitVisible=!orbitVisible;break;
    }
}
- (void)keyUp:(NSEvent *)event { if(event.keyCode<held.size()) held[event.keyCode]=false; }
- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; }
- (void)mouseDragged:(NSEvent *)event { if(smokeFrames) return; yaw+=event.deltaX*.009; pitch=std::clamp(pitch+event.deltaY*.009,-1.35,1.35); }
- (void)scrollWheel:(NSEvent *)event { if(smokeFrames) return; distance=std::clamp(distance*exp(event.scrollingDeltaY*.025),14.,1000.); }
@end
@interface AppDelegate : NSObject<NSApplicationDelegate,NSWindowDelegate>
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) FlightView *view;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    @try { try {
        NSRect rect=NSMakeRect(0,0,1280,800);
        self.window=[[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        self.window.title=@"Orbiter Native — Delta-glider"; self.window.minSize=NSMakeSize(900,600); self.window.delegate=self;
        self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        self.view=[[FlightView alloc] initWithFrame:rect]; self.view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        NSView *root=[[NSView alloc] initWithFrame:rect]; [root addSubview:self.view];
        FlightHUD *hud=[[FlightHUD alloc] initWithFrame:rect]; hud.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; hud.flightView=self.view;
        [root addSubview:hud]; self.view.hud=hud; self.window.contentView=root;
        NSMenu *main=[NSMenu new]; NSMenuItem *appItem=[NSMenuItem new]; [main addItem:appItem];
        NSMenu *app=[NSMenu new]; [app addItemWithTitle:@"Quit Orbiter" action:@selector(terminate:) keyEquivalent:@"q"]; appItem.submenu=app;
        NSMenuItem *fileItem=[NSMenuItem new]; fileItem.title=@"File"; [main addItem:fileItem]; NSMenu *file=[NSMenu new]; fileItem.submenu=file;
        NSMenuItem *open=[file addItemWithTitle:@"Open Scenario…" action:@selector(openScenario:) keyEquivalent:@"o"]; open.target=self.view;
        NSMenuItem *save=[file addItemWithTitle:@"Save Scenario…" action:@selector(saveScenario:) keyEquivalent:@"s"]; save.target=self.view;
        NSMenuItem *flightItem=[NSMenuItem new]; flightItem.title=@"Flight"; [main addItem:flightItem]; NSMenu *fm=[NSMenu new]; flightItem.submenu=fm;
        NSMenuItem *pause=[fm addItemWithTitle:@"Pause / Resume" action:@selector(pauseFlight:) keyEquivalent:@""]; pause.target=self.view;
        NSMenuItem *reset=[fm addItemWithTitle:@"Restart Flight" action:@selector(resetFlight:) keyEquivalent:@""]; reset.target=self.view;
        NSMenuItem *help=[fm addItemWithTitle:@"Flight Controls" action:@selector(toggleHelp:) keyEquivalent:@"?"]; help.target=self.view;
        NSApp.mainMenu=main; [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    } catch(const std::exception &e) { [self fail:[NSString stringWithUTF8String:e.what()]]; } }
    @catch(NSException *e) { [self fail:e.reason]; }
}
- (void)fail:(NSString *)message { fprintf(stderr,"Orbiter Native: %s\n",message.UTF8String); NSAlert *a=[NSAlert new]; a.messageText=@"Orbiter could not start"; a.informativeText=message; [a runModal]; [NSApp terminate:nil]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)windowDidResignKey:(NSNotification *)note { [self.view clearInput]; }
- (void)applicationDidResignActive:(NSNotification *)note { [self.view clearInput]; }
@end
int main(int argc,const char **argv) { @autoreleasepool {
    NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    AppDelegate *delegate=[AppDelegate new]; app.delegate=delegate; [app run]; return 0;
} }

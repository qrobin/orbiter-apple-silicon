#import "SolarRenderer.h"
#include "SolarSystem.h"
#include <algorithm>
#include <vector>
using namespace native;
static simd_float4 solarVector(Vector v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
@interface SolarRenderer(){
    id<MTLDevice> gpu;MTKTextureLoader *loader;NSMutableDictionary<NSNumber*,id<MTLTexture>> *cache;
    id<MTLTexture> white;id<MTLRenderPipelineState> pipeline;
}
@end
@implementation SolarRenderer
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library samples:(NSUInteger)samples earth:(id<MTLTexture>)earth{
    if(!(self=[super init]))return nil;gpu=device;loader=[[MTKTextureLoader alloc]initWithDevice:device];cache=[NSMutableDictionary new];cache[@((int)BodyId::Earth)]=earth;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:1 height:1 mipmapped:NO];white=[gpu newTextureWithDescriptor:d];uint32_t pixel=0xffffffff;[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];
    NSError *error=nil;NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Bodies/saturn-ring.png"];
    _rings=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:path] options:@{MTKTextureLoaderOptionSRGB:@YES} error:&error];
    if(!_rings)@throw [NSException exceptionWithName:@"Ring texture unavailable" reason:error.localizedDescription userInfo:nil];
    MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:@"celestialVertex"];p.fragmentFunction=[library newFunctionWithName:@"celestialFragment"];p.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA16Float;p.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;p.rasterSampleCount=samples;
    p.colorAttachments[0].blendingEnabled=YES;p.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;p.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    pipeline=[gpu newRenderPipelineStateWithDescriptor:p error:&error];if(!pipeline)@throw [NSException exceptionWithName:@"Solar System pipeline error" reason:error.localizedDescription userInfo:nil];return self;
}
- (id<MTLTexture>)textureForBody:(BodyId)bodyId{
    NSNumber *key=@((int)bodyId);if(cache[key])return cache[key];auto &b=body(bodyId);if(!b.texture[0])return white;
    NSString *file=[NSString stringWithFormat:@"Bodies/%s.jpg",b.texture],*path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:file];NSError *error=nil;
    id<MTLTexture> t=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:path] options:@{MTKTextureLoaderOptionSRGB:@YES,MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];
    if(!t)@throw [NSException exceptionWithName:@"Planet texture unavailable" reason:error.localizedDescription userInfo:nil];cache[key]=t;return t;
}
- (void)updateFrame:(FrameUniforms *)f flight:(const Flight &)flight offset:(Vector)offset{
    auto &b=flight.centralBody();double date=flight.mjd+flight.elapsed/86400;auto central=bodyState(flight.reference,date);Vector ship=central.position+flight.position+offset,sun=(-ship).unit();
    float visible=1;
    for(auto &other:bodies())if(other.id!=BodyId::Sun){auto state=bodyState(other.id,date);Vector v=state.position-ship;double along=dotp(v,sun);if(along>0&&along<ship.length()&&crossp(v,sun).length()<other.radius){visible=0;break;}}
    f->sun=solarVector(sun,visible);f->position=solarVector((flight.position+offset)/b.radius);
    f->sunShape={(float)(body(BodyId::Sun).radius/ship.length()),1,0,0};
    f->environment.x=(float)((flight.position+offset).length()/b.radius-1);f->screen.w=(float)(b.rotation(date)/Pi2);
    double scale=b.pressure>0&&b.density>0?b.pressure/(b.density*b.mu()/(b.radius*b.radius)):13000;
    scale=std::clamp(scale,1000.,100000.);float atmosphere=b.pressure>100?1:b.pressure>0?(float)(b.pressure/100000.):0;Vector haze(.1,.33,.75);
    if(b.id==BodyId::Earth){atmosphere=1;scale=13000;}
    if(b.id==BodyId::Mars){atmosphere=.18;haze={.47,.27,.14};}
    if(b.id==BodyId::Venus)haze={.64,.47,.22};
    if(b.id==BodyId::Titan)haze={.60,.33,.11};
    if(b.id==BodyId::Jupiter||b.id==BodyId::Saturn)haze={.60,.47,.28};
    if(b.id==BodyId::Uranus)haze={.13,.48,.53};if(b.id==BodyId::Neptune)haze={.08,.19,.51};
    f->body={(float)b.radius,atmosphere,(float)scale,b.id==BodyId::Sun?2.f:b.solid?0.f:1.f};f->haze=solarVector(haze,(float)std::min(b.radius*.06,scale*6));
    f->equatorX=solarVector(b.equatorX(),b.texture[0]?1:0);f->pole=solarVector(b.pole(),b.id==BodyId::Saturn?1.24:0);f->equatorZ=solarVector(b.equatorZ(),b.id==BodyId::Saturn?2.4:0);f->surfaceColor=solarVector(b.color,(int)b.id);
}
- (void)encodeBodies:(id<MTLRenderCommandEncoder>)e frame:(const FrameUniforms &)f flight:(const Flight &)flight offset:(Vector)offset{
    double date=flight.mjd+flight.elapsed/86400;auto central=bodyState(flight.reference,date);Vector camera=central.position+flight.position+offset;
    struct Visible {BodyId id;Vector delta;double distance;};std::vector<Visible> objects;
    Vector forward(f.forward.x,f.forward.y,f.forward.z);
    for(auto &b:bodies())if(b.id!=flight.reference){Vector delta=bodyState(b.id,date).position-camera;double distance=delta.length();if(distance>b.radius&&dotp(delta,forward)>0&&b.radius/distance*f.screen.y/f.screen.z>.35)objects.push_back({b.id,delta,distance});}
    std::sort(objects.begin(),objects.end(),[](auto &a,auto &b){return a.distance>b.distance;});
    [e setRenderPipelineState:pipeline];[e setVertexBytes:&f length:sizeof(f) atIndex:0];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:_rings atIndex:1];
    for(auto &v:objects){const auto &b=body(v.id);Vector sun=b.id==BodyId::Sun?Vector(0,1,0):(-bodyState(b.id,date).position).unit();CelestialUniforms u{};
        u.directionRadius=solarVector(v.delta/v.distance,b.radius/v.distance);u.axisX=solarVector(b.equatorX(),b.rotation(date)/Pi2);u.pole=solarVector(b.pole(),b.id==BodyId::Sun?2:b.solid?0:1);u.axisZ=solarVector(b.equatorZ(),b.texture[0]?1:0);
        u.light=solarVector(sun,v.distance);u.material=solarVector(b.color,(int)b.id);u.rings={b.id==BodyId::Saturn?1.24f:0.f,b.id==BodyId::Saturn?2.4f:0.f,0,0};
        [e setVertexBytes:&u length:sizeof(u) atIndex:1];[e setFragmentBytes:&u length:sizeof(u) atIndex:1];[e setFragmentTexture:[self textureForBody:b.id] atIndex:0];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    }
}
@end

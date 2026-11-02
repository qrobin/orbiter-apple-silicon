#import "SolarRenderer.h"
#include "TerrainFrame.h"
#include "SolarSystem.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>
using namespace native;
static simd_float4 solarVector(Vector v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
// Approximate geometric albedos, ordered by the original Sol catalogue.
static double bodyAlbedo(BodyId id){
    static const double albedo[BodyCount]={0,.142,.689,.367,.12,.170,.071,.068,.423,.538,.63,.67,.43,.22,.499,.69,.99,.81,.55,.95,.21,.30,.05,.488,.32,.39,.19,.27,.23,.442,.76,.10,.16};
    return albedo[(size_t)id];
}
static void reflectedLights(BodyId receiver,double date,simd_float4 *out){
    std::fill_n(out,4,simd_float4{});
    if(receiver==BodyId::Sun)return;
    const auto &target=body(receiver);Vector targetPosition=bodyState(receiver,date).position;
    struct Light {Vector offset;double flux;};std::vector<Light> lights;
    for(const auto &source:bodies()){
        if(source.id==BodyId::Sun||source.id==receiver)continue;
        Vector position=bodyState(source.id,date).position,offset=position-targetPosition;
        double distance=offset.length(),solarDistance=position.length();
        if(distance<=source.radius+target.radius||solarDistance<=body(BodyId::Sun).radius)continue;
        Vector toSun=-position/solarDistance,toTarget=-offset/distance;
        double phase=acos(std::clamp(dotp(toSun,toTarget),-1.,1.));
        double flux=reflectedIrradiance(solarDistance,source.radius,distance,bodyAlbedo(source.id),phase);
        if(flux<1e-12)continue;
        // The reflecting body can itself be eclipsed, including by the receiver.
        double sunRadius=asin(std::clamp(body(BodyId::Sun).radius/solarDistance,0.,1.));
        for(const auto &occluder:bodies())if(occluder.id!=BodyId::Sun&&occluder.id!=source.id){
            Vector delta=bodyState(occluder.id,date).position-position;double d=delta.length();
            if(d<=occluder.radius||dotp(delta,toSun)<=0||d>=solarDistance)continue;
            double angular=asin(std::clamp(occluder.radius/d,0.,1.));
            double separation=acos(std::clamp(dotp(delta/d,toSun),-1.,1.));
            flux*=solarDiscVisibility(sunRadius,angular,separation);
            if(flux<1e-12)break;
        }
        if(flux>=1e-12)lights.push_back({offset/target.radius,flux});
    }
    std::sort(lights.begin(),lights.end(),[](const Light &a,const Light &b){return a.flux>b.flux;});
    for(size_t i=0;i<std::min<size_t>(4,lights.size());++i)out[i]=solarVector(lights[i].offset,(float)lights[i].flux);
}
struct VisibleBody {BodyId id;Vector delta;double distance;};
@interface SolarRenderer(){
    id<MTLDevice> gpu;MTKTextureLoader *loader;NSMutableDictionary<NSNumber*,id<MTLTexture>> *cache;
    id<MTLTexture> white;id<MTLRenderPipelineState> pipeline;
    std::vector<VisibleBody> visibleBodies;
    std::array<bool,BodyCount> pinned,pending,failed;
    std::array<uint64_t,BodyCount> lastUsed;uint64_t clock;
}
@end
@implementation SolarRenderer
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library samples:(NSUInteger)samples earth:(id<MTLTexture>)earth{
    if(!(self=[super init]))return nil;gpu=device;loader=[[MTKTextureLoader alloc]initWithDevice:device];cache=[NSMutableDictionary new];cache[@((int)BodyId::Earth)]=earth;
    pinned.fill(false);pending.fill(false);failed.fill(false);lastUsed.fill(0);clock=0;
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:1 height:1 mipmapped:NO];white=[gpu newTextureWithDescriptor:d];uint32_t pixel=0xffffffff;[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];
    NSError *error=nil;NSString *path=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Bodies/saturn-ring.png"];
    _rings=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:path] options:@{MTKTextureLoaderOptionSRGB:@YES} error:&error];
    if(!_rings)@throw [NSException exceptionWithName:@"Ring texture unavailable" reason:error.localizedDescription userInfo:nil];
    MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:@"celestialVertex"];p.fragmentFunction=[library newFunctionWithName:@"celestialFragment"];p.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA16Float;p.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;p.rasterSampleCount=samples;
    p.colorAttachments[0].blendingEnabled=YES;p.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;p.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    pipeline=[gpu newRenderPipelineStateWithDescriptor:p error:&error];if(!pipeline)@throw [NSException exceptionWithName:@"Solar System pipeline error" reason:error.localizedDescription userInfo:nil];return self;
}
// Retain every body needed by this frame, even when it exceeds the normal
// cache limit. Evict only inactive maps, least recently used first.
- (void)trimCache {
    while(cache.count>8){
        NSNumber *victim=nil;uint64_t oldest=UINT64_MAX;
        for(NSNumber *key in cache){size_t i=key.unsignedIntegerValue;
            if(i!=(size_t)BodyId::Earth&&!pinned[i]&&lastUsed[i]<oldest){victim=key;oldest=lastUsed[i];}}
        if(!victim)break;
        [cache removeObjectForKey:victim];
    }
}
- (id<MTLTexture>)textureForBody:(BodyId)bodyId{
    size_t i=(size_t)bodyId;NSNumber *key=@((int)bodyId);lastUsed[i]=++clock;
    id<MTLTexture> cached=cache[key];if(cached)return cached;
    const auto &b=body(bodyId);if(!b.texture[0]||pending[i]||failed[i])return white;
    pending[i]=true;
    NSString *file=[NSString stringWithFormat:@"Bodies/%s.jpg",b.texture];
    NSURL *url=[NSURL fileURLWithPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:file]];
    __weak SolarRenderer *weakSelf=self;
    [loader newTextureWithContentsOfURL:url options:@{MTKTextureLoaderOptionSRGB:@YES,MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} completionHandler:^(id<MTLTexture> texture,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            SolarRenderer *renderer=weakSelf;if(!renderer)return;
            renderer->pending[i]=false;
            if(texture){renderer->cache[key]=texture;[renderer trimCache];}
            else {renderer->failed[i]=true;fprintf(stderr,"Planet texture unavailable: %s\n",error.localizedDescription.UTF8String);}
        });
    }];
    return white;
}
- (void)updateFrame:(FrameUniforms *)f flight:(const Flight &)flight offset:(Vector)offset{
    auto &b=flight.centralBody();double date=flight.mjd+flight.elapsed/86400;auto central=bodyState(flight.reference,date);Vector ship=central.position+flight.position+offset,sun=(-ship).unit();
    double sunDistance=ship.length(),solarRadius=asin(std::clamp(body(BodyId::Sun).radius/sunDistance,0.,1.));float visible=1;
    for(auto &other:bodies())if(other.id!=BodyId::Sun){auto state=bodyState(other.id,date);Vector v=state.position-ship;double distance=v.length(),along=dotp(v,sun);if(distance<=other.radius){visible=0;break;}if(along>0&&along<sunDistance){double radius=asin(std::clamp(other.radius/distance,0.,1.));double separation=acos(std::clamp(dotp(v/distance,sun),-1.,1.));visible=std::min(visible,(float)solarDiscVisibility(solarRadius,radius,separation));}}
    reflectedLights(b.id,date,f->reflectedLights);
    f->sun=solarVector(sun,visible);f->position=solarVector((flight.position+offset)/b.radius);
    f->sunShape={(float)(body(BodyId::Sun).radius/sunDistance),1,0,(float)solarIrradiance(sunDistance)};
    f->environment.x=(float)((flight.position+offset).length()/b.radius-1);f->screen.w=(float)(b.rotation(date)/Pi2);
    double angle=b.rotation(date),c=cos(angle),s=sin(angle);
    setTerrainFrame(*f,flight.position+offset,b.equatorX()*c-b.equatorZ()*s,b.pole(),b.equatorX()*s+b.equatorZ()*c);
    double scale=b.pressure>0&&b.density>0?b.pressure/(b.density*b.mu()/(b.radius*b.radius)):13000;
    scale=std::clamp(scale,1000.,100000.);float atmosphere=b.pressure>100?1:b.pressure>0?(float)(b.pressure/100000.):0;Vector haze(.1,.33,.75);
    if(b.id==BodyId::Earth){atmosphere=1;scale=13000;}
    if(b.id==BodyId::Mars){atmosphere=.18;haze={.47,.27,.14};}
    if(b.id==BodyId::Venus)haze={.64,.47,.22};
    if(b.id==BodyId::Titan)haze={.60,.33,.11};
    if(b.id==BodyId::Jupiter||b.id==BodyId::Saturn)haze={.60,.47,.28};
    if(b.id==BodyId::Uranus)haze={.13,.48,.53};if(b.id==BodyId::Neptune)haze={.08,.19,.51};
    f->body={(float)b.radius,atmosphere,(float)scale,b.id==BodyId::Sun?2.f:b.solid?0.f:1.f};f->haze=solarVector(haze,(float)std::min(b.radius*.06,scale*6));
    id<MTLTexture> centralMap=[self textureForBody:b.id];
    f->equatorX=solarVector(b.equatorX(),b.texture[0]&&centralMap!=white?1:0);f->pole=solarVector(b.pole(),b.id==BodyId::Saturn?1.24:0);f->equatorZ=solarVector(b.equatorZ(),b.id==BodyId::Saturn?2.4:0);f->surfaceColor=solarVector(b.color,(int)b.id);
    // Cull against the actual view frustum and the central planet before
    // requesting maps. The camera and body centres are in the same frame.
    visibleBodies.clear();pinned.fill(false);pinned[(size_t)flight.reference]=true;
    Vector forward(f->forward.x,f->forward.y,f->forward.z),right(f->right.x,f->right.y,f->right.z),up(f->up.x,f->up.y,f->up.z);
    Vector cameraLocal=flight.position+offset;double cameraRadius=cameraLocal.length();
    double tanY=f->screen.z,tanX=tanY*f->screen.x/std::max(1.f,f->screen.y);
    for(const auto &other:bodies())if(other.id!=flight.reference){
        Vector delta=bodyState(other.id,date).position-ship;double distance=delta.length();
        if(distance<=other.radius||other.radius/distance*f->screen.y/f->screen.z<=.35)continue;
        double x=dotp(delta,right),y=dotp(delta,up),z=dotp(delta,forward),r=other.radius;
        if(z < -r || fabs(x)>z*tanX+r*sqrt(1+tanX*tanX) || fabs(y)>z*tanY+r*sqrt(1+tanY*tanY))continue;
        if(cameraRadius>b.radius){
            double separation=acos(std::clamp(dotp(delta/distance,-cameraLocal/cameraRadius),-1.,1.));
            double horizon=asin(std::clamp(b.radius/cameraRadius,0.,1.));
            double apparent=asin(std::clamp(r/distance,0.,1.));
            if(distance>cameraRadius&&separation+apparent<horizon)continue;
        }
        visibleBodies.push_back({other.id,delta,distance});pinned[(size_t)other.id]=true;
    }
    std::sort(visibleBodies.begin(),visibleBodies.end(),[](const auto &a,const auto &b){return a.distance>b.distance;});
    [self trimCache];
}
- (void)encodeBodies:(id<MTLRenderCommandEncoder>)e frame:(const FrameUniforms &)f flight:(const Flight &)flight offset:(Vector)offset{
    double date=flight.mjd+flight.elapsed/86400;
    [e setRenderPipelineState:pipeline];[e setVertexBytes:&f length:sizeof(f) atIndex:0];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:_rings atIndex:1];
    for(auto &v:visibleBodies){const auto &b=body(v.id);Vector sun=b.id==BodyId::Sun?Vector(0,1,0):(-bodyState(b.id,date).position).unit();CelestialUniforms u{};
        id<MTLTexture> map=[self textureForBody:b.id];
        u.directionRadius=solarVector(v.delta/v.distance,b.radius/v.distance);u.axisX=solarVector(b.equatorX(),b.rotation(date)/Pi2);u.pole=solarVector(b.pole(),b.id==BodyId::Sun?2:b.solid?0:1);u.axisZ=solarVector(b.equatorZ(),b.texture[0]&&map!=white?1:0);
        reflectedLights(b.id,date,u.reflectedLights);
        u.light=solarVector(sun,v.distance);u.material=solarVector(b.color,(int)b.id);u.rings={b.id==BodyId::Saturn?1.24f:0.f,b.id==BodyId::Saturn?2.4f:0.f,(float)solarIrradiance(bodyState(b.id,date).position.length()),0};
        [e setVertexBytes:&u length:sizeof(u) atIndex:1];[e setFragmentBytes:&u length:sizeof(u) atIndex:1];[e setFragmentTexture:map atIndex:0];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    }
}
@end

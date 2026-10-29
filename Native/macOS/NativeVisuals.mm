#import "NativeVisuals.h"
#include "Exhaust.h"
#include <algorithm>
#include <array>
#include <cmath>
using namespace native;
static simd_float4 visualVector(Vector v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
static void visualCheck(id object,NSError *error){if(!object)@throw [NSException exceptionWithName:@"Metal visual pipeline error" reason:error.localizedDescription?:@"Unable to allocate a Metal resource" userInfo:nil];}
struct SmokeDraw {TrailSegmentUniforms segment;float depth;};
@interface NativeVisuals () {
    id<MTLDevice> gpu;
    NSUInteger samples,width,height,trailWidth,trailHeight,historyIndex,frameIndex;
    BOOL historyValid,haveFlight;
    FrameUniforms lastFrame;
    double lastElapsed;
    NSInteger lastWeather;
    id<MTLTexture> hdr,lit,depth,trailLayer,msaaColor,msaaDepth;
    std::array<id<MTLTexture>,2> cloudHistory,cloudData,bloom;
    std::array<id<MTLBuffer>,3> smokeBuffers;
    ExhaustTrail exhaustTrail;
    std::vector<SmokeDraw> visibleSmoke;
    id<MTLComputePipelineState> noiseKernel,shadowKernel,cloudKernel,extractKernel,blurKernel;
    id<MTLRenderPipelineState> compositePipeline,flamePipeline,smokePipeline,trailCompositePipeline,presentPipeline;
    id<MTLDepthStencilState> flameDepth;
}
@end
@implementation NativeVisuals
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library queue:(id<MTLCommandQueue>)queue samples:(NSUInteger)count {
    if(!(self=[super init]))return nil;gpu=device;samples=count;_weather=1;lastWeather=-1;
    NSError *error=nil;
    auto kernel=[&](NSString *name){id<MTLComputePipelineState> p=[gpu newComputePipelineStateWithFunction:[library newFunctionWithName:name] error:&error];visualCheck(p,error);return p;};
    noiseKernel=kernel(@"makeCloudNoise");shadowKernel=kernel(@"cloudShadowMap");cloudKernel=kernel(@"marchClouds");
    extractKernel=kernel(@"extractBloom");blurKernel=kernel(@"blurBloom");
    auto pipeline=[&](NSString *vertex,NSString *fragment,MTLPixelFormat format,BOOL depthEnabled,int blend){
        MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:vertex];p.fragmentFunction=[library newFunctionWithName:fragment];
        p.colorAttachments[0].pixelFormat=format;
        if(depthEnabled)p.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        if(blend){p.colorAttachments[0].blendingEnabled=YES;p.colorAttachments[0].sourceRGBBlendFactor=blend==3?MTLBlendFactorOne:MTLBlendFactorSourceAlpha;p.colorAttachments[0].destinationRGBBlendFactor=blend==1?MTLBlendFactorOne:MTLBlendFactorOneMinusSourceAlpha;p.colorAttachments[0].sourceAlphaBlendFactor=blend==2?MTLBlendFactorOne:MTLBlendFactorZero;p.colorAttachments[0].destinationAlphaBlendFactor=blend==2?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorOne;}
        id<MTLRenderPipelineState> result=[gpu newRenderPipelineStateWithDescriptor:p error:&error];visualCheck(result,error);return result;
    };
    compositePipeline=pipeline(@"skyVertex",@"compositeClouds",MTLPixelFormatRGBA16Float,NO,NO);
    flamePipeline=pipeline(@"flameVertex",@"flameFragment",MTLPixelFormatRGBA16Float,YES,YES);
    smokePipeline=pipeline(@"trailVolumeVertex",@"trailVolumeFragment",MTLPixelFormatRGBA16Float,NO,2);
    trailCompositePipeline=pipeline(@"skyVertex",@"compositeTrail",MTLPixelFormatRGBA16Float,NO,3);
    presentPipeline=pipeline(@"skyVertex",@"toneMap",MTLPixelFormatBGRA8Unorm_sRGB,NO,NO);
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionAlways;ds.depthWriteEnabled=NO;flameDepth=[gpu newDepthStencilStateWithDescriptor:ds];
    MTLTextureDescriptor *n=[MTLTextureDescriptor new];n.textureType=MTLTextureType3D;n.width=n.height=n.depth=128;n.pixelFormat=MTLPixelFormatRGBA8Unorm;n.storageMode=MTLStorageModePrivate;n.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    _cloudNoise=[gpu newTextureWithDescriptor:n];visualCheck(_cloudNoise,nil);
    _cloudShadows=[self texture:MTLPixelFormatR8Unorm width:512 height:256 usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
    for(auto &buffer:smokeBuffers){buffer=[gpu newBufferWithLength:(ExhaustTrail::capacity+64)*sizeof(TrailSegmentUniforms) options:MTLResourceStorageModeShared];visualCheck(buffer,nil);}
    visibleSmoke.reserve(ExhaustTrail::capacity+64);
    id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];[e setComputePipelineState:noiseKernel];[e setTexture:_cloudNoise atIndex:0];[e dispatchThreads:MTLSizeMake(128,128,128) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[e endEncoding];[cb commit];[cb waitUntilCompleted];
    if(cb.error)@throw [NSException exceptionWithName:@"Cloud noise generation failed" reason:cb.error.localizedDescription userInfo:nil];
    return self;
}
- (id<MTLTexture>)texture:(MTLPixelFormat)format width:(NSUInteger)w height:(NSUInteger)h usage:(MTLTextureUsage)usage {
    MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];d.storageMode=MTLStorageModePrivate;d.usage=usage;
    id<MTLTexture> t=[gpu newTextureWithDescriptor:d];visualCheck(t,nil);return t;
}
- (void)prepare:(FrameUniforms *)f width:(NSUInteger)w height:(NSUInteger)h {
    if(w!=width||h!=height){
        width=w;height=h;historyValid=NO;
        hdr=[self texture:MTLPixelFormatRGBA16Float width:w height:h usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        lit=[self texture:MTLPixelFormatRGBA16Float width:w height:h usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        depth=[self texture:MTLPixelFormatDepth32Float width:w height:h usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        float trailScale=std::min(.5f,1080.f/std::max(1.f,(float)w));
        trailWidth=std::max(1ul,(NSUInteger)ceil(w*trailScale));trailHeight=std::max(1ul,(NSUInteger)ceil(h*trailScale));
        trailLayer=[self texture:MTLPixelFormatRGBA16Float width:trailWidth height:trailHeight usage:MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead];
        if(samples>1){
            MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float width:w height:h mipmapped:NO];
            d.textureType=MTLTextureType2DMultisample;d.sampleCount=samples;d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageRenderTarget;
            msaaColor=[gpu newTextureWithDescriptor:d];d.pixelFormat=MTLPixelFormatDepth32Float;msaaDepth=[gpu newTextureWithDescriptor:d];visualCheck(msaaColor,nil);visualCheck(msaaDepth,nil);
        }
        float scale=std::min(.5f,760.f/std::max(1.f,(float)w));_cloudWidth=std::max(1ul,(NSUInteger)ceil(w*scale));_cloudHeight=std::max(1ul,(NSUInteger)ceil(h*scale));
        _cloudShadows=[self texture:MTLPixelFormatR8Unorm width:_cloudWidth height:_cloudHeight usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
        for(int i=0;i<2;++i){
            cloudHistory[i]=[self texture:MTLPixelFormatRGBA16Float width:_cloudWidth height:_cloudHeight usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
            cloudData[i]=[self texture:MTLPixelFormatRGBA32Float width:_cloudWidth height:_cloudHeight usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
            bloom[i]=[self texture:MTLPixelFormatRGBA16Float width:std::max(1ul,w/4) height:std::max(1ul,h/4) usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
        }
    }
    _weather=std::clamp((int)_weather,0,3);
    if(_weather!=lastWeather){historyValid=NO;lastWeather=_weather;}
    const simd_float4 presets[]={{1800,6500,0,0},{1800,6500,.48,0},{1400,6200,.78,.10},{1000,9000,.91,1}};
    f->clouds=presets[_weather];if((int)f->surfaceColor.w!=(int)BodyId::Earth)f->clouds.z=0;
    float moved=simd_length(simd_make_float3(f->position.x-lastFrame.position.x,f->position.y-lastFrame.position.y,f->position.z-lastFrame.position.z))*f->body.x;
    float aligned=simd_dot(simd_make_float3(f->forward.x,f->forward.y,f->forward.z),simd_make_float3(lastFrame.forward.x,lastFrame.forward.y,lastFrame.forward.z));
    if(moved>5000||aligned<.94)historyValid=NO;
    f->environment.z=historyValid?1:0;
    f->previousRight=historyValid?lastFrame.right:f->right;f->previousUp=historyValid?lastFrame.up:f->up;
    f->previousForward=historyValid?lastFrame.forward:f->forward;f->previousPosition=historyValid?lastFrame.position:f->position;
    _scenePass=[MTLRenderPassDescriptor renderPassDescriptor];
    _scenePass.colorAttachments[0].texture=samples>1?msaaColor:hdr;
    _scenePass.colorAttachments[0].loadAction=MTLLoadActionClear;
    _scenePass.colorAttachments[0].storeAction=samples>1?MTLStoreActionMultisampleResolve:MTLStoreActionStore;
    _scenePass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);
    if(samples>1)_scenePass.colorAttachments[0].resolveTexture=hdr;
    _scenePass.depthAttachment.texture=samples>1?msaaDepth:depth;_scenePass.depthAttachment.clearDepth=0;
    _scenePass.depthAttachment.loadAction=MTLLoadActionClear;_scenePass.depthAttachment.storeAction=samples>1?MTLStoreActionMultisampleResolve:MTLStoreActionStore;
    if(samples>1){_scenePass.depthAttachment.resolveTexture=depth;_scenePass.depthAttachment.depthResolveFilter=MTLMultisampleDepthResolveFilterMax;}
}
- (void)dispatch:(id<MTLComputeCommandEncoder>)e texture:(id<MTLTexture>)t {
    [e dispatchThreads:MTLSizeMake(t.width,t.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
}
- (void)encodeShadows:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)f {
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];e.label=@"Planetary cloud shadows";
    [e setComputePipelineState:shadowKernel];[e setBytes:&f length:sizeof(f) atIndex:0];[e setTexture:_cloudNoise atIndex:0];[e setTexture:_cloudShadows atIndex:1];[self dispatch:e texture:_cloudShadows];[e endEncoding];
}
- (void)encodeWeather:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)f {
    NSUInteger index=historyIndex%2,previous=1-index;uint32_t jitter=(uint32_t)frameIndex++;
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];e.label=@"Volumetric clouds and temporal reconstruction";[e setComputePipelineState:cloudKernel];
    [e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&jitter length:sizeof(jitter) atIndex:1];
    [e setTexture:_cloudNoise atIndex:0];[e setTexture:depth atIndex:1];[e setTexture:cloudHistory[previous] atIndex:2];[e setTexture:cloudData[previous] atIndex:3];[e setTexture:cloudHistory[index] atIndex:4];[e setTexture:cloudData[index] atIndex:5];[self dispatch:e texture:cloudHistory[index]];[e endEncoding];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=lit;pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];r.label=@"Depth-aware cloud composite";[r setRenderPipelineState:compositePipeline];[r setFragmentBytes:&f length:sizeof(f) atIndex:0];[r setFragmentTexture:hdr atIndex:0];[r setFragmentTexture:cloudHistory[index] atIndex:1];[r setFragmentTexture:cloudData[index] atIndex:2];[r setFragmentTexture:depth atIndex:3];[r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[r endEncoding];
    ++historyIndex;lastFrame=f;historyValid=YES;
}
- (void)encodeExhaust:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)f flight:(const Flight &)flight offset:(Vector)offset {
    std::array<EmitterUniforms,32> jets{};NSUInteger count=0;
    auto world=[&](Vector v){return flight.right*v.x+flight.up*v.y+flight.forward*v.z;};
    for(const auto &jet:gliderExhaust(flight)){
        if(count==jets.size())break;auto shape=plumeShape(flight,jet.kind);int kind=(int)jet.kind;
        double length=kind==0?12:kind==1?3:kind==2?6:.85;
        double vacuum=std::clamp((shape.spread-(kind==3?.10:.035))/(kind==3?.3:.10),0.,1.);length*=1+vacuum*1.2;
        jets[count++]={visualVector(world(jet.position),jet.level),visualVector(world(jet.direction),jet.radius),{(float)kind,(float)length,(float)(shape.speed*.28),(float)shape.spread}};
    }
    _emitterCount=count;double dt=haveFlight?flight.elapsed-lastElapsed:0;
    const double humidity[]={.25,.5,.75,.95};exhaustTrail.update(flight,dt,humidity[std::clamp((int)_weather,0,3)]);
    EffectUniforms step{};step.clock={(float)dt,(float)fmod(flight.elapsed,4096.),0,(float)count};step.offset=visualVector(offset);
    lastElapsed=flight.elapsed;haveFlight=YES;
    visibleSmoke.clear();ExhaustCameraFrame cameraFrame(flight,offset);
    auto direction=[](simd_float4 v){return Vector(v.x,v.y,v.z);};
    Vector cameraForward=direction(f.forward),cameraRight=direction(f.right),cameraUp=direction(f.up);
    double aspect=f.screen.x/std::max(1.f,f.screen.y);
    for(const auto &p:exhaustTrail.segments(flight)){
        Vector start,end;
        if(!cameraFrame.relative(p.body,p.start.position,start)||!cameraFrame.relative(p.body,p.end.position,end))continue;
        Vector midpoint=(start+end)*.5;double z=dotp(midpoint,cameraForward),extent=(start-end).length()*.5+std::max(p.start.radius,p.end.radius);
        if(z+extent<.2||fabs(dotp(midpoint,cameraRight))>std::max(0.,z)*f.screen.z*aspect+extent||fabs(dotp(midpoint,cameraUp))>std::max(0.,z)*f.screen.z+extent)continue;
        double footprint=std::max(0.,z)*f.screen.z*1.2/std::max(1.f,f.screen.y);
        double r0=std::max(p.start.radius,footprint),r1=std::max(p.end.radius,footprint);
        double o0=p.start.opacity*std::min(1.,p.start.radius/r0),o1=p.end.opacity*std::min(1.,p.end.radius/r1);
        constexpr double noiseScale=64.;
        Vector phase{std::remainder(p.start.position.x,noiseScale)/noiseScale,std::remainder(p.start.position.y,noiseScale)/noiseScale,std::remainder(p.start.position.z,noiseScale)/noiseScale};
        TrailSegmentUniforms u{visualVector(start,r0),visualVector(end,r1),{(float)o0,(float)o1,(float)p.start.age,(float)p.end.age},visualVector(phase,p.vacuum?1:0)};
        visibleSmoke.push_back({u,(float)z});
    }
    if(!count&&visibleSmoke.empty())return;
    if(!visibleSmoke.empty()){
        std::sort(visibleSmoke.begin(),visibleSmoke.end(),[](const SmokeDraw &a,const SmokeDraw &b){return a.depth>b.depth;});
        id<MTLBuffer> buffer=smokeBuffers[frameIndex%smokeBuffers.size()];auto *draw=(TrailSegmentUniforms *)buffer.contents;
        for(size_t i=0;i<visibleSmoke.size();++i)draw[i]=visibleSmoke[i].segment;
        FrameUniforms trailFrame=f;trailFrame.screen.x=(float)trailWidth;trailFrame.screen.y=(float)trailHeight;
        MTLRenderPassDescriptor *volumePass=[MTLRenderPassDescriptor renderPassDescriptor];volumePass.colorAttachments[0].texture=trailLayer;
        volumePass.colorAttachments[0].loadAction=MTLLoadActionClear;volumePass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);volumePass.colorAttachments[0].storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:volumePass];r.label=@"World-space exhaust meshes";
        [r setCullMode:MTLCullModeNone];[r setVertexBytes:&trailFrame length:sizeof(trailFrame) atIndex:0];[r setFragmentBytes:&trailFrame length:sizeof(trailFrame) atIndex:0];
        [r setFragmentTexture:depth atIndex:0];[r setFragmentTexture:_cloudNoise atIndex:1];
        [r setRenderPipelineState:smokePipeline];[r setVertexBuffer:buffer offset:0 atIndex:1];[r setVertexTexture:_cloudNoise atIndex:0];
        [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:12*18 instanceCount:visibleSmoke.size()];
        [r endEncoding];
        MTLRenderPassDescriptor *blendPass=[MTLRenderPassDescriptor renderPassDescriptor];blendPass.colorAttachments[0].texture=lit;
        blendPass.colorAttachments[0].loadAction=MTLLoadActionLoad;blendPass.colorAttachments[0].storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> composite=[cb renderCommandEncoderWithDescriptor:blendPass];composite.label=@"Depth-aware exhaust reconstruction";
        [composite setRenderPipelineState:trailCompositePipeline];[composite setFragmentTexture:trailLayer atIndex:0];[composite setFragmentTexture:depth atIndex:1];
        [composite drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[composite endEncoding];
    }
    if(count){
        MTLRenderPassDescriptor *flamePass=[MTLRenderPassDescriptor renderPassDescriptor];flamePass.colorAttachments[0].texture=lit;flamePass.colorAttachments[0].loadAction=MTLLoadActionLoad;flamePass.colorAttachments[0].storeAction=MTLStoreActionStore;
        flamePass.depthAttachment.texture=depth;flamePass.depthAttachment.loadAction=MTLLoadActionLoad;flamePass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:flamePass];r.label=@"Nozzle flame cores";
        [r setDepthStencilState:flameDepth];[r setCullMode:MTLCullModeNone];[r setRenderPipelineState:flamePipeline];
        [r setVertexBytes:&f length:sizeof(f) atIndex:0];[r setVertexBytes:&step length:sizeof(step) atIndex:1];[r setVertexBytes:jets.data() length:sizeof(jets) atIndex:2];
        [r setFragmentBytes:&f length:sizeof(f) atIndex:0];[r setFragmentTexture:depth atIndex:0];[r setFragmentTexture:_cloudNoise atIndex:1];
        [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:count];[r endEncoding];
    }
}
- (void)encodePresent:(id<MTLCommandBuffer>)cb drawable:(id<CAMetalDrawable>)drawable {
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];e.label=@"HDR bloom";[e setComputePipelineState:extractKernel];[e setTexture:lit atIndex:0];[e setTexture:bloom[0] atIndex:1];[self dispatch:e texture:bloom[0]];
    [e setComputePipelineState:blurKernel];uint32_t vertical=0;[e setBytes:&vertical length:sizeof(vertical) atIndex:0];[e setTexture:bloom[0] atIndex:0];[e setTexture:bloom[1] atIndex:1];[self dispatch:e texture:bloom[1]];
    vertical=1;[e setBytes:&vertical length:sizeof(vertical) atIndex:0];[e setTexture:bloom[1] atIndex:0];[e setTexture:bloom[0] atIndex:1];[self dispatch:e texture:bloom[0]];[e endEncoding];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];r.label=@"Tone mapping at full output resolution";[r setRenderPipelineState:presentPipeline];[r setFragmentTexture:lit atIndex:0];[r setFragmentTexture:bloom[0] atIndex:1];[r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[r endEncoding];
}
- (NSUInteger)liveTrailPuffCount {return exhaustTrail.puffs().size();}
- (NSString *)weatherName{return @[@"Clear",@"Scattered",@"Overcast",@"Storm"][_weather];}
- (void)reset {historyValid=NO;haveFlight=NO;exhaustTrail.reset();}
- (void)resetForReferenceChange {historyValid=NO;haveFlight=NO;}
@end

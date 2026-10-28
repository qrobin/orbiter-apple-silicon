#import "NativeVisuals.h"
#include "Exhaust.h"
#include <algorithm>
#include <array>
#include <cmath>
using namespace native;
static simd_float4 visualVector(Vector v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
static void visualCheck(id object,NSError *error){if(!object)@throw [NSException exceptionWithName:@"Metal visual pipeline error" reason:error.localizedDescription?:@"Unable to allocate a Metal resource" userInfo:nil];}
@interface NativeVisuals () {
    id<MTLDevice> gpu;
    NSUInteger samples,width,height,historyIndex,frameIndex;
    BOOL historyValid,haveFlight;
    FrameUniforms lastFrame;
    Vector lastPosition;
    double lastElapsed;
    NSInteger lastWeather;
    id<MTLTexture> hdr,lit,depth,msaaColor,msaaDepth;
    std::array<id<MTLTexture>,2> cloudHistory,cloudData,bloom;
    id<MTLBuffer> particleBuffer;
    id<MTLComputePipelineState> noiseKernel,shadowKernel,cloudKernel,particleKernel,extractKernel,blurKernel;
    id<MTLRenderPipelineState> compositePipeline,flamePipeline,particlePipeline,presentPipeline;
    id<MTLDepthStencilState> effectDepth;
}
@end
@implementation NativeVisuals
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library queue:(id<MTLCommandQueue>)queue samples:(NSUInteger)count {
    if(!(self=[super init]))return nil;gpu=device;samples=count;_weather=1;lastWeather=-1;
    NSError *error=nil;
    auto kernel=[&](NSString *name){id<MTLComputePipelineState> p=[gpu newComputePipelineStateWithFunction:[library newFunctionWithName:name] error:&error];visualCheck(p,error);return p;};
    noiseKernel=kernel(@"makeCloudNoise");shadowKernel=kernel(@"cloudShadowMap");cloudKernel=kernel(@"marchClouds");
    particleKernel=kernel(@"updateExhaust");extractKernel=kernel(@"extractBloom");blurKernel=kernel(@"blurBloom");
    auto pipeline=[&](NSString *vertex,NSString *fragment,MTLPixelFormat format,BOOL depthEnabled,BOOL additive){
        MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:vertex];p.fragmentFunction=[library newFunctionWithName:fragment];
        p.colorAttachments[0].pixelFormat=format;
        if(depthEnabled)p.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        if(additive){p.colorAttachments[0].blendingEnabled=YES;p.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;p.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOne;p.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorZero;p.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOne;}
        id<MTLRenderPipelineState> result=[gpu newRenderPipelineStateWithDescriptor:p error:&error];visualCheck(result,error);return result;
    };
    compositePipeline=pipeline(@"skyVertex",@"compositeClouds",MTLPixelFormatRGBA16Float,NO,NO);
    flamePipeline=pipeline(@"flameVertex",@"exhaustFragment",MTLPixelFormatRGBA16Float,YES,YES);
    particlePipeline=pipeline(@"particleVertex",@"exhaustFragment",MTLPixelFormatRGBA16Float,YES,YES);
    presentPipeline=pipeline(@"skyVertex",@"toneMap",MTLPixelFormatBGRA8Unorm_sRGB,NO,NO);
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=NO;effectDepth=[gpu newDepthStencilStateWithDescriptor:ds];
    MTLTextureDescriptor *n=[MTLTextureDescriptor new];n.textureType=MTLTextureType3D;n.width=n.height=n.depth=128;n.pixelFormat=MTLPixelFormatRGBA8Unorm;n.storageMode=MTLStorageModePrivate;n.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    _cloudNoise=[gpu newTextureWithDescriptor:n];visualCheck(_cloudNoise,nil);
    _cloudShadows=[self texture:MTLPixelFormatR8Unorm width:512 height:256 usage:MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite];
    particleBuffer=[gpu newBufferWithLength:4096*sizeof(ParticleUniforms) options:MTLResourceStorageModeShared];visualCheck(particleBuffer,nil);
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
    f->clouds=presets[_weather];
    float moved=simd_length(simd_make_float3(f->position.x-lastFrame.position.x,f->position.y-lastFrame.position.y,f->position.z-lastFrame.position.z))*EarthRadius;
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
        if(count==jets.size())break;auto shape=plumeShape(flight.altitude(),jet.kind);int kind=(int)jet.kind;
        double length=kind==0?12:kind==1?3:kind==2?6:.85;
        jets[count++]={visualVector(world(jet.position),jet.level),visualVector(world(jet.direction),jet.radius),{(float)kind,(float)length,(float)(shape.speed*.28),(float)shape.spread}};
    }
    _emitterCount=count;double dt=haveFlight?flight.elapsed-lastElapsed:0;Vector translation=haveFlight?lastPosition-flight.position:Vector(0,0,0);
    bool reset=!haveFlight||dt<0||dt>.25||translation.length()>5000;
    EffectUniforms step{};step.clock={(float)(reset?0:dt),(float)fmod(flight.elapsed,4096.),(float)fmod(lastElapsed,4096.),(float)count};
    if(fmod(flight.elapsed,4096.)<fmod(lastElapsed,4096.))reset=true;
    step.translation=visualVector(translation,reset?1:0);step.velocity=visualVector(flight.velocity);step.offset=visualVector(offset);
    step.gravity=visualVector(-flight.position.unit()*(Mu/(flight.position.length2())));
    lastPosition=flight.position;lastElapsed=flight.elapsed;haveFlight=YES;
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];e.label=@"Thrust-driven GPU exhaust";[e setComputePipelineState:particleKernel];
    [e setBuffer:particleBuffer offset:0 atIndex:0];[e setBytes:jets.data() length:sizeof(jets) atIndex:1];[e setBytes:&step length:sizeof(step) atIndex:2];[e dispatchThreads:MTLSizeMake(4096,1,1) threadsPerThreadgroup:MTLSizeMake(64,1,1)];[e endEncoding];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=lit;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionLoad;pass.depthAttachment.storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];r.label=@"Nozzle flame cores and soft particles";[r setDepthStencilState:effectDepth];[r setCullMode:MTLCullModeNone];
    [r setVertexBytes:&f length:sizeof(f) atIndex:0];[r setVertexBytes:&step length:sizeof(step) atIndex:1];[r setFragmentBytes:&f length:sizeof(f) atIndex:0];[r setFragmentTexture:depth atIndex:0];[r setFragmentTexture:_cloudNoise atIndex:1];
    if(count){[r setRenderPipelineState:flamePipeline];[r setVertexBytes:jets.data() length:sizeof(jets) atIndex:2];[r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:12*12*6*2 instanceCount:count];}
    [r setRenderPipelineState:particlePipeline];[r setVertexBuffer:particleBuffer offset:0 atIndex:2];[r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:4096];[r endEncoding];
}
- (void)encodePresent:(id<MTLCommandBuffer>)cb drawable:(id<CAMetalDrawable>)drawable {
    id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];e.label=@"HDR bloom";[e setComputePipelineState:extractKernel];[e setTexture:lit atIndex:0];[e setTexture:bloom[0] atIndex:1];[self dispatch:e texture:bloom[0]];
    [e setComputePipelineState:blurKernel];uint32_t vertical=0;[e setBytes:&vertical length:sizeof(vertical) atIndex:0];[e setTexture:bloom[0] atIndex:0];[e setTexture:bloom[1] atIndex:1];[self dispatch:e texture:bloom[1]];
    vertical=1;[e setBytes:&vertical length:sizeof(vertical) atIndex:0];[e setTexture:bloom[1] atIndex:0];[e setTexture:bloom[0] atIndex:1];[self dispatch:e texture:bloom[0]];[e endEncoding];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=drawable.texture;pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];r.label=@"Tone mapping at full output resolution";[r setRenderPipelineState:presentPipeline];[r setFragmentTexture:lit atIndex:0];[r setFragmentTexture:bloom[0] atIndex:1];[r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[r endEncoding];
}
- (NSUInteger)liveParticleCount {NSUInteger n=0;const auto *p=(const ParticleUniforms *)particleBuffer.contents;for(int i=0;i<4096;++i)if(p[i].positionAge.w>=0&&p[i].positionAge.w<p[i].velocityLife.w)++n;return n;}
- (NSString *)weatherName{return @[@"Clear",@"Scattered",@"Overcast",@"Storm"][_weather];}
- (void)reset {historyValid=NO;haveFlight=NO;}
@end

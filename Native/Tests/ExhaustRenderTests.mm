#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "VisualTypes.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

static void require(bool condition,const char *message){if(!condition){fprintf(stderr,"%s\n",message);exit(1);}}
int main(){@autoreleasepool{
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device){puts("No Metal device; skipping exhaust render test");return 77;}
    id<MTLCommandQueue> queue=[device newCommandQueue];NSError *error=nil;
    NSString *root=@ORBITER_TEST_DATA;
    NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];
        require(part!=nil,"Unable to read Metal source");[source appendString:part];[source appendString:@"\n"];
    }
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){fprintf(stderr,"Metal shader compilation failed: %s\n",error.localizedDescription.UTF8String);return 1;}
    auto makePipeline=[&](NSString *vertex,NSString *fragment,int blend){
        MTLRenderPipelineDescriptor *desc=[MTLRenderPipelineDescriptor new];
        desc.vertexFunction=[library newFunctionWithName:vertex];desc.fragmentFunction=[library newFunctionWithName:fragment];
        desc.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;desc.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        desc.colorAttachments[0].blendingEnabled=YES;desc.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor=blend==1?MTLBlendFactorOne:MTLBlendFactorOneMinusSourceAlpha;
        id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:desc error:&error];
        if(!pipeline){fprintf(stderr,"Metal pipeline failed: %s\n",error.localizedDescription.UTF8String);exit(1);}return pipeline;
    };
    auto flame=makePipeline(@"flameVertex",@"flameFragment",1),smoke=makePipeline(@"smokeVertex",@"smokeFragment",2);
    id<MTLComputePipelineState> noiseKernel=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"makeCloudNoise"] error:&error];require(noiseKernel!=nil,"Noise kernel failed");
    constexpr NSUInteger width=320,height=180;MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    desc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;desc.storageMode=MTLStorageModeShared;id<MTLTexture> color=[device newTextureWithDescriptor:desc];
    desc.pixelFormat=MTLPixelFormatDepth32Float;desc.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[device newTextureWithDescriptor:desc];
    desc=[MTLTextureDescriptor new];desc.textureType=MTLTextureType3D;desc.width=desc.height=desc.depth=32;desc.pixelFormat=MTLPixelFormatRGBA8Unorm;
    desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;id<MTLTexture> noise=[device newTextureWithDescriptor:desc];
    require(color&&depth&&noise,"Metal texture allocation failed");
    MTLDepthStencilDescriptor *stateDesc=[MTLDepthStencilDescriptor new];stateDesc.depthCompareFunction=MTLCompareFunctionAlways;stateDesc.depthWriteEnabled=NO;id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:stateDesc];
    FrameUniforms frame{};float halfFov=std::tan(50.*M_PI/360.);
    frame.projection.columns[0]={1.f/((float(width)/height)*halfFov),0,0,0};frame.projection.columns[1]={0,1.f/halfFov,0,0};
    frame.projection.columns[2]={0,0,0,-1};frame.projection.columns[3]={0,0,.2,0};
    frame.right={1,0,0,0};frame.up={0,1,0,0};frame.forward={0,0,1,0};frame.position={0,0,1,0};frame.sun={0,1,0,1};
    frame.screen={(float)width,(float)height,halfFov,0};frame.body={6371000,1,13000,0};
    id<MTLCommandBuffer> prepare=[queue commandBuffer];id<MTLComputeCommandEncoder> compute=[prepare computeCommandEncoder];
    [compute setComputePipelineState:noiseKernel];[compute setTexture:noise atIndex:0];
    [compute dispatchThreads:MTLSizeMake(32,32,32) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[compute endEncoding];[prepare commit];[prepare waitUntilCompleted];require(prepare.error==nil,"Noise generation failed");
    auto render=[&](EmitterUniforms jet,float time,float depthClear,bool drawSmoke,float smokeOpacity){
        EffectUniforms effects{};effects.clock={.016f,time,time-.016f,1};
        ParticleUniforms puff{{0,0,32,.2f},{1,0,0,2},{2,smokeOpacity,.37f,0}};
        id<MTLBuffer> puffBuffer=[device newBufferWithBytes:&puff length:sizeof(puff) options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *clearDepth=[MTLRenderPassDescriptor renderPassDescriptor];
        clearDepth.depthAttachment.texture=depth;clearDepth.depthAttachment.loadAction=MTLLoadActionClear;clearDepth.depthAttachment.storeAction=MTLStoreActionStore;clearDepth.depthAttachment.clearDepth=depthClear;
        id<MTLRenderCommandEncoder> clear=[cb renderCommandEncoderWithDescriptor:clearDepth];[clear endEncoding];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);pass.depthAttachment.texture=depth;
        pass.depthAttachment.loadAction=MTLLoadActionLoad;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];[r setDepthStencilState:depthState];[r setCullMode:MTLCullModeNone];
        [r setVertexBytes:&frame length:sizeof(frame) atIndex:0];[r setFragmentBytes:&frame length:sizeof(frame) atIndex:0];
        [r setFragmentTexture:depth atIndex:0];[r setFragmentTexture:noise atIndex:1];
        if(drawSmoke){[r setRenderPipelineState:smoke];[r setVertexBuffer:puffBuffer offset:0 atIndex:1];}
        else{[r setRenderPipelineState:flame];[r setVertexBytes:&effects length:sizeof(effects) atIndex:1];[r setVertexBytes:&jet length:sizeof(jet) atIndex:2];}
        [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];[r endEncoding];[cb commit];[cb waitUntilCompleted];
        if(cb.error){fprintf(stderr,"Metal render failed: %s\n",cb.error.localizedDescription.UTF8String);exit(1);}
        std::vector<unsigned char> pixels(width*height*4);[color getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto energy=[](const std::vector<unsigned char>&p){uint64_t sum=0;for(size_t i=0;i<p.size();i+=4)sum+=p[i]+p[i+1]+p[i+2];return sum;};
    EmitterUniforms side{{-6,0,32,1},{1,0,0,.8f},{0,12,100,.035f}};
    auto first=render(side,30,0,false,0),later=render(side,30.33,0,false,0);
    require(energy(first)>5000,"Side-on flame must be visible");size_t changes=0;for(size_t i=0;i<first.size();i+=4)if(first[i]!=later[i]||first[i+1]!=later[i+1]||first[i+2]!=later[i+2])++changes;
    require(changes>20,"Flame turbulence must animate");
    EmitterUniforms endOn{{0,0,32,1},{0,0,-1,.8f},{0,12,100,.035f}};
    require(energy(render(endOn,30,0,false,0))>1000,"End-on flame must remain visible");
    require(energy(render(endOn,30,.2f/26,false,0))>200,"A flame in front of nearby geometry must remain partially visible");
    EmitterUniforms inside{{0,0,5,1},{0,0,-1,.8f},{0,12,100,.035f}};
    require(energy(render(inside,30,0,false,0))>1000,"A flame must remain visible when the camera is inside it");
    require(energy(render(side,30,.04,false,0))==0,"Depth must hide flames behind foreground geometry");
    auto thick=energy(render(side,30,0,true,.3f)),thin=energy(render(side,30,0,true,.03f));
    require(thick>1000&&thick>thin*3,"Smoke must render and fade with opacity");
    printf("Metal exhaust visibility, animation, occlusion and smoke checks passed on %s\n",device.name.UTF8String);
    return 0;
}}

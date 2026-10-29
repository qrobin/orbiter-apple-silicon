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
    [source appendString:@"\nvertex float4 testDepthVertex(uint i [[vertex_id]]) { float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)}; return float4(p[i],.04,1); }\n"];
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){fprintf(stderr,"Metal shader compilation failed: %s\n",error.localizedDescription.UTF8String);return 1;}
    auto makePipeline=[&](NSString *vertex,NSString *fragment,int blend,bool hasDepth){
        MTLRenderPipelineDescriptor *desc=[MTLRenderPipelineDescriptor new];
        desc.vertexFunction=[library newFunctionWithName:vertex];desc.fragmentFunction=[library newFunctionWithName:fragment];
        desc.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;if(hasDepth)desc.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        desc.colorAttachments[0].blendingEnabled=YES;desc.colorAttachments[0].sourceRGBBlendFactor=blend==3?MTLBlendFactorOne:MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].destinationRGBBlendFactor=blend==1?MTLBlendFactorOne:MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor=blend==2?MTLBlendFactorOne:MTLBlendFactorZero;
        desc.colorAttachments[0].destinationAlphaBlendFactor=blend==2?MTLBlendFactorOneMinusSourceAlpha:MTLBlendFactorOne;
        id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:desc error:&error];
        if(!pipeline){fprintf(stderr,"Metal pipeline failed: %s\n",error.localizedDescription.UTF8String);exit(1);}return pipeline;
    };
    auto flame=makePipeline(@"flameVertex",@"flameFragment",1,true),smoke=makePipeline(@"trailVolumeVertex",@"trailVolumeFragment",2,false);
    auto composite=makePipeline(@"skyVertex",@"compositeTrail",3,false);
    MTLRenderPipelineDescriptor *depthDesc=[MTLRenderPipelineDescriptor new];depthDesc.vertexFunction=[library newFunctionWithName:@"testDepthVertex"];depthDesc.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> depthPipeline=[device newRenderPipelineStateWithDescriptor:depthDesc error:&error];require(depthPipeline!=nil,"Depth fixture pipeline failed");
    id<MTLComputePipelineState> noiseKernel=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"makeCloudNoise"] error:&error];require(noiseKernel!=nil,"Noise kernel failed");
    constexpr NSUInteger width=320,height=180;MTLTextureDescriptor *desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
    desc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;desc.storageMode=MTLStorageModeShared;id<MTLTexture> color=[device newTextureWithDescriptor:desc];
    desc.pixelFormat=MTLPixelFormatDepth32Float;desc.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[device newTextureWithDescriptor:desc];
    desc=[MTLTextureDescriptor new];desc.textureType=MTLTextureType3D;desc.width=desc.height=desc.depth=32;desc.pixelFormat=MTLPixelFormatRGBA8Unorm;
    desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;id<MTLTexture> noise=[device newTextureWithDescriptor:desc];
    require(color&&depth&&noise,"Metal texture allocation failed");
    MTLDepthStencilDescriptor *stateDesc=[MTLDepthStencilDescriptor new];stateDesc.depthCompareFunction=MTLCompareFunctionAlways;stateDesc.depthWriteEnabled=NO;id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:stateDesc];
    stateDesc.depthWriteEnabled=YES;id<MTLDepthStencilState> depthWriter=[device newDepthStencilStateWithDescriptor:stateDesc];
    FrameUniforms frame{};float halfFov=std::tan(50.*M_PI/360.);
    frame.projection.columns[0]={1.f/((float(width)/height)*halfFov),0,0,0};frame.projection.columns[1]={0,1.f/halfFov,0,0};
    frame.projection.columns[2]={0,0,0,-1};frame.projection.columns[3]={0,0,.2,0};
    frame.right={1,0,0,0};frame.up={0,1,0,0};frame.forward={0,0,1,0};frame.position={0,0,1,0};frame.sun={0,1,0,1};
    frame.screen={(float)width,(float)height,halfFov,0};frame.body={6371000,1,13000,0};
    id<MTLCommandBuffer> prepare=[queue commandBuffer];id<MTLComputeCommandEncoder> compute=[prepare computeCommandEncoder];
    [compute setComputePipelineState:noiseKernel];[compute setTexture:noise atIndex:0];
    [compute dispatchThreads:MTLSizeMake(32,32,32) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[compute endEncoding];[prepare commit];[prepare waitUntilCompleted];require(prepare.error==nil,"Noise generation failed");
    auto render=[&](EmitterUniforms jet,float time,float depthClear,bool drawSmoke,float smokeOpacity,bool endOnTrail=false){
        EffectUniforms effects{};effects.clock={.016f,time,time-.016f,1};
        TrailSegmentUniforms volume{{-6,0,32,2},{6,0,32,2},{smokeOpacity,smokeOpacity,3,3},{0,0,0,0}};
        if(endOnTrail){volume.startRadius={0,0,25,2};volume.endRadius={0,0,35,2};}
        id<MTLBuffer> puffBuffer=[device newBufferWithBytes:&volume length:sizeof(volume) options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *clearDepth=[MTLRenderPassDescriptor renderPassDescriptor];
        clearDepth.depthAttachment.texture=depth;clearDepth.depthAttachment.loadAction=MTLLoadActionClear;clearDepth.depthAttachment.storeAction=MTLStoreActionStore;clearDepth.depthAttachment.clearDepth=depthClear;
        id<MTLRenderCommandEncoder> clear=[cb renderCommandEncoderWithDescriptor:clearDepth];[clear endEncoding];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);
        if(!drawSmoke){pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionLoad;pass.depthAttachment.storeAction=MTLStoreActionStore;}
        id<MTLRenderCommandEncoder> r=[cb renderCommandEncoderWithDescriptor:pass];if(!drawSmoke)[r setDepthStencilState:depthState];[r setCullMode:MTLCullModeNone];
        [r setVertexBytes:&frame length:sizeof(frame) atIndex:0];[r setFragmentBytes:&frame length:sizeof(frame) atIndex:0];
        [r setFragmentTexture:depth atIndex:0];[r setFragmentTexture:noise atIndex:1];
        if(drawSmoke){[r setRenderPipelineState:smoke];[r setVertexBuffer:puffBuffer offset:0 atIndex:1];[r setVertexTexture:noise atIndex:0];}
        else{[r setRenderPipelineState:flame];[r setVertexBytes:&effects length:sizeof(effects) atIndex:1];[r setVertexBytes:&jet length:sizeof(jet) atIndex:2];}
        [r drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:drawSmoke?12*18:6];[r endEncoding];[cb commit];[cb waitUntilCompleted];
        if(cb.error){fprintf(stderr,"Metal render failed: %s\n",cb.error.localizedDescription.UTF8String);exit(1);}
        std::vector<unsigned char> pixels(width*height*4);[color getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto energy=[](const std::vector<unsigned char>&p){uint64_t sum=0;for(size_t i=0;i<p.size();i+=4)sum+=p[i]+p[i+1]+p[i+2];return sum;};
    EmitterUniforms side{{-6,0,32,1},{1,0,0,.8f},{0,12,100,.035f}};
    auto first=render(side,30,0,false,0),later=render(side,30.33,0,false,0);
    require(energy(first)>5000,"Side-on flame must be visible");size_t changes=0;for(size_t i=0;i<first.size();i+=4)if(first[i]!=later[i]||first[i+1]!=later[i+1]||first[i+2]!=later[i+2])++changes;
    require(changes>20,"Flame turbulence must animate");
    auto quickly=render(side,30.03,0,false,0);size_t rapidChanges=0;
    for(size_t i=0;i<first.size();i+=4)if(first[i]!=quickly[i]||first[i+1]!=quickly[i+1]||first[i+2]!=quickly[i+2])++rapidChanges;
    require(rapidChanges>20,"Combustion flow changes visibly within a few frames");
    EmitterUniforms endOn{{0,0,32,1},{0,0,-1,.8f},{0,12,100,.035f}};
    require(energy(render(endOn,30,0,false,0))>1000,"End-on flame must remain visible");
    require(energy(render(endOn,30,.2f/26,false,0))>200,"A flame in front of nearby geometry must remain partially visible");
    EmitterUniforms inside{{0,0,5,1},{0,0,-1,.8f},{0,12,100,.035f}};
    require(energy(render(inside,30,0,false,0))>1000,"A flame must remain visible when the camera is inside it");
    require(energy(render(side,30,.04,false,0))==0,"Depth must hide flames behind foreground geometry");
    auto thick=energy(render(side,30,0,true,.3f)),thin=energy(render(side,30,0,true,.03f));
    require(thick>1000&&thick>thin*3,"Smoke must render and fade with opacity");
    auto volume=render(side,30,0,true,.3f);uint64_t outside=0;
    for(size_t y=0;y<height;++y)for(size_t x=0;x<width;++x)if(x<117||x>203){size_t i=(y*width+x)*4;outside+=volume[i]+volume[i+1]+volume[i+2];}
    require(outside==0,"A world-space volume must not stretch past its endpoints");
    auto axialEnergy=energy(render(side,30,0,true,.3f,true));if(axialEnergy<=1000)fprintf(stderr,"End-on trail energy: %llu\n",(unsigned long long)axialEnergy);
    require(axialEnergy>1000,"The gas volume must remain visible when viewed down its axis");
    require(energy(render(side,30,.04,true,.3f))==0,"Foreground geometry must occlude the exhaust volume");
    // Exercise the half-resolution volume pass and the production upsampling blend.
    MTLTextureDescriptor *halfDesc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width/2 height:height/2 mipmapped:NO];
    halfDesc.storageMode=MTLStorageModePrivate;halfDesc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;id<MTLTexture> half=[device newTextureWithDescriptor:halfDesc];
    TrailSegmentUniforms sample{{-6,0,32,2},{6,0,32,2},{.3f,.3f,3,3},{0,0,0,0}};
    id<MTLBuffer> sampleBuffer=[device newBufferWithBytes:&sample length:sizeof(sample) options:MTLResourceStorageModeShared];
    FrameUniforms halfFrame=frame;halfFrame.screen.x=width/2;halfFrame.screen.y=height/2;
    auto reconstruct=[&](bool occlude){
    id<MTLCommandBuffer> reconstruction=[queue commandBuffer];MTLRenderPassDescriptor *depthPass=[MTLRenderPassDescriptor renderPassDescriptor];
    depthPass.depthAttachment.texture=depth;depthPass.depthAttachment.loadAction=MTLLoadActionClear;depthPass.depthAttachment.storeAction=MTLStoreActionStore;depthPass.depthAttachment.clearDepth=occlude?.002:0;
    id<MTLRenderCommandEncoder> encoder=[reconstruction renderCommandEncoderWithDescriptor:depthPass];
    if(occlude){[encoder setRenderPipelineState:depthPipeline];[encoder setDepthStencilState:depthWriter];[encoder setViewport:MTLViewport{0,0,width/2,height,0,1}];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];}
    [encoder endEncoding];
    MTLRenderPassDescriptor *halfPass=[MTLRenderPassDescriptor renderPassDescriptor];halfPass.colorAttachments[0].texture=half;
    halfPass.colorAttachments[0].loadAction=MTLLoadActionClear;halfPass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);halfPass.colorAttachments[0].storeAction=MTLStoreActionStore;
    encoder=[reconstruction renderCommandEncoderWithDescriptor:halfPass];[encoder setRenderPipelineState:smoke];[encoder setCullMode:MTLCullModeNone];
    [encoder setVertexBytes:&halfFrame length:sizeof(halfFrame) atIndex:0];[encoder setVertexBuffer:sampleBuffer offset:0 atIndex:1];[encoder setVertexTexture:noise atIndex:0];[encoder setFragmentBytes:&halfFrame length:sizeof(halfFrame) atIndex:0];
    [encoder setFragmentTexture:depth atIndex:0];[encoder setFragmentTexture:noise atIndex:1];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:12*18];[encoder endEncoding];
    MTLRenderPassDescriptor *fullPass=[MTLRenderPassDescriptor renderPassDescriptor];fullPass.colorAttachments[0].texture=color;
    fullPass.colorAttachments[0].loadAction=MTLLoadActionClear;fullPass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);fullPass.colorAttachments[0].storeAction=MTLStoreActionStore;
    encoder=[reconstruction renderCommandEncoderWithDescriptor:fullPass];[encoder setRenderPipelineState:composite];[encoder setFragmentTexture:half atIndex:0];[encoder setFragmentTexture:depth atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[encoder endEncoding];[reconstruction commit];[reconstruction waitUntilCompleted];require(reconstruction.error==nil,"Trail reconstruction failed");
    std::vector<unsigned char> reconstructed(width*height*4);[color getBytes:reconstructed.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];
    return reconstructed;
    };
    auto reconstructed=reconstruct(false);require(energy(reconstructed)>1000,"Half-resolution volume survives depth-aware reconstruction");
    auto edge=reconstruct(true);uint64_t occludedEnergy=0,visibleEnergy=0;
    for(size_t y=0;y<height;++y)for(size_t x=0;x<width;++x){size_t i=(y*width+x)*4;uint64_t e=edge[i]+edge[i+1]+edge[i+2];if(x<width/2-2)occludedEnergy+=e;else if(x>width/2+2)visibleEnergy+=e;}
    require(occludedEnergy==0&&visibleEnergy>100,"Depth-aware reconstruction must not leak exhaust across a foreground edge");
    printf("Metal volumetric exhaust visibility, animation, bounds, occlusion and fading checks passed on %s\n",device.name.UTF8String);
    return 0;
}}

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include "VisualTypes.h"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA;NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"Missing shader source");[source appendFormat:@"%@\n",part];}
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];if(!library)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(library!=nil,"Metal shader compilation");
    id<MTLComputePipelineState> adapt=[gpu newComputePipelineStateWithFunction:[library newFunctionWithName:@"adaptSolarExposure"] error:&error];check(adapt!=nil,"Exposure pipeline");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"skyVertex"];pd.fragmentFunction=[library newFunctionWithName:@"toneMap"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA32Float;
    id<MTLRenderPipelineState> tone=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(tone!=nil,"Tone mapping pipeline");
    auto texture=[&](MTLPixelFormat format,int w,int h,MTLTextureUsage usage){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];d.usage=usage;d.storageMode=MTLStorageModeShared;return [gpu newTextureWithDescriptor:d];};
    constexpr int size=64;id<MTLTexture> scene=texture(MTLPixelFormatRGBA32Float,size,size,MTLTextureUsageShaderRead),bloom=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead),exposure=texture(MTLPixelFormatR32Float,1,1,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite),output=texture(MTLPixelFormatRGBA32Float,size,size,MTLTextureUsageRenderTarget);
    std::vector<float> pixels(size*size*4,1);for(int y=28;y<36;++y)for(int x=28;x<36;++x)for(int c=0;c<3;++c)pixels[(y*size+x)*4+c]=50;
    [scene replaceRegion:MTLRegionMake2D(0,0,size,size) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:size*16];float black[4]={0,0,0,1};[bloom replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:black bytesPerRow:16];float initial=1;[exposure replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&initial bytesPerRow:4];
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,1,0};f.sun={0,0,1,1};f.sunShape={.00465,1,0,1};f.screen={size,size,.466,0};
    id<MTLCommandQueue> queue=[gpu newCommandQueue];float dt=.1;
    auto update=[&](int steps){id<MTLCommandBuffer> cb=[queue commandBuffer];for(int i=0;i<steps;++i){id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];[e setComputePipelineState:adapt];[e setTexture:scene atIndex:0];[e setTexture:exposure atIndex:1];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&dt length:sizeof(dt) atIndex:1];[e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[e endEncoding];}[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"Exposure update failed");float v;[exposure getBytes:&v bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];return v;};
    float darkened=update(30);check(darkened>.41&&darkened<.44,"Visible Sun gradually reduces exposure");
    auto unobscured=pixels;std::fill(pixels.begin(),pixels.end(),1);[scene replaceRegion:MTLRegionMake2D(0,0,size,size) mipmapLevel:0 withBytes:pixels.data() bytesPerRow:size*16];
    float recovered=update(60);check(recovered>.995,"An obscured solar disc lets exposure recover");
    [scene replaceRegion:MTLRegionMake2D(0,0,size,size) mipmapLevel:0 withBytes:unobscured.data() bytesPerRow:size*16];
    f.sun.w=0;check(update(10)>.995,"Eclipse does not darken exposure");f.sun.w=1;f.sun={1,0,0,1};check(update(10)>.995,"Sun outside the view does not darken exposure");
    auto render=[&](float headroom){id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:tone];[e setFragmentBytes:&headroom length:sizeof(headroom) atIndex:0];[e setFragmentTexture:scene atIndex:0];[e setFragmentTexture:bloom atIndex:1];[e setFragmentTexture:exposure atIndex:2];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"Tone mapping failed");float p[4];[output getBytes:p bytesPerRow:16 fromRegion:MTLRegionMake2D(32,32,1,1) mipmapLevel:0];return p[0];};
    float sdr=render(1),hdr=render(3);check(sdr<=1.001&&sdr>.9&&hdr>2.0&&hdr<=3.001,"HDR highlights exceed SDR white within display headroom");
    std::cout<<"Exposure "<<darkened<<" -> "<<recovered<<"; SDR "<<sdr<<", EDR "<<hdr<<'\n';return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

#import <Metal/Metal.h>
#include "VisualTypes.h"
#include <array>
#include <iostream>
#include <stdexcept>
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
struct Vertex {float position[3],normal[3],uv[2];};
struct Object {simd_float4x4 model;simd_float4 color,options,specular,emission;};
int main(){@autoreleasepool{try{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSMutableString *source=[NSMutableString string];NSError *error=nil;
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[@ORBITER_TEST_DATA stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"missing shader source");[source appendFormat:@"%@\n",part];
    }
    id<MTLLibrary> lib=[gpu newLibraryWithSource:source options:nil error:&error];if(!lib)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(lib!=nil,"reflection shaders compile");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"vesselReflectionVertex"];pd.fragmentFunction=[lib newFunctionWithName:@"vesselReflectionFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> pipeline=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(pipeline!=nil,"reflection pipeline");
    auto texture=[&](MTLPixelFormat format,int width,int height,MTLTextureUsage usage){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:width height:height mipmapped:NO];d.usage=usage;d.storageMode=MTLStorageModeShared;return [gpu newTextureWithDescriptor:d];};
    auto color=texture(MTLPixelFormatRGBA8Unorm,64,64,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead),depth=texture(MTLPixelFormatDepth32Float,64,64,MTLTextureUsageRenderTarget),white=texture(MTLPixelFormatRGBA8Unorm,1,1,MTLTextureUsageShaderRead);
    uint32_t opaque=0xffffffff;[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&opaque bytesPerRow:4];
    Vertex vertices[]={{{-.1f,-.1f,0},{0,1,0},{0,0}},{{.1f,-.1f,0},{0,1,0},{1,0}},{{.1f,.1f,0},{0,1,0},{1,1}},{{-.1f,-.1f,0},{0,1,0},{0,0}},{{.1f,.1f,0},{0,1,0},{1,1}},{{-.1f,.1f,0},{0,1,0},{0,1}}};
    FrameUniforms f{};f.projection=matrix_identity_float4x4;f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.sun={0,1,0,1};f.waterPlane={0,1,0,0};
    Object object{};object.model=matrix_identity_float4x4;object.color={1,1,1,1};
    id<MTLCommandQueue> queue=[gpu newCommandQueue];id<MTLCommandBuffer> cb=[queue commandBuffer];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=YES;
    id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:pipeline];[e setDepthStencilState:[gpu newDepthStencilStateWithDescriptor:ds]];[e setVertexBytes:vertices length:sizeof(vertices) atIndex:0];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:white atIndex:1];
    // Two independent vessel instances use different transforms and planes.
    for(int i=0;i<2;++i){object.model.columns[3]={(i?0.5f:-0.5f),.5f,.5f,1};f.waterPlane.w=i?.1f:0;
        [e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&object length:sizeof(object) atIndex:2];[e setFragmentBytes:&object length:sizeof(object) atIndex:2];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];}
    [e endEncoding];[cb commit];[cb waitUntilCompleted];if(cb.error)std::cerr<<cb.error.localizedDescription.UTF8String<<'\n';check(cb.error==nil,"reflection render");
    std::array<unsigned char,64*64*4> pixels{};[color getBytes:pixels.data() bytesPerRow:64*4 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];
    auto alpha=[&](int x,int y){return pixels[(y*64+x)*4+3];};
    check(alpha(16,48)>240&&alpha(48,42)>240,"both vessels reflect across their own water planes");
    check(alpha(16,16)==0&&alpha(48,16)==0,"vessels are mirrored rather than copied to their original positions");
    check(alpha(32,48)==0,"empty space remains transparent");
    std::cout<<"Independent vessel water reflections passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

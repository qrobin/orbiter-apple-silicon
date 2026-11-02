#import <Metal/Metal.h>
#include "VisualTypes.h"
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
    [source appendString:@"kernel void testGroundShadow(constant FrameUniforms &f [[buffer(0)]],device float *out [[buffer(1)]],texture2d<float> mask [[texture(0)]],uint i [[thread_position_in_grid]]) { float3 points[4]={float3(-60,0,-80),float3(-40,0,-80),float3(60,0,80),float3(-60,15,-80)}; out[i]=vesselSunVisibility(f,points[i],mask); }"];
    id<MTLLibrary> lib=[gpu newLibraryWithSource:source options:nil error:&error];if(!lib)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(lib!=nil,"shadow shaders compile");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"vesselShadowVertex"];pd.fragmentFunction=[lib newFunctionWithName:@"vesselShadowFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatR8Unorm;
    id<MTLRenderPipelineState> render=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(render!=nil,"shadow mask pipeline");
    id<MTLComputePipelineState> compute=[gpu newComputePipelineStateWithFunction:[lib newFunctionWithName:@"testGroundShadow"] error:&error];check(compute!=nil,"shadow sampling pipeline");
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:512 height:512 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;id<MTLTexture> mask=[gpu newTextureWithDescriptor:td];
    // A real projected rectangle, oriented in the Sun plane, acts as the hull.
    Vertex vertices[]={{{-4, -5, 3}},{{4,-5,-3}},{{4,5,-3}},{{-4,-5,3}},{{4,5,-3}},{{-4,5,3}}};
    FrameUniforms f{};f.sun={.6,0,.8,1};f.shadowOrigin={0,0,0,1};f.shadowAxisX={.8,0,-.6,0};f.shadowAxisY={0,1,0,0};
    Object object{};object.model=matrix_identity_float4x4;
    id<MTLBuffer> output=[gpu newBufferWithLength:4*sizeof(float) options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue=[gpu newCommandQueue];id<MTLCommandBuffer> cb=[queue commandBuffer];
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=mask;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:render];[e setVertexBytes:vertices length:sizeof(vertices) atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&object length:sizeof(object) atIndex:2];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];[e endEncoding];
    id<MTLComputeCommandEncoder> c=[cb computeCommandEncoder];[c setComputePipelineState:compute];[c setBytes:&f length:sizeof(f) atIndex:0];[c setBuffer:output offset:0 atIndex:1];[c setTexture:mask atIndex:0];[c dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];[c endEncoding];[cb commit];[cb waitUntilCompleted];if(cb.error)std::cerr<<cb.error.localizedDescription.UTF8String<<'\n';check(cb.error==nil,"shadow render and sampling");
    float *v=(float *)output.contents;check(v[0]<.05f,"surface behind the vessel along the Sun ray is shadowed");check(v[1]>.95f&&v[3]>.95f,"shadow follows the hull silhouette");check(v[2]>.95f,"surface on the Sun-facing side remains lit");
    std::cout<<"Sun-aligned vessel silhouette shadow passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

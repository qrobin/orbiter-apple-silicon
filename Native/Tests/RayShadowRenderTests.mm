#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "RayShadows.h"
#include "VisualTypes.h"
#include "Mesh.h"
#include "Glider.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace native;
struct Object {simd_float4x4 model;simd_float4 color,options,specular,emission;};
struct ShipFrame {simd_float4 right,up,forward,origin;};
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(![RayShadows supportsDevice:gpu])return 77;
    NSString *root=@ORBITER_TEST_DATA;NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"VisualTypes.h",@"NativeVisuals.metal",@"Shaders.metal",@"SolarSystem.metal",@"RayShadows.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[[root stringByAppendingPathComponent:@"Native/macOS"] stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];
    }
    id<MTLCommandQueue> queue=[gpu newCommandQueue];
    auto geometry=[&](const std::vector<Vertex> &vertices,const std::vector<uint32_t> &indices){
        MTLAccelerationStructureTriangleGeometryDescriptor *g=[MTLAccelerationStructureTriangleGeometryDescriptor descriptor];
        g.vertexBuffer=[gpu newBufferWithBytes:vertices.data() length:vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];g.vertexStride=sizeof(Vertex);g.vertexFormat=MTLAttributeFormatFloat3;
        g.indexBuffer=[gpu newBufferWithBytes:indices.data() length:indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];g.indexType=MTLIndexTypeUInt32;g.triangleCount=indices.size()/3;g.opaque=YES;return g;};
    std::vector<Vertex> blocker={{-.6f,-.6f,3,0,0,-1,0,0},{.6f,-.6f,3,0,0,-1,0,0},{.6f,.6f,3,0,0,-1,0,0},{-.6f,.6f,3,0,0,-1,0,0}};
    std::vector<uint32_t> indices={0,1,2,0,2,3};auto blockerGeometry=geometry(blocker,indices);
    RayShadows *ray=[[RayShadows alloc] initWithDevice:gpu queue:queue source:source geometry:@[blockerGeometry] samples:1 colorFormat:MTLPixelFormatRGBA8Unorm];
    check(ray&&ray.enabled&&ray.pipeline&&ray.structure,"Hardware ray-tracing pipeline and acceleration structure are available");
    check(![[RayShadows alloc] initWithDevice:gpu queue:queue source:source geometry:@[] samples:1 colorFormat:MTLPixelFormatRGBA8Unorm],"An empty scene falls back safely");
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];check(library!=nil,"Metal library failed");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"meshVertex"];pd.fragmentFunction=[library newFunctionWithName:@"meshFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> regular=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(regular!=nil,"Fallback pipeline failed");
    std::vector<Vertex> receiver={{-2,-2,5,0,0,-1,0,0},{2,-2,5,0,0,-1,1,0},{2,2,5,0,0,-1,1,1},{-2,2,5,0,0,-1,0,1}};
    id<MTLBuffer> vertexBuffer=[gpu newBufferWithBytes:receiver.data() length:receiver.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];id<MTLBuffer> indexBuffer=[gpu newBufferWithBytes:indices.data() length:indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    constexpr int width=256,height=256;MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;id<MTLTexture> image=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];td.usage=MTLTextureUsageShaderRead;td.storageMode=MTLStorageModeShared;id<MTLTexture> white=[gpu newTextureWithDescriptor:td];uint32_t pixel=0xffffffff;[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[gpu newDepthStencilStateWithDescriptor:ds];
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,1,0};f.sun={0,0,-1,1};f.position={0,1,0,0};f.screen={width,height,.466f,0};
    f.projection.columns[0]={1/.466f,0,0,0};f.projection.columns[1]={0,1/.466f,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2f,0};
    Object object{};object.model.columns[0]={1,0,0,0};object.model.columns[1]={0,1,0,0};object.model.columns[2]={0,0,1,0};object.model.columns[3]={0,0,0,1};object.color={1,1,1,1};
    ShipFrame ship={{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,0}};
    auto render=[&](bool traced,id<MTLTexture> planet=nil,id<MTLTexture> stars=nil){id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=image;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:traced?ray.pipeline:regular];[e setDepthStencilState:depthState];[e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:vertexBuffer offset:0 atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&object length:sizeof(object) atIndex:2];float dummy[12]={};[e setVertexBytes:dummy length:sizeof(dummy) atIndex:3];
        [e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&object length:sizeof(object) atIndex:2];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:white atIndex:1];[e setFragmentTexture:planet?:white atIndex:2];[e setFragmentTexture:white atIndex:3];[e setFragmentTexture:stars?:white atIndex:4];
        if(traced){[e setFragmentBytes:&ship length:sizeof(ship) atIndex:4];[e setFragmentAccelerationStructure:ray.structure atBufferIndex:5];[e useResource:ray.structure usage:MTLResourceUsageRead stages:MTLRenderStageFragment];}
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:indices.size() indexType:MTLIndexTypeUInt32 indexBuffer:indexBuffer indexBufferOffset:0];[e endEncoding];[cb commit];[cb waitUntilCompleted];if(cb.error)std::cerr<<cb.error.localizedDescription.UTF8String<<'\n';check(cb.error==nil,"Ray-shadow render failed");
        std::vector<uint8_t> pixels(width*height*4);[image getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
    auto fallback=render(false),traced=render(true);auto red=[](const auto &v,int x,int y){return int(v[(y*width+x)*4]);};
    check(red(fallback,128,128)>200&&red(traced,128,128)+70<red(fallback,128,128),"An occluding triangle blocks direct sunlight");
    check(abs(red(traced,50,128)-red(fallback,50,128))<3,"Unoccluded surfaces remain lit");
    auto solid=[&](uint32_t value){id<MTLTexture> t=[gpu newTextureWithDescriptor:td];[t replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&value bytesPerRow:4];return t;};
    id<MTLTexture> redWorld=solid(0xff0000ff),blueWorld=solid(0xffff0000),black=solid(0xff000000);
    f.position={0,0,2,0};f.body={6371010,0,13000,0};f.environment={1,6371010,0,0};f.equatorX={1,0,0,1};f.pole={0,1,0,0};f.equatorZ={0,0,1,0};f.sun={0,0,1,1};
    object.options.y=-1;object.specular={1,1,1,40};
    auto earthRed=render(false,redWorld,black),earthBlue=render(false,blueWorld,black);
    auto tracedRed=render(true,redWorld,black),tracedBlue=render(true,blueWorld,black);
    check(red(earthRed,128,128)>red(earthBlue,128,128)+10,"The hull reflects the planet facing it");
    check(red(tracedRed,128,128)>red(tracedBlue,128,128)+10,"Ray-shadowed hulls also reflect the planet");
    f.position={0,0,-2,0};auto skyRed=render(false,black,redWorld),skyBlue=render(false,black,blueWorld);
    check(red(skyRed,128,128)>red(skyBlue,128,128)+10,"The hull reflects the sky when it faces away from the planet");
    auto hull=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh");std::vector<bool> moving(hull.groups.size());
    for(const auto &a:Glider::animations())if(a.mesh==0)for(size_t index:a.groups)if(index<moving.size())moving[index]=true;
    NSMutableArray<MTLAccelerationStructureGeometryDescriptor *> *parts=[NSMutableArray new];size_t triangles=0;
    for(size_t i=0;i<hull.groups.size();++i){auto &g=hull.groups[i];if(!moving[i]&&hull.materials[g.material].diffuse[3]>=.99&&!g.indices.empty()){
        [parts addObject:geometry(g.vertices,g.indices)];triangles+=g.indices.size()/3;}}
    check(triangles>5000,"The static original glider hull supplies ray occluders");
    RayShadows *actual=[[RayShadows alloc] initWithDevice:gpu queue:queue source:source geometry:parts samples:1 colorFormat:MTLPixelFormatRGBA8Unorm];check(actual&&actual.structure,"Original glider acceleration structure builds on the GPU");
    std::cout<<"ray-traced sunlight shadow verified with "<<triangles<<" original hull triangles\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

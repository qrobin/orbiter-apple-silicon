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
    check(ray&&!ray.enabled&&ray.pipeline&&ray.structure,"Hardware ray-tracing pipeline is available but starts disabled");
    check(![[RayShadows alloc] initWithDevice:gpu queue:queue source:source geometry:@[] samples:1 colorFormat:MTLPixelFormatRGBA8Unorm],"An empty scene falls back safely");
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];check(library!=nil,"Metal library failed");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"meshVertex"];pd.fragmentFunction=[library newFunctionWithName:@"meshFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> regular=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(regular!=nil,"Fallback pipeline failed");
    std::vector<Vertex> receiver={{-2,-2,5,0,0,-1,0,0},{2,-2,5,0,0,-1,1,0},{2,2,5,0,0,-1,1,1},{-2,2,5,0,0,-1,0,1}};
    id<MTLBuffer> vertexBuffer=[gpu newBufferWithBytes:receiver.data() length:receiver.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];id<MTLBuffer> indexBuffer=[gpu newBufferWithBytes:indices.data() length:indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    constexpr int width=256,height=256;MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;id<MTLTexture> image=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];td.usage=MTLTextureUsageShaderRead;td.storageMode=MTLStorageModeShared;id<MTLTexture> white=[gpu newTextureWithDescriptor:td];uint32_t pixel=0xffffffff;[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pixel bytesPerRow:4];
    MTLTextureDescriptor *nd=[MTLTextureDescriptor new];nd.textureType=MTLTextureType3D;nd.width=nd.height=nd.depth=1;nd.pixelFormat=MTLPixelFormatRGBA8Unorm;nd.usage=MTLTextureUsageShaderRead;nd.storageMode=MTLStorageModeShared;id<MTLTexture> noise=[gpu newTextureWithDescriptor:nd],emptyNoise=[gpu newTextureWithDescriptor:nd];[noise replaceRegion:MTLRegionMake3D(0,0,0,1,1,1) mipmapLevel:0 slice:0 withBytes:&pixel bytesPerRow:4 bytesPerImage:4];uint32_t emptyPixel=0;[emptyNoise replaceRegion:MTLRegionMake3D(0,0,0,1,1,1) mipmapLevel:0 slice:0 withBytes:&emptyPixel bytesPerRow:4 bytesPerImage:4];id<MTLTexture> activeNoise=noise;
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[gpu newDepthStencilStateWithDescriptor:ds];
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,1,0};f.sun={0,0,-1,1};f.position={0,1,0,0};f.screen={width,height,.466f,0};
    f.projection.columns[0]={1/.466f,0,0,0};f.projection.columns[1]={0,1/.466f,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2f,0};
    Object object{};object.model.columns[0]={1,0,0,0};object.model.columns[1]={0,1,0,0};object.model.columns[2]={0,0,1,0};object.model.columns[3]={0,0,0,1};object.color={1,1,1,1};
    ShipFrame ship={{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,0}};
    auto render=[&](bool traced,id<MTLTexture> planet=nil,id<MTLTexture> stars=nil,id<MTLTexture> clouds=nil){id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=image;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:traced?ray.pipeline:regular];[e setDepthStencilState:depthState];[e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:vertexBuffer offset:0 atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&object length:sizeof(object) atIndex:2];float dummy[12]={};[e setVertexBytes:dummy length:sizeof(dummy) atIndex:3];
        [e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&object length:sizeof(object) atIndex:2];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:white atIndex:1];[e setFragmentTexture:planet?:white atIndex:2];[e setFragmentTexture:clouds?:white atIndex:3];[e setFragmentTexture:stars?:white atIndex:4];[e setFragmentTexture:activeNoise atIndex:5];
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
    f.position={0,0,-(1+1000.0f/6371010),0};f.environment={1000.0f/6371010,1000,0,0};f.body.y=1;f.surfaceColor.w=3;f.sun={0,1,0,1};f.clouds={1800,6500,.48f,0};f.weather={4,0,0,0};
    auto clearSky=render(false,black,black,black),cloudySky=render(false,black,black,white);size_t center=(128*width+128)*4;int cloudDifference=0;
    for(int c=0;c<3;++c)cloudDifference+=abs(int(clearSky[center+c])-int(cloudySky[center+c]));
    check(cloudDifference>3,"Changing cloud cover changes the hull's reflected sky");
    activeNoise=emptyNoise;auto emptyVolume=render(false,black,black,white);int volumeDifference=0;
    for(int c=0;c<3;++c)volumeDifference+=abs(int(emptyVolume[center+c])-int(cloudySky[center+c]));
    check(volumeDifference>3,"The hull reflection follows the actual 3D cloud volume, not just the coverage map");
    // The depth prepass must cull opaque overdraw without hiding geometry
    // visible through a partially transparent texture.
    MTLRenderPipelineDescriptor *blendDescriptor=[pd copy];blendDescriptor.fragmentFunction=[library newFunctionWithName:@"meshFragment"];
    blendDescriptor.colorAttachments[0].blendingEnabled=YES;blendDescriptor.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;blendDescriptor.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;blendDescriptor.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;blendDescriptor.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> blended=[gpu newRenderPipelineStateWithDescriptor:blendDescriptor error:&error];check(blended!=nil,"Blended mesh pipeline");
    MTLRenderPipelineDescriptor *preDescriptor=[blendDescriptor copy];preDescriptor.fragmentFunction=[library newFunctionWithName:@"meshDepthFragment"];preDescriptor.colorAttachments[0].blendingEnabled=NO;preDescriptor.colorAttachments[0].writeMask=MTLColorWriteMaskNone;
    id<MTLRenderPipelineState> prepass=[gpu newRenderPipelineStateWithDescriptor:preDescriptor error:&error];check(prepass!=nil,"Mesh depth pipeline");
    MTLDepthStencilDescriptor *equalDescriptor=[MTLDepthStencilDescriptor new];equalDescriptor.depthCompareFunction=MTLCompareFunctionEqual;equalDescriptor.depthWriteEnabled=NO;id<MTLDepthStencilState> equalDepth=[gpu newDepthStencilStateWithDescriptor:equalDescriptor];
    MTLTextureDescriptor *alphaDescriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:2 height:1 mipmapped:NO];alphaDescriptor.usage=MTLTextureUsageShaderRead;alphaDescriptor.storageMode=MTLStorageModeShared;id<MTLTexture> partial=[gpu newTextureWithDescriptor:alphaDescriptor];uint8_t alphaPixels[8]={255,255,255,0,255,255,255,128};[partial replaceRegion:MTLRegionMake2D(0,0,2,1) mipmapLevel:0 withBytes:alphaPixels bytesPerRow:8];
    std::vector<Vertex> centerQuad={{-.35f,-.35f,3,0,0,-1,0,0},{.35f,-.35f,3,0,0,-1,1,0},{.35f,.35f,3,0,0,-1,1,1},{-.35f,.35f,3,0,0,-1,0,1}};
    id<MTLBuffer> centerVertices=[gpu newBufferWithBytes:centerQuad.data() length:centerQuad.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];
    f={};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,1,0};f.sun={0,0,-1,1};f.position={0,1,0,0};f.screen={width,height,.466f,0};f.projection.columns[0]={1/.466f,0,0,0};f.projection.columns[1]={0,1/.466f,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2f,0};
    auto layerImage=[&](bool usePrepass,bool useRay=false){
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=image;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setCullMode:MTLCullModeNone];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];float dummy[12]={};[e setVertexBytes:dummy length:sizeof(dummy) atIndex:3];[e setFragmentTexture:white atIndex:1];[e setFragmentTexture:white atIndex:2];[e setFragmentTexture:white atIndex:3];[e setFragmentTexture:white atIndex:4];[e setFragmentTexture:noise atIndex:5];
        if(useRay){[e setFragmentBytes:&ship length:sizeof(ship) atIndex:4];[e setFragmentAccelerationStructure:ray.structure atBufferIndex:5];[e useResource:ray.structure usage:MTLResourceUsageRead stages:MTLRenderStageFragment];}
        auto draw=[&](id<MTLBuffer> vertices,float z,simd_float4 color,id<MTLTexture> texture){Object o{};o.model.columns[0]={1,0,0,0};o.model.columns[1]={0,1,0,0};o.model.columns[2]={0,0,1,0};o.model.columns[3]={0,0,z,1};o.color=color;[e setVertexBuffer:vertices offset:0 atIndex:0];[e setVertexBytes:&o length:sizeof(o) atIndex:2];[e setFragmentBytes:&o length:sizeof(o) atIndex:2];[e setFragmentTexture:texture atIndex:0];[e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:indices.size() indexType:MTLIndexTypeUInt32 indexBuffer:indexBuffer indexBufferOffset:0];};
        simd_float4 redColor={1,0,0,1},greenColor={0,1,0,1},blueColor={0,0,1,1},yellowColor={1,1,0,1};
        if(usePrepass){[e setRenderPipelineState:prepass];[e setDepthStencilState:depthState];draw(vertexBuffer,0,redColor,white);draw(centerVertices,0,blueColor,white);draw(centerVertices,0,yellowColor,white);[e setRenderPipelineState:useRay?ray.pipeline:blended];[e setDepthStencilState:equalDepth];draw(centerVertices,0,yellowColor,white);draw(centerVertices,0,blueColor,white);draw(vertexBuffer,0,redColor,white);[e setDepthStencilState:depthState];draw(vertexBuffer,-1,greenColor,partial);}
        else {[e setRenderPipelineState:useRay?ray.pipeline:blended];[e setDepthStencilState:depthState];draw(vertexBuffer,0,redColor,white);draw(vertexBuffer,-1,greenColor,partial);draw(centerVertices,0,blueColor,white);draw(centerVertices,0,yellowColor,white);}
        [e endEncoding];[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"Mesh depth prepass render failed");std::vector<uint8_t> pixels(width*height*4);[image getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto originalLayers=layerImage(false),prepassedLayers=layerImage(true);check(originalLayers==prepassedLayers,"The prepass preserves opaque surfaces, depth ties and alpha blending");
    auto originalRayLayers=layerImage(false,true),prepassedRayLayers=layerImage(true,true);
    check(originalRayLayers==prepassedRayLayers,"The depth prepass preserves ray-traced surfaces");
    size_t mixedPixels=0;for(size_t i=0;i<originalLayers.size();i+=4)if(originalLayers[i]>20&&originalLayers[i+1]>20&&originalLayers[i+2]<10)++mixedPixels;
    check(mixedPixels>100,"The test includes visible partially transparent layers");
    auto hull=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh");std::vector<bool> moving(hull.groups.size());
    for(const auto &a:Glider::animations())if(a.mesh==0)for(size_t index:a.groups)if(index<moving.size())moving[index]=true;
    NSMutableArray<MTLAccelerationStructureGeometryDescriptor *> *parts=[NSMutableArray new];size_t triangles=0;
    for(size_t i=0;i<hull.groups.size();++i){auto &g=hull.groups[i];if(!moving[i]&&hull.materials[g.material].diffuse[3]>=.99&&!g.indices.empty()){
        [parts addObject:geometry(g.vertices,g.indices)];triangles+=g.indices.size()/3;}}
    check(triangles>5000,"The static original glider hull supplies ray occluders");
    RayShadows *actual=[[RayShadows alloc] initWithDevice:gpu queue:queue source:source geometry:parts samples:1 colorFormat:MTLPixelFormatRGBA8Unorm];check(actual&&actual.structure,"Original glider acceleration structure builds on the GPU");
    std::cout<<"ray-traced sunlight shadow verified with "<<triangles<<" original hull triangles\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

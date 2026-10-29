#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include "VisualTypes.h"
#include "Mesh.h"
#include <cmath>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace native;
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA;NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];
        check(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];
    }
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];
    if(!library)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(library!=nil,"Metal shader compilation failed");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"rainGlassVertex"];pd.fragmentFunction=[library newFunctionWithName:@"rainGlassFragment"];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> pipeline=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(pipeline!=nil,"Rain glass pipeline failed");
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=NO;id<MTLDepthStencilState> depthState=[gpu newDepthStencilStateWithDescriptor:ds];
    auto mesh=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_vc.msh");
    check(mesh.groups.size()>77&&mesh.groups[77].vertices.size()==120&&mesh.materials[mesh.groups[77].material].diffuse[3]<.2,"Original cockpit glass exists");auto &glass=mesh.groups[77];
    id<MTLBuffer> vertices=[gpu newBufferWithBytes:glass.vertices.data() length:glass.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];
    id<MTLBuffer> indices=[gpu newBufferWithBytes:glass.indices.data() length:glass.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    constexpr int width=640,height=640;
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];td.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;
    id<MTLTexture> scene=[gpu newTextureWithDescriptor:td],output=[gpu newTextureWithDescriptor:td];
    std::vector<uint8_t> background(width*height*4);
    for(int y=0;y<height;++y)for(int x=0;x<width;++x){size_t i=(size_t(y)*width+x)*4;bool stripe=(x/30+y/30)%2;
        background[i]=stripe?105:55;background[i+1]=stripe?154:100;background[i+2]=stripe?202:149;background[i+3]=255;}
    [scene replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:background.data() bytesPerRow:width*4];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[gpu newTextureWithDescriptor:td];
    id<MTLCommandQueue> queue=[gpu newCommandQueue];simd_float4x4 model={};model.columns[0]={1,0,0,0};model.columns[1]={0,1,0,0};model.columns[2]={0,0,1,0};model.columns[3]={0,-1.467f,-6.782f,1};
    auto render=[&](float rain,float time,bool occluded,float yaw){
        FrameUniforms f{};f.right={cosf(yaw),0,-sinf(yaw),0};f.up={0,1,0,0};f.forward={sinf(yaw),0,cosf(yaw),0};
        f.position={0,1,0,0};f.sun={0,1,0,1};f.weather={3,.9f,rain,0};f.weatherWind={0,0,80,0};f.environment.w=time;f.screen={width,height,.466f,0};
        f.projection.columns[0]={1/.466f,0,0,0};f.projection.columns[1]={0,1/.466f,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2f,0};
        id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        [blit copyFromTexture:scene sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toTexture:output destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[blit endEncoding];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=occluded?1:0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:pipeline];[e setDepthStencilState:depthState];[e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:vertices offset:0 atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&model length:sizeof(model) atIndex:2];
        [e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&model length:sizeof(model) atIndex:2];[e setFragmentTexture:scene atIndex:0];
        [e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:glass.indices.size() indexType:MTLIndexTypeUInt32 indexBuffer:indices indexBufferOffset:0];[e endEncoding];
        [cb commit];[cb waitUntilCompleted];check(cb.error==nil,"Cockpit rain render failed");
        std::vector<uint8_t> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto dry=render(0,1,false,0),wet=render(1,1,false,0),later=render(1,5,false,0),blocked=render(1,1,true,0),turned=render(1,1,false,.16f);
    check(dry==background&&blocked==background,"Dry and foreground-occluded glass leave the scene unchanged");
    auto differences=[](const auto &a,const auto &b){size_t count=0;for(size_t i=0;i<a.size();i+=4)if(abs(int(a[i])-int(b[i]))>2||abs(int(a[i+1])-int(b[i+1]))>2||abs(int(a[i+2])-int(b[i+2]))>2)++count;return count;};
    auto visible=differences(dry,wet);std::cout<<"Visible wet glass pixels: "<<visible<<'\n';
    check(visible>100&&visible<width*height/4,"Droplets appear on a bounded part of the original glass");
    check(differences(wet,later)>100,"Rainwater moves across the glass over time");
    check(differences(wet,turned)>100,"Wet glass follows the cockpit view");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_RAIN_PREVIEW"];
    if(path.length){NSBitmapImageRep *out=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(out.bitmapData,wet.data(),wet.size());[[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    std::cout<<"cockpit rain geometry and refraction verified\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

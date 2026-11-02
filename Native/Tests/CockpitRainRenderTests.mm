#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include "VisualTypes.h"
#include "Mesh.h"
#include "Weather.h"
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
    [source appendString:@"kernel void testSlab(device float4 *out [[buffer(0)]],uint i [[thread_position_in_grid]]) { float3 ray=i==0?float3(0,0,1):normalize(float3(.6,0,.8)); float thickness=i==2?0:.04; float ior=i==3?1:1.5; out[i]=float4(glassSlabDisplacement(ray,float3(0,0,-1),thickness,ior),1); }"];
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];
    if(!library)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(library!=nil,"Metal shader compilation failed");
    id<MTLComputePipelineState> slabPipeline=[gpu newComputePipelineStateWithFunction:[library newFunctionWithName:@"testSlab"] error:&error];check(slabPipeline!=nil,"Glass slab pipeline failed");
    id<MTLBuffer> slabOut=[gpu newBufferWithLength:4*sizeof(simd_float4) options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> slabCommand=[[gpu newCommandQueue] commandBuffer];id<MTLComputeCommandEncoder> slabEncoder=[slabCommand computeCommandEncoder];
    [slabEncoder setComputePipelineState:slabPipeline];[slabEncoder setBuffer:slabOut offset:0 atIndex:0];[slabEncoder dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];[slabEncoder endEncoding];[slabCommand commit];[slabCommand waitUntilCompleted];check(slabCommand.error==nil,"Glass slab calculation failed");
    auto slabValues=(simd_float4 *)slabOut.contents;
    check(simd_length(slabValues[0].xyz)<1e-6f&&simd_length(slabValues[1].xyz)>.001f,"Thick glass displacement increases away from normal incidence");
    check(simd_length(slabValues[2].xyz)<1e-6f&&simd_length(slabValues[3].xyz)<1e-6f,"Zero thickness or matching refractive indices produce no displacement");
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
    constexpr int scratchSize=256;
    MTLTextureDescriptor *scratchDesc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm width:scratchSize height:scratchSize mipmapped:NO];scratchDesc.usage=MTLTextureUsageShaderRead;scratchDesc.storageMode=MTLStorageModeShared;
    id<MTLTexture> scratchTexture=[gpu newTextureWithDescriptor:scratchDesc];std::vector<uint8_t> scratchPixels(scratchSize*scratchSize);
    for(int y=0;y<scratchSize;++y)for(int x=0;x<scratchSize;++x)scratchPixels[y*scratchSize+x]=((x+2*y)%19<2)?220:0;
    [scratchTexture replaceRegion:MTLRegionMake2D(0,0,scratchSize,scratchSize) mipmapLevel:0 withBytes:scratchPixels.data() bytesPerRow:scratchSize];
    id<MTLCommandQueue> queue=[gpu newCommandQueue];simd_float4x4 model={};model.columns[0]={1,0,0,0};model.columns[1]={0,1,0,0};model.columns[2]={0,0,1,0};model.columns[3]={0,-1.467f,-6.782f,1};
    auto render=[&](float rain,float time,bool occluded,float yaw,float speed=80,int sunMode=0,bool textured=false,float thickness=0){
        FrameUniforms f{};f.right={cosf(yaw),0,-sinf(yaw),0};f.up={0,1,0,0};f.forward={sinf(yaw),0,cosf(yaw),0};
        f.position={0,1,0,0};f.sun=sunMode==4?simd_float4{0,1,0,0}:sunMode==1?simd_float4{0,0,1,1}:sunMode==2?simd_float4{0,0,-1,1}:sunMode==3?simd_float4{1,0,0,1}:simd_float4{0,1,0,1};f.weather={3,.9f,rain,0};f.weatherWind={0,0,speed,0};f.environment.w=time;f.screen={width,height,.466f,0};
        Vector flow=glassRunoffVelocity({0,0,speed},{0,1,0},{1,0,0},{0,1,0},{0,0,1})*time;simd_float4 runoff={(float)flow.x,(float)flow.y,(float)flow.z,0};
        f.projection.columns[0]={1/.466f,0,0,0};f.projection.columns[1]={0,1/.466f,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2f,0};
        id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
        [blit copyFromTexture:scene sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toTexture:output destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[blit endEncoding];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionLoad;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=occluded?1:0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:pipeline];[e setDepthStencilState:depthState];[e setCullMode:MTLCullModeNone];
        [e setVertexBuffer:vertices offset:0 atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&model length:sizeof(model) atIndex:2];
        [e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&model length:sizeof(model) atIndex:2];[e setFragmentBytes:&runoff length:sizeof(runoff) atIndex:3];[e setFragmentTexture:scene atIndex:0];
        uint32_t hasTexture=textured?1:0;[e setFragmentBytes:&hasTexture length:sizeof(hasTexture) atIndex:4];[e setFragmentTexture:scratchTexture atIndex:1];[e setFragmentBytes:&thickness length:sizeof(thickness) atIndex:5];
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
    size_t scratches=0;for(int sun=1;sun<=3;++sun)scratches=std::max(scratches,differences(background,render(0,1,false,0,80,sun)));
    std::cout<<"Sunlit scratch pixels: "<<scratches<<'\n';
    check(scratches>10&&scratches<width*height/8,"Dry glass shows restrained sunlight-dependent scratches");
    size_t textureDifference=0;for(int sun=1;sun<=3;++sun)textureDifference=std::max(textureDifference,differences(render(0,1,false,0,80,sun),render(0,1,false,0,80,sun,true)));
    check(textureDifference>100,"Local scratch texture changes sunlit glass");
    check(render(0,1,true,0,80,1,true)==background,"Cockpit geometry occludes the scratch texture");
    auto bent=render(0,1,false,0,80,4,true);
    auto unbent=render(0,1,false,0,80,4,false);
    check(differences(bent,unbent)>20,"Scratch slopes refract the background without direct sunlight");
    check(render(0,1,true,0,80,4,true)==background,"Foreground geometry occludes scratch refraction");
    auto slab=render(0,1,false,0,80,4,false,.04f);
    check(differences(slab,unbent)>50,"Thick angled glass displaces the transmitted scene");
    check(render(0,1,true,0,80,4,false,.04f)==background,"Cockpit surfaces occlude thick-glass refraction");

    auto slow=render(1,1,false,0,0),slowLater=render(1,1.1f,false,0,0),fast=render(1,1,false,0,250),fastLater=render(1,1.1f,false,0,250);
    auto slowMotion=differences(slow,slowLater),fastMotion=differences(fast,fastLater);
    std::cout<<"Drop motion: stationary "<<slowMotion<<", fast "<<fastMotion<<'\n';
    check(fastMotion>slowMotion*2&&fastMotion>100,"Airflow makes droplets move faster over the canopy");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_RAIN_PREVIEW"];
    if(path.length){NSBitmapImageRep *out=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(out.bitmapData,wet.data(),wet.size());[[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    std::cout<<"cockpit rain geometry and refraction verified\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

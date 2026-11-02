#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#include "VisualTypes.h"
#include "Surface.h"
#include "TerrainFrame.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <utility>
#include <vector>
static void require(bool ok,const char *message){if(!ok){fprintf(stderr,"%s\n",message);exit(1);}}
int main(){@autoreleasepool{
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    NSError *error=nil;NSString *root=@ORBITER_TEST_DATA;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];require(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];}
    [source appendString:@"\nkernel void checkSkyCoordinates(device float2 *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {float3 v[3]={float3(1,0,0),float3(0,-.3977772,.9174821),float3(0,.9174821,.3977772)}; if(id<3)out[id]=skyCoordinates(v[id]);}\n"];
    [source appendString:@"\nkernel void copyWaterDepth(texture2d<float,access::read> src [[texture(0)]], texture2d<float,access::write> dst [[texture(1)]], uint2 id [[thread_position_in_grid]]) {if(id.x<dst.get_width()&&id.y<dst.get_height())dst.write(src.read(id),id);}\n"];
    [source appendString:@"\nkernel void probeCloudVolume(constant FrameUniforms &f [[buffer(0)]], device float4 *out [[buffer(1)]], texture3d<float> noise [[texture(0)]], texture2d<float> map [[texture(1)]]) {float3 p=f.position.xyz*f.body.x;float2 cloud=reflectedCloudRay(p,f.sun.xyz,1e9f,f,noise,map);float shadow=cloudShadowTransmission(p,f,noise,map);float3 reflected=reflectCloudVolume(float3(0),p,f.sun.xyz,1e9f,f,noise,map);float2 segment=cloudRaySegment(p,f.sun.xyz,f);float step=(segment.y-segment.x)/512.0f,optical=0;for(int i=0;i<512;++i)optical+=sampleCloudDensity(p+f.sun.xyz*(segment.x+(i+.5f)*step),f,noise,map)*step;out[0]=float4(cloud.x,shadow,reflected.r,exp(-optical));}\n"];
    [source appendString:@"\nkernel void probeTerrain(device const float4 *p [[buffer(0)]],device float *out [[buffer(1)]],texture2d<float> mask [[texture(0)]],uint id [[thread_position_in_grid]]) {if(id<6)out[id]=terrainHeightAt(normalize(p[id].xyz),mask); }\n"];
    [source appendString:@"\nkernel void probeMarsMaterial(device float4 *out [[buffer(0)]],uint id [[thread_position_in_grid]]) {if(id<4){float3 p=float3(1200000+float(id)*13,700000,2500000);out[id]=float4(marsGroundMaterial(float3(.4,.2,.1),p,id==3?7000.0f:50.0f,0.0f),1);}}\n"];
    [source appendString:@"\nkernel void probeOtherTerrain(device const float4 *p [[buffer(0)]],device float *out [[buffer(1)]],device const float2 *body [[buffer(2)]],uint id [[thread_position_in_grid]]) {if(id<27)out[id]=bodyTerrainHeight(normalize(p[id].xyz),int(body[id].x),body[id].y); }\n"];
    [source appendString:@"\nkernel void probeGroundCoverage(device const float4 *p [[buffer(0)]],device uint *out [[buffer(1)]],uint id [[thread_position_in_grid]]) {float2 point=p[id].xy,camera=p[id].zw;uint count=0;for(uint level=0;level<7;++level){float spacing=80.0f*float(1u<<level);int2 tile=int2(floor(point/spacing)),center=groundCenter(camera,spacing);if(all(tile>=center-24)&&all(tile<center+24)&&groundTileVisible(tile,camera,spacing,level))++count;}out[id]=count;}\n"];
    [source appendString:@"\nkernel void probeReflectedBody(constant FrameUniforms &f [[buffer(0)]],device float *out [[buffer(1)]],uint i [[thread_position_in_grid]]) {float3 p=i==0?float3(0,0,1):i==1?float3(0,0,-1):float3(0,0,1);float3 n=i==2?float3(0,0,-1):p;out[i]=reflectedBodyLight(f.reflectedLights,p,n); }\n"];
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){fprintf(stderr,"Metal compilation: %s\n",error.localizedDescription.UTF8String);return 1;}
    {
        id<MTLComputePipelineState> probe=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeReflectedBody"] error:&error];require(probe!=nil,"Reflected light probe pipeline");
        FrameUniforms frame{};frame.reflectedLights[0]={0,0,60,0.001f};
        id<MTLBuffer> values=[device newBufferWithLength:3*sizeof(float) options:MTLResourceStorageModeShared];
        id<MTLCommandQueue> queue=[device newCommandQueue];id<MTLCommandBuffer> command=[queue commandBuffer];id<MTLComputeCommandEncoder> encoder=[command computeCommandEncoder];
        [encoder setComputePipelineState:probe];[encoder setBytes:&frame length:sizeof(frame) atIndex:0];[encoder setBuffer:values offset:0 atIndex:1];[encoder dispatchThreads:MTLSizeMake(3,1,1) threadsPerThreadgroup:MTLSizeMake(3,1,1)];[encoder endEncoding];[command commit];[command waitUntilCompleted];
        require(command.status==MTLCommandBufferStatusCompleted,"Reflected light probe completes");float *light=(float *)values.contents;
        require(light[0]>.001f&&light[1]==0&&light[2]==0,"Reflected light reaches the facing side and respects the horizon and surface normal");
    }
    auto pipeline=[&](NSString *fragment,MTLPixelFormat color,bool depth){
        MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[library newFunctionWithName:@"skyVertex"];d.fragmentFunction=[library newFunctionWithName:fragment];
        d.colorAttachments[0].pixelFormat=color;if(depth)d.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> p=[device newRenderPipelineStateWithDescriptor:d error:&error];
        if(!p)fprintf(stderr,"Pipeline %s: %s\n",fragment.UTF8String,error.localizedDescription.UTF8String);require(p!=nil,"Pipeline failed");return p;};
    auto sky=pipeline(@"skyFragment",MTLPixelFormatRGBA16Float,true),composite=pipeline(@"compositeClouds",MTLPixelFormatRGBA8Unorm_sRGB,false);
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    auto load=[&](NSString *path,bool srgb){id<MTLTexture> t=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:path]] options:@{MTKTextureLoaderOptionSRGB:@(srgb),MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];
        if(!t)fprintf(stderr,"Texture %s: %s\n",path.UTF8String,error.localizedDescription.UTF8String);require(t!=nil,"Texture load failed");return t;};
    id<MTLTexture> earth=load(@"Native/Assets/earth-8k.jpg",true),cloudMap=load(@"Native/Assets/earth-clouds.png",false),ocean=load(@"Native/Assets/earth-ocean-mask.png",false),oceanWaves=load(@"Native/Assets/earth-waves.png",false),oceanDetail=load(@"Native/Assets/earth-waves-detail.png",false),starMap=load(@"Native/Assets/sky-8k.jpg",true);
    // The native catalogue must reference a packaged, decodable image for
    // every body, including worlds without a complete spacecraft mosaic.
    for(const auto &b:native::bodies()){@autoreleasepool{
        require(b.texture[0]!=0,"Every body has a texture assignment");
        NSString *path=b.id==native::BodyId::Earth?@"Native/Assets/earth-8k.jpg":[NSString stringWithFormat:@"Native/Assets/Bodies/%s.jpg",b.texture];
        id<MTLTexture> image=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:path]] options:@{MTKTextureLoaderOptionSRGB:@YES} error:&error];
        if(!image)fprintf(stderr,"Missing or invalid texture for %s: %s\n",b.name,error.localizedDescription.UTF8String);require(image!=nil,"Body texture decodes");
        require(image.width>=1024&&image.height>=512,"Body texture has at least 1K dimensions");
    }}
    id<MTLTexture> venusSurface=load(@"Native/Assets/Bodies/venus_surface.jpg",true);require(venusSurface.width>=2048,"Venus surface map decodes");
    require(cloudMap.width==8192&&cloudMap.height==4096,"Cloud map must retain its 8K source detail");
    require(starMap.width==8192&&starMap.height==4096,"Celestial sky map must retain 8K source detail");
    id<MTLComputePipelineState> skyCheck=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"checkSkyCoordinates"] error:&error];require(skyCheck!=nil,"Sky coordinate test pipeline");
    id<MTLBuffer> skyCoords=[device newBufferWithLength:3*sizeof(simd_float2) options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> skyQueue=[device newCommandQueue];id<MTLCommandBuffer> skyCommand=[skyQueue commandBuffer];id<MTLComputeCommandEncoder> skyEncoder=[skyCommand computeCommandEncoder];
    [skyEncoder setComputePipelineState:skyCheck];[skyEncoder setBuffer:skyCoords offset:0 atIndex:0];[skyEncoder dispatchThreads:MTLSizeMake(3,1,1) threadsPerThreadgroup:MTLSizeMake(3,1,1)];[skyEncoder endEncoding];[skyCommand commit];[skyCommand waitUntilCompleted];require(skyCommand.error==nil,"Sky coordinate test");
    auto coords=(simd_float2 *)skyCoords.contents;require(fabs(coords[0].x-.5)<1e-5&&fabs(coords[0].y-.5)<1e-5&&fabs(coords[1].x-.25)<1e-5&&coords[2].y<.001,"J2000 celestial coordinates and orientation");
    const NSUInteger width=NSProcessInfo.processInfo.environment[@"ORBITER_WIDE_PREVIEW"]?1280:640;
    const NSUInteger height=NSProcessInfo.processInfo.environment[@"ORBITER_WIDE_PREVIEW"]?800:640;
    auto texture=[&](MTLPixelFormat format,NSUInteger w,NSUInteger h,MTLTextureUsage usage){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];d.usage=usage;d.storageMode=MTLStorageModeShared;return [device newTextureWithDescriptor:d];};
    id<MTLTexture> scene=texture(MTLPixelFormatRGBA16Float,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    id<MTLTexture> output=texture(MTLPixelFormatRGBA8Unorm_sRGB,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    MTLTextureDescriptor *dd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];dd.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;dd.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[device newTextureWithDescriptor:dd];
    id<MTLTexture> white=texture(MTLPixelFormatRGBA8Unorm,1,1,MTLTextureUsageShaderRead),zero=texture(MTLPixelFormatRGBA8Unorm,1,1,MTLTextureUsageShaderRead),data=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead);
    uint32_t w=0xffffffff,z=0;float far[4]={1e9f,0,0,0};[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&w bytesPerRow:4];[zero replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&z bytesPerRow:4];[data replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:far bytesPerRow:16];
    require(native::loadTerrainMask(std::filesystem::path(ORBITER_TEST_DATA)/"Native/Assets/earth-terrain-mask.r8"),"CPU terrain mask loads");
    NSData *terrainBytes=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"Native/Assets/earth-terrain-mask.r8"]];
    auto terrainMap=texture(MTLPixelFormatR8Unorm,2048,1024,MTLTextureUsageShaderRead);[terrainMap replaceRegion:MTLRegionMake2D(0,0,2048,1024) mipmapLevel:0 withBytes:terrainBytes.bytes bytesPerRow:2048];
    std::array<simd_float4,6> terrainPoints{};double terrainLat[]={40,35,50,-25,28.58438,0},terrainLon[]={-110,-105,10,135,-80.65165,0};
    for(int i=0;i<6;++i){double lat=terrainLat[i]*M_PI/180,lon=terrainLon[i]*M_PI/180;terrainPoints[i]={(float)(cos(lat)*cos(lon)),(float)sin(lat),(float)(cos(lat)*sin(lon)),0};}
    auto terrainInput=[device newBufferWithBytes:terrainPoints.data() length:sizeof(terrainPoints) options:MTLResourceStorageModeShared];auto terrainOutput=[device newBufferWithLength:6*sizeof(float) options:MTLResourceStorageModeShared];
    auto terrainProbe=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeTerrain"] error:&error];require(terrainProbe!=nil,"terrain probe pipeline");
    auto terrainCommands=[device newCommandQueue];auto terrainCommand=[terrainCommands commandBuffer];auto terrainCompute=[terrainCommand computeCommandEncoder];[terrainCompute setComputePipelineState:terrainProbe];[terrainCompute setBuffer:terrainInput offset:0 atIndex:0];[terrainCompute setBuffer:terrainOutput offset:0 atIndex:1];[terrainCompute setTexture:terrainMap atIndex:0];[terrainCompute dispatchThreads:MTLSizeMake(6,1,1) threadsPerThreadgroup:MTLSizeMake(6,1,1)];[terrainCompute endEncoding];[terrainCommand commit];[terrainCommand waitUntilCompleted];require(terrainCommand.error==nil,"terrain probe executes");
    for(int i=0;i<6;++i){auto p=native::earthSurface(Rad(terrainLat[i]),Rad(terrainLon[i]),51982.5).up*native::EarthRadius;double cpu=native::terrainElevation(native::BodyId::Earth,p,51982.5),gpu=((float *)terrainOutput.contents)[i];if(fabs(cpu-gpu)>1)fprintf(stderr,"terrain CPU/GPU %d: %.3f %.3f\n",i,cpu,gpu);require(fabs(cpu-gpu)<1,"rendering and physics terrain match");}
    {
        std::array<simd_float4,27> points{};std::array<simd_float2,27> bodyData{};std::array<native::BodyId,27> bodyIds{};size_t count=0;
        for(const auto &b:native::bodies())if(b.solid&&b.id!=native::BodyId::Earth){require(count<points.size(),"solid body probe capacity");double lat=.31+double(count%3)*.12,lon=-1.4+double(count%7)*.35;points[count]={(float)(cos(lat)*cos(lon)),(float)sin(lat),(float)(cos(lat)*sin(lon)),0};bodyData[count]={(float)(int)b.id,(float)b.radius};bodyIds[count++]=b.id;}
        require(count==points.size(),"probe all non-Earth solid bodies");
        auto inputs=[device newBufferWithBytes:points.data() length:sizeof(points) options:MTLResourceStorageModeShared];auto bodies=[device newBufferWithBytes:bodyData.data() length:sizeof(bodyData) options:MTLResourceStorageModeShared];auto results=[device newBufferWithLength:count*sizeof(float) options:MTLResourceStorageModeShared];
        auto pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeOtherTerrain"] error:&error];require(pipeline!=nil,"other-body terrain probe pipeline");
        auto cmd=[terrainCommands commandBuffer];auto e=[cmd computeCommandEncoder];[e setComputePipelineState:pipeline];[e setBuffer:inputs offset:0 atIndex:0];[e setBuffer:results offset:0 atIndex:1];[e setBuffer:bodies offset:0 atIndex:2];[e dispatchThreads:MTLSizeMake(count,1,1) threadsPerThreadgroup:MTLSizeMake(count,1,1)];[e endEncoding];[cmd commit];[cmd waitUntilCompleted];require(cmd.error==nil,"other-body terrain probe executes");
        for(size_t i=0;i<count;++i){double lat=.31+double(i%3)*.12,lon=-1.4+double(i%7)*.35;auto id=bodyIds[i];auto p=native::bodySurface(id,lat,lon,51982.5).up*native::body(id).radius;double cpu=native::terrainElevation(id,p,51982.5),gpu=((float *)results.contents)[i];if(fabs(cpu-gpu)>1)fprintf(stderr,"terrain %s CPU/GPU: %.3f %.3f\n",native::body(id).name,cpu,gpu);require(fabs(cpu-gpu)<1,"other-body rendering and physics terrain match");}
    }
    {
        auto pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeMarsMaterial"] error:&error];require(pipeline!=nil,"Mars material probe pipeline");
        auto results=[device newBufferWithLength:4*sizeof(simd_float4) options:MTLResourceStorageModeShared];auto cmd=[terrainCommands commandBuffer];auto e=[cmd computeCommandEncoder];[e setComputePipelineState:pipeline];[e setBuffer:results offset:0 atIndex:0];[e dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];[e endEncoding];[cmd commit];[cmd waitUntilCompleted];require(cmd.error==nil,"Mars material probe executes");
        auto p=(simd_float4 *)results.contents;require(fabs(p[0].x-p[1].x)+fabs(p[1].x-p[2].x)>.002,"Mars dust and bedrock vary across the surface");require(fabs(p[3].x-.4)<1e-6&&fabs(p[3].y-.2)<1e-6,"Mars ground detail fades to the orbital texture at distance");
    }
    id<MTLCommandQueue> queue=[device newCommandQueue];MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionAlways;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:ds];
    {
        // Every point near a detail-level seam has exactly one owner, even
        // while the clipmap crosses a cell boundary or a negative coordinate.
        std::vector<simd_float4> points;
        for(float phase:{-161.f,-1.f,0.f,79.f,161.f})for(int level=0;level<6;++level)
            for(float sign:{-1.f,1.f})for(float epsilon:{-.1f,.1f})for(int axis=0;axis<2;++axis){
                float edge=sign*24*80*(1<<level)+epsilon;
                points.push_back(simd_make_float4(axis==0?edge:phase,axis==1?edge:phase,phase,phase+2));
            }
        auto input=[device newBufferWithBytes:points.data() length:points.size()*sizeof(simd_float4) options:MTLResourceStorageModeShared];
        auto output=[device newBufferWithLength:points.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
        auto pipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeGroundCoverage"] error:&error];require(pipeline!=nil,"terrain detail seam probe pipeline");
        auto command=[queue commandBuffer];auto encoder=[command computeCommandEncoder];[encoder setComputePipelineState:pipeline];[encoder setBuffer:input offset:0 atIndex:0];[encoder setBuffer:output offset:0 atIndex:1];
        [encoder dispatchThreads:MTLSizeMake(points.size(),1,1) threadsPerThreadgroup:MTLSizeMake(32,1,1)];[encoder endEncoding];[command commit];[command waitUntilCompleted];require(command.error==nil,"terrain detail seam probe executes");
        for(size_t i=0;i<points.size();++i)require(((uint32_t *)output.contents)[i]==1,"Terrain detail rings must never overlap or leave holes");
    }
    MTLTextureDescriptor *noiseDescriptor=[MTLTextureDescriptor new];noiseDescriptor.textureType=MTLTextureType3D;noiseDescriptor.width=noiseDescriptor.height=noiseDescriptor.depth=64;noiseDescriptor.pixelFormat=MTLPixelFormatRGBA8Unorm;noiseDescriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;noiseDescriptor.storageMode=MTLStorageModePrivate;
    id<MTLTexture> cloudNoise=[device newTextureWithDescriptor:noiseDescriptor];
    id<MTLComputePipelineState> noisePipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"makeCloudNoise"] error:&error];require(noisePipeline!=nil,"Cloud noise pipeline failed");
    id<MTLCommandBuffer> noiseCommand=[queue commandBuffer];id<MTLComputeCommandEncoder> noiseEncoder=[noiseCommand computeCommandEncoder];[noiseEncoder setComputePipelineState:noisePipeline];[noiseEncoder setTexture:cloudNoise atIndex:0];[noiseEncoder dispatchThreads:MTLSizeMake(64,64,64) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[noiseEncoder endEncoding];[noiseCommand commit];[noiseCommand waitUntilCompleted];require(noiseCommand.error==nil,"Cloud noise generation failed");
    MTLTextureDescriptor *emptyDescriptor=[MTLTextureDescriptor new];emptyDescriptor.textureType=MTLTextureType3D;emptyDescriptor.width=emptyDescriptor.height=emptyDescriptor.depth=1;emptyDescriptor.pixelFormat=MTLPixelFormatRGBA8Unorm;emptyDescriptor.usage=MTLTextureUsageShaderRead;emptyDescriptor.storageMode=MTLStorageModeShared;id<MTLTexture> emptyCloudNoise=[device newTextureWithDescriptor:emptyDescriptor];[emptyCloudNoise replaceRegion:MTLRegionMake3D(0,0,0,1,1,1) mipmapLevel:0 slice:0 withBytes:&z bytesPerRow:4 bytesPerImage:4];
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.position={0,0,3,0};f.sun={0,0,1,1};
    f.screen={(float)width,(float)height,.39f,0};f.environment={2,12742020,0,0};f.body={6371010,1,13000,0};f.haze={.1,.33,.75,78000};
    f.equatorX={1,0,0,1};f.pole={0,1,0,0};f.equatorZ={0,0,1,0};f.surfaceColor={.48,.46,.43,3};
    id<MTLTexture> surfaceMask=ocean,activeCloudMap=cloudMap,activeShadow=white,activeEarth=earth,activeVolumeNoise=cloudNoise;
    auto render=[&](float coverage){f.clouds={1800,6500,coverage,0};id<MTLCommandBuffer> cb=[queue commandBuffer];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=scene;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setDepthStencilState:depthState];[e setRenderPipelineState:sky];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentTexture:activeEarth atIndex:0];[e setFragmentTexture:activeShadow atIndex:1];[e setFragmentTexture:white atIndex:2];[e setFragmentTexture:surfaceMask atIndex:3];[e setFragmentTexture:activeCloudMap atIndex:4];[e setFragmentTexture:oceanWaves atIndex:5];[e setFragmentTexture:oceanDetail atIndex:6];[e setFragmentTexture:starMap atIndex:7];[e setFragmentTexture:activeVolumeNoise atIndex:8];[e setFragmentTexture:zero atIndex:9];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
        pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:composite];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:scene atIndex:0];[e setFragmentTexture:zero atIndex:1];[e setFragmentTexture:data atIndex:2];[e setFragmentTexture:depth atIndex:3];[e setFragmentTexture:activeCloudMap atIndex:4];[e setFragmentTexture:cloudNoise atIndex:5];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];[cb commit];[cb waitUntilCompleted];
        if(cb.error)fprintf(stderr,"Render error: %s\n",cb.error.localizedDescription.UTF8String);require(cb.error==nil,"Earth render failed");std::vector<unsigned char> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
    auto clear=render(0),cloud=render(.48);size_t changed=0;for(size_t i=0;i<cloud.size();i+=4)if(abs(int(cloud[i])-int(clear[i]))>5)++changed;
    require(changed>10000&&changed<width*height*3/4,"Satellite clouds must change the globe without covering the whole sky");
    require(abs(int(cloud[0])-int(clear[0]))<3&&abs(int(cloud[1])-int(clear[1]))<3&&abs(int(cloud[2])-int(clear[2]))<3,
            "Cloud shell misses leave empty space unchanged");
    // Check the final composite, not just the volume march: distant opaque
    // clouds must hide the background even while atmospheric haze colours them.
    {
        FrameUniforms saved=f;
        f.position={0,0,1+1000.0f/6371010,0};f.environment={1000.0f/6371010,1000,0,0};
        f.right={0,1,0,0};f.up={0,0,1,0};f.forward={1,0,0,0};f.sun={0,0,1,1};f.sunShape={0,0,0,1};f.weather={0,0,0,0};f.clouds={0,0,0,0};
        id<MTLTexture> cloudFixture=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead);
        id<MTLTexture> dataFixture=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead);
        auto compositeFixture=[&](id<MTLTexture> background,float distance,float alpha){
            float sample[4]={.15f*alpha,.15f*alpha,.15f*alpha,alpha},info[4]={1e9f,distance,0,0};
            [cloudFixture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:sample bytesPerRow:sizeof(sample)];
            [dataFixture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:info bytesPerRow:sizeof(info)];
            id<MTLCommandBuffer> cb=[queue commandBuffer];
            MTLRenderPassDescriptor *clearPass=[MTLRenderPassDescriptor renderPassDescriptor];clearPass.depthAttachment.texture=depth;clearPass.depthAttachment.loadAction=MTLLoadActionClear;clearPass.depthAttachment.clearDepth=0;clearPass.depthAttachment.storeAction=MTLStoreActionStore;
            id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:clearPass];[e endEncoding];
            MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:composite];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];
            [e setFragmentTexture:background atIndex:0];[e setFragmentTexture:cloudFixture atIndex:1];[e setFragmentTexture:dataFixture atIndex:2];[e setFragmentTexture:depth atIndex:3];[e setFragmentTexture:cloudMap atIndex:4];[e setFragmentTexture:cloudNoise atIndex:5];
            [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Cloud composite fixture failed");
            std::array<unsigned char,4> pixel{};[output getBytes:pixel.data() bytesPerRow:4 fromRegion:MTLRegionMake2D(width/2,height/2,1,1) mipmapLevel:0];return pixel;
        };
        auto nearCloud=compositeFixture(zero,2000,1),farDark=compositeFixture(zero,200000,1),farLight=compositeFixture(white,200000,1);
        auto thinDark=compositeFixture(zero,200000,.5f),thinLight=compositeFixture(white,200000,.5f);
        require(abs(int(farDark[0])-int(farLight[0]))<=2,"Distant opaque clouds must hide the scene behind them");
        require(int(thinLight[0])-int(thinDark[0])>25,"Thin clouds must preserve their partial transparency");
        require(abs(int(nearCloud[0])-int(farDark[0]))>2||abs(int(nearCloud[2])-int(farDark[2]))>2,"Air must still affect distant cloud colour");
        f=saved;
    }
    // Reproduce a low-orbit view like the reported screenshot, and compare
    // the 8K map against the same data reduced to 2K.
    NSData *regional=[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"Native/Assets/earth-clouds.r8"]];require(regional.length==2048*1024,"Regional map is present");
    id<MTLTexture> reduced=texture(MTLPixelFormatR8Unorm,2048,1024,MTLTextureUsageShaderRead);
    [reduced replaceRegion:MTLRegionMake2D(0,0,2048,1024) mipmapLevel:0 withBytes:regional.bytes bytesPerRow:2048];
    float phi=20*M_PI/180,lambda=-40*M_PI/180,tilt=-10*M_PI/180;
    simd_float3 radial={cosf(phi)*cosf(lambda),sinf(phi),cosf(phi)*sinf(lambda)};
    simd_float3 east={-sinf(lambda),0,cosf(lambda)},north={-sinf(phi)*cosf(lambda),cosf(phi),-sinf(phi)*sinf(lambda)};
    simd_float3 forward=east*cosf(tilt)+radial*sinf(tilt),viewUp=radial*cosf(tilt)-east*sinf(tilt);
    f.position={radial.x*(1+169500.0f/6371010),radial.y*(1+169500.0f/6371010),radial.z*(1+169500.0f/6371010),0};f.environment={169500.0f/6371010,169500,0,20};
    f.forward={forward.x,forward.y,forward.z,0};f.right={-north.x,-north.y,-north.z,0};f.up={viewUp.x,viewUp.y,viewUp.z,0};f.sun={radial.x,radial.y,radial.z,1};f.weather={4,0,0,0};
    auto orbitalHigh=render(.48);activeCloudMap=reduced;auto orbitalLow=render(.48);activeCloudMap=cloudMap;
    size_t detail=0;for(size_t i=0;i<orbitalHigh.size();i+=4)if(abs(int(orbitalHigh[i])-int(orbitalLow[i]))>3)++detail;
    require(detail>1000,"8K satellite clouds add visible structure in low orbit");
    auto orbitalClear=render(0);f.weather.x=1;auto orbitalScattered=render(.48);f.weather.x=4;
    double scatteredChange=0,regionalChange=0;
    for(size_t i=0;i<orbitalHigh.size();i+=4)for(int c=0;c<3;++c){
        scatteredChange+=abs(int(orbitalScattered[i+c])-int(orbitalClear[i+c]));
        regionalChange+=abs(int(orbitalHigh[i+c])-int(orbitalClear[i+c]));
    }
    require(scatteredChange>0&&scatteredChange<regionalChange*.55,"Scattered weather must reduce orbital cloud coverage as it does nearby");
    NSString *orbitPath=NSProcessInfo.processInfo.environment[@"ORBITER_LOW_ORBIT_PREVIEW"];
    if(orbitPath.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,orbitalHigh.data(),orbitalHigh.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:orbitPath atomically:YES];}
    // A sunlit camera can see across the terminator. The air near that camera
    // must not paint a bright daylight veil over the opposite hemisphere.
    f.position={0,0,1+10000000.0f/6371010,0};f.environment={10000000.0f/6371010,10000000,0,0};
    f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.sun={.990f,0,.141f,1};f.weather={0,0,0,0};
    activeEarth=white;surfaceMask=zero;auto terminator=render(0);activeEarth=earth;surfaceMask=ocean;
    auto sampleTerminator=[&](int x,int c){return int(terminator[(height/2*width+x)*4+c]);};
    printf("Orbital terminator red/blue: night %d/%d, day %d/%d\n",sampleTerminator(width/4,0),sampleTerminator(width/4,2),sampleTerminator(width*3/4,0),sampleTerminator(width*3/4,2));
    require(sampleTerminator(width/4,2)<45&&sampleTerminator(width*3/4,0)>sampleTerminator(width/4,0)+25,"Atmospheric haze must not illuminate the night side from a sunlit camera");
    MTLRenderPipelineDescriptor *terrainDescriptor=[MTLRenderPipelineDescriptor new];terrainDescriptor.vertexFunction=[library newFunctionWithName:@"terrainVertex"];terrainDescriptor.fragmentFunction=[library newFunctionWithName:@"terrainFragment"];terrainDescriptor.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm_sRGB;terrainDescriptor.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> terrainPipeline=[device newRenderPipelineStateWithDescriptor:terrainDescriptor error:&error];require(terrainPipeline!=nil,"Procedural terrain pipeline");
    MTLDepthStencilDescriptor *terrainDepthDescriptor=[MTLDepthStencilDescriptor new];terrainDepthDescriptor.depthCompareFunction=MTLCompareFunctionGreater;terrainDepthDescriptor.depthWriteEnabled=YES;id<MTLDepthStencilState> terrainDepth=[device newDepthStencilStateWithDescriptor:terrainDepthDescriptor];
    f.position={0,0,1+400.0f/6371010,0};f.environment={400.0f/6371010,400,0,0};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.sun={0,0,1,1};f.screen.w=0;
    f.projection={};f.projection.columns[0]={1/(f.screen.z*(float(width)/height)),0,0,0};f.projection.columns[1]={0,1/f.screen.z,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2,0};
    auto renderTerrain=[&](id<MTLTexture> mask,id<MTLTexture> landMap){
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionDontCare;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:terrainPipeline];[e setDepthStencilState:terrainDepth];[e setVertexBytes:&f length:sizeof(f) atIndex:0];[e setVertexTexture:mask atIndex:0];[e setVertexTexture:landMap atIndex:1];[e setVertexTexture:white atIndex:2];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:zero atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:828 instanceCount:64*64];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Procedural terrain render");
        std::vector<unsigned char> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto vegetation=renderTerrain(zero,white),waterTerrain=renderTerrain(white,white);size_t landPixels=0,waterPixels=0;
    for(size_t i=0;i<vegetation.size();i+=4){if(vegetation[i+1]>5)++landPixels;if(waterTerrain[i+1]>5)++waterPixels;}
    require(landPixels>100&&waterPixels==0,"Procedural trees and rocks render on land, never over ocean");
    float franceLat=46*M_PI/180,franceLon=2*M_PI/180;simd_float3 france={cosf(franceLat)*cosf(franceLon),sinf(franceLat),cosf(franceLat)*sinf(franceLon)};
    simd_float3 franceEast={-sinf(franceLon),0,cosf(franceLon)},franceNorth={-sinf(franceLat)*cosf(franceLon),cosf(franceLat),-sinf(franceLat)*sinf(franceLon)};
    f.position={france.x*(1+400.0f/6371010),france.y*(1+400.0f/6371010),france.z*(1+400.0f/6371010),0};f.forward={-france.x,-france.y,-france.z,0};f.right={franceEast.x,franceEast.y,franceEast.z,0};f.up={franceNorth.x,franceNorth.y,franceNorth.z,0};f.sun={france.x,france.y,france.z,1};
    auto franceTerrain=renderTerrain(ocean,earth);size_t francePixels=0;for(size_t i=0;i<franceTerrain.size();i+=4)if(franceTerrain[i+1]>5)++francePixels;
    require(francePixels>20,"The 400 m France scenario has procedural land scenery");
    {
        // A camera attached to a rotating planet must see stationary scenery.
        // Static screenshots cannot expose cancellation at planet-sized positions.
        FrameUniforms saved=f;std::vector<unsigned char> previous;size_t worst=0;
        for(int frame=0;frame<24;++frame){
            double angle=4.2+frame*(Pi2/native::SiderealDay)/30;
            auto world=[&](double x,double y,double z,float w=0){return simd_float4{(float)(cos(angle)*x+sin(angle)*z),(float)y,(float)(-sin(angle)*x+cos(angle)*z),w};};
            double lat=Rad(46),lon=Rad(2),x=cos(lat)*cos(lon),y=sin(lat),z=cos(lat)*sin(lon);
            double r=1+12.0/native::EarthRadius;
            Vector axisX(cos(angle),0,-sin(angle)),axisZ(sin(angle),0,cos(angle));
            setTerrainFrame(f,(axisX*x+Vector(0,1,0)*y+axisZ*z)*(native::EarthRadius+12),axisX,Vector(0,1,0),axisZ);
            f.position=world(x*r,y*r,z*r);f.forward=world(-x,-y,-z);
            f.right=world(-sin(lon),0,cos(lon));f.up=world(-sin(lat)*cos(lon),cos(lat),-sin(lat)*sin(lon));f.sun=world(x,y,z,1);
            f.screen.w=(float)(angle/Pi2);f.environment={12.0f/(float)native::EarthRadius,12,0,0};
            auto current=renderTerrain(ocean,earth);
            if(!previous.empty()){size_t changed=0;for(size_t i=0;i<current.size();i+=4)
                if(abs(int(current[i])-int(previous[i]))+abs(int(current[i+1])-int(previous[i+1]))+abs(int(current[i+2])-int(previous[i+2]))>30)++changed;
                worst=std::max(worst,changed);}
            previous=std::move(current);
        }
        printf("Rotating surface temporal changes: %zu pixels\n",worst);
        require(worst<width*height/200,"A surface-fixed camera must not see terrain shaking as the planet rotates");f=saved;
    }
    {
    // Render the elevation mesh itself, not only its vegetation instances.
    terrainDescriptor.vertexFunction=[library newFunctionWithName:@"groundVertex"];terrainDescriptor.fragmentFunction=[library newFunctionWithName:@"groundFragment"];
    id<MTLRenderPipelineState> groundPipeline=[device newRenderPipelineStateWithDescriptor:terrainDescriptor error:&error];require(groundPipeline!=nil,"elevation mesh pipeline");
    float testLat=40*M_PI/180,testLon=-110*M_PI/180;simd_float3 radial={cosf(testLat)*cosf(testLon),sinf(testLat),cosf(testLat)*sinf(testLon)};
    simd_float3 east={-sinf(testLon),0,cosf(testLon)},north={-sinf(testLat)*cosf(testLon),cosf(testLat),-sinf(testLat)*sinf(testLon)};
    f.position={radial.x*(1+400.0f/6371010),radial.y*(1+400.0f/6371010),radial.z*(1+400.0f/6371010),0};f.forward={-radial.x,-radial.y,-radial.z,0};f.right={east.x,east.y,east.z,0};f.up={north.x,north.y,north.z,0};f.sun={radial.x,radial.y,radial.z,1};
    auto groundCommand=[queue commandBuffer];auto groundPass=[MTLRenderPassDescriptor renderPassDescriptor];groundPass.colorAttachments[0].texture=output;groundPass.colorAttachments[0].loadAction=MTLLoadActionClear;groundPass.colorAttachments[0].storeAction=MTLStoreActionStore;groundPass.depthAttachment.texture=depth;groundPass.depthAttachment.loadAction=MTLLoadActionClear;groundPass.depthAttachment.clearDepth=0;groundPass.depthAttachment.storeAction=MTLStoreActionDontCare;
    auto groundEncoder=[groundCommand renderCommandEncoderWithDescriptor:groundPass];[groundEncoder setRenderPipelineState:groundPipeline];[groundEncoder setDepthStencilState:terrainDepth];[groundEncoder setVertexBytes:&f length:sizeof(f) atIndex:0];[groundEncoder setVertexTexture:terrainMap atIndex:0];[groundEncoder setFragmentBytes:&f length:sizeof(f) atIndex:0];[groundEncoder setFragmentTexture:earth atIndex:0];[groundEncoder setFragmentTexture:white atIndex:1];[groundEncoder setFragmentTexture:white atIndex:2];[groundEncoder setFragmentTexture:zero atIndex:3];
    for(uint32_t level=0;level<4;++level){[groundEncoder setVertexBytes:&level length:sizeof(level) atIndex:1];[groundEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:48*48];}[groundEncoder endEncoding];[groundCommand commit];[groundCommand waitUntilCompleted];require(groundCommand.error==nil,"elevation mesh render");
    std::vector<unsigned char> groundPixels(width*height*4);[output getBytes:groundPixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];size_t groundCount=0;for(size_t i=0;i<groundPixels.size();i+=4)if(groundPixels[i]+groundPixels[i+1]+groundPixels[i+2]>10)++groundCount;require(groundCount>width*height/3,"elevated land mesh covers the nearby view");
    NSString *groundPath=NSProcessInfo.processInfo.environment[@"ORBITER_TERRAIN_PREVIEW"];if(groundPath.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,groundPixels.data(),groundPixels.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:groundPath atomically:YES];}
    // Representative mapped planets and untextured small moons must render the
    // generated mesh with their own materials and size, not Earth's land mask.
    FrameUniforms savedGroundFrame=f;
    auto moonMap=load(@"Native/Assets/Bodies/moon.jpg",true),marsMap=load(@"Native/Assets/Bodies/mars.jpg",true),marsDetail=load(@"Native/Assets/mars-regolith.png",true);
    for(auto id:{native::BodyId::Moon,native::BodyId::Mars,native::BodyId::Phobos}){
        const auto &b=native::body(id);float radius=(float)b.radius,cameraAltitude=1100;
        f.body.x=radius;f.body.y=0;f.surfaceColor={(float)b.color.x,(float)b.color.y,(float)b.color.z,(float)(int)id};f.equatorX.w=id==native::BodyId::Phobos?0:1;
        f.environment={cameraAltitude/radius,cameraAltitude,0,0};f.position={radial.x*(1+cameraAltitude/radius),radial.y*(1+cameraAltitude/radius),radial.z*(1+cameraAltitude/radius),0};
        auto command=[queue commandBuffer];auto encoder=[command renderCommandEncoderWithDescriptor:groundPass];[encoder setRenderPipelineState:groundPipeline];[encoder setDepthStencilState:terrainDepth];[encoder setVertexBytes:&f length:sizeof(f) atIndex:0];[encoder setVertexTexture:terrainMap atIndex:0];[encoder setFragmentBytes:&f length:sizeof(f) atIndex:0];[encoder setFragmentTexture:id==native::BodyId::Moon?moonMap:id==native::BodyId::Mars?marsMap:white atIndex:0];[encoder setFragmentTexture:white atIndex:1];[encoder setFragmentTexture:marsDetail atIndex:2];[encoder setFragmentTexture:zero atIndex:3];
        for(uint32_t level=0;level<4;++level){[encoder setVertexBytes:&level length:sizeof(level) atIndex:1];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:48*48];}
        [encoder endEncoding];[command commit];[command waitUntilCompleted];require(command.error==nil,"other-body terrain mesh renders");
        [output getBytes:groundPixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];size_t count=0;for(size_t i=0;i<groundPixels.size();i+=4)if(groundPixels[i]+groundPixels[i+1]+groundPixels[i+2]>10)++count;
        if(count<=width*height/3)fprintf(stderr,"%s ground pixels: %zu\n",b.name,count);require(count>width*height/3,"other-body elevation mesh covers the nearby view");
    }
    {
        const auto &b=native::body(native::BodyId::Mars);float lat=10*M_PI/180,lon=0;simd_float3 radial={cosf(lat),sinf(lat),0},east={0,0,1},north={-sinf(lat),cosf(lat),0};
        double elevation=native::terrainElevation(b.id,native::bodySurface(b.id,lat,lon,51982.5).up*b.radius,51982.5);
        float cameraAltitude=(float)elevation+120;f.body.x=(float)b.radius;f.body.y=0;f.environment={cameraAltitude/(float)b.radius,cameraAltitude,0,0};f.equatorX.w=1;f.surfaceColor={(float)b.color.x,(float)b.color.y,(float)b.color.z,(float)(int)b.id};
        f.position={radial.x*(1+cameraAltitude/(float)b.radius),radial.y*(1+cameraAltitude/(float)b.radius),0,0};f.forward={-radial.x,-radial.y,0,0};f.right={east.x,east.y,east.z,0};f.up={north.x,north.y,north.z,0};f.sun={radial.x,radial.y,radial.z,1};
        terrainDescriptor.vertexFunction=[library newFunctionWithName:@"marsRockVertex"];terrainDescriptor.fragmentFunction=[library newFunctionWithName:@"marsRockFragment"];
        auto rockPipeline=[device newRenderPipelineStateWithDescriptor:terrainDescriptor error:&error];require(rockPipeline!=nil,"Mars rock pipeline");
        auto renderMars=[&](bool rocks){auto command=[queue commandBuffer];auto encoder=[command renderCommandEncoderWithDescriptor:groundPass];[encoder setDepthStencilState:terrainDepth];[encoder setRenderPipelineState:groundPipeline];[encoder setVertexBytes:&f length:sizeof(f) atIndex:0];[encoder setVertexTexture:terrainMap atIndex:0];[encoder setFragmentBytes:&f length:sizeof(f) atIndex:0];[encoder setFragmentTexture:marsMap atIndex:0];[encoder setFragmentTexture:white atIndex:1];[encoder setFragmentTexture:marsDetail atIndex:2];[encoder setFragmentTexture:zero atIndex:3];
            for(uint32_t level=0;level<3;++level){[encoder setVertexBytes:&level length:sizeof(level) atIndex:1];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:48*48];}
            if(rocks){[encoder setRenderPipelineState:rockPipeline];[encoder setVertexBytes:&f length:sizeof(f) atIndex:0];[encoder setFragmentBytes:&f length:sizeof(f) atIndex:0];[encoder setFragmentTexture:marsDetail atIndex:0];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:192 instanceCount:40*40];}
            [encoder endEncoding];[command commit];[command waitUntilCompleted];require(command.error==nil,"Mars ground and rock render");std::vector<unsigned char> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
        auto bare=renderMars(false),rocks=renderMars(true);size_t changed=0;for(size_t i=0;i<rocks.size();i+=4)if(abs(int(rocks[i])-int(bare[i]))+abs(int(rocks[i+1])-int(bare[i+1]))+abs(int(rocks[i+2])-int(bare[i+2]))>10)++changed;
        printf("Mars rock pixels: %zu\n",changed);require(changed>25,"Mars rocks visibly cover the generated surface");
        {
            // Looking across Mars from a parked, surface-fixed viewpoint, the
            // regolith must remain stable while the planet rotates underneath.
            auto saved=f;std::vector<unsigned char> previous;double worst=0;
            double latitude=Rad(10),longitude=0,altitude=elevation+3;
            Vector fixed(cos(latitude)*cos(longitude),sin(latitude),cos(latitude)*sin(longitude));
            Vector fixedEast(-sin(longitude),0,cos(longitude)),fixedNorth(-sin(latitude)*cos(longitude),cos(latitude),-sin(latitude)*sin(longitude));
            for(int frame=0;frame<24;++frame){
                double angle=4.2+frame*(Pi2/88642.7)/30;
                Vector axisX(cos(angle),0,-sin(angle)),axisZ(sin(angle),0,cos(angle)),pole(0,1,0);
                auto world=[&](Vector v){return axisX*v.x+pole*v.y+axisZ*v.z;};
                auto simd=[](Vector v,float w=0){return simd_float4{(float)v.x,(float)v.y,(float)v.z,w};};
                setTerrainFrame(f,world(fixed)*(b.radius+altitude),axisX,pole,axisZ);
                f.position=simd(world(fixed)*(1+altitude/b.radius));f.right=simd(world(fixedEast));
                f.up=simd(world(fixed));f.forward=simd(world(fixedNorth));f.sun=simd(world((fixed+fixedNorth*.5).unit()),1);
                f.screen.w=(float)(angle/Pi2);f.environment={(float)(altitude/b.radius),(float)altitude,0,0};
                auto current=renderMars(false);
                if(!previous.empty()){double sum=0;for(size_t i=0;i<current.size();i+=4)for(int c=0;c<3;++c)sum+=abs(int(current[i+c])-int(previous[i+c]));
                    worst=std::max(worst,sum/(width*height*3));}
                previous=std::move(current);
            }
            printf("Mars ground temporal mean change: %.4f/255\n",worst);
            require(worst<.15,"Mars ground material must remain stable at a parked surface viewpoint");f=saved;
        }
        NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_MARS_PREVIEW"];if(path.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,rocks.data(),rocks.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    }
    f=savedGroundFrame;
    }
    // The local horizontal direction is not an atmosphere boundary: sky
    // colours immediately above and below it must not form a rectangular band.
    f.position={0,0,1+5000.0f/6371010,0};f.environment={5000.0f/6371010,5000,0,1};
    f.right={0,1,0,0};f.up={0,0,1,0};f.forward={1,0,0,0};f.sun={0,0,1,1};f.weather={0,0,0,0};
    auto daylightSky=render(0);auto pixel=[&](const std::vector<unsigned char> &v,int x,int y,int channel){return int(v[(size_t(y)*width+x)*4+channel]);};
    int seam=0;for(int c=0;c<3;++c)seam=std::max(seam,abs(pixel(daylightSky,width/2,height/2-1,c)-pixel(daylightSky,width/2,height/2+1,c)));
    printf("Atmospheric horizontal seam difference: %d\n",seam);require(seam<25,"The atmospheric sky must not have a hard horizontal band");
    NSString *airPath=NSProcessInfo.processInfo.environment[@"ORBITER_ATMOSPHERE_PREVIEW"];
    if(airPath.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,daylightSky.data(),daylightSky.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:airPath atomically:YES];}
    f.sun={0,0,-1,1};auto nightSky=render(0);
    require(pixel(daylightSky,width/2,height/2-10,2)>pixel(nightSky,width/2,height/2-10,2)+20,"Earth's sky responds to sunlight");
    // The same composition pass should produce precipitation and a local bolt
    // only when the simulation supplies an active storm and flash.
    f.position={0,0,1+5000.0f/6371010,0};f.environment={5000.0f/6371010,5000,0,1};
    f.right={0,-1,0,0};f.up={0,0,1,0};f.forward={1,0,0,0};f.weatherWind={180,0,0,0};
    f.weather={3,.8f,0,0};f.lightning={18000,0,-5000,0};
    auto dry=render(.91f);f.weather.z=1;auto rainy=render(.91f);
    size_t drops=0;for(size_t i=0;i<rainy.size();i+=4)if(abs(int(rainy[i])-int(dry[i]))>3)++drops;
    require(drops>100&&drops<width*height/10,"Rain is visible without covering the view in dense stripes");
    f.lightning.w=1;auto lightning=render(.91f);size_t flashes=0;
    for(size_t i=0;i<lightning.size();i+=4)if(int(lightning[i])>int(rainy[i])+8)++flashes;
    require(flashes>100,"Lightning must illuminate the local storm view");
    // A cloud-shadowed surface receives a modest amount of scattered daylight,
    // but the same cloud cover must not light the surface at night.
    f.position={0,0,1+5000.0f/6371010,0};f.environment={5000.0f/6371010,5000,0,1};
    f.forward={0,0,-1,0};f.right={1,0,0,0};f.up={0,1,0,0};f.sun={0,0,1,1};f.weather={0,0,0,0};f.lightning.w=0;
    activeShadow=zero;surfaceMask=zero;activeEarth=white;auto unfilled=render(0),filled=render(.9);
    size_t fillPixels=0;int maxFill=0;for(size_t i=0;i<filled.size();i+=4){int delta=int(filled[i])-int(unfilled[i]);maxFill=std::max(maxFill,delta);if(delta>2)++fillPixels;}
    printf("Cloud fill: %zu pixels, maximum %d\n",fillPixels,maxFill);
    require(fillPixels>1000,"Sunlit clouds add diffuse illumination to the shaded ground");
    f.sun={0,0,-1,1};auto darkClear=render(0),darkCloud=render(.9);
    size_t nightFill=0;for(size_t i=0;i<darkCloud.size();i+=4)if(int(darkCloud[i])>int(darkClear[i])+2)++nightFill;
    require(nightFill<100,"Clouds do not emit daylight at night");activeShadow=white;surfaceMask=ocean;activeEarth=earth;
    // Render the real celestial shader in HDR so the Sun's brightness and
    // atmospheric attenuation are checked before display tone mapping.
    MTLRenderPipelineDescriptor *sunDescriptor=[MTLRenderPipelineDescriptor new];sunDescriptor.vertexFunction=[library newFunctionWithName:@"celestialVertex"];sunDescriptor.fragmentFunction=[library newFunctionWithName:@"celestialFragment"];sunDescriptor.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA32Float;sunDescriptor.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> sunPipeline=[device newRenderPipelineStateWithDescriptor:sunDescriptor error:&error];require(sunPipeline!=nil,"Sun pipeline failed");
    id<MTLTexture> sunColor=texture(MTLPixelFormatRGBA32Float,64,64,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    MTLTextureDescriptor *sd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:64 height:64 mipmapped:NO];sd.usage=MTLTextureUsageRenderTarget;sd.storageMode=MTLStorageModePrivate;id<MTLTexture> sunDepth=[device newTextureWithDescriptor:sd];
    FrameUniforms sunFrame{};sunFrame.position={0,0,1,0};sunFrame.forward={0,0,1,0};sunFrame.right={1,0,0,0};sunFrame.up={0,1,0,0};sunFrame.sun={0,0,1,1};sunFrame.screen={64,64,.1,0};sunFrame.body={6371010,1,13000,0};
    CelestialUniforms sunBody{};sunBody.directionRadius={0,0,1,.02f};sunBody.axisX={1,0,0,0};sunBody.pole={0,1,0,2};sunBody.axisZ={0,0,1,1};sunBody.light={0,0,1,1};sunBody.material={1,1,1,0};
    auto renderSun=[&](bool earthAtmosphere){sunFrame.surfaceColor.w=earthAtmosphere?3:0;id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=sunColor;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=sunDepth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setDepthStencilState:depthState];[e setRenderPipelineState:sunPipeline];[e setVertexBytes:&sunFrame length:sizeof(sunFrame) atIndex:0];[e setVertexBytes:&sunBody length:sizeof(sunBody) atIndex:1];[e setFragmentBytes:&sunFrame length:sizeof(sunFrame) atIndex:0];[e setFragmentBytes:&sunBody length:sizeof(sunBody) atIndex:1];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:white atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Sun render failed");std::array<float,4> pixel;[sunColor getBytes:pixel.data() bytesPerRow:sizeof(pixel) fromRegion:MTLRegionMake2D(32,32,1,1) mipmapLevel:0];return pixel;};
    auto sunVacuum=renderSun(false),sunInAir=renderSun(true);
    require(sunVacuum[0]>50&&sunInAir[0]>30,"The Sun emits bright HDR light");
    require(sunInAir[2]<sunVacuum[2]*.9f,"Atmospheric scattering attenuates sunlight more strongly at short wavelengths");
    sunBody.pole.w=0;sunBody.light={0,0,1,1}; // Unlit hemisphere facing the camera.
    auto darkMoonVacuum=renderSun(false),darkMoonDay=renderSun(true);
    require(darkMoonDay[2]>darkMoonVacuum[2]+.05f&&darkMoonDay[2]>darkMoonDay[0],"The dark Moon is veiled by blue daylight air");
    sunFrame.sun={0,0,-1,1};auto darkMoonNight=renderSun(true);
    require(darkMoonNight[2]<darkMoonDay[2]*.2f,"The daylight veil fades at night");
    // Count the actual rendered Sun and Moon discs, not just the scale helper.
    // Looking horizontally puts either body on the observer's horizon.
    sunFrame.position={0,1,0,0};sunFrame.sun={0,0,1,1};sunBody.directionRadius={0,0,1,.02f};
    auto discPixels=[&](bool moon,bool atmosphere,float height){
        sunFrame.surfaceColor.w=atmosphere?3:0;sunFrame.environment.x=height/6371010.0f;
        sunBody.pole.w=moon?0:2;sunBody.material.w=moon?4:0;sunBody.light={0,0,-1,1};
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=sunColor;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=sunDepth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionDontCare;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setDepthStencilState:depthState];[e setRenderPipelineState:sunPipeline];[e setVertexBytes:&sunFrame length:sizeof(sunFrame) atIndex:0];[e setVertexBytes:&sunBody length:sizeof(sunBody) atIndex:1];[e setFragmentBytes:&sunFrame length:sizeof(sunFrame) atIndex:0];[e setFragmentBytes:&sunBody length:sizeof(sunBody) atIndex:1];[e setFragmentTexture:white atIndex:0];[e setFragmentTexture:white atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Atmospheric disc render failed");
        std::vector<float> pixels(64*64*4);[sunColor getBytes:pixels.data() bytesPerRow:64*16 fromRegion:MTLRegionMake2D(0,0,64,64) mipmapLevel:0];size_t count=0;for(size_t i=3;i<pixels.size();i+=4)if(pixels[i]>.5f)++count;return count;
    };
    for(bool moon:{false,true}){size_t vacuum=discPixels(moon,false,0),air=discPixels(moon,true,0),orbit=discPixels(moon,true,100000);
        require(air>vacuum*2&&abs((long)orbit-(long)vacuum)<(long)vacuum/3,"Sun and Moon discs grow near the horizon and return to normal in space");}
    // Animated waves must appear over water and leave the land material still.
    f.position={1+5000.0f/6371010,0,0,0};f.environment={5000.0f/6371010,5000,0,1};
    f.forward={-1,0,0,0};f.right={0,0,1,0};f.up={0,1,0,0};f.sun={.8,.4,.447,1};f.weather={3,.8f,0,0};f.lightning.w=0;
    surfaceMask=white;auto water1=render(0);f.environment.w=4;auto water2=render(0);
    size_t waves=0;for(size_t i=0;i<water1.size();i+=4)if(abs(int(water1[i])-int(water2[i]))>2)++waves;
    require(waves>1000,"Ocean waves must animate");
    id<MTLComputePipelineState> depthCopy=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"copyWaterDepth"] error:&error];require(depthCopy!=nil,"Water depth test pipeline");
    id<MTLTexture> depthReadback=texture(MTLPixelFormatR32Float,width,height,MTLTextureUsageShaderWrite|MTLTextureUsageShaderRead);
    auto readDepth=[&](){id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];[e setComputePipelineState:depthCopy];[e setTexture:depth atIndex:0];[e setTexture:depthReadback atIndex:1];[e dispatchThreads:MTLSizeMake(width,height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Water depth readback");std::vector<float> values(width*height);[depthReadback getBytes:values.data() bytesPerRow:width*sizeof(float) fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return values;};
    auto depth2=readDepth();f.environment.w=1;render(0);auto depth1=readDepth();size_t depthChanges=0;
    for(size_t i=0;i<depth1.size();++i)if(fabs(depth1[i]-depth2[i])>1e-9f)++depthChanges;
    require(depthChanges>1000,"Ocean wave heights change the depth buffer over time");
    f.environment.w=86401;auto nextDay=render(0);size_t discontinuous=0;
    for(size_t i=0;i<water1.size();i+=4)if(abs(int(water1[i])-int(nextDay[i]))>2)++discontinuous;
    require(discontinuous<width*height/50,"Wave motion remains continuous when the daily visual clock wraps");
    surfaceMask=zero;f.environment.w=1;auto land1=render(0);f.environment.w=4;auto land2=render(0);
    require(land1==land2,"Animated waves must not affect land");
    surfaceMask=ocean;f.environment.w=1;auto mappedWater1=render(0);f.environment.w=4;auto mappedWater2=render(0);
    size_t mappedWaves=0;for(size_t i=0;i<mappedWater1.size();i+=4)if(abs(int(mappedWater1[i])-int(mappedWater2[i]))>2)++mappedWaves;
    require(mappedWaves>1000,"The geographic mask identifies the equatorial Atlantic as water");
    f.environment.w=1;f.weather.x=0;auto calmWater=render(0);f.weather.x=3;auto stormWater=render(0);
    size_t rough=0;for(size_t i=0;i<calmWater.size();i+=4)if(abs(int(calmWater[i])-int(stormWater[i]))>2)++rough;
    require(rough>1000,"Storm conditions visibly change ocean roughness");
    f.weather.x=0;activeCloudMap=zero;auto clearReflection=render(.48);activeCloudMap=white;auto cloudReflection=render(.48);
    size_t reflected=0;for(size_t i=0;i<clearReflection.size();i+=4)if(abs(int(clearReflection[i])-int(cloudReflection[i]))>2)++reflected;
    require(reflected>1000,"Cloud coverage affects reflected light on water");
    activeVolumeNoise=emptyCloudNoise;auto emptyVolumeWater=render(.48);activeVolumeNoise=cloudNoise;activeCloudMap=cloudMap;
    size_t volumeReflected=0;for(size_t i=0;i<cloudReflection.size();i+=4)if(abs(int(emptyVolumeWater[i])-int(cloudReflection[i]))>2)++volumeReflected;
    require(volumeReflected>1000,"Water reflections follow the 3D cloud volume, not only the coverage map");
    float lat=15*M_PI/180,lon=20*M_PI/180;simd_float3 normal={cosf(lat)*cosf(lon),sinf(lat),cosf(lat)*sinf(lon)};
    f.position={normal.x*(1+5000.0f/6371010),normal.y*(1+5000.0f/6371010),normal.z*(1+5000.0f/6371010),0};
    f.forward={-normal.x,-normal.y,-normal.z,0};f.right={-sinf(lon),0,cosf(lon),0};f.up={-sinf(lat)*cosf(lon),cosf(lat),-sinf(lat)*sinf(lon),0};f.sun={normal.x,normal.y,normal.z,1};
    f.environment.w=1;auto sahara1=render(0);f.environment.w=4;auto sahara2=render(0);
    require(sahara1==sahara2,"The geographic mask keeps ocean waves off the Sahara");
    NSString *oceanPath=NSProcessInfo.processInfo.environment[@"ORBITER_OCEAN_PREVIEW"];
    if(oceanPath.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,water1.data(),water1.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:oceanPath atomically:YES];}
    // Verify that regional coverage reaches the actual volume marcher, not
    // only the orbital composite.
    id<MTLComputePipelineState> marcher=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"marchClouds"] error:&error];require(marcher!=nil,"Cloud marcher pipeline failed");
    MTLTextureDescriptor *nd=[MTLTextureDescriptor new];nd.textureType=MTLTextureType3D;nd.width=nd.height=nd.depth=1;nd.pixelFormat=MTLPixelFormatRGBA8Unorm;nd.usage=MTLTextureUsageShaderRead;nd.storageMode=MTLStorageModeShared;
    id<MTLTexture> noise=[device newTextureWithDescriptor:nd];[noise replaceRegion:MTLRegionMake3D(0,0,0,1,1,1) mipmapLevel:0 slice:0 withBytes:&w bytesPerRow:4 bytesPerImage:4];
    id<MTLTexture> volume=texture(MTLPixelFormatRGBA32Float,16,16,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite),volumeData=texture(MTLPixelFormatRGBA32Float,16,16,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    f.position={0,0,1+1000.0f/6371010,0};f.environment={1000.0f/6371010,1000,0,1};f.forward={0,0,1,0};f.right={1,0,0,0};f.up={0,1,0,0};f.screen={16,16,.25,0};f.weather={4,0,0,0};f.clouds={1800,6500,.48,0};
    auto march=[&](id<MTLTexture> regional){uint32_t index=0;id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];
        [e setComputePipelineState:marcher];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&index length:sizeof(index) atIndex:1];
        [e setTexture:noise atIndex:0];[e setTexture:zero atIndex:1];[e setTexture:zero atIndex:2];[e setTexture:data atIndex:3];[e setTexture:volume atIndex:4];[e setTexture:volumeData atIndex:5];[e setTexture:regional atIndex:6];
        [e dispatchThreads:MTLSizeMake(16,16,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Cloud march failed");std::array<float,4> pixel;[volume getBytes:pixel.data() bytesPerRow:sizeof(pixel) fromRegion:MTLRegionMake2D(8,8,1,1) mipmapLevel:0];return pixel;};
    float empty=march(zero)[3],dense=march(white)[3];require(empty<.001f&&dense>.05f,"Regional cloud map must affect local cloud volumes");
    f.weather.x=1;float scatteredCore=march(white)[3];f.weather.x=4;
    require(scatteredCore>.70f,"Scattered weather must still produce opaque cloud cores");
    // Looking up through thicker cloud should block more of the background
    // and transmit less direct sunlight to the cloud's lower face.
    f.sun={.8f,0,.6f,1};f.clouds={1800,2200,.48,0};auto thin=march(white);
    f.clouds.y=3500;auto core=march(white);
    f.clouds.y=8500;auto thick=march(white);
    printf("Cloud thickness: alpha %.3f -> %.3f -> %.3f, light per opacity %.3f -> %.3f\n",thin[3],core[3],thick[3],thin[0]/thin[3],thick[0]/thick[3]);
    require(thin[3]>.1f&&thin[3]<.9f&&core[3]>.94f&&thick[3]>.97f,"Thin clouds transmit light while dense cumulus cores are opaque");
    require(thick[0]/thick[3]<thin[0]/thin[3]*.85f,"Thicker clouds must transmit less sunlight");
    f.sun.w=0;auto eclipsedCloud=march(white);
    require(eclipsedCloud[0]<thick[0]*.15f,"Eclipsed clouds must not retain direct sunlight");
    f.sun.w=1;f.position={0,0,1+7000.0f/6371010,0};f.environment.x=7000.0f/6371010;
    f.clouds.y=8500;auto clearAboveLow=march(white);
    f.clouds.y=12000;auto upperLayer=march(white);
    printf("Upper cloud layer alpha: %.3f -> %.3f\n",clearAboveLow[3],upperLayer[3]);
    require(clearAboveLow[3]<.001f&&upperLayer[3]>.03f&&upperLayer[3]<thick[3]*.7f,"A separate thin high layer must appear above the lower clouds");
    // The vessel's single world-space shadow must follow the ship, not the
    // camera or whichever piece of ground happens to be behind the cockpit.
    id<MTLComputePipelineState> shipShadow=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"vesselCloudShadow"] error:&error];require(shipShadow!=nil,"Vessel shadow pipeline failed");
    id<MTLTexture> shipShadowOutput=texture(MTLPixelFormatR32Float,1,1,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    id<MTLTexture> activeNoise=noise;
    auto shadowAt=[&](simd_float4 position){id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];
        [e setComputePipelineState:shipShadow];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&position length:sizeof(position) atIndex:1];
        [e setTexture:activeNoise atIndex:0];[e setTexture:white atIndex:1];[e setTexture:shipShadowOutput atIndex:2];
        [e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Vessel shadow failed");
        float value=0;[shipShadowOutput getBytes:&value bytesPerRow:sizeof(value) fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];return value;};
    id<MTLComputePipelineState> groundShadow=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"cloudShadowMap"] error:&error];require(groundShadow!=nil,"Ground shadow pipeline failed");
    id<MTLTexture> groundShadowOutput=texture(MTLPixelFormatR32Float,1,1,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    auto shadowOnGround=[&](){id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];
        [e setComputePipelineState:groundShadow];[e setBytes:&f length:sizeof(f) atIndex:0];[e setTexture:activeNoise atIndex:0];[e setTexture:groundShadowOutput atIndex:1];[e setTexture:white atIndex:2];
        [e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Ground cloud shadow failed");
        float value=0;[groundShadowOutput getBytes:&value bytesPerRow:sizeof(value) fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];return value;};
    // A single cloud lies east of the surface point. Only sunlight from the
    // east passes through it, so the shadow must move with the Sun.
    nd.width=128;id<MTLTexture> striped=[device newTextureWithDescriptor:nd];std::array<uint8_t,128*4> stripes{};
    for(size_t i=0;i<128;++i){stripes[4*i]=(i>=18&&i<=42)?255:0;stripes[4*i+1]=255;stripes[4*i+2]=128;stripes[4*i+3]=255;}
    [striped replaceRegion:MTLRegionMake3D(0,0,0,128,1,1) mipmapLevel:0 slice:0 withBytes:stripes.data() bytesPerRow:128*4 bytesPerImage:128*4];
    f.position={0,0,1+1000.0f/6371010,0};f.environment={1000.0f/6371010,1000,0,0};f.forward={0,0,-1,0};f.right={1,0,0,0};f.up={0,1,0,0};f.screen={1,1,.25,0};f.weather.x=4;f.clouds={1800,6500,.48,0};
    simd_float4 groundPosition={0,0,1,0};
    activeNoise=striped;f.sun={.8f,0,.6f,1};float eastShadow=shadowOnGround(),eastShip=shadowAt(groundPosition);
    f.sun={-.8f,0,.6f,1};float westShadow=shadowOnGround();
    printf("Directional cloud shadow: east %.3f, west %.3f, vessel %.3f\n",eastShadow,westShadow,eastShip);
    require(eastShadow<.05f&&westShadow>.98f&&fabsf(eastShadow-eastShip)<.02f,"Opaque clouds must block sunlight in the Sun's direction for both ground and vessel");
    // Looking from the vessel toward the Sun, a cloud must be visible on the
    // same ray that blocks sunlight and appears in a reflection.
    id<MTLComputePipelineState> probe=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"probeCloudVolume"] error:&error];require(probe!=nil,"Cloud volume probe pipeline failed");
    id<MTLBuffer> probeResult=[device newBufferWithLength:sizeof(simd_float4) options:MTLResourceStorageModeShared];
    id<MTLTexture> oneVolume=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite),oneData=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    auto checkVolumeRay=[&](float sunX,float sunZ){
        f.sun={sunX,0,sunZ,1};f.forward=f.sun;f.forward.w=0;f.right={0,1,0,0};f.up={-sunZ,0,sunX,0};
        uint32_t index=7;id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];
        [e setComputePipelineState:marcher];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&index length:sizeof(index) atIndex:1];
        [e setTexture:activeNoise atIndex:0];[e setTexture:zero atIndex:1];[e setTexture:zero atIndex:2];[e setTexture:data atIndex:3];[e setTexture:oneVolume atIndex:4];[e setTexture:oneData atIndex:5];[e setTexture:white atIndex:6];
        [e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
        [e setComputePipelineState:probe];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBuffer:probeResult offset:0 atIndex:1];[e setTexture:activeNoise atIndex:0];[e setTexture:white atIndex:1];
        [e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Cloud volume ray probe failed");
        std::array<float,4> visible{};[oneVolume getBytes:visible.data() bytesPerRow:sizeof(visible) fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
        return std::pair<float,simd_float4>{visible[3],*(simd_float4 *)probeResult.contents};
    };
    auto throughCloud=checkVolumeRay(.8f,.6f),throughGap=checkVolumeRay(-.8f,.6f);
    printf("Cloud volume: visible %.3f / %.3f, reflected alpha %.3f / %.3f, sunlight %.3f / %.3f\n",throughCloud.first,throughGap.first,throughCloud.second.x,throughGap.second.x,throughCloud.second.y,throughGap.second.y);
    require(throughCloud.first>.9f&&throughCloud.second.x>.9f&&throughCloud.second.y<.05f&&throughCloud.second.z>.01f,"The same cloud must be visible, reflected and block sunlight");
    require(throughGap.first<.02f&&throughGap.second.x<.02f&&throughGap.second.y>.98f,"A clear ray must stay clear in the view, reflection and shadow");
    f.environment.w=1000;auto movedCloud=checkVolumeRay(.8f,.6f);f.environment.w=0;
    require(movedCloud.first<.02f&&movedCloud.second.x<.02f&&movedCloud.second.y>.98f,"Cloud drift must move its appearance, reflection and shadow together");
    activeNoise=cloudNoise;f.weather.x=1;double viewError=0,shadowError=0,reflectionError=0;int rays=0;
    for(float sunZ:{.6f,.2f,.07f}){
        double sunViewError=0,sunShadowError=0,sunReflectionError=0;
        for(int i=0;i<24;++i){
            float x=(float(i)-12)*3000.0f/6371010.0f,rad=1+1000.0f/6371010;
            f.position={x,0,sqrtf(rad*rad-x*x),0};auto result=checkVolumeRay(sqrtf(1-sunZ*sunZ),sunZ);
            sunViewError+=fabsf((1-result.first)-result.second.w);sunShadowError+=fabsf(result.second.y-result.second.w);sunReflectionError+=fabsf((1-result.second.x)-result.second.w);++rays;
        }
        printf("  Sun elevation %.2f: view %.3f, shadow %.3f, reflection %.3f mean error\n",sunZ,sunViewError/24,sunShadowError/24,sunReflectionError/24);
        require(sunViewError/24<.15&&sunShadowError/24<.08&&sunReflectionError/24<.10,"Cloud rays must remain consistent at every tested Sun angle");
        viewError+=sunViewError;shadowError+=sunShadowError;reflectionError+=sunReflectionError;
    }
    printf("Shared cloud ray mean error: view %.3f, shadow %.3f, reflection %.3f\n",viewError/rays,shadowError/rays,reflectionError/rays);
    require(viewError/rays<.06&&shadowError/rays<.05&&reflectionError/rays<.05,"Views, shadows and reflections must follow the same procedural clouds");
    // At a very low Sun angle, curvature places the cloud crossing more than
    // 100 km away. Both ground and vessel shadows must still see it.
    activeNoise=noise;f.weather.x=4;f.position={0,0,1+1000.0f/6371010,0};f.forward={0,0,-1,0};f.right={1,0,0,0};f.up={0,1,0,0};f.sun={.99995f,0,.01f,1};float lowSun=shadowOnGround(),lowShip=shadowAt(groundPosition);
    printf("Low-Sun cloud shadow: ground %.3f, vessel %.3f\n",lowSun,lowShip);
    require(lowSun<.05f&&fabsf(lowSun-lowShip)<.02f,"Low-Sun shadows must follow the curved cloud layer without a distance cutoff");
    f.sun={0,0,1,1};simd_float4 ship={0,0,1+1000.0f/6371010,0};float sheltered=shadowAt(ship);
    f.position={.2f,0,1.1f,0};f.forward={1,0,0,0};float movedCamera=shadowAt(ship);
    simd_float4 above={0,0,1+150000.0f/6371010,0};float exposed=shadowAt(above);
    printf("Vessel cloud shadow: below %.3f, after camera move %.3f, above %.3f\n",sheltered,movedCamera,exposed);
    require(sheltered<.8f&&fabsf(sheltered-movedCamera)<.001f&&exposed>.99f,"Cloud shading must be stable across the vessel and follow its position");
    f.clouds.z=0;require(shadowAt(ship)>.99f,"Clear weather leaves the vessel unshadowed");f.clouds.z=.48;
    f.position={0,0,1+169500.0f/6371010,0};f.environment.x=169500.0f/6371010;
    require(march(white)[3]<.001f,"The expensive local cloud march is skipped above the orbital transition");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_EARTH_PREVIEW"];
    if(path.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,cloud.data(),cloud.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    printf("Earth clouds: %zu globe pixels, %zu low-orbit detail pixels; texture format %lu\n",changed,detail,(unsigned long)cloudMap.pixelFormat);return 0;
}}

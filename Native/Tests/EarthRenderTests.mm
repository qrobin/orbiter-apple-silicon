#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#include "VisualTypes.h"
#include <cmath>
#include <cstdio>
#include <vector>
static void require(bool ok,const char *message){if(!ok){fprintf(stderr,"%s\n",message);exit(1);}}
int main(){@autoreleasepool{
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    NSError *error=nil;NSString *root=@ORBITER_TEST_DATA;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];require(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];}
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){fprintf(stderr,"Metal compilation: %s\n",error.localizedDescription.UTF8String);return 1;}
    auto pipeline=[&](NSString *fragment,MTLPixelFormat color,bool depth){
        MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[library newFunctionWithName:@"skyVertex"];d.fragmentFunction=[library newFunctionWithName:fragment];
        d.colorAttachments[0].pixelFormat=color;if(depth)d.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> p=[device newRenderPipelineStateWithDescriptor:d error:&error];
        if(!p)fprintf(stderr,"Pipeline %s: %s\n",fragment.UTF8String,error.localizedDescription.UTF8String);require(p!=nil,"Pipeline failed");return p;};
    auto sky=pipeline(@"skyFragment",MTLPixelFormatRGBA16Float,true),composite=pipeline(@"compositeClouds",MTLPixelFormatRGBA8Unorm_sRGB,false);
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    auto load=[&](NSString *path,bool srgb){id<MTLTexture> t=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:path]] options:@{MTKTextureLoaderOptionSRGB:@(srgb),MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];
        if(!t)fprintf(stderr,"Texture %s: %s\n",path.UTF8String,error.localizedDescription.UTF8String);require(t!=nil,"Texture load failed");return t;};
    id<MTLTexture> earth=load(@"Native/Assets/earth-8k.jpg",true),cloudMap=load(@"Native/Assets/earth-clouds.png",false),ocean=load(@"Native/Assets/earth-ocean-mask.png",false);
    const NSUInteger width=640,height=640;
    auto texture=[&](MTLPixelFormat format,NSUInteger w,NSUInteger h,MTLTextureUsage usage){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];d.usage=usage;d.storageMode=MTLStorageModeShared;return [device newTextureWithDescriptor:d];};
    id<MTLTexture> scene=texture(MTLPixelFormatRGBA16Float,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    id<MTLTexture> output=texture(MTLPixelFormatRGBA8Unorm_sRGB,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    MTLTextureDescriptor *dd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];dd.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;dd.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[device newTextureWithDescriptor:dd];
    id<MTLTexture> white=texture(MTLPixelFormatRGBA8Unorm,1,1,MTLTextureUsageShaderRead),zero=texture(MTLPixelFormatRGBA8Unorm,1,1,MTLTextureUsageShaderRead),data=texture(MTLPixelFormatRGBA32Float,1,1,MTLTextureUsageShaderRead);
    uint32_t w=0xffffffff,z=0;float far[4]={1e9f,0,0,0};[white replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&w bytesPerRow:4];[zero replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&z bytesPerRow:4];[data replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:far bytesPerRow:16];
    id<MTLCommandQueue> queue=[device newCommandQueue];MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionAlways;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:ds];
    MTLTextureDescriptor *oceanNoiseDescriptor=[MTLTextureDescriptor new];oceanNoiseDescriptor.textureType=MTLTextureType3D;oceanNoiseDescriptor.width=oceanNoiseDescriptor.height=oceanNoiseDescriptor.depth=32;oceanNoiseDescriptor.pixelFormat=MTLPixelFormatRGBA8Unorm;oceanNoiseDescriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;oceanNoiseDescriptor.storageMode=MTLStorageModePrivate;
    id<MTLTexture> oceanNoise=[device newTextureWithDescriptor:oceanNoiseDescriptor];
    id<MTLComputePipelineState> noisePipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"makeCloudNoise"] error:&error];require(noisePipeline!=nil,"Ocean noise pipeline failed");
    id<MTLCommandBuffer> noiseCommand=[queue commandBuffer];id<MTLComputeCommandEncoder> noiseEncoder=[noiseCommand computeCommandEncoder];[noiseEncoder setComputePipelineState:noisePipeline];[noiseEncoder setTexture:oceanNoise atIndex:0];[noiseEncoder dispatchThreads:MTLSizeMake(32,32,32) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[noiseEncoder endEncoding];[noiseCommand commit];[noiseCommand waitUntilCompleted];require(noiseCommand.error==nil,"Ocean noise generation failed");
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.position={0,0,3,0};f.sun={0,0,1,1};
    f.screen={(float)width,(float)height,.39f,0};f.environment={2,12742020,0,0};f.body={6371010,1,13000,0};f.haze={.1,.33,.75,78000};
    f.equatorX={1,0,0,1};f.pole={0,1,0,0};f.equatorZ={0,0,1,0};f.surfaceColor={.48,.46,.43,3};
    id<MTLTexture> surfaceMask=ocean;
    auto render=[&](float coverage){f.clouds={1800,6500,coverage,0};id<MTLCommandBuffer> cb=[queue commandBuffer];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=scene;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setDepthStencilState:depthState];[e setRenderPipelineState:sky];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentTexture:earth atIndex:0];[e setFragmentTexture:white atIndex:1];[e setFragmentTexture:white atIndex:2];[e setFragmentTexture:surfaceMask atIndex:3];[e setFragmentTexture:cloudMap atIndex:4];[e setFragmentTexture:oceanNoise atIndex:5];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
        pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:composite];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:scene atIndex:0];[e setFragmentTexture:zero atIndex:1];[e setFragmentTexture:data atIndex:2];[e setFragmentTexture:depth atIndex:3];[e setFragmentTexture:cloudMap atIndex:4];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];[cb commit];[cb waitUntilCompleted];
        if(cb.error)fprintf(stderr,"Render error: %s\n",cb.error.localizedDescription.UTF8String);require(cb.error==nil,"Earth render failed");std::vector<unsigned char> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
    auto clear=render(0),cloud=render(.48);size_t changed=0;for(size_t i=0;i<cloud.size();i+=4)if(abs(int(cloud[i])-int(clear[i]))>5)++changed;
    require(changed>10000&&changed<width*height*3/4,"Satellite clouds must change the globe without covering the whole sky");
    require(abs(int(cloud[0])-int(clear[0]))<3&&abs(int(cloud[1])-int(clear[1]))<3&&abs(int(cloud[2])-int(clear[2]))<3,
            "Cloud shell misses leave empty space unchanged");
    // The same composition pass should produce precipitation and a local bolt
    // only when the simulation supplies an active storm and flash.
    f.position={0,0,1+5000.0f/6371010,0};f.environment={5000.0f/6371010,5000,0,1};
    f.right={0,-1,0,0};f.up={0,0,1,0};f.forward={1,0,0,0};f.weatherWind={180,0,0,0};
    f.weather={3,.8f,0,0};f.lightning={18000,0,-5000,0};
    auto dry=render(.91f);f.weather.z=1;auto rainy=render(.91f);
    size_t drops=0;for(size_t i=0;i<rainy.size();i+=4)if(abs(int(rainy[i])-int(dry[i]))>3)++drops;
    require(drops>100,"Rain must become visible in a local storm");
    f.lightning.w=1;auto lightning=render(.91f);size_t flashes=0;
    for(size_t i=0;i<lightning.size();i+=4)if(int(lightning[i])>int(rainy[i])+8)++flashes;
    require(flashes>100,"Lightning must illuminate the local storm view");
    // Animated waves must appear over water and leave the land material still.
    f.position={1+5000.0f/6371010,0,0,0};f.environment={5000.0f/6371010,5000,0,1};
    f.forward={-1,0,0,0};f.right={0,0,1,0};f.up={0,1,0,0};f.sun={.8,.4,.447,1};f.weather={3,.8f,0,0};f.lightning.w=0;
    surfaceMask=white;auto water1=render(0);f.environment.w=4;auto water2=render(0);
    size_t waves=0;for(size_t i=0;i<water1.size();i+=4)if(abs(int(water1[i])-int(water2[i]))>2)++waves;
    require(waves>1000,"Ocean waves must animate");
    surfaceMask=zero;f.environment.w=1;auto land1=render(0);f.environment.w=4;auto land2=render(0);
    require(land1==land2,"Animated waves must not affect land");
    surfaceMask=ocean;f.environment.w=1;auto mappedWater1=render(0);f.environment.w=4;auto mappedWater2=render(0);
    size_t mappedWaves=0;for(size_t i=0;i<mappedWater1.size();i+=4)if(abs(int(mappedWater1[i])-int(mappedWater2[i]))>2)++mappedWaves;
    require(mappedWaves>1000,"The geographic mask identifies the equatorial Atlantic as water");
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
        [e dispatchThreads:MTLSizeMake(16,16,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Cloud march failed");float pixel[4];[volume getBytes:pixel bytesPerRow:sizeof(pixel) fromRegion:MTLRegionMake2D(8,8,1,1) mipmapLevel:0];return pixel[3];};
    float empty=march(zero),dense=march(white);require(empty<.001f&&dense>.05f,"Regional cloud map must affect local cloud volumes");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_EARTH_PREVIEW"];
    if(path.length){NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(rep.bitmapData,cloud.data(),cloud.size());[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    printf("Earth cloud render: %zu changed pixels\n",changed);return 0;
}}

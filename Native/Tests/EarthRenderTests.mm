#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#include "VisualTypes.h"
#include <array>
#include <cmath>
#include <cstdio>
#include <vector>
static void require(bool ok,const char *message){if(!ok){fprintf(stderr,"%s\n",message);exit(1);}}
int main(){@autoreleasepool{
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    NSError *error=nil;NSString *root=@ORBITER_TEST_DATA;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];require(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];}
    [source appendString:@"\nkernel void checkSkyCoordinates(device float2 *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {float3 v[3]={float3(1,0,0),float3(0,-.3977772,.9174821),float3(0,.9174821,.3977772)}; if(id<3)out[id]=skyCoordinates(v[id]);}\n"];
    [source appendString:@"\nkernel void copyWaterDepth(texture2d<float,access::read> src [[texture(0)]], texture2d<float,access::write> dst [[texture(1)]], uint2 id [[thread_position_in_grid]]) {if(id.x<dst.get_width()&&id.y<dst.get_height())dst.write(src.read(id),id);}\n"];
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
    id<MTLTexture> earth=load(@"Native/Assets/earth-8k.jpg",true),cloudMap=load(@"Native/Assets/earth-clouds.png",false),ocean=load(@"Native/Assets/earth-ocean-mask.png",false),oceanWaves=load(@"Native/Assets/earth-waves.png",false),oceanDetail=load(@"Native/Assets/earth-waves-detail.png",false),starMap=load(@"Native/Assets/sky-8k.jpg",true);
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
    id<MTLCommandQueue> queue=[device newCommandQueue];MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionAlways;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:ds];
    MTLTextureDescriptor *noiseDescriptor=[MTLTextureDescriptor new];noiseDescriptor.textureType=MTLTextureType3D;noiseDescriptor.width=noiseDescriptor.height=noiseDescriptor.depth=64;noiseDescriptor.pixelFormat=MTLPixelFormatRGBA8Unorm;noiseDescriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;noiseDescriptor.storageMode=MTLStorageModePrivate;
    id<MTLTexture> cloudNoise=[device newTextureWithDescriptor:noiseDescriptor];
    id<MTLComputePipelineState> noisePipeline=[device newComputePipelineStateWithFunction:[library newFunctionWithName:@"makeCloudNoise"] error:&error];require(noisePipeline!=nil,"Cloud noise pipeline failed");
    id<MTLCommandBuffer> noiseCommand=[queue commandBuffer];id<MTLComputeCommandEncoder> noiseEncoder=[noiseCommand computeCommandEncoder];[noiseEncoder setComputePipelineState:noisePipeline];[noiseEncoder setTexture:cloudNoise atIndex:0];[noiseEncoder dispatchThreads:MTLSizeMake(64,64,64) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[noiseEncoder endEncoding];[noiseCommand commit];[noiseCommand waitUntilCompleted];require(noiseCommand.error==nil,"Cloud noise generation failed");
    FrameUniforms f{};f.right={1,0,0,0};f.up={0,1,0,0};f.forward={0,0,-1,0};f.position={0,0,3,0};f.sun={0,0,1,1};
    f.screen={(float)width,(float)height,.39f,0};f.environment={2,12742020,0,0};f.body={6371010,1,13000,0};f.haze={.1,.33,.75,78000};
    f.equatorX={1,0,0,1};f.pole={0,1,0,0};f.equatorZ={0,0,1,0};f.surfaceColor={.48,.46,.43,3};
    id<MTLTexture> surfaceMask=ocean,activeCloudMap=cloudMap,activeShadow=white,activeEarth=earth;
    auto render=[&](float coverage){f.clouds={1800,6500,coverage,0};id<MTLCommandBuffer> cb=[queue commandBuffer];
        MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=scene;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setDepthStencilState:depthState];[e setRenderPipelineState:sky];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentTexture:activeEarth atIndex:0];[e setFragmentTexture:activeShadow atIndex:1];[e setFragmentTexture:white atIndex:2];[e setFragmentTexture:surfaceMask atIndex:3];[e setFragmentTexture:activeCloudMap atIndex:4];[e setFragmentTexture:oceanWaves atIndex:5];[e setFragmentTexture:oceanDetail atIndex:6];[e setFragmentTexture:starMap atIndex:7];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
        pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:composite];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:scene atIndex:0];[e setFragmentTexture:zero atIndex:1];[e setFragmentTexture:data atIndex:2];[e setFragmentTexture:depth atIndex:3];[e setFragmentTexture:activeCloudMap atIndex:4];[e setFragmentTexture:cloudNoise atIndex:5];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];[cb commit];[cb waitUntilCompleted];
        if(cb.error)fprintf(stderr,"Render error: %s\n",cb.error.localizedDescription.UTF8String);require(cb.error==nil,"Earth render failed");std::vector<unsigned char> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
    auto clear=render(0),cloud=render(.48);size_t changed=0;for(size_t i=0;i<cloud.size();i+=4)if(abs(int(cloud[i])-int(clear[i]))>5)++changed;
    require(changed>10000&&changed<width*height*3/4,"Satellite clouds must change the globe without covering the whole sky");
    require(abs(int(cloud[0])-int(clear[0]))<3&&abs(int(cloud[1])-int(clear[1]))<3&&abs(int(cloud[2])-int(clear[2]))<3,
            "Cloud shell misses leave empty space unchanged");
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
    f.weather.x=0;activeCloudMap=zero;auto clearReflection=render(.48);activeCloudMap=white;auto cloudReflection=render(.48);activeCloudMap=cloudMap;
    size_t reflected=0;for(size_t i=0;i<clearReflection.size();i+=4)if(abs(int(clearReflection[i])-int(cloudReflection[i]))>2)++reflected;
    require(reflected>1000,"Cloud coverage affects reflected light on water");
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
    // Looking up through thicker cloud should block more of the background
    // and transmit less direct sunlight to the cloud's lower face.
    f.sun={.8f,0,.6f,1};f.clouds={1800,3500,.48,0};auto thin=march(white);
    f.clouds.y=8500;auto thick=march(white);
    printf("Cloud thickness: alpha %.3f -> %.3f, light per opacity %.3f -> %.3f\n",thin[3],thick[3],thin[0]/thin[3],thick[0]/thick[3]);
    require(thick[3]>thin[3]+.2f,"Thicker clouds must block more background light");
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
    auto shadowAt=[&](simd_float4 position){id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLComputeCommandEncoder> e=[cb computeCommandEncoder];
        [e setComputePipelineState:shipShadow];[e setBytes:&f length:sizeof(f) atIndex:0];[e setBytes:&position length:sizeof(position) atIndex:1];
        [e setTexture:noise atIndex:0];[e setTexture:white atIndex:1];[e setTexture:shipShadowOutput atIndex:2];
        [e dispatchThreads:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[e endEncoding];[cb commit];[cb waitUntilCompleted];require(cb.error==nil,"Vessel shadow failed");
        float value=0;[shipShadowOutput getBytes:&value bytesPerRow:sizeof(value) fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];return value;};
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

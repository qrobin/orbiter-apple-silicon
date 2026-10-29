#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#include "VisualTypes.h"
#include "Flight.h"
#include "SolarSystem.h"
#include "Surface.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>
using namespace native;
static void require(bool ok,const char *message){if(!ok){fprintf(stderr,"%s\n",message);exit(1);}}
static simd_float4 v4(const Vector &v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
int main(){@autoreleasepool{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA,*shaderDirectory=NSProcessInfo.processInfo.environment[@"ORBITER_SHADER_DIRECTORY"];NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *path=shaderDirectory.length?[shaderDirectory stringByAppendingPathComponent:name.lastPathComponent]:[root stringByAppendingPathComponent:name];
        NSString *part=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];require(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];
    }
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];if(!library)fprintf(stderr,"Metal: %s\n",error.localizedDescription.UTF8String);require(library!=nil,"Metal compile failed");
    auto renderPipeline=[&](NSString *vertex,NSString *fragment,MTLPixelFormat format,bool useDepth){
        MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[library newFunctionWithName:vertex];d.fragmentFunction=[library newFunctionWithName:fragment];d.colorAttachments[0].pixelFormat=format;if(useDepth)d.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
        id<MTLRenderPipelineState> p=[gpu newRenderPipelineStateWithDescriptor:d error:&error];if(!p)fprintf(stderr,"%s: %s\n",fragment.UTF8String,error.localizedDescription.UTF8String);require(p!=nil,"Render pipeline failed");return p;};
    auto computePipeline=[&](NSString *name){id<MTLComputePipelineState> p=[gpu newComputePipelineStateWithFunction:[library newFunctionWithName:name] error:&error];require(p!=nil,"Compute pipeline failed");return p;};
    auto sky=renderPipeline(@"skyVertex",@"skyFragment",MTLPixelFormatRGBA16Float,true),sun=renderPipeline(@"celestialVertex",@"celestialFragment",MTLPixelFormatRGBA16Float,true),composite=renderPipeline(@"skyVertex",@"compositeClouds",MTLPixelFormatRGBA16Float,false),tone=renderPipeline(@"skyVertex",@"toneMap",MTLPixelFormatRGBA8Unorm_sRGB,false);
    auto noiseKernel=computePipeline(@"makeCloudNoise"),shadowKernel=computePipeline(@"cloudShadowMap"),cloudKernel=computePipeline(@"marchClouds"),extract=computePipeline(@"extractBloom"),blur=computePipeline(@"blurBloom");
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:gpu];
    auto load=[&](NSString *path,bool srgb){id<MTLTexture> t=[loader newTextureWithContentsOfURL:[NSURL fileURLWithPath:[root stringByAppendingPathComponent:path]] options:@{MTKTextureLoaderOptionSRGB:@(srgb),MTKTextureLoaderOptionGenerateMipmaps:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:&error];if(!t)fprintf(stderr,"Texture %s: %s\n",path.UTF8String,error.localizedDescription.UTF8String);require(t!=nil,"Missing image");return t;};
    auto earth=load(@"Native/Assets/earth-8k.jpg",true),cloudMap=load(@"Native/Assets/earth-clouds.png",false),ocean=load(@"Native/Assets/earth-ocean-mask.png",false),waves=load(@"Native/Assets/earth-waves.png",false),detail=load(@"Native/Assets/earth-waves-detail.png",false),sunMap=load(@"Native/Assets/Bodies/sun.jpg",true);
    constexpr NSUInteger width=960,height=600,cw=480,ch=300;
    auto texture=[&](MTLPixelFormat format,NSUInteger w,NSUInteger h,MTLTextureUsage usage,MTLStorageMode storage=MTLStorageModePrivate){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];d.usage=usage;d.storageMode=storage;return [gpu newTextureWithDescriptor:d];};
    auto hdr=texture(MTLPixelFormatRGBA16Float,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead),lit=texture(MTLPixelFormatRGBA16Float,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    auto output=texture(MTLPixelFormatRGBA8Unorm_sRGB,width,height,MTLTextureUsageRenderTarget,MTLStorageModeShared),depth=texture(MTLPixelFormatDepth32Float,width,height,MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead);
    auto shadow=texture(MTLPixelFormatR8Unorm,cw,ch,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);
    bool debug=NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_DEBUG"]!=nil;
    id<MTLTexture> clouds[2],data[2],bloom[2];for(int i=0;i<2;++i){clouds[i]=texture(debug?MTLPixelFormatRGBA32Float:MTLPixelFormatRGBA16Float,cw,ch,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite,debug?MTLStorageModeShared:MTLStorageModePrivate);data[i]=texture(MTLPixelFormatRGBA32Float,cw,ch,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite,debug?MTLStorageModeShared:MTLStorageModePrivate);bloom[i]=texture(MTLPixelFormatRGBA16Float,width/4,height/4,MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite);}
    MTLTextureDescriptor *nd=[MTLTextureDescriptor new];nd.textureType=MTLTextureType3D;nd.width=nd.height=nd.depth=128;nd.pixelFormat=MTLPixelFormatRGBA8Unorm;nd.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;nd.storageMode=MTLStorageModePrivate;id<MTLTexture> noise=[gpu newTextureWithDescriptor:nd];
    id<MTLCommandQueue> queue=[gpu newCommandQueue];id<MTLCommandBuffer> setup=[queue commandBuffer];id<MTLComputeCommandEncoder> setupEncoder=[setup computeCommandEncoder];[setupEncoder setComputePipelineState:noiseKernel];[setupEncoder setTexture:noise atIndex:0];[setupEncoder dispatchThreads:MTLSizeMake(128,128,128) threadsPerThreadgroup:MTLSizeMake(4,4,4)];[setupEncoder endEncoding];[setup commit];[setup waitUntilCompleted];require(setup.error==nil,"Noise setup failed");
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionAlways;ds.depthWriteEnabled=YES;auto skyDepth=[gpu newDepthStencilStateWithDescriptor:ds];ds.depthCompareFunction=MTLCompareFunctionGreater;auto objectDepth=[gpu newDepthStencilStateWithDescriptor:ds];
    auto project=std::filesystem::path(ORBITER_TEST_DATA);loadEphemerides(project/"Src/Celbody");require(loadEarthWeatherMap(project/"Native/Assets/earth-clouds.r8"),"Weather map failed");
    Flight flight;flight.load(project/"Native/Assets/Scenarios/Hawaii sunset.scn");
    NSString *elapsed=NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_ELAPSED"];
    int steps=elapsed?std::clamp((int)(elapsed.doubleValue/.05),0,100000):60;for(int i=0;i<steps;++i)flight.advance(.05);
    if(NSString *later=NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_LATER"]){
        double lat,lon;bodyCoordinates(BodyId::Earth,flight.position,flight.mjd,flight.elapsed,lat,lon);
        flight.mjd+=later.doubleValue/86400.;auto surface=bodySurface(BodyId::Earth,lat,lon,flight.mjd,flight.elapsed);
        flight.position=surface.up*(flight.centralBody().radius+flight.altitude());
        Vector sunDirection=(-bodyState(BodyId::Earth,flight.mjd+flight.elapsed/86400.).position-flight.position).unit();flight.align(sunDirection-surface.up*dotp(sunDirection,surface.up));
    }
    if(NSString *altitude=NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_ALTITUDE"])flight.position=flight.position.unit()*(flight.centralBody().radius+altitude.doubleValue);
    const auto &b=flight.centralBody();double date=flight.mjd+flight.elapsed/86400.;Vector eyeOffset=flight.up*1.467+flight.forward*6.782,eye=flight.position+eyeOffset;
    Vector direction=(flight.forward*cos(-.25)+flight.up*sin(-.25)).unit(),right=crossp(flight.up,direction).unit(),up=crossp(direction,right).unit(),sunDirection=(-(bodyState(BodyId::Earth,date).position+eye)).unit();
    FrameUniforms f{};f.right=v4(right);f.up=v4(up);f.forward=v4(direction);f.position=v4(eye/b.radius);f.sun=v4(sunDirection,1);
    f.screen={(float)width,(float)height,(float)tan(25*RAD),(float)(b.rotation(date)/Pi2)};f.environment={(float)(eye.length()/b.radius-1),(float)(eye.length()-b.radius),0,(float)flight.elapsed};
    f.body={(float)b.radius,1,13000,0};f.haze={.1,.33,.75,78000};f.equatorX=v4(b.equatorX(),1);f.pole=v4(b.pole());f.equatorZ=v4(b.equatorZ());f.surfaceColor=v4(b.color,(int)b.id);
    f.weather={(float)flight.weatherPreset,(float)flight.currentWeather().storm,(float)flight.currentWeather().rain,0};f.weatherWind=v4(flight.airRelativeVelocity());
    CelestialUniforms s{};double distance=(bodyState(BodyId::Earth,date).position+eye).length();s.directionRadius=v4(sunDirection,(float)(body(BodyId::Sun).radius/distance));f.sunShape={s.directionRadius.w,0,0,0};s.axisX=v4({1,0,0});s.pole=v4({0,1,0},2);s.axisZ=v4({0,0,1},1);s.light=v4({0,1,0},(float)distance);s.material=v4({1,.8,.4},0);
    auto render=[&](bool withClouds){
        f.clouds={1800,6500,withClouds?.48f:0,0};f.environment.z=0;double gpuMs=0;
        for(uint32_t frame=0;frame<6;++frame){
            NSUInteger index=frame%2,previous=1-index;id<MTLCommandBuffer> cb=[queue commandBuffer];
            id<MTLComputeCommandEncoder> c=[cb computeCommandEncoder];[c setComputePipelineState:shadowKernel];[c setBytes:&f length:sizeof(f) atIndex:0];[c setTexture:noise atIndex:0];[c setTexture:shadow atIndex:1];[c setTexture:cloudMap atIndex:2];[c dispatchThreads:MTLSizeMake(cw,ch,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[c endEncoding];
            MTLRenderPassDescriptor *p=[MTLRenderPassDescriptor renderPassDescriptor];p.colorAttachments[0].texture=hdr;p.colorAttachments[0].loadAction=MTLLoadActionClear;p.colorAttachments[0].storeAction=MTLStoreActionStore;p.depthAttachment.texture=depth;p.depthAttachment.loadAction=MTLLoadActionClear;p.depthAttachment.clearDepth=0;p.depthAttachment.storeAction=MTLStoreActionStore;
            id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:p];[e setRenderPipelineState:sky];[e setDepthStencilState:skyDepth];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentTexture:earth atIndex:0];[e setFragmentTexture:shadow atIndex:1];[e setFragmentTexture:earth atIndex:2];[e setFragmentTexture:ocean atIndex:3];[e setFragmentTexture:cloudMap atIndex:4];[e setFragmentTexture:waves atIndex:5];[e setFragmentTexture:detail atIndex:6];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [e setRenderPipelineState:sun];[e setDepthStencilState:objectDepth];[e setVertexBytes:&f length:sizeof(f) atIndex:0];[e setVertexBytes:&s length:sizeof(s) atIndex:1];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentBytes:&s length:sizeof(s) atIndex:1];[e setFragmentTexture:sunMap atIndex:0];[e setFragmentTexture:sunMap atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];[e endEncoding];
            c=[cb computeCommandEncoder];[c setComputePipelineState:cloudKernel];[c setBytes:&f length:sizeof(f) atIndex:0];[c setBytes:&frame length:sizeof(frame) atIndex:1];[c setTexture:noise atIndex:0];[c setTexture:depth atIndex:1];[c setTexture:clouds[previous] atIndex:2];[c setTexture:data[previous] atIndex:3];[c setTexture:clouds[index] atIndex:4];[c setTexture:data[index] atIndex:5];[c setTexture:cloudMap atIndex:6];[c dispatchThreads:MTLSizeMake(cw,ch,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];[c endEncoding];
            p=[MTLRenderPassDescriptor renderPassDescriptor];p.colorAttachments[0].texture=lit;p.colorAttachments[0].loadAction=MTLLoadActionDontCare;p.colorAttachments[0].storeAction=MTLStoreActionStore;
            e=[cb renderCommandEncoderWithDescriptor:p];[e setRenderPipelineState:composite];[e setFragmentBytes:&f length:sizeof(f) atIndex:0];[e setFragmentTexture:hdr atIndex:0];[e setFragmentTexture:clouds[index] atIndex:1];[e setFragmentTexture:data[index] atIndex:2];[e setFragmentTexture:depth atIndex:3];[e setFragmentTexture:cloudMap atIndex:4];[e setFragmentTexture:noise atIndex:5];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
            c=[cb computeCommandEncoder];[c setComputePipelineState:extract];[c setTexture:lit atIndex:0];[c setTexture:bloom[0] atIndex:1];[c dispatchThreads:MTLSizeMake(width/4,height/4,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
            [c setComputePipelineState:blur];for(uint32_t vertical=0;vertical<2;++vertical){[c setBytes:&vertical length:sizeof(vertical) atIndex:0];[c setTexture:bloom[vertical?1:0] atIndex:0];[c setTexture:bloom[vertical?0:1] atIndex:1];[c dispatchThreads:MTLSizeMake(width/4,height/4,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];}[c endEncoding];
            p=[MTLRenderPassDescriptor renderPassDescriptor];p.colorAttachments[0].texture=output;p.colorAttachments[0].loadAction=MTLLoadActionDontCare;p.colorAttachments[0].storeAction=MTLStoreActionStore;e=[cb renderCommandEncoderWithDescriptor:p];[e setRenderPipelineState:tone];[e setFragmentTexture:lit atIndex:0];[e setFragmentTexture:bloom[0] atIndex:1];[e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
            [cb commit];[cb waitUntilCompleted];if(cb.error)fprintf(stderr,"Render: %s\n",cb.error.localizedDescription.UTF8String);require(cb.error==nil,"Sunset frame failed");
            if(frame>=2)gpuMs+=(cb.GPUEndTime-cb.GPUStartTime)*1000;
            f.previousRight=f.right;f.previousUp=f.up;f.previousForward=f.forward;f.previousPosition=f.position;f.environment.z=1;
        }
        if(NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_TIMING"])printf("Sunset %s: %.3f ms GPU, %lux%lu offscreen\n",withClouds?"clouds":"clear",gpuMs/4,(unsigned long)width,(unsigned long)height);
        std::vector<uint8_t> pixels(width*height*4);[output getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;
    };
    auto clear=render(false),cloudy=render(true);auto write=[&](NSString *suffix,const auto &pixels){NSString *base=NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_PREVIEW"];if(!base.length)return;NSBitmapImageRep *out=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(out.bitmapData,pixels.data(),pixels.size());[[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[base stringByAppendingString:suffix] atomically:YES];};
    write(@"-clear.png",clear);write(@"-clouds.png",cloudy);
    if(debug){
        std::vector<float> cv(cw*ch*4),dv(cw*ch*4);
        [clouds[1] getBytes:cv.data() bytesPerRow:cw*16 fromRegion:MTLRegionMake2D(0,0,cw,ch) mipmapLevel:0];
        [data[1] getBytes:dv.data() bytesPerRow:cw*16 fromRegion:MTLRegionMake2D(0,0,cw,ch) mipmapLevel:0];
        for(int y=55;y<85;++y){size_t i=(size_t(y)*cw+cw/2)*4;printf("cloud row %d: rgb %.3f %.3f %.3f a %.3f geom %.0f sample %.0f start %.0f\n",y,cv[i],cv[i+1],cv[i+2],cv[i+3],dv[i],dv[i+1],dv[i+2]);}
    }
    if(!shaderDirectory.length&&!NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_ALTITUDE"]&&!NSProcessInfo.processInfo.environment[@"ORBITER_SUNSET_LATER"]){
        auto channel=[&](const auto &p,int x,int y,int c){return int(p[(size_t(y)*width+x)*4+c]);};
        double maxJump=0;for(int y=100;y<190;++y)for(int c=0;c<3;++c){double delta=0;for(int x=0;x<(int)width;++x)delta+=channel(cloudy,x,y+1,c)-channel(cloudy,x,y,c);maxJump=std::max(maxJump,fabs(delta/width));}
        require(maxJump<6,"The Hawaii cloud layer must not form a rectangular horizon stripe");
        require(channel(cloudy,width/2,10,2)>channel(cloudy,width/2,10,0)+8,"The upper sunset sky keeps blue skylight");
        require(channel(cloudy,width/2,145,0)>channel(cloudy,width/2,145,2)+8,"The setting Sun warms the horizon");
        double nearOcean=0,nearHorizon=0;for(int x=0;x<(int)width;++x){nearOcean+=channel(cloudy,x,550,0)+channel(cloudy,x,550,1)+channel(cloudy,x,550,2);nearHorizon+=channel(cloudy,x,145,0)+channel(cloudy,x,145,1)+channel(cloudy,x,145,2);}
        require(nearOcean+90*width<nearHorizon,"Scattered weather leaves the ocean visible");
        size_t changed=0;for(size_t i=0;i<cloudy.size();i+=4)if(abs(int(cloudy[i])-int(clear[i]))>3)++changed;require(changed>1000,"The Hawaii scene retains visible clouds");
        float solarRadius=f.sunShape.x;f.sunShape.x=0;auto noHalo=render(false);f.sunShape.x=solarRadius;
        size_t haloPixels=0;for(size_t i=0;i<clear.size();i+=4)if(int(clear[i])>int(noHalo[i])+3)++haloPixels;
        require(haloPixels>100,"Atmospheric scattering creates a visible halo around the Sun");
        f.sun.w=0;auto eclipsed=render(false);f.sunShape.x=0;auto eclipsedNoHalo=render(false);
        require(eclipsed==eclipsedNoHalo,"The atmospheric halo disappears when the Sun is occluded");
        f.sun.w=1;f.sunShape.x=solarRadius;f.position=v4(eye.unit()*(1+150000./b.radius));f.environment.x=150000./b.radius;f.environment.y=150000;
        auto high=render(false);f.sunShape.x=0;auto highNoHalo=render(false);
        size_t highHalo=0;for(size_t i=0;i<high.size();i+=4)if(int(high[i])>int(highNoHalo[i])+3)++highHalo;
        require(highHalo<haloPixels/20,"The solar halo fades when the observer is above the atmosphere");
    }
    printf("Hawaii sun elevation %.2f deg; camera height %.0f m\n",Deg(asin(dotp(eye.unit(),sunDirection))),eye.length()-b.radius);
    return 0;
}}

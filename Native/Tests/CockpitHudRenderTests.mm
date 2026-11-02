#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "CockpitHUD.h"
#include "VisualTypes.h"
#include "Mesh.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace native;
struct Object {simd_float4x4 model;simd_float4 color,options,specular,emission;};
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    [NSApplication sharedApplication];id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA;NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"Missing Metal source");[source appendFormat:@"%@\n",part];}
    id<MTLLibrary> library=[gpu newLibraryWithSource:source options:nil error:&error];if(!library)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(library!=nil,"Metal shader compilation failed");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[library newFunctionWithName:@"meshVertex"];pd.fragmentFunction=[library newFunctionWithName:@"meshFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    pd.colorAttachments[0].blendingEnabled=YES;pd.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;pd.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;pd.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;pd.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> pipeline=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(pipeline!=nil,"HUD pipeline failed");
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[gpu newDepthStencilStateWithDescriptor:ds];
    auto mesh=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/DeltaGlider/Meshes/deltaglider_vc.msh");
    check(mesh.groups.size()>132&&mesh.groups[132].label.find("HUDDISP")!=std::string::npos,"Original HUD surface exists");auto &group=mesh.groups[132];
    id<MTLBuffer> vertices=[gpu newBufferWithBytes:group.vertices.data() length:group.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];id<MTLBuffer> indices=[gpu newBufferWithBytes:group.indices.data() length:group.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    Flight flight;flight.hud.mode=2;NSBitmapImageRep *rep=makeCockpitHud(flight);
    auto bitmap=[](const Flight &f){NSBitmapImageRep *r=makeCockpitHud(f);return std::vector<uint8_t>(r.bitmapData,r.bitmapData+512*512*4);};
    auto changed=[](const std::vector<uint8_t> &a,const std::vector<uint8_t> &b){size_t n=0;for(size_t i=3;i<a.size();i+=4)if(a[i]!=b[i])++n;return n;};
    auto surface=bitmap(flight);Flight tilted=flight;tilted.forward=(flight.forward*.94+flight.up*.342).unit();tilted.up=crossp(tilted.forward,tilted.right).unit();
    check(changed(surface,bitmap(tilted))>500,"Surface HUD responds to pitch and velocity direction");
    flight.hud.mode=1;auto orbitHud=bitmap(flight);check(changed(surface,orbitHud)>500,"Orbit and surface modes have distinct symbology");
    Flight docking;docking.startISSApproach();auto dockHud=bitmap(docking);check(changed(orbitHud,dockHud)>500,"Docking mode shows its own target display");
    docking.reference=BodyId::Moon;check(changed(dockHud,bitmap(docking))>200,"Docking target and gates disappear away from Earth");
    flight.hud.mode=2;
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:512 height:512 mipmapped:NO];td.usage=MTLTextureUsageShaderRead;td.storageMode=MTLStorageModeShared;id<MTLTexture> hud=[gpu newTextureWithDescriptor:td];[hud replaceRegion:MTLRegionMake2D(0,0,512,512) mipmapLevel:0 withBytes:rep.bitmapData bytesPerRow:2048];
    MTLTextureDescriptor *nd=[MTLTextureDescriptor new];nd.textureType=MTLTextureType3D;nd.width=nd.height=nd.depth=1;nd.pixelFormat=MTLPixelFormatRGBA8Unorm;nd.usage=MTLTextureUsageShaderRead;id<MTLTexture> noise=[gpu newTextureWithDescriptor:nd];
    constexpr int width=640,height=640;td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;id<MTLTexture> image=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[gpu newTextureWithDescriptor:td];id<MTLCommandQueue> queue=[gpu newCommandQueue];
    Object object{};object.model.columns[0]={1,0,0,0};object.model.columns[1]={0,1,0,0};object.model.columns[2]={0,0,1,0};object.model.columns[3]={0,-1.467f,-6.782f,1};object.color={0,1,0,1};object.options={5,0,0,0};
    id<MTLTexture> material=nil;
    auto render=[&](float yaw,float tanHalf){FrameUniforms f{};f.right={cosf(yaw),0,-sinf(yaw),0};f.up={0,1,0,0};f.forward={sinf(yaw),0,cosf(yaw),0};
        if(object.options.x<0){f.sun={0,0,-1,1};f.position={0,1,0,0};}
        f.projection.columns[0]={1/tanHalf,0,0,0};f.projection.columns[1]={0,1/tanHalf,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2,0};
        id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=image;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].clearColor=MTLClearColorMake(.08,.15,.24,1);pass.colorAttachments[0].storeAction=MTLStoreActionStore;pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
        id<MTLRenderCommandEncoder> e=[cb renderCommandEncoderWithDescriptor:pass];[e setRenderPipelineState:pipeline];[e setDepthStencilState:depthState];[e setCullMode:MTLCullModeNone];[e setVertexBuffer:vertices offset:0 atIndex:0];[e setVertexBytes:&f length:sizeof(f) atIndex:1];[e setVertexBytes:&object length:sizeof(object) atIndex:2];float dummy[12]={};[e setVertexBytes:dummy length:sizeof(dummy) atIndex:3];[e setFragmentBytes:&f length:sizeof(f) atIndex:1];[e setFragmentBytes:&object length:sizeof(object) atIndex:2];[e setFragmentTexture:hud atIndex:0];[e setFragmentTexture:hud atIndex:1];[e setFragmentTexture:hud atIndex:2];[e setFragmentTexture:hud atIndex:3];[e setFragmentTexture:hud atIndex:4];[e setFragmentTexture:noise atIndex:5];[e setFragmentTexture:material?:hud atIndex:6];[e drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:group.indices.size() indexType:MTLIndexTypeUInt32 indexBuffer:indices indexBufferOffset:0];[e endEncoding];[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"HUD render failed");
        std::vector<uint8_t> pixels(width*height*4);[image getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];return pixels;};
    auto stats=[](const std::vector<uint8_t> &pixels){double count=0,xsum=0;for(int y=0;y<height;++y)for(int x=0;x<width;++x){size_t i=(y*width+x)*4;if(pixels[i+1]>100&&pixels[i+1]>pixels[i]*2){++count;xsum+=x;}}return std::array<double,2>{count,count?xsum/count:0};};
    auto straight=render(0,.466f),turned=render(.12f,.466f),zoomed=render(0,.30f),away=render(.9f,.466f);auto base=stats(straight),turn=stats(turned),zoom=stats(zoomed),miss=stats(away);
    check(base[0]>200&&base[0]<width*height/10,"HUD symbols occupy only a small transparent portion of the combiner");
    check(turn[0]>100&&turn[1]<base[1]-35,"HUD moves with the cockpit geometry when looking to the side");
    check(zoom[0]>base[0]*1.3,"HUD grows with cockpit zoom");check(miss[0]==0,"HUD disappears when looking away from the combiner");
    group=mesh.groups[77];vertices=[gpu newBufferWithBytes:group.vertices.data() length:group.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];indices=[gpu newBufferWithBytes:group.indices.data() length:group.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];object.options={6,0,0,0};
    auto glass=render(0,.466f);size_t glassPixels=0;int maxDifference=0;
    for(size_t i=0;i<glass.size();i+=4){int difference=abs(int(glass[i])-int(away[i]))+abs(int(glass[i+1])-int(away[i+1]))+abs(int(glass[i+2])-int(away[i+2]));if(difference>2)++glassPixels;maxDifference=std::max(maxDifference,difference);}
    check(glassPixels>100&&maxDifference<100,"Dry canopy has a subtle transparent surface");
    // The unmarked interior material must use its own texture, not the
    // original label atlas, and work through the normal Metal mesh path.
    group.vertices={{-.2f,1.267f,7.20f,0,0,-1,0,0},{.2f,1.267f,7.20f,0,0,-1,1,0},{.2f,1.667f,7.20f,0,0,-1,1,1},{-.2f,1.667f,7.20f,0,0,-1,0,1}};
    group.indices={0,1,2,0,2,3};vertices=[gpu newBufferWithBytes:group.vertices.data() length:group.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];indices=[gpu newBufferWithBytes:group.indices.data() length:group.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];td.usage=MTLTextureUsageShaderRead;td.storageMode=MTLStorageModeShared;
    material=[gpu newTextureWithDescriptor:td];uint32_t pigment=0xff0000ff;[material replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pigment bytesPerRow:4];
    object.options={-1,0,0,0};object.color={1,1,1,1};auto redMaterial=render(0,.466f);
    pigment=0xffff0000;[material replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&pigment bytesPerRow:4];auto blueMaterial=render(0,.466f);
    size_t center=(height/2*width+width/2)*4;
    check(redMaterial[center]>redMaterial[center+2]+80&&blueMaterial[center+2]>blueMaterial[center]+80,"Cockpit coating samples its replacement texture");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_COCKPIT_HUD_PREVIEW"];if(path.length){NSBitmapImageRep *out=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(out.bitmapData,straight.data(),straight.size());[[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    std::cout<<"cockpit HUD geometry and projection verified\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

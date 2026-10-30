#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#include "Flight.h"
#include "Mesh.h"
#include "VisualTypes.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace native;
struct Object {simd_float4x4 model;simd_float4 color,options,specular,emission;};
static simd_float4 v4(const Vector &v,float w=0){return {(float)v.x,(float)v.y,(float)v.z,w};}
static void check(bool value,const char *message){if(!value)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    [NSApplication sharedApplication];id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA;NSError *error=nil;NSMutableString *source=[NSMutableString string];
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"Missing shader source");[source appendFormat:@"%@\n",part];}
    id<MTLLibrary> lib=[gpu newLibraryWithSource:source options:nil error:&error];if(!lib)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(lib!=nil,"Shader compilation");
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"meshVertex"];pd.fragmentFunction=[lib newFunctionWithName:@"meshFragment"];pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;pd.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    pd.colorAttachments[0].blendingEnabled=YES;pd.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;pd.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> pipeline=[gpu newRenderPipelineStateWithDescriptor:pd error:&error];check(pipeline!=nil,"ISS pipeline");
    MTLDepthStencilDescriptor *ds=[MTLDepthStencilDescriptor new];ds.depthCompareFunction=MTLCompareFunctionGreater;ds.depthWriteEnabled=YES;id<MTLDepthStencilState> depthState=[gpu newDepthStencilStateWithDescriptor:ds];
    auto mesh=loadMesh(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/ISS/Meshes/ProjectAlpha_ISS.msh");
    NSMutableArray<id<MTLTexture>> *textures=[NSMutableArray new];
    auto texture=[&](const Image &img){MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm_sRGB width:img.width height:img.height mipmapped:NO];id<MTLTexture> tex=[gpu newTextureWithDescriptor:d];[tex replaceRegion:MTLRegionMake2D(0,0,img.width,img.height) mipmapLevel:0 withBytes:img.rgba.data() bytesPerRow:img.width*4];return tex;};
    Image white{1,1,{255,255,255,255}};[textures addObject:texture(white)];
    for(const auto &name:mesh.textures){auto file=std::filesystem::path(name).filename().string();std::transform(file.begin(),file.end(),file.begin(),[](unsigned char c){return std::tolower(c);});[textures addObject:texture(loadDDS(std::filesystem::path(ORBITER_TEST_DATA)/"Src/Vessel/ISS/Textures"/file))];}
    constexpr int width=800,height=600;MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModeShared;id<MTLTexture> image=[gpu newTextureWithDescriptor:td];
    td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float width:width height:height mipmapped:NO];td.usage=MTLTextureUsageRenderTarget;td.storageMode=MTLStorageModePrivate;id<MTLTexture> depth=[gpu newTextureWithDescriptor:td];
    Flight ship;ship.startISSApproach();auto station=issState(ship.issOrbit,ship.mjd);
    Vector eye=ship.position+ship.up*1.467+ship.forward*6.782;
    FrameUniforms f{};float h=tan(25*RAD);f.projection.columns[0]={1/(h*width/height),0,0,0};f.projection.columns[1]={0,1/h,0,0};f.projection.columns[2]={0,0,0,-1};f.projection.columns[3]={0,0,.2,0};
    f.right=v4(ship.right);f.up=v4(ship.up);f.forward=v4(ship.forward);f.position=v4(eye/EarthRadius);f.sun=v4(-ship.forward,1);f.screen={(float)width,(float)height,h,0};f.body={(float)EarthRadius,0,0,0};
    Object object{};object.model.columns[0]=v4(station.right);object.model.columns[1]=v4(station.up);object.model.columns[2]=v4(station.forward);object.model.columns[3]=v4(station.position-eye,1);
    id<MTLCommandQueue> queue=[gpu newCommandQueue];id<MTLCommandBuffer> cb=[queue commandBuffer];MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=image;pass.colorAttachments[0].loadAction=MTLLoadActionClear;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1);pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction=MTLLoadActionClear;pass.depthAttachment.clearDepth=0;pass.depthAttachment.storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> enc=[cb renderCommandEncoderWithDescriptor:pass];[enc setRenderPipelineState:pipeline];[enc setDepthStencilState:depthState];[enc setCullMode:MTLCullModeNone];[enc setVertexBytes:&f length:sizeof(f) atIndex:1];[enc setFragmentBytes:&f length:sizeof(f) atIndex:1];[enc setFragmentTexture:textures[0] atIndex:1];float dummy[12]={};[enc setVertexBytes:dummy length:sizeof(dummy) atIndex:3];
    for(const auto &g:mesh.groups){const auto &m=mesh.materials[g.material];object.color={m.diffuse[0],m.diffuse[1],m.diffuse[2],m.diffuse[3]};id<MTLBuffer> vb=[gpu newBufferWithBytes:g.vertices.data() length:g.vertices.size()*sizeof(Vertex) options:MTLResourceStorageModeShared];id<MTLBuffer> ib=[gpu newBufferWithBytes:g.indices.data() length:g.indices.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];[enc setVertexBuffer:vb offset:0 atIndex:0];[enc setVertexBytes:&object length:sizeof(object) atIndex:2];[enc setFragmentBytes:&object length:sizeof(object) atIndex:2];[enc setFragmentTexture:textures[g.texture] atIndex:0];[enc drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:g.indices.size() indexType:MTLIndexTypeUInt32 indexBuffer:ib indexBufferOffset:0];}
    [enc endEncoding];[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"ISS rendering failed");
    std::vector<uint8_t> pixels(width*height*4);[image getBytes:pixels.data() bytesPerRow:width*4 fromRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0];size_t visible=0;for(size_t i=0;i<pixels.size();i+=4)if(pixels[i]+pixels[i+1]+pixels[i+2]>30)++visible;
    check(visible>500,"ISS must be visible from the approach cockpit");
    NSString *path=NSProcessInfo.processInfo.environment[@"ORBITER_ISS_PREVIEW"];if(path.length){NSBitmapImageRep *out=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width*4 bitsPerPixel:32];memcpy(out.bitmapData,pixels.data(),pixels.size());[[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];}
    std::cout<<"ISS visible from 50 m approach: "<<visible<<" pixels\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

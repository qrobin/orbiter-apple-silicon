#import "RayShadows.h"
#include <cstdio>
@implementation RayShadows
+ (BOOL)supportsDevice:(id<MTLDevice>)device {
    if(@available(macOS 14.0,*))return device&&device.supportsRaytracing&&device.supportsRaytracingFromRender&&[device supportsFamily:MTLGPUFamilyApple9];
    return NO;
}
- (instancetype)initWithDevice:(id<MTLDevice>)device queue:(id<MTLCommandQueue>)queue source:(NSString *)source geometry:(NSArray<MTLAccelerationStructureGeometryDescriptor *> *)geometry samples:(NSUInteger)samples colorFormat:(MTLPixelFormat)format {
    if(![RayShadows supportsDevice:device]||!queue||!source.length||!geometry.count)return nil;
    if(!(self=[super init]))return nil;
    NSError *error=nil;id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){fprintf(stderr,"Ray-traced shadows unavailable: %s\n",error.localizedDescription.UTF8String);return nil;}
    MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[library newFunctionWithName:@"meshVertex"];p.fragmentFunction=[library newFunctionWithName:@"rayShadowMeshFragment"];
    p.colorAttachments[0].pixelFormat=format;p.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;p.rasterSampleCount=samples;
    p.colorAttachments[0].blendingEnabled=YES;p.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;p.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    p.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;p.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    _pipeline=[device newRenderPipelineStateWithDescriptor:p error:&error];
    if(!_pipeline){fprintf(stderr,"Ray-traced shadows unavailable: %s\n",error.localizedDescription.UTF8String);return nil;}
    MTLPrimitiveAccelerationStructureDescriptor *description=[MTLPrimitiveAccelerationStructureDescriptor descriptor];description.geometryDescriptors=geometry;
    MTLAccelerationStructureSizes sizes=[device accelerationStructureSizesWithDescriptor:description];
    _structure=[device newAccelerationStructureWithSize:sizes.accelerationStructureSize];
    id<MTLBuffer> scratch=[device newBufferWithLength:MAX(256,sizes.buildScratchBufferSize) options:MTLResourceStorageModePrivate];
    if(!_structure||!scratch)return nil;
    id<MTLCommandBuffer> cb=[queue commandBuffer];id<MTLAccelerationStructureCommandEncoder> encoder=[cb accelerationStructureCommandEncoder];
    if(!encoder)return nil;
    [encoder buildAccelerationStructure:_structure descriptor:description scratchBuffer:scratch scratchBufferOffset:0];[encoder endEncoding];[cb commit];[cb waitUntilCompleted];
    if(cb.error){fprintf(stderr,"Ray-traced shadows unavailable: %s\n",cb.error.localizedDescription.UTF8String);return nil;}
    _enabled=YES;return self;
}
@end

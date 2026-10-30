#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "VisualTypes.h"
#include "Flight.h"

@interface NativeVisuals : NSObject
@property(nonatomic) NSInteger weather;
@property(nonatomic,readonly) id<MTLTexture> cloudNoise,cloudShadows,vesselCloudShadow;
- (id<MTLTexture>)satelliteClouds;
- (id<MTLTexture>)oceanMask;
- (id<MTLTexture>)oceanWaves;
- (id<MTLTexture>)oceanWaveDetail;
@property(nonatomic,readonly) NSUInteger cloudWidth,cloudHeight,emitterCount;
@property(nonatomic,readonly) MTLRenderPassDescriptor *scenePass;
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library queue:(id<MTLCommandQueue>)queue samples:(NSUInteger)samples;
- (void)prepare:(FrameUniforms *)frame width:(NSUInteger)width height:(NSUInteger)height;
- (void)encodeShadows:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)frame vesselPosition:(Vector)position;
- (void)encodeWeather:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)frame;
- (void)encodeExhaust:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)frame flight:(const native::Flight &)flight offset:(Vector)offset;
- (void)encodeCockpitRain:(id<MTLCommandBuffer>)cb frame:(const FrameUniforms &)frame model:(simd_float4x4)model vertices:(id<MTLBuffer>)vertices indices:(id<MTLBuffer>)indices count:(NSUInteger)count;
- (void)encodePresent:(id<MTLCommandBuffer>)cb drawable:(id<CAMetalDrawable>)drawable headroom:(float)headroom;
- (NSUInteger)liveTrailPuffCount;
- (NSString *)weatherName;
- (void)reset;
- (void)resetForReferenceChange;
@end

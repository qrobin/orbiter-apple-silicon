#import <Metal/Metal.h>

// Optional hardware ray-traced sunlight visibility for the rigid glider hull.
@interface RayShadows : NSObject
@property(nonatomic,readonly) id<MTLRenderPipelineState> pipeline;
@property(nonatomic,readonly) id<MTLAccelerationStructure> structure;
@property(nonatomic) BOOL enabled;
+ (BOOL)supportsDevice:(id<MTLDevice>)device;
- (instancetype)initWithDevice:(id<MTLDevice>)device queue:(id<MTLCommandQueue>)queue source:(NSString *)source geometry:(NSArray<MTLAccelerationStructureGeometryDescriptor *> *)geometry samples:(NSUInteger)samples colorFormat:(MTLPixelFormat)format;
@end

#import <MetalKit/MetalKit.h>
#include "Flight.h"
#include "VisualTypes.h"
@interface SolarRenderer : NSObject
@property(nonatomic,readonly) id<MTLTexture> rings;
- (instancetype)initWithDevice:(id<MTLDevice>)device library:(id<MTLLibrary>)library samples:(NSUInteger)samples earth:(id<MTLTexture>)earth;
- (id<MTLTexture>)textureForBody:(native::BodyId)body;
- (void)updateFrame:(FrameUniforms *)frame flight:(const native::Flight &)flight offset:(Vector)offset;
- (void)encodeBodies:(id<MTLRenderCommandEncoder>)encoder frame:(const FrameUniforms &)frame flight:(const native::Flight &)flight offset:(Vector)offset;
@end

#import <Metal/Metal.h>
#include "VisualTypes.h"
#include <cmath>
#include <iostream>
#include <stdexcept>
static void check(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
int main(){@autoreleasepool{try{
    id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();if(!gpu)return 77;
    NSString *root=@ORBITER_TEST_DATA;NSMutableString *source=[NSMutableString string];NSError *error=nil;
    for(NSString *name in @[@"Native/macOS/VisualTypes.h",@"Native/macOS/NativeVisuals.metal",@"Native/macOS/Shaders.metal",@"Native/macOS/SolarSystem.metal"]){
        NSString *part=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:&error];check(part!=nil,"missing shader source");[source appendFormat:@"%@\n",part];
    }
    [source appendString:@"kernel void testLights(constant FrameUniforms &f [[buffer(0)]],device float4 *out [[buffer(1)]],uint i [[thread_position_in_grid]]) { float3 p=i==1?float3(0,0,20):i==2?float3(5,0,1):float3(0,0,1); float3 n=float3(0,0,-1); out[i]=float4(vesselIllumination(f,p,n,i==3),1); }"];
    id<MTLLibrary> lib=[gpu newLibraryWithSource:source options:nil error:&error];if(!lib)std::cerr<<error.localizedDescription.UTF8String<<'\n';check(lib!=nil,"lighting shaders compile");
    id<MTLComputePipelineState> pipeline=[gpu newComputePipelineStateWithFunction:[lib newFunctionWithName:@"testLights"] error:&error];check(pipeline!=nil,"lighting test pipeline");
    FrameUniforms frame{};frame.vesselLights[0].positionRange={0,0,0,10};frame.vesselLights[0].directionOuter={0,0,1,.8};frame.vesselLights[0].colorIntensity={1,.5,.25,1};frame.vesselLights[0].attenuationInner={1,1,.95,0};
    id<MTLBuffer> out=[gpu newBufferWithLength:4*sizeof(simd_float4) options:MTLResourceStorageModeShared];
    auto run=[&](){id<MTLCommandBuffer> cb=[[gpu newCommandQueue] commandBuffer];id<MTLComputeCommandEncoder> enc=[cb computeCommandEncoder];[enc setComputePipelineState:pipeline];[enc setBytes:&frame length:sizeof(frame) atIndex:0];[enc setBuffer:out offset:0 atIndex:1];[enc dispatchThreads:MTLSizeMake(4,1,1) threadsPerThreadgroup:MTLSizeMake(4,1,1)];[enc endEncoding];[cb commit];[cb waitUntilCompleted];check(cb.error==nil,"GPU lighting evaluation failed");};
    run();auto values=(simd_float4 *)out.contents;
    check(values[0].x>.4f&&values[0].y>0&&values[0].z>0,"spotlight lights a facing surface within its cone");
    check(values[1].x==0&&values[2].x==0,"light respects range and cone");
    check(values[3].x==0,"exterior emitter does not illuminate cockpit-only pass");
    frame.vesselLights[0].attenuationInner.w=1;run();
    check(values[0].x==0&&values[3].x>.4f,"cabin floodlight illuminates cockpit only");
    frame.vesselLights[0].colorIntensity.w=0;run();check(values[3].x==0,"switched-off cabin light emits no illumination");
    // Flame sources share this lighting path for hull and ground and coexist with all marker lights.
    frame.vesselLights[19].positionRange={0,0,0,32};frame.vesselLights[19].directionOuter={0,0,0,-1};
    frame.vesselLights[19].colorIntensity={1,.48,.18,1.3};frame.vesselLights[19].attenuationInner={.25,.025,0,0};run();
    check(values[0].x>values[0].y&&values[0].y>values[0].z&&values[0].z>0,"Flame light gives a nearby facing surface a warm glow");
    check(values[1].x>0&&values[1].x<values[0].x,"Flame illumination falls off with distance");
    check(values[2].x>0&&values[3].x==0,"Flame light is omnidirectional and stays outside the cockpit");
    frame.vesselLights[19].colorIntensity.w=0;run();check(values[0].x==0&&values[1].x==0,"Extinguishing the flame removes its illumination");
    std::cout<<"Vessel light shading, cone, range and cabin isolation passed\n";return 0;
}catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}}}

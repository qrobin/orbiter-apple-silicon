#include <metal_raytracing>
using namespace metal::raytracing;

// Ship-local acceleration structure: the basis and origin convert a visible
// fragment and the Sun direction from the renderer's camera-relative frame.
struct RayShadowFrame {float4 right,up,forward,origin;};
fragment float4 rayShadowMeshFragment(Raster in [[stage_in]],constant Frame &f [[buffer(1)]],
    constant Object &o [[buffer(2)]],constant RayShadowFrame &ship [[buffer(4)]],
    primitive_acceleration_structure hull [[buffer(5)]],texture2d<float> tex [[texture(0)]],texture2d<float> shadows [[texture(1)]]) {
    float3 normal=normalize(in.normal);if(dot(normal,-in.world)<0)normal=-normal;
    float visibility=1;
    if(f.sun.w>0&&dot(normal,f.sun.xyz)>.001f){
        float3 world=in.world-ship.origin.xyz;
        float3 p=float3(dot(world,ship.right.xyz),dot(world,ship.up.xyz),dot(world,ship.forward.xyz));
        float3 n=float3(dot(normal,ship.right.xyz),dot(normal,ship.up.xyz),dot(normal,ship.forward.xyz));
        float3 direction=normalize(float3(dot(f.sun.xyz,ship.right.xyz),dot(f.sun.xyz,ship.up.xyz),dot(f.sun.xyz,ship.forward.xyz)));
        ray r;r.origin=p+n*.012f;r.direction=direction;r.min_distance=.003f;r.max_distance=80.0f;
        intersector<triangle_data> trace;trace.accept_any_intersection(true);
        visibility=trace.intersect(r,hull).type==intersection_type::none?1.0f:0.0f;
    }
    return shadeMesh(in,f,o,tex,shadows,visibility);
}

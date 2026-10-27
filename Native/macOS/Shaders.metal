#include <metal_stdlib>
using namespace metal;
struct Frame {
    float4x4 projection;
    float4 cameraRight, cameraUp, cameraForward, cameraPosition;
    float4 sun, screen; // screen: width, height, tan(fov/2), rotation
};
struct Object { float4x4 model; float4 color; float4 options; };
struct Vertex { packed_float3 position; packed_float3 normal; packed_float2 uv; };
struct Raster { float4 position [[position]]; float3 normal; float2 uv; float3 world; };
vertex Raster meshVertex(uint id [[vertex_id]],const device Vertex *vertices [[buffer(0)]],
                         constant Frame &f [[buffer(1)]],constant Object &o [[buffer(2)]]) {
    Raster out; Vertex v=vertices[id]; float3 p=(o.model*float4(float3(v.position),1)).xyz;
    float3 view=float3(dot(p,f.cameraRight.xyz),dot(p,f.cameraUp.xyz),-dot(p,f.cameraForward.xyz));
    out.position=f.projection*float4(view,1);
    out.normal=(o.model*float4(float3(v.normal),0)).xyz;
    out.world=p; out.uv=float2(v.uv); return out;
}
fragment float4 meshFragment(Raster in [[stage_in]],constant Frame &f [[buffer(1)]],
                             constant Object &o [[buffer(2)]],texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,address::repeat, max_anisotropy(8));
    float4 albedo=tex.sample(s,in.uv)*o.color;
    if(albedo.a<.03) discard_fragment();
    float3 normal=normalize(in.normal);
    if(dot(normal,-in.world)<0) normal=-normal;
    float lit=max(0.0f,dot(normal,f.sun.xyz));
    float3 view=normalize(-in.world);
    float spec=pow(max(0.0f,dot(normal,normalize(f.sun.xyz+view))),40.0f)*.18;
    float3 color=albedo.rgb*(.20+lit*.8)+spec;
    return float4(color,albedo.a);
}
struct SkyRaster { float4 position [[position]]; float2 uv; };
vertex SkyRaster skyVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2); return {float4(p*2-1,1,1),p};
}
float hash(float3 p) { return fract(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453); }
fragment float4 skyFragment(SkyRaster in [[stage_in]],constant Frame &f [[buffer(1)]],
                            texture2d<float> earth [[texture(0)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    float2 xy=in.uv*2-1;
    float3 ray=normalize(f.cameraForward.xyz+f.cameraRight.xyz*xy.x*f.screen.z*(f.screen.x/f.screen.y)+f.cameraUp.xyz*xy.y*f.screen.z);
    float3 origin=f.cameraPosition.xyz;
    float b=dot(origin,ray), c=dot(origin,origin)-1, disc=b*b-c;
    float3 sky=float3(.0008,.0012,.0025);
    float3 cell=floor(ray*900);
    float star=hash(cell);
    if(star>.9987) {
        float3 center=normalize(cell+.5); float d=length(ray-center)*900;
        sky+=float3(.65,.76,1)*pow(max(0.0f,1-d),5.0f)*(star-.9987)*650;
    }
    float sunDot=dot(ray,f.sun.xyz);
    sky+=float3(1,.9,.72)*pow(max(0.0f,sunDot),4000.0f)*3;
    if(disc>=0&&b<0) {
        float t=-b-sqrt(disc); float3 n=normalize(origin+ray*t);
        // Ecliptic to terrestrial equatorial frame (mean obliquity), then Earth rotation.
        float ob=.4090928;
        float3 equ=float3(n.x,n.y*cos(ob)+n.z*sin(ob),-n.y*sin(ob)+n.z*cos(ob));
        float2 uv=float2(atan2(equ.z,equ.x)/(2*M_PI_F)+.5+f.screen.w,acos(clamp(equ.y,-1.0f,1.0f))/M_PI_F);
        float3 base=earth.sample(s,uv).rgb;
        float day=smoothstep(-.14,.16,dot(n,f.sun.xyz));
        float light=max(.03f,dot(n,f.sun.xyz));
        float3 surface=base*(.035+light*.96)*day+base*.018*(1-day);
        float fresnel=pow(1-max(0.0f,dot(n,-ray)),4.0f);
        surface=mix(surface,float3(.14,.37,.68)*(.3+.7*day),fresnel*.72);
        return float4(surface,1);
    }
    float atmosphereDisc=b*b-(dot(origin,origin)-1.025*1.025);
    if(atmosphereDisc>0&&b<0) {
        float closest=sqrt(max(0.0f,dot(origin,origin)-b*b));
        float glow=exp(-(closest-1)*160)*.7;
        float3 n=normalize(origin+ray*(-b));
        float light=smoothstep(-.3,.4,dot(n,f.sun.xyz));
        sky+=float3(.10,.33,.75)*glow*light;
    }
    return float4(sky,1);
}

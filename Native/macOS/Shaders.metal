#include <metal_stdlib>
using namespace metal;
using Frame=FrameUniforms;
struct Object { float4x4 model; float4 color; float4 options; };
struct SwitchUniform { float4 pivotAngle,axisStart,range; };
struct Vertex { packed_float3 position; packed_float3 normal; packed_float2 uv; };
struct Raster { float4 position [[position]]; float3 normal; float2 uv; float3 world; };
vertex Raster meshVertex(uint id [[vertex_id]],const device Vertex *vertices [[buffer(0)]],
                         constant Frame &f [[buffer(1)]],constant Object &o [[buffer(2)]],constant SwitchUniform *switches [[buffer(3)]]) {
    Raster out; Vertex v=vertices[id]; float3 local=float3(v.position),normal=float3(v.normal);float2 uv=float2(v.uv);
    for(int i=0;i<int(o.options.w);++i) {
        SwitchUniform sw=switches[i];
        if(int(o.options.z)!=int(sw.range.y)||id<uint(sw.axisStart.w)||id>=uint(sw.axisStart.w+sw.range.x)) continue;
        if(sw.range.z>.5) {
            local+=sw.axisStart.xyz*sw.pivotAngle.w;
            if(sw.range.z>1.5&&sw.range.z<2.5&&id>=uint(sw.axisStart.w+6))uv.y=(sw.range.w>.5?1.5f:10.5f)/1024;
            continue;
        }
        float3 axis=sw.axisStart.xyz,q=local-sw.pivotAngle.xyz;float c=cos(sw.pivotAngle.w),s=sin(sw.pivotAngle.w);
        local=sw.pivotAngle.xyz+q*c+cross(axis,q)*s+axis*dot(axis,q)*(1-c);
        normal=normal*c+cross(axis,normal)*s+axis*dot(axis,normal)*(1-c);
    }
    float3 p=(o.model*float4(local,1)).xyz;
    float3 view=float3(dot(p,f.right.xyz),dot(p,f.up.xyz),-dot(p,f.forward.xyz));
    out.position=f.projection*float4(view,1);
    out.normal=(o.model*float4(normal,0)).xyz;
    out.world=p; out.uv=uv; return out;
}
fragment float4 meshFragment(Raster in [[stage_in]],constant Frame &f [[buffer(1)]],
                             constant Object &o [[buffer(2)]],texture2d<float> tex [[texture(0)]],texture2d<float> shadows [[texture(1)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,address::repeat, max_anisotropy(8));
    if(o.options.x>2.5) return float4(tex.sample(s,in.uv).rgb,1);
    if(o.options.x>.5) {
        float alpha=o.options.x>1.5?pow(max(0.0f,1-length(in.uv)),2.0f):pow(max(0.0f,1-abs(in.uv.x)),1.5f)*pow(max(0.0f,1-in.uv.y),.65f);
        return float4(o.color.rgb*(1.1+alpha*.7),o.color.a*alpha);
    }
    float4 albedo=tex.sample(s,in.uv)*o.color;
    if(albedo.a<.03) discard_fragment();
    float3 normal=normalize(in.normal);
    if(dot(normal,-in.world)<0) normal=-normal;
    float lit=max(0.0f,dot(normal,f.sun.xyz))*f.sun.w;
    if(f.environment.y<f.clouds.y&&f.clouds.z>0){
        float2 shadowUV=in.position.xy/f.screen.xy;
        lit*=shadows.sample(s,shadowUV).r;
    }
    float3 view=normalize(-in.world);
    float spec=pow(max(0.0f,dot(normal,normalize(f.sun.xyz+view))),40.0f)*.18*f.sun.w;
    float3 color=albedo.rgb*(.025+.175*f.sun.w+o.options.y+lit*.8)+spec;
    return float4(color,albedo.a);
}
vertex SkyRaster skyVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2); return {float4(p*2-1,1,1),p};
}
float hash(float3 p) { return fract(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453); }
struct SkyOutput { float4 color [[color(0)]]; float depth [[depth(any)]]; };

float planetNoise(float3 p){int3 cell=int3(floor(p));float3 u=fract(p);u=u*u*(3-2*u);float v=0;for(int z=0;z<2;++z)for(int y=0;y<2;++y)for(int x=0;x<2;++x){float3 q=float3(x,y,z);float w=(x?u.x:1-u.x)*(y?u.y:1-u.y)*(z?u.z:1-u.z);v+=hash(float3(cell)+q)*w;}return v;}
float3 planetMaterial(float3 n,float2 uv,float3 color,int id,bool mapped,texture2d<float> map){
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    if(mapped)return map.sample(s,uv).rgb;
    float lon=(uv.x-.5)*(2*M_PI_F),col=uv.y*M_PI_F;n=float3(cos(lon)*sin(col),cos(col),sin(lon)*sin(col));
    float broad=planetNoise(n*7),detail=planetNoise(n*85);
    float3 c=color*(.65+.5*broad+.13*detail);
    if(id==10)c=mix(float3(.22,.075,.025),color,smoothstep(.27f,.65f,broad)); // Io: volcanic approximation
    else if(id==11){float veins=pow(abs(sin(n.x*180+n.z*93+broad*12)),24.0f);c=mix(color,float3(.30,.18,.11),veins*.5);}
    else if(id==20)c=color*(.91+.13*broad); // Titan: optically thick haze
    else if(id==22)c*=mix(.22f,1.3f,smoothstep(-.1f,.3f,n.x));
    else {float2 p=uv*float2(240,120);float2 cell=floor(p),q=fract(p)-.5;float seed=hash(float3(cell,1));float r=length(q-float2(seed-.5,fract(seed*37)-.5)*.4);float crater=exp(-pow((r-.22-seed*.1)*35,2.0f))*.15-exp(-r*r*45)*.13;c*=1+crater;}
    return c;
}
float4 ringMaterial(float3 point,float3 ray,float3 pole,float inner,float outer,float3 sun,texture2d<float> rings){
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float r=length(point),u=(r-inner)/(outer-inner);float4 c=rings.sample(s,float2(u,.5));
    float optical=1-pow(max(.001f,1-c.a),1/max(.12f,abs(dot(pole,ray))));
    bool shadow=dot(point,sun)<0&&length(cross(point,sun))<1;
    return float4(c.rgb*(shadow?.09f:.35f+.65f*abs(dot(pole,sun))),optical);
}
fragment SkyOutput skyFragment(SkyRaster in [[stage_in]],constant Frame &f [[buffer(1)]],
    texture2d<float> map [[texture(0)]],texture2d<float> shadows [[texture(1)]],texture2d<float> rings [[texture(2)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    float2 xy=in.uv*2-1;float3 ray=normalize(f.forward.xyz+f.right.xyz*xy.x*f.screen.z*(f.screen.x/f.screen.y)+f.up.xyz*xy.y*f.screen.z);
    float3 origin=f.position.xyz;float height=f.environment.x,radius=f.body.x;
    float b=dot(normalize(origin),ray)*(1+height),c=height*(2+height),disc=b*b-c;
    float3 sky=float3(.0008,.0012,.0025);float3 cell=floor(ray*900);float star=hash(cell);
    if(star>.9987){float3 center=normalize(cell+.5);float d=length(ray-center)*900;sky+=float3(.65,.76,1)*pow(max(0.0f,1-d),5.0f)*(star-.9987)*650;}
    float dayAtCamera=smoothstep(-.18f,.12f,dot(normalize(origin),f.sun.xyz));
    float air=saturate(exp(-max(0.0f,height)*radius/max(1.0f,f.body.z))*dayAtCamera*f.body.y);
    float elevation=max(0.0f,dot(ray,normalize(origin)));
    float3 airColor=mix(f.haze.rgb*1.6,f.haze.rgb*.55,pow(elevation,.35f));sky=mix(sky,airColor,air*.98);
    float distance=1e25;float3 color=sky;
    if(disc>=0&&b<0){
        float t=c/max(1e-12f,-b+sqrt(disc));distance=t;float3 n=normalize(origin+ray*t);float2 uv=terrestrialUV(n,f);
        float3 base=planetMaterial(n,uv,f.surfaceColor.rgb,int(f.surfaceColor.w),f.equatorX.w>.5,map);
        float day=smoothstep(-.06f,.06f,dot(n,f.sun.xyz)),light=max(0.0f,dot(n,f.sun.xyz));
        float cloudShade=shadows.sample(s,in.position.xy/f.screen.xy).r;
        if(f.pole.w>0){float den=dot(f.sun.xyz,f.pole.xyz);float ts=-dot(n,f.pole.xyz)/(abs(den)>.0001?den:.0001f);float3 point=n+f.sun.xyz*ts;float r=length(point);if(ts>0&&r>f.pole.w&&r<f.equatorZ.w)cloudShade*=1-ringMaterial(point,ray,f.pole.xyz,f.pole.w,f.equatorZ.w,f.sun.xyz,rings).a*.85;}
        color=base*(.025+light*cloudShade)*day+base*.008*(1-day);
        if(f.body.w>1.5)color=base*12;
        float detail=1-.10*hash(floor(n*radius/2));color*=mix(1.0f,detail,exp(-max(0.0f,height)*radius/1800));
        float fresnel=pow(1-max(0.0f,dot(n,-ray)),4.0f);
        color=mix(color,f.haze.rgb*(.3+.7*day),fresnel*.55*min(1.0f,f.body.y));
        color=mix(color,airColor,air*(1-exp(-t*radius/35000))*.8);
    }else if(f.body.y>0){
        float limit=1+f.haze.w/radius;float atmosphereDisc=b*b-(dot(origin,origin)-limit*limit);
        if(atmosphereDisc>0&&b<0){float closest=sqrt(max(0.0f,dot(origin,origin)-b*b));float glow=exp(-max(0.0f,closest-1)*radius/max(1.0f,f.body.z))*.7;float3 n=normalize(origin-ray*b);float light=smoothstep(-.3f,.4f,dot(n,f.sun.xyz));color+=f.haze.rgb*glow*light*min(1.0f,f.body.y);}
    }
    if(f.pole.w>0){float den=dot(ray,f.pole.xyz);if(abs(den)>.00001){float t=-dot(origin,f.pole.xyz)/den;float3 point=origin+ray*t;float r=length(point);if(t>0&&t<distance&&r>f.pole.w&&r<f.equatorZ.w){float4 ring=ringMaterial(point,ray,f.pole.xyz,f.pole.w,f.equatorZ.w,f.sun.xyz,rings);color=mix(color,ring.rgb,ring.a);if(ring.a>.05)distance=t;}}}
    float depth=distance<1e24?.2/max(.0001f,distance*radius*dot(ray,f.forward.xyz)):0;
    return {float4(color,1),clamp(depth,0.0f,1.0f)};
}

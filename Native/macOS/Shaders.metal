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
    if(o.options.x>4.5) { float alpha=tex.sample(s,in.uv).a; if(alpha<.03)discard_fragment(); return float4(o.color.rgb,alpha); }
    if(o.options.x>3.5) { float4 label=tex.sample(s,in.uv); if(label.a<.03) discard_fragment(); return label; }
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
// Approximate exponential air columns along a spherical atmosphere. The
// smooth grazing-angle expression avoids a discontinuity at the local horizon.
float atmosphericColumn(float height,float mu,float scaleHeight,float radius,float maximumDistance){
    float density=exp(-max(0.0f,height)/scaleHeight);
    float denominator=max(.0001f,mu+sqrt(mu*mu+2*scaleHeight/radius));
    float column=min(2000000.0f,2*scaleHeight*density/denominator);
    if(maximumDistance<1e20f)column=min(column,maximumDistance*(density+1)*.5f);
    // A camera above the dense air can still see a long sunlit path through
    // it. Approximate surface-bound rays and limb-grazing rays separately.
    if(height>30000.0f&&mu<0){
        float ratio=1+height/radius,external;
        if(maximumDistance<1e20f){
            float surfaceMu=sqrt(max(0.0f,ratio*ratio*mu*mu-(ratio*ratio-1)));
            external=2*scaleHeight/(surfaceMu+sqrt(surfaceMu*surfaceMu+2*scaleHeight/radius));
        }else{
            float closest=radius*(ratio*sqrt(max(0.0f,1-mu*mu))-1);
            external=exp(-max(0.0f,closest)/scaleHeight)*sqrt(2*M_PI_F*radius*scaleHeight);
        }
        column=mix(column,external*.35f,smoothstep(30000.0f,90000.0f,height));
    }
    return column;
}
float3 earthSunTransmission(constant Frame &f){
    float height=max(0.0f,f.environment.x*f.body.x);
    float sunMu=dot(normalize(f.position.xyz),f.sun.xyz);
    float r=atmosphericColumn(height,max(.05f,sunMu),8000.0f,f.body.x,1e25f);
    float m=atmosphericColumn(height,max(.05f,sunMu),1200.0f,f.body.x,1e25f);
    return exp(-(float3(5.8e-6,13.5e-6,33.1e-6)*r+float3(2.1e-5)*m));
}
struct AirLight {float3 transmission,scattering;};
AirLight earthAirLight(constant Frame &f,float3 ray,float maximumDistance){
    float height=max(0.0f,f.environment.x*f.body.x),mu=dot(normalize(f.position.xyz),ray);
    float r=atmosphericColumn(height,mu,8000.0f,f.body.x,maximumDistance);
    float m=atmosphericColumn(height,mu,1200.0f,f.body.x,maximumDistance);
    float3 betaR=float3(5.8e-6,13.5e-6,33.1e-6),betaM=float3(2.1e-5);
    float3 transmission=exp(-(betaR*r+betaM*m));
    float cosine=dot(ray,f.sun.xyz),phaseR=.75f*(1+cosine*cosine),g=.76f;
    float phaseM=(1-g*g)/pow(max(.03f,1+g*g-2*g*cosine),1.5f);
    float sunlight=smoothstep(-.10f,.04f,dot(normalize(f.position.xyz),f.sun.xyz));
    float3 scattered=earthSunTransmission(f)*sunlight*((1-exp(-betaR*r))*phaseR*.95f+(1-exp(-betaM*m))*phaseM*.13f);
    return {transmission,scattered};
}
fragment SkyOutput skyFragment(SkyRaster in [[stage_in]],constant Frame &f [[buffer(1)]],
    texture2d<float> map [[texture(0)]],texture2d<float> shadows [[texture(1)]],texture2d<float> rings [[texture(2)]],
    texture2d<float> oceanMask [[texture(3)]],texture2d<float> cloudMap [[texture(4)]],texture2d<float> oceanWaves [[texture(5)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    float2 xy=in.uv*2-1;float3 ray=normalize(f.forward.xyz+f.right.xyz*xy.x*f.screen.z*(f.screen.x/f.screen.y)+f.up.xyz*xy.y*f.screen.z);
    float3 origin=f.position.xyz;float height=f.environment.x,radius=f.body.x;
    float b=dot(normalize(origin),ray)*(1+height),c=height*(2+height),disc=b*b-c;
    float3 sky=float3(.0008,.0012,.0025);float3 cell=floor(ray*900);float star=hash(cell);
    if(star>.9987){float3 center=normalize(cell+.5);float d=length(ray-center)*900;sky+=float3(.65,.76,1)*pow(max(0.0f,1-d),5.0f)*(star-.9987)*650;}
    float dayAtCamera=smoothstep(-.18f,.12f,dot(normalize(origin),f.sun.xyz));
    float air=saturate(exp(-max(0.0f,height)*radius/max(1.0f,f.body.z))*dayAtCamera*f.body.y);
    float elevation=max(0.0f,dot(ray,normalize(origin)));
    float3 airColor=mix(f.haze.rgb*1.6,f.haze.rgb*.55,pow(elevation,.35f));
    bool earth=int(f.surfaceColor.w)==3;
    float surfaceDistance=disc>=0&&b<0?c/max(1e-12f,-b+sqrt(disc)):1e25;
    AirLight earthAir={float3(1),float3(0)};
    if(earth){earthAir=earthAirLight(f,ray,surfaceDistance<1e24?surfaceDistance*radius:1e25);sky=sky*earthAir.transmission+earthAir.scattering;}
    else sky=mix(sky,airColor,air*.98);
    float distance=1e25;float3 color=sky;
    if(disc>=0&&b<0){
        float t=surfaceDistance;distance=t;float3 n=normalize(origin+ray*t);float2 uv=terrestrialUV(n,f);
        float3 base=planetMaterial(n,uv,f.surfaceColor.rgb,int(f.surfaceColor.w),f.equatorX.w>.5,map);
        float day=smoothstep(-.06f,.06f,dot(n,f.sun.xyz)),light=max(0.0f,dot(n,f.sun.xyz));
        float cloudShade=shadows.sample(s,in.position.xy/f.screen.xy).r;
        if(f.pole.w>0){float den=dot(f.sun.xyz,f.pole.xyz);float ts=-dot(n,f.pole.xyz)/(abs(den)>.0001?den:.0001f);float3 point=n+f.sun.xyz*ts;float r=length(point);if(ts>0&&r>f.pole.w&&r<f.equatorZ.w)cloudShade*=1-ringMaterial(point,ray,f.pole.xyz,f.pole.w,f.equatorZ.w,f.sun.xyz,rings).a*.85;}
        color=base*(.025+light*cloudShade)*day+base*.008*(1-day);
        // Ocean detail is shaded, not displaced geometry. Filter waves whose
        // wavelength is smaller than a pixel to prevent distant shimmer.
        float waveFade=1-smoothstep(22000.0f,55000.0f,t*radius);
        if(int(f.surfaceColor.w)==3&&waveFade>0){
            float water=smoothstep(.35f,.75f,oceanMask.sample(s,uv).r)*waveFade;
            if(water>.001f){
                float regional=cloudMap.sample(s,uv).r;
                float storm=f.weather.x>2.5&&f.weather.x<3.5?.9f:(f.weather.x>3.5?smoothstep(.72f,.97f,regional):0.0f);
                float lon=(uv.x-.5f)*2*M_PI_F,lat=(.5f-uv.y)*M_PI_F;
                float2 metres=float2(lon*cos(lat),lat)*radius;
                // A directional ocean spectrum supplies many irregular wave
                // scales at once. Mipmaps filter distant waves; two advected
                // samples produce motion without a per-pixel FFT or ray march.
                constexpr sampler waveSampler(filter::linear,mip_filter::linear,address::repeat);
                float time=f.environment.w/86400.0f;
                float3 longWave=oceanWaves.sample(waveSampler,metres/16000.0f+float2(24,7)*time).rgb;
                float3 shortWave=oceanWaves.sample(waveSampler,metres/8000.0f+float2(-17,33)*time).rgb;
                float2 slope=((longWave.rg-.5f)*.52f+(shortWave.rg-.5f)*.20f)*(.55+1.5*storm);
                float3 east=cross(n,f.pole.xyz);east=length(east)>.001f?normalize(east):normalize(f.equatorZ.xyz);
                float3 north=normalize(cross(east,n));
                float3 waveNormal=normalize(n-east*slope.x-north*slope.y);
                float3 halfVector=normalize(f.sun.xyz-ray);
                float glint=pow(max(0.0f,dot(waveNormal,halfVector)),storm>.5f?96.0f:220.0f);
                float fresnelWater=pow(1-max(0.0f,dot(waveNormal,-ray)),5.0f);
                float waveLight=max(0.0f,dot(waveNormal,f.sun.xyz));
                float3 ocean=base*(.025+waveLight*cloudShade)*day+base*.008*(1-day);
                ocean+=float3(.45,.55,.64)*(glint*.16f+fresnelWater*.15f)*day*cloudShade;
                float crest=longWave.b*.7f+shortWave.b*.3f;
                float foam=smoothstep(.60f,.78f,crest)*smoothstep(.04f,.17f,length(slope))*storm*.08f;
                ocean=mix(ocean,float3(.5,.57,.58)*(.12+.88*day)*cloudShade,foam);
                color=mix(color,ocean,water);
            }
        }
        if(f.body.w>1.5)color=base*80;
        float detail=1-.10*hash(floor(n*radius/2));color*=mix(1.0f,detail,exp(-max(0.0f,height)*radius/1800));
        if(earth)color=color*earthAir.transmission+earthAir.scattering;
        else {
            float fresnel=pow(1-max(0.0f,dot(n,-ray)),4.0f);
            color=mix(color,f.haze.rgb*(.3+.7*day),fresnel*.55*min(1.0f,f.body.y));
            color=mix(color,airColor,air*(1-exp(-t*radius/35000))*.8);
        }
    }else if(f.body.y>0){
        float limit=1+f.haze.w/radius;float atmosphereDisc=b*b-(dot(origin,origin)-limit*limit);
        if(atmosphereDisc>0&&b<0){float closest=sqrt(max(0.0f,dot(origin,origin)-b*b));float glow=exp(-max(0.0f,closest-1)*radius/max(1.0f,f.body.z))*.7;float3 n=normalize(origin-ray*b);float light=smoothstep(-.3f,.4f,dot(n,f.sun.xyz));float orbital=smoothstep(f.haze.w*.45f,f.haze.w,height*radius);color+=f.haze.rgb*glow*light*min(1.0f,f.body.y)*orbital;}
    }
    if(f.pole.w>0){float den=dot(ray,f.pole.xyz);if(abs(den)>.00001){float t=-dot(origin,f.pole.xyz)/den;float3 point=origin+ray*t;float r=length(point);if(t>0&&t<distance&&r>f.pole.w&&r<f.equatorZ.w){float4 ring=ringMaterial(point,ray,f.pole.xyz,f.pole.w,f.equatorZ.w,f.sun.xyz,rings);color=mix(color,ring.rgb,ring.a);if(ring.a>.05)distance=t;}}}
    float depth=distance<1e24?.2/max(.0001f,distance*radius*dot(ray,f.forward.xyz)):0;
    return {float4(color,1),clamp(depth,0.0f,1.0f)};
}

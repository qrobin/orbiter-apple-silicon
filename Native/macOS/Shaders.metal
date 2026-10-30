#include <metal_stdlib>
using namespace metal;
using Frame=FrameUniforms;
struct Object { float4x4 model; float4 color; float4 options; float4 specular; float4 emission; };
float3 earthSunTransmission(constant Frame &f);
float solarIntensity(constant Frame &f){return f.sunShape.w>0?f.sunShape.w:1.0f;}
struct SwitchUniform { float4 pivotAngle,axisStart,range; };
struct Vertex { packed_float3 position; packed_float3 normal; packed_float2 uv; };
struct Raster { float4 position [[position]]; float3 normal; float2 uv; float3 world; float3 local; };
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
    out.world=p; out.uv=uv; out.local=local;return out;
}
float4 shadeMesh(Raster in,constant Frame &f,constant Object &o,texture2d<float> tex,texture2d<float> shadows,float sunVisibility) {
    constexpr sampler s(filter::linear,mip_filter::linear,address::repeat, max_anisotropy(8));
    if(o.options.x>5.5){
        float3 n=normalize(in.normal),view=normalize(-in.world);
        float fresnel=pow(1-abs(dot(n,view)),5.0f);
        float grain=fract(sin(dot(floor(in.local*620),float3(127.1,311.7,74.7)))*43758.5453);
        float dust=smoothstep(.997f,.9997f,grain)*.045f;
        float3 h=f.sun.xyz+view;float glint=pow(max(0.0f,abs(dot(n,h/max(length(h),.001f)))),180.0f)*f.sun.w*sunVisibility;
        float alpha=clamp(.012f+.05f*fresnel+dust+glint*.15f,0.0f,.25f);
        return float4(float3(.48,.57,.63)+glint*float3(.55,.55,.52),alpha);
    }
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
    float lit=max(0.0f,dot(normal,f.sun.xyz))*f.sun.w*sunVisibility*solarIntensity(f);
    float cloudShade=1;
    if(f.environment.y<f.clouds.y&&f.clouds.z>0){
        float2 shadowUV=in.position.xy/f.screen.xy;
        cloudShade=shadows.sample(s,shadowUV).r;lit*=cloudShade;
    }
    float3 view=normalize(-in.world);
    float3 spec=o.specular.w>0?o.specular.rgb*pow(max(0.0f,dot(normal,normalize(f.sun.xyz+view))),max(1.0f,o.specular.w))*.18f*lit:float3(0);
    // Planetshine is directional: only surfaces facing a sunlit nearby body
    // receive its reflected light. Space itself provides no solar fill.
    float3 radial=length(f.position.xyz)>.001f?normalize(f.position.xyz):float3(0,1,0);
    float planetSize=f.body.x>1?saturate(f.body.x/max(f.body.x,f.body.x+f.environment.y)):0;
    float planetDay=smoothstep(-.2f,.3f,dot(radial,f.sun.xyz))*f.sun.w;
    float bounce=planetSize*planetSize*max(0.0f,dot(normal,-radial))*planetDay*.13f;
    float skylight=exp(-max(0.0f,f.environment.y)/9000.0f)*f.body.y*planetDay*.035f;
    float3 sunlight=int(f.surfaceColor.w)==3?earthSunTransmission(f):float3(1);
    float3 color=albedo.rgb*(.006f+o.options.y+skylight+o.emission.rgb)+albedo.rgb*sunlight*lit*.8f+albedo.rgb*float3(.76,.84,1.0)*bounce*solarIntensity(f)+spec*sunlight;
    // A low-cost hemispheric fill approximates sunlight scattered back down
    // by cloud cover; it softens shadows without making clouds emit at night.
    if(int(f.surfaceColor.w)==3&&f.clouds.z>0){
        float mu=dot(normalize(f.position.xyz),f.sun.xyz);
        float day=smoothstep(-.08f,.16f,mu)*f.sun.w;
        float below=1-smoothstep(f.clouds.y,f.clouds.y+6000.0f,f.environment.y);
        float cloudFill=f.clouds.z*below*day*(.035f+.085f*(1-cloudShade));
        float3 tint=mix(float3(1,.58,.35),float3(.80,.87,1),smoothstep(.02f,.3f,mu));
        color+=albedo.rgb*tint*cloudFill*(.5f+.5f*max(0.0f,dot(normal,normalize(f.position.xyz))));
    }
    return float4(color,albedo.a);
}
fragment float4 meshFragment(Raster in [[stage_in]],constant Frame &f [[buffer(1)]],
                             constant Object &o [[buffer(2)]],texture2d<float> tex [[texture(0)]],texture2d<float> shadows [[texture(1)]]) {
    return shadeMesh(in,f,o,tex,shadows,1);
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
    float r=atmosphericColumn(height,sunMu,8000.0f,f.body.x,1e25f);
    float m=atmosphericColumn(height,sunMu,1200.0f,f.body.x,1e25f);
    return exp(-(float3(5.8e-6,13.5e-6,33.1e-6)*r+float3(2.1e-5)*m));
}
float earthSunHaze(constant Frame &f){
    float height=max(0.0f,f.environment.x*f.body.x),sunMu=dot(normalize(f.position.xyz),f.sun.xyz);
    float r=atmosphericColumn(height,sunMu,8000.0f,f.body.x,1e25f);
    float m=atmosphericColumn(height,sunMu,1200.0f,f.body.x,1e25f);
    return 1-exp(-(r*1.35e-5f+m*2.1e-5f));
}
struct AirLight {float3 transmission,scattering;};
// NASA's map is J2000 equatorial, while Orbiter's world axes are ecliptic.
// Its right ascension increases leftward from the centre of the texture.
float2 skyCoordinates(float3 ray){
    const float c=.9174821f,s=.3977772f;
    float3 eq=float3(ray.x,ray.y*c+ray.z*s,ray.z*c-ray.y*s);
    return float2(.5f-atan2(eq.z,eq.x)/(2*M_PI_F),acos(clamp(eq.y,-1.0f,1.0f))/M_PI_F);
}
AirLight earthAirLight(constant Frame &f,float3 ray,float maximumDistance){
    float height=max(0.0f,f.environment.x*f.body.x),mu=dot(normalize(f.position.xyz),ray);
    float r=atmosphericColumn(height,mu,8000.0f,f.body.x,maximumDistance);
    float m=atmosphericColumn(height,mu,1200.0f,f.body.x,maximumDistance);
    float3 betaR=float3(5.8e-6,13.5e-6,33.1e-6),betaM=float3(2.1e-5);
    float3 transmission=exp(-(betaR*r+betaM*m));
    float cosine=dot(ray,f.sun.xyz),phaseR=.75f*(1+cosine*cosine),g=.76f;
    float phaseM=(1-g*g)/pow(max(.03f,1+g*g-2*g*cosine),1.5f);
    float sunMu=dot(normalize(f.position.xyz),f.sun.xyz);
    float sunlight=smoothstep(-.10f,.04f,sunMu)*solarIntensity(f);
    // At sunset much of the visible sky scatters sunlight higher than the
    // observer. Approximate that shorter solar path instead of applying the
    // low-altitude, heavily reddened Sun transmission to the entire sky.
    float twilight=1-smoothstep(.05f,.32f,sunMu);
    float scatterHeight=2000+12000*max(0.0f,mu);
    float solarR=atmosphericColumn(height,max(0.0f,sunMu),8000.0f,f.body.x,1e25f)*mix(1.0f,exp(-scatterHeight/8000.0f),twilight);
    float solarM=atmosphericColumn(height,max(0.0f,sunMu),1200.0f,f.body.x,1e25f)*mix(1.0f,exp(-scatterHeight/1200.0f),twilight);
    float3 incident=exp(-(betaR*solarR+betaM*solarM));
    float3 scattered=incident*sunlight*((1-exp(-betaR*r))*phaseR*.95f+(1-exp(-betaM*m))*phaseM*mix(.13f,.085f,twilight));
    // A small broad skylight term approximates higher-order blue scattering,
    // while low solar angles leave warmer light near the horizon.
    float skyHeight=smoothstep(-.02f,.35f,mu);
    float horizon=exp(-abs(mu)*10.0f),towardSun=.08f+.92f*pow(max(0.0f,cosine),2.0f);
    float airPath=saturate(r/6000.0f);
    scattered+=sunlight*twilight*airPath*(float3(.012,.035,.26)*skyHeight+float3(.09,.018,.018)*horizon*towardSun);
    // Low-angle light is warmer near the horizon, with more blue skylight
    // remaining above it instead of a uniform yellow wash.
    scattered*=mix(float3(1),float3(1.12,.48,1.12),twilight*towardSun*(.55f+.45f*horizon));
    float antisolar=(1-smoothstep(-.55f,.2f,cosine))*(1-smoothstep(.02f,.55f,abs(mu)))*twilight;
    scattered*=1-.65f*antisolar;
    return {transmission,scattered};
}
fragment SkyOutput skyFragment(SkyRaster in [[stage_in]],constant Frame &f [[buffer(1)]],
    texture2d<float> map [[texture(0)]],texture2d<float> shadows [[texture(1)]],texture2d<float> rings [[texture(2)]],
    texture2d<float> oceanMask [[texture(3)]],texture2d<float> cloudMap [[texture(4)]],texture2d<float> oceanWaves [[texture(5)]],texture2d<float> oceanDetail [[texture(6)]],texture2d<float> starMap [[texture(7)]]) {
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    float2 xy=in.uv*2-1;float3 ray=normalize(f.forward.xyz+f.right.xyz*xy.x*f.screen.z*(f.screen.x/f.screen.y)+f.up.xyz*xy.y*f.screen.z);
    float3 origin=f.position.xyz;float height=f.environment.x,radius=f.body.x;
    float b=dot(normalize(origin),ray)*(1+height),c=height*(2+height),disc=b*b-c;
    constexpr sampler stars(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge, max_anisotropy(8));
    float3 sky=starMap.sample(stars,skyCoordinates(ray)).rgb*1.35f;
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
        if(earth&&t*radius<6000.0f){
            float land=1-smoothstep(.15f,.50f,oceanMask.sample(s,uv).r);
            float fade=(1-smoothstep(1000.0f,6000.0f,t*radius))*land;
            float3 fixed=terrestrial(n,f)*radius;
            // Broad field patches and finer tufts break up the satellite map;
            // both are fixed to the rotating surface and fade with distance.
            float patch=planetNoise(fixed/130.0f),tuft=planetNoise(fixed/8.0f);
            float green=saturate((base.g-base.r*.65f)*3.5f);
            float3 grass=mix(base*.72f,float3(.075,.13,.035),green*.6f);
            base=mix(base,grass*(.68f+.48f*patch+.16f*tuft),fade*.65f);
        }
        float day=smoothstep(-.06f,.06f,dot(n,f.sun.xyz)),light=max(0.0f,dot(n,f.sun.xyz));
        float cloudShade=shadows.sample(s,in.position.xy/f.screen.xy).r;
        if(f.pole.w>0){float den=dot(f.sun.xyz,f.pole.xyz);float ts=-dot(n,f.pole.xyz)/(abs(den)>.0001?den:.0001f);float3 point=n+f.sun.xyz*ts;float r=length(point);if(ts>0&&r>f.pole.w&&r<f.equatorZ.w)cloudShade*=1-ringMaterial(point,ray,f.pole.xyz,f.pole.w,f.equatorZ.w,f.sun.xyz,rings).a*.85;}
        color=base*(.025+light*cloudShade*solarIntensity(f))*day+base*.008*(1-day);
        if(earth&&f.clouds.z>0){
            float cloudFill=f.clouds.z*day*f.sun.w*(.025f+.07f*(1-cloudShade));
            float3 tint=mix(float3(1,.58,.35),float3(.8,.87,1),smoothstep(.02f,.3f,dot(n,f.sun.xyz)));
            color+=base*tint*cloudFill;
        }
        // Fade distant waves and filter subpixel structure to prevent shimmer.
        float waveFade=1-smoothstep(22000.0f,55000.0f,t*radius);
        if(int(f.surfaceColor.w)==3&&waveFade>0){
            float water=smoothstep(.35f,.75f,oceanMask.sample(s,uv).r)*waveFade;
            if(water>.001f){
                float regional=cloudMap.sample(s,uv).r;
                float storm=f.weather.x>2.5&&f.weather.x<3.5?.9f:(f.weather.x>3.5?smoothstep(.72f,.97f,regional):0.0f);
                float lon=(uv.x-.5f)*2*M_PI_F,lat=(.5f-uv.y)*M_PI_F;
                float2 metres=float2(lon*cos(lat),lat)*radius;
                // Four independently moving spectral bands approximate
                // deep-water dispersion: long swells travel faster than chop.
                // Integer daily cycles keep motion continuous when time wraps.
                constexpr sampler waveSampler(filter::linear,mip_filter::linear,address::repeat);
                float time=f.environment.w/86400.0f;
                float3 swell=oceanWaves.sample(waveSampler,metres/16000.0f+float2(200,32)*time).rgb;
                float3 waves=oceanWaves.sample(waveSampler,metres/8000.0f+float2(.27,.61)+float2(280,55)*time).rgb;
                float3 chop=oceanDetail.sample(waveSampler,metres/16000.0f+float2(.41,.18)+float2(96,24)*time).rgb;
                float3 ripples=oceanDetail.sample(waveSampler,metres/8000.0f+float2(.72,.38)+float2(130,-12)*time).rgb;
                // Correct the spherical intersection by the moving height field.
                // This gives nearby waves changing depth as well as changing
                // normals, while capping grazing-ray excursions near the horizon.
                float waveHeight=((swell.b-.5f)*10.0f+(waves.b-.5f)*5.0f+(chop.b-.5f)*2.0f)*(0.45f+1.6f*storm);
                float correction=clamp(waveHeight/min(-.025f,dot(ray,n)),-60.0f,60.0f)*water;
                distance=max(.001f/radius,t+correction/radius);
                float2 slope=((swell.rg-.5f)*.42f+(waves.rg-.5f)*.25f+(chop.rg-.5f)*.18f+(ripples.rg-.5f)*.10f)*(.55+1.5*storm);
                float3 east=cross(n,f.pole.xyz);east=length(east)>.001f?normalize(east):normalize(f.equatorZ.xyz);
                float3 north=normalize(cross(east,n));
                float3 waveNormal=normalize(n-east*slope.x-north*slope.y);
                float3 halfVector=normalize(f.sun.xyz-ray);
                float glint=pow(max(0.0f,dot(waveNormal,halfVector)),storm>.5f?96.0f:220.0f);
                float fresnelWater=pow(1-max(0.0f,dot(waveNormal,-ray)),5.0f);
                float waveLight=max(0.0f,dot(waveNormal,f.sun.xyz));
                float3 ocean=base*(.025+waveLight*cloudShade*solarIntensity(f))*day+base*.008*(1-day);
                // The source globe's open-ocean pixels are almost black;
                // add a subtle blue contribution from the sky at low altitude.
                ocean+=float3(.001,.006,.018)*(.25f+.75f*day);
                if(f.clouds.z>0){float3 tint=mix(float3(1,.58,.35),float3(.8,.87,1),smoothstep(.02f,.3f,dot(n,f.sun.xyz)));ocean+=base*tint*f.clouds.z*day*f.sun.w*(.025f+.07f*(1-cloudShade));}
                float lowSun=1-smoothstep(.05f,.35f,dot(n,f.sun.xyz));
                float3 sunGlint=mix(float3(.45,.55,.64),float3(.65,.34,.22),lowSun);
                float3 reflected=reflect(ray,waveNormal);
                if(dot(reflected,n)>0){
                    AirLight reflectedAir=earthAirLight(f,reflected,1e25f);
                    float3 reflection=starMap.sample(stars,skyCoordinates(reflected)).rgb*1.35f*reflectedAir.transmission+reflectedAir.scattering;
                    if(f.clouds.z>0){
                        float mu=dot(n,reflected);float2 shell=cloudShellRoots(0,f.clouds.x,mu,radius);
                        float3 cloudPoint=n*radius+reflected*max(0.0f,shell.y);
                        float coverage=cloudMap.sample(s,terrestrialUV(cloudPoint,f)).r;
                        float alpha=smoothstep(.32f,.90f,coverage)*saturate(f.clouds.z*1.8f);
                        float3 cloudLight=mix(float3(.12,.14,.19),float3(.85,.90,.97),day)*(.4f+.6f*cloudShade);
                        reflection=mix(reflection,cloudLight,alpha);
                    }
                    ocean+=reflection*(.04f+.38f*fresnelWater);
                }
                ocean+=sunGlint*glint*.16f*day*cloudShade*solarIntensity(f);
                float crest=swell.b*.35f+waves.b*.25f+chop.b*.25f+ripples.b*.15f;
                float foam=smoothstep(.60f,.78f,crest)*smoothstep(.04f,.17f,length(slope))*storm*.08f;
                ocean=mix(ocean,float3(.5,.57,.58)*(.12+.88*day)*cloudShade,foam);
                color=mix(color,ocean,water);
            }
        }
        if(f.body.w>1.5)color=base*80;
        float detail=1-.10*hash(floor(n*radius/2));color*=mix(1.0f,detail,exp(-max(0.0f,height)*radius/1800));
        if(earth){
            // At orbital distances the surface can cross the terminator even
            // when the camera itself is in daylight. Do not apply the camera's
            // sunlit atmospheric veil to the planet's dark hemisphere.
            float orbital=smoothstep(40000.0f,120000.0f,height*radius);
            float localSun=smoothstep(-.12f,.06f,dot(n,f.sun.xyz))*f.sun.w;
            color=color*earthAir.transmission+earthAir.scattering*mix(1.0f,localSun,orbital);
        }
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
    // Atmospheric forward scattering creates an aureole larger than the
    // physical solar disc; cloud and surface depth can still obscure it.
    if(distance>1e24f&&f.sun.w>0&&f.sunShape.x>0){
        float cosine=dot(ray,f.sun.xyz),radius=clamp(f.sunShape.x,.00001f,.05f);
        float angle2=max(0.0f,2*(1-cosine));
        if(angle2<radius*radius*900){
            if(earth&&f.sunShape.z<.5f){
                float haze=earthSunHaze(f),width=radius*(1.15f+4.5f*haze);
                float core=exp(-angle2/(2*width*width)),wing=exp(-sqrt(angle2)/(width*1.8f));
                color+=earthSunTransmission(f)*f.sun.w*haze*(core*3.0f+wing*.22f);
            }
        }
    }
    float depth=distance<1e24?.2/max(.0001f,distance*radius*dot(ray,f.forward.xyz)):0;
    return {float4(color,1),clamp(depth,0.0f,1.0f)};
}

// Cloud volumes, temporal reconstruction and exhaust implemented directly in Metal.
float earthSunHaze(constant FrameUniforms &f);
float solarIntensity(constant FrameUniforms &f);
uint visualHash(uint x) { x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16); }
float visualRandom(uint x) { return float(visualHash(x)&0xffffffu)/16777216.0f; }
float noiseCorner(int3 p,int period) {
    uint3 q=uint3((p%period+period)%period);
    return visualRandom(q.x+q.y*157u+q.z*11317u);
}
float periodicNoise(float3 p,int period) {
    int3 i=int3(floor(p));float3 u=fract(p);u=u*u*(3-2*u);
    float a=mix(noiseCorner(i,period),noiseCorner(i+int3(1,0,0),period),u.x);
    float b=mix(noiseCorner(i+int3(0,1,0),period),noiseCorner(i+int3(1,1,0),period),u.x);
    float c=mix(noiseCorner(i+int3(0,0,1),period),noiseCorner(i+int3(1,0,1),period),u.x);
    float d=mix(noiseCorner(i+int3(0,1,1),period),noiseCorner(i+int3(1,1,1),period),u.x);
    return mix(mix(a,b,u.y),mix(c,d,u.y),u.z);
}
kernel void makeCloudNoise(texture3d<float,access::write> output [[texture(0)]],uint3 id [[thread_position_in_grid]]) {
    if(any(id>=uint3(output.get_width(),output.get_height(),output.get_depth())))return;
    float3 p=(float3(id)+.5)/float(output.get_width());
    float base=.52*periodicNoise(p*4,4)+.28*periodicNoise(p*8,8)+.14*periodicNoise(p*16,16)+.06*periodicNoise(p*32,32);
    float3 w=p*8;int3 cell=int3(floor(w));float nearest=2;
    for(int z=-1;z<=1;++z)for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x){
        int3 c=cell+int3(x,y,z);uint3 h=uint3((c%8+8)%8);uint seed=h.x+h.y*157u+h.z*11317u;
        float3 v=float3(visualRandom(seed),visualRandom(seed+97),visualRandom(seed+239));
        nearest=min(nearest,length(float3(c)+v-w));
    }
    float worley=1-clamp(nearest,0.0f,1.0f);
    output.write(float4(base*.7+worley*.3,worley,periodicNoise(p*4+19,4),1),id);
}
float3 terrestrial(float3 p,constant FrameUniforms &f) {
    float3 e=float3(dot(p,f.equatorX.xyz),dot(p,f.pole.xyz),dot(p,f.equatorZ.xyz));
    float a=f.screen.w*(2*M_PI_F),c=cos(a),s=sin(a);
    return float3(c*e.x-s*e.z,e.y,s*e.x+c*e.z);
}
float2 terrestrialUV(float3 p,constant FrameUniforms &f) {
    float3 e=normalize(terrestrial(p,f));
    return float2(atan2(e.z,e.x)/(2*M_PI_F)+.5,acos(clamp(e.y,-1.0f,1.0f))/M_PI_F);
}
// Stable cells are fixed to Earth's rotating coordinates, rather than to the
// camera. Instances are generated only in the small neighbourhood being drawn.
struct TerrainRaster { float4 position [[position]]; float3 normal; float3 color; };
vertex TerrainRaster terrainVertex(uint vertexID [[vertex_id]],uint instanceID [[instance_id]],
                                   constant FrameUniforms &f [[buffer(0)]],
                                   texture2d<float> ocean [[texture(0)]],texture2d<float> earth [[texture(1)]]) {
    TerrainRaster out;out.position=float4(2,2,2,1);out.normal=float3(0,1,0);out.color=0;
    constexpr float spacing=38.0f;constexpr int grid=96;
    float3 camera=normalize(f.position.xyz),fixed=normalize(terrestrial(camera,f));
    float lat=asin(clamp(fixed.y,-1.0f,1.0f)),lon=atan2(fixed.z,fixed.x);
    if(abs(lat)>1.38f)return out;
    int2 center=int2(floor(float2(lon,lat)*f.body.x/spacing));
    int2 cell=center+int2(int(instanceID%grid)-grid/2,int(instanceID/grid)-grid/2);
    uint seed=visualHash(as_type<uint>(cell.x)*0x9e3779b9u^as_type<uint>(cell.y)*0x85ebca6bu);
    if(visualRandom(seed+29)<smoothstep(1700.0f,2500.0f,f.environment.y))return out;
    float2 jitter=float2(visualRandom(seed),visualRandom(seed+7));
    float2 coords=(float2(cell)+jitter)*spacing/f.body.x;
    float cl=cos(coords.y);float3 surfaceFixed=float3(cl*cos(coords.x),sin(coords.y),cl*sin(coords.x));
    float2 uv=float2(coords.x/(2*M_PI_F)+.5f,.5f-coords.y/M_PI_F);
    constexpr sampler s(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    float water=ocean.sample(s,uv,level(0)).r;float3 land=earth.sample(s,uv,level(0)).rgb;
    if(water>.25f)return out;
    // Keep deserts and snow mostly bare; rocks can still appear in dry areas.
    float green=saturate((land.g-land.r*.65f)*4.0f);bool tree=visualRandom(seed+11)<green*.80f;
    if(!tree&&visualRandom(seed+13)>.28f)return out;
    float angle=f.screen.w*(2*M_PI_F),c=cos(angle),sine=sin(angle);
    float3 n=normalize(f.equatorX.xyz*(c*surfaceFixed.x+sine*surfaceFixed.z)+f.pole.xyz*surfaceFixed.y+f.equatorZ.xyz*(-sine*surfaceFixed.x+c*surfaceFixed.z));
    float3 east=normalize(cross(f.pole.xyz,n)),north=normalize(cross(n,east));
    uint face=vertexID/3,corner=vertexID%3,side=face%4,layer=face/4;
    float phi=float(side)*M_PI_F*.5f,phiNext=phi+M_PI_F*.5f;
    float size=tree?mix(2.4f,4.5f,visualRandom(seed+17)):mix(.6f,2.2f,visualRandom(seed+17));
    float height=tree?mix(6.0f,14.0f,visualRandom(seed+19)):size*.8f;
    float lower=tree?(layer==0?.18f:.52f):0.0f,upper=tree?(layer==0?.75f:1.0f):1.0f;
    float width=size*(layer==0?1.0f:.68f);
    float3 radial=corner==0?east*cos(phi)*width+north*sin(phi)*width:corner==1?east*cos(phiNext)*width+north*sin(phiNext)*width:float3(0);
    float3 point=(n-camera)*f.body.x-camera*f.environment.y+radial+n*(corner==2?upper*height:lower*height);
    float3 view=float3(dot(point,f.right.xyz),dot(point,f.up.xyz),-dot(point,f.forward.xyz));
    out.position=f.projection*float4(view,1);
    float mid=phi+M_PI_F*.25f;out.normal=normalize((east*cos(mid)+north*sin(mid))*.8f+n*.6f);
    out.color=tree?mix(float3(.035,.085,.025),float3(.12,.21,.055),visualRandom(seed+23)):mix(float3(.16,.14,.11),float3(.36,.34,.30),visualRandom(seed+23));
    if(!tree&&layer>0)out.position=float4(2,2,2,1);
    return out;
}
fragment float4 terrainFragment(TerrainRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],texture2d<float> shadows [[texture(0)]]) {
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float day=smoothstep(-.08f,.12f,dot(normalize(f.position.xyz),f.sun.xyz))*f.sun.w;
    float shadow=shadows.sample(s,in.position.xy/f.screen.xy).r;
    float light=max(0.0f,dot(normalize(in.normal),f.sun.xyz))*f.sun.w*shadow*solarIntensity(f);
    return float4(in.color*(.008f+day*.12f+light*.85f),1);
}
// Regional coverage varies slowly compared with the volume noise. Sample once
// per ray instead of once per density and sunlight step.
float regionalCloudCoverage(float observed,float weather) {
    float region=smoothstep(.32f,.90f,observed);
    if(weather>.5&&weather<1.5)region*=.18f;
    if(weather>2.5&&weather<3.5)region=max(region,.72f);
    else if(weather>1.5&&weather<2.5)region=max(region,.25f);
    return region;
}
float cloudRegion(float3 p,constant FrameUniforms &f,texture2d<float> cloudMap) {
    constexpr sampler mapSampler(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
    return regionalCloudCoverage(cloudMap.sample(mapSampler,terrestrialUV(p,f),level(0)).r,f.weather.x);
}
float lowCloudTop(constant FrameUniforms &f) {
    return min(f.clouds.y,6500.0f+2500.0f*saturate(f.clouds.w));
}
float cloudDensity(float3 p,constant FrameUniforms &f,texture3d<float> noise,float region) {
    if(f.clouds.z<=0||region<=0)return 0;
    float h=length(p)-f.body.x;
    if(h<=f.clouds.x||h>=f.clouds.y)return 0;
    constexpr sampler s(filter::linear,address::repeat);
    float3 w=terrestrial(p,f)+float3(f.environment.w*14,0,f.environment.w*7);
    float density=0,highDensity=0,lowTop=lowCloudTop(f);
    if(h<lowTop){
        float height=(h-f.clouds.x)/max(1.0f,lowTop-f.clouds.x);
        float weather=noise.sample(s,w/320000.0f).b;
        float coverage=clamp(.22+region*.50+(weather-.5)*.2,.01f,.98f);
        float shape=noise.sample(s,w/22000.0f).r;
        float threshold=.92-coverage*.70+height*height*.16;
        float lower=smoothstep(threshold,threshold+.11,shape);
        if(lower>0){
            float detail=noise.sample(s,w/4500.0f).g;
            lower=max(0.0f,lower-(1-detail)*.32*(1-lower));
            float profile=smoothstep(0.0f,.14f,height)*(1-smoothstep(.55f,1.0f,height));
            density=lower*profile*region*(.00065+f.clouds.w*.00045);
        }
    }
    // Thin, independently patterned high cloud sits above the lower cumulus
    // and storm layers. Both layers share the same march and sun shadows.
    if(h>8500.0f&&f.clouds.y>8500.0f){
        float height=(h-8500.0f)/(f.clouds.y-8500.0f);
        float broad=noise.sample(s,w/90000.0f+float3(.17,.39,.61)).r;
        float wisps=noise.sample(s,w/18000.0f+float3(.53,.11,.27)).r;
        float shape=smoothstep(.43f,.62f,broad*.7f+wisps*.3f);
        float profile=smoothstep(0.0f,.18f,height)*(1-smoothstep(.72f,1.0f,height));
        highDensity=shape*profile*saturate(region*2.0f)*(.00010f+.00004f*f.clouds.w);
    }
    // Keep cloud cores visually solid even in the low-density scattered preset.
    // The extinction is shared by camera rays, solar self-shadowing and shadows
    // on the surface so opaque billows also block direct light consistently.
    return density*2.6f+highDensity*1.32f;
}
// Stable sphere intersections avoid subtracting two large, nearly equal squared radii.
float2 cloudShellRoots(float cameraHeight,float shellHeight,float mu,float radius) {
    float b=(radius+cameraHeight)*mu;
    float c=(cameraHeight-shellHeight)*(2*radius+cameraHeight+shellHeight);
    float d=b*b-c;if(d<0)return float2(1,-1);
    float q=-b-copysign(sqrt(d),b);float other=abs(q)>1e-6?c/q:-b;
    return float2(min(q,other),max(q,other));
}
float3 viewRay(float2 uv,constant FrameUniforms &f) {
    float2 ndc=float2(uv.x*2-1,1-uv.y*2);
    return normalize(f.forward.xyz+f.right.xyz*ndc.x*f.screen.z*f.screen.x/f.screen.y+f.up.xyz*ndc.y*f.screen.z);
}
float depthDistance(float depth,float3 ray,constant FrameUniforms &f) {
    return depth>0?.2/max(1e-12f,depth*dot(ray,f.forward.xyz)):1e9;
}
float cloudSunTransmittance(float3 p,constant FrameUniforms &f,texture3d<float> noise,float region) {
    float height=length(p)-f.body.x,mu=dot(normalize(p),f.sun.xyz);
    float2 top=cloudShellRoots(height,f.clouds.y,mu,f.body.x);
    float distance=clamp(top.y,0.0f,70000.0f);
    if(mu<0){
        float2 ground=cloudShellRoots(height,0,mu,f.body.x);
        if(ground.y>ground.x&&ground.x>0&&ground.x<distance)return 0;
    }
    // Near sunset the light can travel tens of kilometres through the cloud
    // layer. Keep the same four samples but spread them across that path.
    float optical=0;
    for(int i=0;i<4;++i){
        float a=float(i)/4.0f,b=float(i+1)/4.0f;
        float near=distance*a*a,far=distance*b*b;
        optical+=cloudDensity(p+f.sun.xyz*((near+far)*.5f),f,noise,region)*(far-near);
    }
    return exp(-optical);
}
kernel void cloudShadowMap(constant FrameUniforms &f [[buffer(0)]],texture3d<float> noise [[texture(0)]],
                           texture2d<float,access::write> shadow [[texture(1)]],texture2d<float> cloudMap [[texture(2)]],uint2 id [[thread_position_in_grid]]) {
    if(id.x>=shadow.get_width()||id.y>=shadow.get_height())return;
    float2 uv=(float2(id)+.5)/float2(shadow.get_width(),shadow.get_height());
    float3 ray=viewRay(uv,f);float cameraHeight=f.environment.x*f.body.x;
    float2 roots=cloudShellRoots(cameraHeight,0,dot(normalize(f.position.xyz),ray),f.body.x);
    float optical=0;
    if(roots.x>=0&&roots.y>roots.x&&f.clouds.z>0){
        float3 surface=normalize(normalize(f.position.xyz)*(f.body.x+cameraHeight)+ray*roots.x)*f.body.x;
        float mu=dot(normalize(surface),f.sun.xyz);
        if(mu>.02){
            float step=(f.clouds.y-f.clouds.x)/4,region=cloudRegion(surface,f,cloudMap);
            for(int i=0;i<4;++i){float t=(f.clouds.x+(i+.5)*step)/max(.08f,mu);optical+=cloudDensity(surface+f.sun.xyz*t,f,noise,region)*step/max(.08f,mu);}
        }
    }
    shadow.write(float4(.26+.74*exp(-optical)),id);
}
// The ground shadow map is projected in screen space. A nearby ship needs
// its own world-space sample, otherwise that ground pattern crosses its hull.
kernel void vesselCloudShadow(constant FrameUniforms &f [[buffer(0)]],constant float4 &position [[buffer(1)]],
                              texture3d<float> noise [[texture(0)]],texture2d<float> cloudMap [[texture(1)]],
                              texture2d<float,access::write> output [[texture(2)]],uint2 id [[thread_position_in_grid]]) {
    if(any(id>0))return;
    float optical=0;
    if(f.clouds.z>0){
        float3 origin=position.xyz*f.body.x;
        float height=length(origin)-f.body.x,mu=dot(normalize(origin),f.sun.xyz);
        float2 outer=cloudShellRoots(height,f.clouds.y,mu,f.body.x);
        float start=max(0.0f,outer.x),end=min(outer.y,100000.0f);
        float2 inner=cloudShellRoots(height,f.clouds.x,mu,f.body.x);
        if(inner.y>inner.x){
            if(height<f.clouds.x)start=max(start,inner.y);
            else if(inner.x>start)end=min(end,inner.x);
        }
        if(mu<0){
            float2 ground=cloudShellRoots(height,0,mu,f.body.x);
            if(ground.y>ground.x&&ground.x>0)end=min(end,ground.x);
        }
        if(end>start){
            float step=(end-start)/8.0f;
            float region=cloudRegion(origin+f.sun.xyz*(start+min((end-start)*.25f,8000.0f)),f,cloudMap);
            for(int i=0;i<8;++i)optical+=cloudDensity(origin+f.sun.xyz*(start+(float(i)+.5f)*step),f,noise,region)*step;
        }
    }
    output.write(float4(.26f+.74f*exp(-optical)),id);
}
kernel void marchClouds(constant FrameUniforms &f [[buffer(0)]],constant uint &frameIndex [[buffer(1)]],
                        texture3d<float> noise [[texture(0)]],texture2d<float,access::read> depth [[texture(1)]],
                        texture2d<float> previous [[texture(2)]],texture2d<float> previousData [[texture(3)]],
                        texture2d<float,access::write> result [[texture(4)]],texture2d<float,access::write> data [[texture(5)]],texture2d<float> cloudMap [[texture(6)]],
                        uint2 id [[thread_position_in_grid]]) {
    uint2 size=uint2(result.get_width(),result.get_height());if(any(id>=size))return;
    float2 uv=(float2(id)+.5)/float2(size);float3 ray=viewRay(uv,f);
    uint2 full=min(uint2(uv*float2(depth.get_width(),depth.get_height())),uint2(depth.get_width()-1,depth.get_height()-1));
    float geometry=depthDistance(depth.read(full).r,ray,f);
    float cameraHeight=f.environment.x*f.body.x;
    // Above the transition the full-resolution satellite shell completely
    // replaces this volume. Avoid its 48-step march and sunlight samples.
    if(cameraHeight>=120000.0f){result.write(float4(0),id);data.write(float4(geometry,0,0,0),id);return;}
    float2 roots=cloudShellRoots(cameraHeight,f.clouds.y,dot(normalize(f.position.xyz),ray),f.body.x);
    float start=max(0.0f,roots.x),end=min(roots.y,geometry);
    float2 inner=cloudShellRoots(cameraHeight,f.clouds.x,dot(normalize(f.position.xyz),ray),f.body.x);
    if(cameraHeight>f.clouds.x&&inner.y>inner.x&&inner.x>start)end=min(end,inner.x);
    float3 origin=normalize(f.position.xyz)*(f.body.x+cameraHeight);
    float3 radiance=0;float trans=1,weightedDistance=0,weight=0;
    if(f.clouds.z>0&&end>start){
        float span=end-start;
        // Sample the weather close to where the ray enters the cloud. Sampling
        // the midpoint jumps tens of kilometres at a grazing inner-shell hit.
        float3 center=normalize(origin+ray*(start+min(span*.25f,8000.0f)));
        float region=cloudRegion(center,f,cloudMap);
        float mu=dot(center,f.sun.xyz),day=smoothstep(-.08f,.12f,mu)*f.sun.w;
        float g=.55,cosTheta=dot(ray,f.sun.xyz);
        float phase=(1-g*g)/pow(max(.05f,1+g*g-2*g*cosTheta),1.5f);
        float3 sunlight=mix(float3(1.20,.40,.20),float3(1.20,1.25,1.32),smoothstep(.02f,.35f,mu))*solarIntensity(f);
        float3 ambient=mix(float3(.003,.005,.012),mix(float3(.065,.065,.085),float3(.15,.20,.29),smoothstep(.02f,.3f,mu)),day);
        float jitter=visualRandom(id.x+id.y*1973u+frameIndex*26699u);
        for(int i=0;i<48;++i){
            // Allocate more samples near the camera. Uniform steps can skip
            // an entire nearby cloud when a grazing ray travels hundreds of km.
            float a=float(i)/48.0f,b=float(i+1)/48.0f;
            float near=start+span*a*a,far=start+span*b*b,step=far-near;
            float t=mix(near,far,jitter);float3 p=origin+ray*t;
            float density=cloudDensity(p,f,noise,region);if(density<.000002)continue;
            float lighting=cloudSunTransmittance(p,f,noise,region);
            // A restrained multiple-scattering term keeps thin edges lit while
            // dense interiors retain their shadows even when backlit.
            float direct=lighting*(.22f+.16f*min(phase,3.0f));
            float3 light=ambient+sunlight*day*(direct+.10f*sqrt(lighting));
            float extinction=1-exp(-density*step),contribution=trans*extinction;
            radiance+=light*contribution;weightedDistance+=t*contribution;weight+=contribution;
            trans*=1-extinction;if(trans<.012)break;
        }
    }
    float distance=weight>.001?weightedDistance/weight:(start+max(start,end))*.5;
    float4 color=float4(radiance,1-trans);
    if(f.environment.z>.5){
        float3 toPrevious=(f.position.xyz-f.previousPosition.xyz)*f.body.x+ray*distance;
        float z=dot(toPrevious,f.previousForward.xyz);
        float2 oldUV=float2(.5+.5*dot(toPrevious,f.previousRight.xyz)/max(.01f,z)/(f.screen.z*f.screen.x/f.screen.y),.5-.5*dot(toPrevious,f.previousUp.xyz)/max(.01f,z)/f.screen.z);
        if(z>0&&all(oldUV>0)&&all(oldUV<1)){
            constexpr sampler linear(filter::linear,address::clamp_to_edge);
            float oldDepth=previousData.sample(linear,oldUV).r;
            if(abs(oldDepth-geometry)<max(3.0f,geometry*.04f)){
                float4 history=previous.sample(linear,oldUV);
                history=clamp(history,color-float4(.14,.14,.14,.2),color+float4(.14,.14,.14,.2));
                color=mix(color,history,.82f);
            }
        }
    }
    result.write(color,id);data.write(float4(geometry,distance,start,0),id);
}
fragment float4 compositeClouds(SkyRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],
                                texture2d<float> scene [[texture(0)]],texture2d<float> clouds [[texture(1)]],
                                texture2d<float> cloudData [[texture(2)]],texture2d<float,access::read> depth [[texture(3)]],
                                texture2d<float> earthCloudMap [[texture(4)]],texture3d<float> noise [[texture(5)]]) {
    float2 uv=float2(in.uv.x,1-in.uv.y);constexpr sampler s(filter::linear,address::clamp_to_edge);
    float3 ray=viewRay(uv,f);uint2 pixel=min(uint2(uv*f.screen.xy),uint2(f.screen.xy)-1);
    float geometry=depthDistance(depth.read(pixel).r,ray,f);
    float2 cloudSize=float2(clouds.get_width(),clouds.get_height());
    float2 p=uv*cloudSize-.5,base=floor(p),frac=fract(p);float4 cloud=0;float total=0,weightedDistance=0;
    for(int y=0;y<2;++y)for(int x=0;x<2;++x){
        float2 q=(base+float2(x,y)+.5)/cloudSize;
        float4 info=cloudData.sample(s,q),sample=clouds.sample(s,q);float d=info.r;
        float w=(x?frac.x:1-frac.x)*(y?frac.y:1-frac.y);
        w*=min(d,geometry)>5000?1:step(abs(d-geometry),max(2.0f,geometry*.025f));
        cloud+=sample*w;total+=w;weightedDistance+=info.g*sample.a*w;
    }
    cloud/=max(total,.0001f);
    // Orbital-scale cloud structure comes from a satellite composite. Blend
    // into the volumetric layer for aircraft and low-altitude views.
    float cameraHeight=f.environment.x*f.body.x;
    if(cloud.a>.0001f){
        float distance=weightedDistance/max(.0001f,total*cloud.a);
        float airDensity=exp(-max(0.0f,cameraHeight)/8000.0f);
        cloud*=exp(-max(0.0f,distance-10000.0f)*airDensity/90000.0f);
    }
    float orbital=smoothstep(40000.0f,120000.0f,cameraHeight);
    if(orbital>0&&f.clouds.z>0){
        float3 origin=normalize(f.position.xyz)*(f.body.x+cameraHeight);
        float2 shell=cloudShellRoots(cameraHeight,(f.clouds.x+f.clouds.y)*.5f,dot(normalize(origin),ray),f.body.x);
        float distance=shell.x;
        if(shell.y>shell.x&&distance>0&&distance<geometry){
            float3 point=origin+ray*distance,normal=normalize(point);
            constexpr sampler mapSampler(filter::linear,mip_filter::linear,s_address::repeat,t_address::clamp_to_edge);
            float mask=earthCloudMap.sample(mapSampler,terrestrialUV(point,f)).r;
            float coverage=saturate(regionalCloudCoverage(mask,f.weather.x)*min(1.5f,f.clouds.z/.48f));
            float detailLight=1;
            // At low orbital altitude, add sub-map cloud structure sampled
            // from the existing 3D noise volume. Fade before it aliases from afar.
            float detailWeight=1-smoothstep(220000.0f,900000.0f,cameraHeight);
            if(detailWeight>0&&coverage>.01f){
                constexpr sampler noiseSampler(filter::linear,address::repeat);
                float3 samplePoint=terrestrial(point,f)+float3(f.environment.w*14,0,f.environment.w*7);
                float broad=noise.sample(noiseSampler,samplePoint/28000.0f).r;
                float fine=noise.sample(noiseSampler,samplePoint/6500.0f).g;
                float variation=(broad-.5f)*.45f+(fine-.5f)*.25f;
                coverage=saturate(coverage+variation*detailWeight*smoothstep(.03f,.4f,coverage)*(1-.5f*coverage));
                detailLight=clamp(1+variation*.55f*detailWeight,.75f,1.15f);
            }
            float viewCosine=abs(dot(normal,ray)),mu=max(.55f,viewCosine);
            // Grazing cloud-shell intersections occupy less than a pixel and
            // are heavily obscured by atmospheric haze at the horizon.
            float alpha=min(.98f,(1-pow(max(.001f,1-coverage),1/mu))*1.28f)*smoothstep(.025f,.12f,viewCosine);
            float daylight=smoothstep(-.08f,.10f,dot(normal,f.sun.xyz))*f.sun.w;
            float3 illumination=mix(float3(.005,.008,.018),float3(.85,.91,1.0)*(0.30+0.42*max(0.0f,dot(normal,f.sun.xyz)))*mix(.70f,1.0f,mask)*detailLight*solarIntensity(f),daylight);
            cloud=mix(cloud,float4(illumination*alpha,alpha),orbital);
        }else cloud*=1-orbital;
    }
    float3 color=scene.sample(s,uv).rgb*(1-cloud.a)+cloud.rgb;
    // Lens ghosts are driven by the resolved, visible solar disc. Cloud and
    // geometry occlusion suppress them; the atmospheric aureole is separate.
    float sunZ=dot(f.sun.xyz,f.forward.xyz);
    if(f.sunShape.y>0&&f.sun.w>0&&sunZ>0){
        float aspect=f.screen.x/f.screen.y;
        float2 sunUV=float2(.5f+.5f*dot(f.sun.xyz,f.right.xyz)/(sunZ*f.screen.z*aspect),.5f-.5f*dot(f.sun.xyz,f.up.xyz)/(sunZ*f.screen.z));
        if(all(sunUV>float2(0))&&all(sunUV<float2(1))){
            float3 source=scene.sample(s,sunUV).rgb;
            float visibility=smoothstep(2.0f,12.0f,max(source.r,max(source.g,source.b)))*(1-clouds.sample(s,sunUV).a);
            visibility*=smoothstep(0.0f,.08f,min(min(sunUV.x,1-sunUV.x),min(sunUV.y,1-sunUV.y)))*f.sunShape.y*f.sun.w;
            float2 axis=sunUV-float2(.5f);
            float2 p1=(uv-(float2(.5f)-axis*.38f))*float2(aspect,1);
            float2 p2=(uv-(float2(.5f)-axis*.82f))*float2(aspect,1);
            float2 p3=(uv-(float2(.5f)+axis*.32f))*float2(aspect,1);
            float ring=exp(-pow((length(p1)-.025f)/.0035f,2.0f));
            float ghost=exp(-dot(p2,p2)/.00011f),small=exp(-dot(p3,p3)/.000045f);
            color+=visibility*(float3(.04,.065,.085)*ring+float3(.095,.065,.045)*ghost+float3(.035,.055,.07)*small);
        }
    }
    // Directional light scattered through gaps near the Sun. This reuses the
    // resolved cloud opacity instead of adding another volume march.
    if(f.clouds.z>0&&cameraHeight<f.clouds.y+9000){
        float sunHeight=dot(normalize(f.position.xyz),f.sun.xyz);
        float day=smoothstep(-.08f,.12f,sunHeight)*f.sun.w;
        float forwardGlow=pow(max(0.0f,dot(ray,f.sun.xyz)),18.0f);
        float3 warm=mix(float3(1.0,.38,.22),float3(.85,.91,1.0),smoothstep(.02f,.3f,sunHeight));
        color+=warm*forwardGlow*(1-cloud.a)*f.clouds.z*day*.04f;
    }
    // Two sparse, short streak layers approximate nearby falling water. Fade
    // against close geometry so rain does not paint over the cockpit panel.
    if(f.weather.z>.01f && cameraHeight<lowCloudTop(f)+1500){
        float3 falling=-f.weatherWind.xyz-normalize(f.position.xyz)*12.0f;
        float2 direction=float2(dot(falling,f.right.xyz),-dot(falling,f.up.xyz));
        direction=length(direction)>1?normalize(direction):float2(.12,1);
        float2 across=float2(direction.y,-direction.x);
        float speed=clamp(length(falling)*.012f,.5f,4.0f),rain=0;
        for(int layer=0;layer<2;++layer){
            float scale=layer==0?1.0f:1.45f;
            float2 coord=float2(dot(in.position.xy,across)/55.0f,dot(in.position.xy,direction)/75.0f)*scale;
            coord.y-=f.environment.w*speed*(layer==0?1.5f:2.2f);
            float2 cell=floor(coord),local=fract(coord)-.5f;
            uint seed=uint(int(cell.x)*1973+int(cell.y)*9277+layer*26699);
            float random=visualRandom(seed);
            float enabled=step(random,f.weather.z*.23f);
            local-=float2(visualRandom(seed+73)-.5f,visualRandom(seed+181)-.5f)*.55f;
            float halfLength=mix(.045f,.17f,visualRandom(seed+239))*mix(.7f,1.3f,saturate(speed/4));
            float streak=(1-smoothstep(.012f,.035f,abs(local.x)))*(1-smoothstep(halfLength*.65f,halfLength,abs(local.y)));
            rain=max(rain,enabled*streak*mix(.035f,.085f,visualRandom(seed+359)));
        }
        float day=smoothstep(-.15f,.15f,dot(normalize(f.position.xyz),f.sun.xyz));
        rain*=smoothstep(2.0f,18.0f,geometry);
        color=mix(color,float3(.65,.72,.8)*(.08+.68*day),rain);
    }
    // A short-lived world-anchored bolt. Screen-space distances give a thin,
    // bright channel and a broad flash without another volume march.
    if(f.lightning.w>.01f && cameraHeight<lowCloudTop(f)+3000){
        float3 ground=f.lightning.xyz;
        float3 radial=normalize(f.position.xyz*f.body.x+ground);
        float3 top=ground+radial*6500.0f;
        float zg=dot(ground,f.forward.xyz),zt=dot(top,f.forward.xyz);
        if(zg>1&&zt>1){
            float aspect=f.screen.x/f.screen.y;
            float2 a=float2(.5+.5*dot(ground,f.right.xyz)/(zg*f.screen.z*aspect),.5-.5*dot(ground,f.up.xyz)/(zg*f.screen.z))*f.screen.xy;
            float2 b=float2(.5+.5*dot(top,f.right.xyz)/(zt*f.screen.z*aspect),.5-.5*dot(top,f.up.xyz)/(zt*f.screen.z))*f.screen.xy;
            float2 delta=b-a,normal=length(delta)>1?normalize(float2(-delta.y,delta.x)):float2(1,0);
            float d=1e9;float2 last=a;uint seed=uint(abs(ground.x)*.1f+abs(ground.y)*.3f+abs(ground.z)*.7f);
            for(int i=1;i<=8;++i){
                float t=float(i)/8.0f;float2 next=mix(a,b,t)+normal*((i==8?0.0f:visualRandom(seed+uint(i)*71)-.5f)*min(55.0f,length(delta)*.15f));
                float2 edge=next-last;float h=saturate(dot(in.position.xy-last,edge)/max(1e-4f,dot(edge,edge)));
                d=min(d,length(in.position.xy-(last+edge*h)));last=next;
            }
            float sceneDepth=geometry*max(.001f,dot(ray,f.forward.xyz));
            if(min(zg,zt)<sceneDepth){
                float flash=f.lightning.w;
                float glow=exp(-d*.055f)*flash*.24f,core=exp(-d*d*.55f)*flash*2.4f;
                color+=float3(.55,.68,1)*glow+float3(.9,.94,1)*core;
                color+=cloud.rgb*flash*.30f;
            }
        }
    }
    return float4(color,1);
}
// Rain is drawn on the original cockpit-glass mesh after the scene has been
// composed. Local coordinates keep droplets on the pane when the pilot looks
// or zooms, and the scene texture supplies a small refractive distortion.
struct RainVertex {packed_float3 position;packed_float3 normal;packed_float2 uv;};
struct RainRaster {float4 position [[position]];float3 local;float3 normal;float3 world;};
vertex RainRaster rainGlassVertex(uint id [[vertex_id]],const device RainVertex *vertices [[buffer(0)]],
                                  constant FrameUniforms &f [[buffer(1)]],constant float4x4 &model [[buffer(2)]]){
    RainVertex v=vertices[id];float3 p=(model*float4(float3(v.position),1)).xyz;
    float3 view=float3(dot(p,f.right.xyz),dot(p,f.up.xyz),-dot(p,f.forward.xyz));
    return {f.projection*float4(view,1),float3(v.position),float3(v.normal),p};
}
// coverage, refraction gradient, and specular rim for one drop per cell.
float4 rainBead(float2 uv,float probability,uint salt,float stretch){
    float2 cell=floor(uv),local=fract(uv);
    uint seed=uint(int(cell.x)*1973+int(cell.y)*9277)+salt;
    if(visualRandom(seed)>probability)return float4(0);
    float2 center=float2(.25f+.5f*visualRandom(seed+17),.25f+.5f*visualRandom(seed+71));
    float2 delta=local-center;delta.y*=stretch;
    float radius=mix(.10f,.22f,visualRandom(seed+151));
    float d=length(delta),angle=atan2(delta.y,delta.x);
    radius*=1+.07f*sin(angle*3+visualRandom(seed+271)*6.2831853f);
    float body=1-smoothstep(radius*.70f,radius,d);
    float rim=smoothstep(radius*.48f,radius*.78f,d)*(1-smoothstep(radius*.88f,radius*1.08f,d));
    rim*=clamp(.55f-(delta.x+delta.y)*1.6f/max(radius,.001f),.15f,1.0f);
    float2 slope=delta/max(radius,.001f)*body;
    return float4(body,slope,rim);
}
fragment float4 rainGlassFragment(RainRaster in [[stage_in]],constant FrameUniforms &f [[buffer(1)]],
                                   constant float4x4 &model [[buffer(2)]],constant float4 &runoff [[buffer(3)]],texture2d<float> scene [[texture(0)]]){
    if(f.weather.z<=.01f)discard_fragment();
    float3 localNormal=normalize(in.normal);float side=smoothstep(.38f,.76f,abs(localNormal.x));
    float sideSign=in.local.x<0?-1.0f:1.0f;
    float2 surface=float2(mix(in.local.x,in.local.z*sideSign,side),in.local.y+in.local.z*.35f);
    float airspeed=length(f.weatherWind.xyz),airflow=smoothstep(5.0f,200.0f,airspeed);
    float4 beads=rainBead(surface*78.0f,f.weather.z*mix(.58f,.22f,airflow),101u,1.0f);
    // Integrate motion on the CPU: multiplying absolute time by the current
    // speed makes droplets jump backwards whenever the aircraft slows down.
    float3 alongGlass=runoff.xyz-localNormal*dot(runoff.xyz,localNormal);
    float2 drift=float2(mix(alongGlass.x,alongGlass.z*sideSign,side),alongGlass.y+alongGlass.z*.35f);
    float2 moving=(surface-drift)*60.0f;
    float4 running=rainBead(moving,f.weather.z*mix(.10f,.35f,airflow),809u,mix(1.0f,.68f,airflow));
    float body=max(beads.x,running.x),rim=max(beads.w,running.w);
    if(body<.004f&&rim<.004f)discard_fragment();
    float2 gradient=beads.yz+running.yz;
    float3 axisX=mix(model[0].xyz,model[2].xyz*sideSign,side);
    float3 axisY=model[1].xyz+model[2].xyz*.35f;
    float3 displacement=axisX*gradient.x+axisY*gradient.y;
    float2 shift=float2(dot(displacement,f.right.xyz),-dot(displacement,f.up.xyz))*.0022f;
    float2 uv=in.position.xy/f.screen.xy;
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float3 refracted=scene.sample(s,clamp(uv+shift,0.0f,1.0f)).rgb;
    float daylight=smoothstep(-.12f,.12f,dot(normalize(f.position.xyz),f.sun.xyz))*f.sun.w;
    float3 normal=normalize((model*float4(localNormal,0)).xyz);
    float3 view=normalize(-in.world),halfVector=normalize(f.sun.xyz+view);
    float spec=pow(max(0.0f,abs(dot(normal,halfVector))),36.0f)*daylight;
    float highlight=rim*(.018f+.075f*daylight)+body*spec*.12f;
    return float4(refracted*(1-body*.035f-rim*.04f)+float3(.80,.89,1.0)*highlight,1);
}
float3 exhaustBasis(float3 d){return normalize(cross(d,abs(d.y)<.9?float3(0,1,0):float3(1,0,0)));}
struct FlameRaster {float4 position [[position]];float3 ray;float3 origin [[flat]];float3 axis [[flat]];float4 properties [[flat]];float time [[flat]];};
vertex FlameRaster flameVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant FrameUniforms &f [[buffer(0)]],
                               constant EffectUniforms &e [[buffer(1)]],constant EmitterUniforms *emitters [[buffer(2)]]) {
    EmitterUniforms jet=emitters[instance];float2 quad[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float3 axis=normalize(jet.directionRadius.xyz),origin=jet.positionLevel.xyz-e.offset.xyz;
    float plumeLength=jet.style.y*sqrt(jet.positionLevel.w),radius=jet.directionRadius.w*(.82+.18*sqrt(jet.positionLevel.w));
    float3 center=origin+axis*(plumeLength*.5);float2 projected=float2(dot(axis,f.right.xyz),dot(axis,f.up.xyz));
    float projectedLength=length(projected);float2 along=projectedLength>.001?projected/projectedLength:float2(0,1),across=float2(-along.y,along.x);
    float maxRadius=radius*(1.8+jet.style.w*3),depth=dot(center,f.forward.xyz);
    float nearDepth=depth-abs(dot(axis,f.forward.xyz))*plumeLength*.5-maxRadius;
    float planeDepth=max(depth,.5f);center+=f.forward.xyz*(planeDepth-depth);
    float perspective=clamp(planeDepth/max(.2f,nearDepth),1.0f,4.0f);
    float2 corner=along*quad[id].y*(plumeLength*projectedLength*.5+maxRadius)*perspective+across*quad[id].x*maxRadius*perspective;
    float3 p=center+f.right.xyz*corner.x+f.up.xyz*corner.y;
    float3 view=float3(dot(p,f.right.xyz),dot(p,f.up.xyz),-dot(p,f.forward.xyz));
    return {f.projection*float4(view,1),p,origin,axis,float4(radius,plumeLength,jet.positionLevel.w,jet.style.w),e.clock.y};
}
fragment float4 flameFragment(FlameRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],
                              texture2d<float,access::read> depth [[texture(0)]],texture3d<float> noise [[texture(1)]],texture2d<float> cloudMap [[texture(2)]]) {
    float3 ray=normalize(in.ray),axis=in.axis,ro=-in.origin;
    float radialBound=in.properties.x*(1.8+in.properties.w*3),len=in.properties.y;
    float rdAxis=dot(ray,axis),roAxis=dot(ro,axis);float3 rd=ray-axis*rdAxis,radial=ro-axis*roAxis;
    float a=dot(rd,rd),b=dot(radial,rd),c=dot(radial,radial)-radialBound*radialBound;
    float nearCylinder=0,farCylinder=1e8;
    if(a>1e-7){float disc=b*b-a*c;if(disc<=0)discard_fragment();float root=sqrt(disc);nearCylinder=(-b-root)/a;farCylinder=(-b+root)/a;}
    else if(c>0)discard_fragment();
    float nearAxial=0,farAxial=1e8;
    if(abs(rdAxis)>1e-7){float x=-roAxis/rdAxis,y=(len-roAxis)/rdAxis;nearAxial=min(x,y);farAxial=max(x,y);}
    else if(roAxis<0||roAxis>len)discard_fragment();
    float start=max(0.0f,max(nearCylinder,nearAxial)),end=min(farCylinder,farAxial);
    float2 depthScale=float2(depth.get_width(),depth.get_height())/f.screen.xy;
    uint2 pixel=min(uint2(in.position.xy*depthScale),uint2(depth.get_width()-1,depth.get_height()-1));float z=depth.read(pixel).r;
    if(z>0)end=min(end,(.2/z)/max(.001f,dot(ray,f.forward.xyz)));
    if(end<=start)discard_fragment();
    constexpr sampler s(filter::linear,address::repeat);float3 basis=exhaustBasis(axis),second=cross(axis,basis);
    float stepLength=(end-start)/12,trans=1;float3 radiance=0;
    for(int i=0;i<12&&trans>.015;++i){
        float t=start+(float(i)+.5)*stepLength;float3 local=ro+ray*t;
        float along=saturate(dot(local,axis)/len);float3 lateral=local-axis*dot(local,axis);
        float width=in.properties.x*(.90+along*(.9+in.properties.w*3))*pow(max(.001f,1-along),.45f);
        float2 crossSection=float2(dot(lateral,basis),dot(lateral,second))/max(.001f,width);
        // Advect the turbulent combustion pattern rapidly away from the nozzle.
        float3 samplePoint=float3(along*5-fmod(in.time*24,16.0f),crossSection*1.4+fmod(in.time*1.1,16.0f));
        float n=noise.sample(s,samplePoint).g,detail=noise.sample(s,samplePoint*2.2+float3(3,1,7)).b;
        float r=length(crossSection),edge=1-smoothstep(.63f,1.10f,r+(n-.5)*.55+(detail-.5)*.18);
        float density=edge*(.28+.72*smoothstep(.16f,.76f,n*.72+detail*.28))*(1-smoothstep(.90f,1.0f,along));
        float core=(1-smoothstep(.08f,.75f,r))*(1-along*.55);
        float shock=.90+.10*cos(along*12*M_PI_F-in.time*12)*(1-saturate(in.properties.w*5));
        float3 hot=mix(float3(7,1.0,.035),float3(12,5.5,.85),core);
        hot=mix(hot,float3(15,13,9),saturate(core*core*shock));hot*=1-along*.60;
        float opacity=1-exp(-density*stepLength*1.5/max(.02f,in.properties.x));
        radiance+=trans*opacity*hot;trans*=1-opacity;
    }
    float alpha=(1-trans)*sqrt(in.properties.z)*.8;if(alpha<.002)discard_fragment();
    if(f.environment.x*f.body.x<f.clouds.y+1000&&f.clouds.z>0){float distance=(start+end)*.5,optical=0;float3 origin=f.position.xyz*f.body.x;
        float region=cloudRegion(origin+ray*distance*.5,f,cloudMap);
        for(int i=0;i<4;++i)optical+=cloudDensity(origin+ray*distance*((i+.5)/4.0f),f,noise,region)*distance*.25;alpha*=exp(-optical);}
    return float4(radiance/max(.001f,1-trans),alpha);
}
// Continuous world-space tube segments follow the emitted exhaust; the material
// adds moving, translucent turbulence without marching every pixel through a volume.
struct TrailRaster {
    float4 position [[position]]; float3 ray,normal,local; float2 opacityAge;
    float edge;float3 phase [[flat]]; float vacuum [[flat]];float cap [[flat]];
};
vertex TrailRaster trailVolumeVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant FrameUniforms &f [[buffer(0)]],
                                    const device TrailSegmentUniforms *segments [[buffer(1)]],texture3d<float> noise [[texture(0)]]){
    constexpr sampler sampler3d(filter::linear,address::repeat);
    TrailSegmentUniforms seg=segments[instance];uint side=id/12,ring=(id/6)%2,corner=id%6;
    uint2 tri[6]={uint2(0,0),uint2(1,0),uint2(1,1),uint2(0,0),uint2(1,1),uint2(0,1)};
    bool cap=id>=144;uint capId=cap?id-144:0,capSide=(capId%36)/3,capCorner=capId%3;
    float t=cap?float(capId/36):(float(ring)+float(tri[corner].y))*.5;
    float angle=cap?float(capSide+(capCorner==2?1:0))*(2*M_PI_F/12):float(side+tri[corner].x)*(2*M_PI_F/12);
    float edge=cap?(capCorner==0?0.0f:1.0f):1.0f;
    float3 delta=seg.endRadius.xyz-seg.startRadius.xyz,axis=normalize(delta);
    float3 first=exhaustBasis(axis),second=cross(axis,first),radial=first*cos(angle)+second*sin(angle);
    float3 center=mix(seg.startRadius.xyz,seg.endRadius.xyz,t);float radius=mix(seg.startRadius.w,seg.endRadius.w,t);
    float3 uv=seg.noiseMode.xyz+(center-seg.startRadius.xyz+radial*radius)/64.0f+float3(f.environment.w*.009,f.environment.w*.006,-f.environment.w*.007);
    float irregularity=noise.sample(sampler3d,uv,level(0)).g;radius*=.65+.70*irregularity;
    float3 p=center+radial*radius*edge;float3 view=float3(dot(p,f.right.xyz),dot(p,f.up.xyz),-dot(p,f.forward.xyz));
    return {f.projection*float4(view,1),p,cap?axis*(t>0?1.0f:-1.0f):radial,p-seg.startRadius.xyz,
            float2(mix(seg.opticalAge.x,seg.opticalAge.y,t),mix(seg.opticalAge.z,seg.opticalAge.w,t)),edge,seg.noiseMode.xyz,seg.noiseMode.w,cap?1.0f:0.0f};
}
fragment float4 trailVolumeFragment(TrailRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],
                                    texture2d<float,access::read> depth [[texture(0)]],texture3d<float> noise [[texture(1)]],texture2d<float> cloudMap [[texture(2)]]){
    constexpr sampler sampler3d(filter::linear,address::repeat);
    float2 depthScale=float2(depth.get_width(),depth.get_height())/f.screen.xy;
    uint2 pixel=min(uint2(in.position.xy*depthScale),uint2(depth.get_width()-1,depth.get_height()-1));float z=depth.read(pixel).r;
    float scene=z>0?.2/z:1e9,viewDepth=dot(in.ray,f.forward.xyz);
    float fade=saturate((scene-viewDepth)/max(.5f,viewDepth*f.screen.z/max(1.0f,f.screen.y)));
    if(fade<=0)discard_fragment();
    float3 uv=in.phase+in.local/64.0f+float3(f.environment.w*.009,f.environment.w*.006,-f.environment.w*.007);
    float4 coarse=noise.sample(sampler3d,uv);float detail=noise.sample(sampler3d,uv*2+float3(.19,.43,.07)).r;
    float turbulence=coarse.g*.64+detail*.36,billows=smoothstep(.36f,.72f,turbulence);
    float3 ray=normalize(in.ray),normal=normalize(in.normal);float facing=pow(abs(dot(ray,normal)),1.2f);
    float material=.24+2.15*billows*billows,optical=clamp(in.opacityAge.x,0.0f,.98f);
    float alpha=(1-pow(max(.001f,1-optical),material*.5))*facing*fade;
    if(in.cap>.5)alpha*=.75*smoothstep(.72f,.95f,abs(dot(ray,normal)))*(1-smoothstep(.20f,1.0f,in.edge));
    if(alpha<.00002)discard_fragment();
    float sunPhase=clamp(.55f*(1-.45f*.45f)/pow(max(.05f,1+.45f*.45f-.9f*dot(ray,f.sun.xyz)),1.5f),.25f,2.0f);
    float light=f.sun.w*sunPhase*(.35+.65*abs(dot(normal,f.sun.xyz)))*exp(-optical*coarse.g*.8);
    float hot=exp(-in.opacityAge.y*(in.vacuum>.5?1.6f:2.5f));
    float3 color=in.vacuum>.5?float3(.46,.59,.76):float3(.84,.83,.78);
    color*=.16+.84*light;color+=hot*(in.vacuum>.5?float3(.60,.38,.18):float3(.50,.28,.12));
    if(f.environment.x*f.body.x<f.clouds.y+1000&&f.clouds.z>0){
        float distance=length(in.ray);float3 midpoint=f.position.xyz*f.body.x+in.ray*.5;
        alpha*=exp(-cloudDensity(midpoint,f,noise,cloudRegion(midpoint,f,cloudMap))*distance);
    }
    return float4(color,alpha);
}
fragment float4 compositeTrail(SkyRaster in [[stage_in]],texture2d<float> trail [[texture(0)]],
                               texture2d<float,access::read> depth [[texture(1)]]){
    constexpr sampler linear(filter::linear,address::clamp_to_edge);
    float2 uv=float2(in.uv.x,1-in.uv.y),size=float2(trail.get_width(),trail.get_height());
    float2 center=(floor(uv*size)+.5)/size;uint2 fullSize=uint2(depth.get_width(),depth.get_height());
    float current=depth.read(min(uint2(uv*float2(fullSize)),fullSize-1)).r;
    float reference=depth.read(min(uint2(center*float2(fullSize)),fullSize-1)).r;
    if((current>0)!=(reference>0))return float4(0);
    if(current>0){float a=.2/current,b=.2/reference;if(abs(a-b)>max(3.0f,min(a,b)*.05f))return float4(0);}
    return trail.sample(linear,uv);
}
kernel void extractBloom(texture2d<float> source [[texture(0)]],texture2d<float,access::write> output [[texture(1)]],constant FrameUniforms &f [[buffer(0)]],uint2 id [[thread_position_in_grid]]){
    if(id.x>=output.get_width()||id.y>=output.get_height())return;
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 uv=(float2(id)+.5)/float2(output.get_width(),output.get_height());
    float3 c=source.sample(s,uv).rgb,bloom=max(c-1.15f,0.0f);
    if(f.sun.w>0&&f.sunShape.x>0&&dot(viewRay(uv,f),f.sun.xyz)>0){
        float haze=int(f.surfaceColor.w)==3?earthSunHaze(f):0;
        float angle=length(cross(viewRay(uv,f),f.sun.xyz));
        float footprint=4*f.screen.z/max(1.0f,f.screen.y);
        float sunMask=1-smoothstep(f.sunShape.x*.5f,f.sunShape.x*1.6f+footprint,angle);
        bloom*=1-sunMask*(1-smoothstep(.005f,.04f,haze));
    }
    output.write(float4(bloom,1),id);
}
kernel void blurBloom(texture2d<float> source [[texture(0)]],texture2d<float,access::write> output [[texture(1)]],constant uint &vertical [[buffer(0)]],uint2 id [[thread_position_in_grid]]){
    if(id.x>=output.get_width()||id.y>=output.get_height())return;
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 size=float2(output.get_width(),output.get_height()),uv=(float2(id)+.5)/size;
    float3 c=0;float total=0;
    for(int i=-5;i<=5;++i){float w=exp(-float(i*i)/12);c+=source.sample(s,uv+(vertical?float2(0,i):float2(i,0))/size).rgb*w;total+=w;}
    output.write(float4(c/total,1),id);
}
kernel void adaptSolarExposure(texture2d<float> scene [[texture(0)]],texture2d<float,access::read_write> exposure [[texture(1)]],constant FrameUniforms &f [[buffer(0)]],constant float &dt [[buffer(1)]],uint id [[thread_position_in_grid]]){
    if(id)return;
    constexpr sampler s(filter::linear,address::clamp_to_edge);
    float visible=0,sunZ=dot(f.sun.xyz,f.forward.xyz);
    if(f.sun.w>0&&f.sunShape.x>0&&sunZ>0){
        float aspect=f.screen.x/f.screen.y;
        float2 uv=float2(.5f+.5f*dot(f.sun.xyz,f.right.xyz)/(sunZ*f.screen.z*aspect),.5f-.5f*dot(f.sun.xyz,f.up.xyz)/(sunZ*f.screen.z));
        if(all(uv>=float2(0))&&all(uv<=float2(1))){
            float3 sample=scene.sample(s,uv).rgb;
            float edge=smoothstep(0.0f,.06f,min(min(uv.x,1-uv.x),min(uv.y,1-uv.y)));
            visible=smoothstep(2.0f,12.0f,max(sample.r,max(sample.g,sample.b)))*edge*f.sun.w;
        }
    }
    float target=mix(1.0f,.42f,saturate(visible));float old=exposure.read(uint2(0)).r;
    float rate=target<old?2.5f:1.0f;
    exposure.write(float4(mix(old,target,1-exp(-clamp(dt,0.0f,.1f)*rate))),uint2(0));
}
fragment float4 toneMap(SkyRaster in [[stage_in]],texture2d<float> scene [[texture(0)]],texture2d<float> bloom [[texture(1)]],texture2d<float,access::read> exposure [[texture(2)]],constant float &headroom [[buffer(0)]]){
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 uv=float2(in.uv.x,1-in.uv.y);
    float3 x=(scene.sample(s,uv).rgb+bloom.sample(s,uv).rgb*.10)*exposure.read(uint2(0)).r;
    float3 color=saturate((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14));
    float peak=max(x.r,max(x.g,x.b));float extra=(max(1.0f,headroom)-1)*(1-exp(-max(0.0f,peak-1.5f)/4.0f));
    color*=1+extra;
    return float4(color,1);
}

// Cloud volumes, temporal reconstruction and exhaust implemented directly in Metal.
constant float planetRadius=6371010.0f;
constant uint particleCapacity=4096;
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
    float co=cos(.4090928f),so=sin(.4090928f);
    float3 e=float3(p.x,p.y*co+p.z*so,-p.y*so+p.z*co);
    float a=f.screen.w*(2*M_PI_F),c=cos(a),s=sin(a);
    return float3(c*e.x-s*e.z,e.y,s*e.x+c*e.z);
}
float2 terrestrialUV(float3 p,constant FrameUniforms &f) {
    float3 e=normalize(terrestrial(p,f));
    return float2(atan2(e.z,e.x)/(2*M_PI_F)+.5,acos(clamp(e.y,-1.0f,1.0f))/M_PI_F);
}
float cloudDensity(float3 p,constant FrameUniforms &f,texture3d<float> noise) {
    if(f.clouds.z<=0)return 0;
    float h=length(p)-planetRadius;
    float height=(h-f.clouds.x)/(f.clouds.y-f.clouds.x);
    if(height<=0||height>=1)return 0;
    constexpr sampler s(filter::linear,address::repeat);
    float3 w=terrestrial(p,f)+float3(f.environment.w*14,0,f.environment.w*7);
    float weather=noise.sample(s,w/320000.0f).b;
    float coverage=clamp(f.clouds.z+(weather-.5)*.65,.01f,.98f);
    float shape=noise.sample(s,w/52000.0f).r;
    float threshold=.84-coverage*.75+height*height*.16;
    float density=smoothstep(threshold,threshold+.20,shape);
    if(density<=0)return 0;
    float detail=noise.sample(s,w/8500.0f).g;
    density=max(0.0f,density-(1-detail)*.32*(1-density));
    float profile=smoothstep(0.0f,.14f,height)*(1-smoothstep(.55f,1.0f,height));
    return density*profile*(.00065+f.clouds.w*.00045);
}
// Stable sphere intersections avoid subtracting two large, nearly equal squared radii.
float2 cloudShellRoots(float cameraHeight,float shellHeight,float mu) {
    float b=(planetRadius+cameraHeight)*mu;
    float c=(cameraHeight-shellHeight)*(2*planetRadius+cameraHeight+shellHeight);
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
float cloudSunTransmittance(float3 p,constant FrameUniforms &f,texture3d<float> noise) {
    float optical=0,last=0;
    for(int i=0;i<4;++i){float t=220.0f*pow(2.8f,float(i));optical+=cloudDensity(p+f.sun.xyz*t,f,noise)*(t-last);last=t;}
    return exp(-optical);
}
kernel void cloudShadowMap(constant FrameUniforms &f [[buffer(0)]],texture3d<float> noise [[texture(0)]],
                           texture2d<float,access::write> shadow [[texture(1)]],uint2 id [[thread_position_in_grid]]) {
    if(id.x>=shadow.get_width()||id.y>=shadow.get_height())return;
    float2 uv=(float2(id)+.5)/float2(shadow.get_width(),shadow.get_height());
    float3 ray=viewRay(uv,f);float cameraHeight=f.environment.x*planetRadius;
    float2 roots=cloudShellRoots(cameraHeight,0,dot(normalize(f.position.xyz),ray));
    float optical=0;
    if(roots.x>=0&&roots.y>roots.x&&f.clouds.z>0){
        float3 surface=normalize(normalize(f.position.xyz)*(planetRadius+cameraHeight)+ray*roots.x)*planetRadius;
        float mu=dot(normalize(surface),f.sun.xyz);
        if(mu>.02){
            float step=(f.clouds.y-f.clouds.x)/4;
            for(int i=0;i<4;++i){float t=(f.clouds.x+(i+.5)*step)/max(.08f,mu);optical+=cloudDensity(surface+f.sun.xyz*t,f,noise)*step/max(.08f,mu);}
        }
    }
    shadow.write(float4(.26+.74*exp(-optical)),id);
}
kernel void marchClouds(constant FrameUniforms &f [[buffer(0)]],constant uint &frameIndex [[buffer(1)]],
                        texture3d<float> noise [[texture(0)]],texture2d<float,access::read> depth [[texture(1)]],
                        texture2d<float> previous [[texture(2)]],texture2d<float> previousData [[texture(3)]],
                        texture2d<float,access::write> result [[texture(4)]],texture2d<float,access::write> data [[texture(5)]],
                        uint2 id [[thread_position_in_grid]]) {
    uint2 size=uint2(result.get_width(),result.get_height());if(any(id>=size))return;
    float2 uv=(float2(id)+.5)/float2(size);float3 ray=viewRay(uv,f);
    uint2 full=min(uint2(uv*float2(depth.get_width(),depth.get_height())),uint2(depth.get_width()-1,depth.get_height()-1));
    float geometry=depthDistance(depth.read(full).r,ray,f);
    float cameraHeight=f.environment.x*planetRadius;
    float2 roots=cloudShellRoots(cameraHeight,f.clouds.y,dot(normalize(f.position.xyz),ray));
    float start=max(0.0f,roots.x),end=min(roots.y,geometry);
    float2 inner=cloudShellRoots(cameraHeight,f.clouds.x,dot(normalize(f.position.xyz),ray));
    if(cameraHeight>f.clouds.x&&inner.x>start)end=min(end,inner.x);
    float3 origin=normalize(f.position.xyz)*(planetRadius+cameraHeight);
    float3 radiance=0;float trans=1,weightedDistance=0,weight=0;
    if(f.clouds.z>0&&end>start){
        float step=(end-start)/48.0f;
        float3 center=normalize(origin+ray*((start+end)*.5));
        float mu=dot(center,f.sun.xyz),day=smoothstep(-.08f,.12f,mu);
        float g=.55,cosTheta=dot(ray,f.sun.xyz);
        float phase=(1-g*g)/pow(max(.05f,1+g*g-2*g*cosTheta),1.5f);
        float3 sunlight=mix(float3(1.9,.88,.43),float3(1.8,1.86,2.0),smoothstep(.02f,.35f,mu));
        float3 ambient=mix(float3(.003,.005,.012),float3(.15,.20,.29),day);
        float jitter=visualRandom(id.x+id.y*1973u+frameIndex*26699u);
        for(int i=0;i<48;++i){
            float t=start+(i+jitter)*step;float3 p=origin+ray*t;
            float density=cloudDensity(p,f,noise);if(density<.000002)continue;
            float lighting=cloudSunTransmittance(p,f,noise);
            float3 light=ambient+sunlight*day*(lighting*(.30+.23*phase)+pow(lighting,.4f)*.17);
            float extinction=1-exp(-density*step),contribution=trans*extinction;
            radiance+=light*contribution;weightedDistance+=t*contribution;weight+=contribution;
            trans*=1-extinction;if(trans<.012)break;
        }
    }
    float distance=weight>.001?weightedDistance/weight:(start+max(start,end))*.5;
    float4 color=float4(radiance,1-trans);
    if(f.environment.z>.5){
        float3 toPrevious=(f.position.xyz-f.previousPosition.xyz)*planetRadius+ray*distance;
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
                                texture2d<float> cloudData [[texture(2)]],texture2d<float,access::read> depth [[texture(3)]]) {
    float2 uv=float2(in.uv.x,1-in.uv.y);constexpr sampler s(filter::linear,address::clamp_to_edge);
    float3 ray=viewRay(uv,f);uint2 pixel=min(uint2(uv*f.screen.xy),uint2(f.screen.xy)-1);
    float geometry=depthDistance(depth.read(pixel).r,ray,f);
    float2 cloudSize=float2(clouds.get_width(),clouds.get_height());
    float2 p=uv*cloudSize-.5,base=floor(p),frac=fract(p);float4 cloud=0;float total=0;
    for(int y=0;y<2;++y)for(int x=0;x<2;++x){
        float2 q=(base+float2(x,y)+.5)/cloudSize;
        float d=cloudData.sample(s,q).r;
        float w=(x?frac.x:1-frac.x)*(y?frac.y:1-frac.y);
        w*=min(d,geometry)>5000?1:step(abs(d-geometry),max(2.0f,geometry*.025f));
        cloud+=clouds.sample(s,q)*w;total+=w;
    }
    cloud/=max(total,.0001f);
    return float4(scene.sample(s,uv).rgb*(1-cloud.a)+cloud.rgb,1);
}
kernel void updateExhaust(device ParticleUniforms *particles [[buffer(0)]],constant EmitterUniforms *emitters [[buffer(1)]],
                          constant EffectUniforms &e [[buffer(2)]],uint id [[thread_position_in_grid]]) {
    if(id>=particleCapacity)return;
    ParticleUniforms p=particles[id];float dt=e.clock.x;
    if(e.translation.w>.5){p.positionAge=float4(0,0,0,-1);p.velocityLife=float4(0,0,0,1);p.style=0;}
    if(p.positionAge.w>=0){
        p.positionAge.xyz+=e.translation.xyz+p.velocityLife.xyz*dt+e.gravity.xyz*(dt*dt*.5);
        p.velocityLife.xyz+=e.gravity.xyz*dt;p.positionAge.w+=dt;
        if(p.positionAge.w>=p.velocityLife.w)p.positionAge.w=-1;
    }
    uint emitter=id/128,slot=id%128;
    if(emitter<uint(e.clock.w)){
        EmitterUniforms jet=emitters[emitter];float rate=(jet.style.x>2.5?75.0f:220.0f)*sqrt(jet.positionLevel.w);
        float cycle=e.clock.y*rate/128.0f+float(slot)/128.0f;
        float oldCycle=e.clock.z*rate/128.0f+float(slot)/128.0f;
        if(dt>0&&floor(cycle)>floor(oldCycle)){
            uint seed=id+uint(floor(cycle))*11939u;float3 d=jet.directionRadius.xyz;
            float3 a=normalize(cross(d,abs(d.y)<.9?float3(0,1,0):float3(1,0,0))),b=cross(d,a);
            float angle=visualRandom(seed)*2*M_PI_F,r=sqrt(visualRandom(seed+71));
            float3 lateral=a*cos(angle)+b*sin(angle);
            p.positionAge=float4(jet.positionLevel.xyz+lateral*r*jet.directionRadius.w,0);
            p.velocityLife=float4(e.velocity.xyz+(d+lateral*r*jet.style.w)*jet.style.z,.30+visualRandom(seed+173)*.20);
            p.style=float4(jet.directionRadius.w*.35,jet.positionLevel.w,jet.style.x,visualRandom(seed+349));
        }
    }
    particles[id]=p;
}
struct ExhaustRaster { float4 position [[position]];float2 uv;float4 color;float3 cameraRelative;float viewDepth;float effect [[flat]]; };
float3 exhaustBasis(float3 d){return normalize(cross(d,abs(d.y)<.9?float3(0,1,0):float3(1,0,0)));}
ExhaustRaster exhaustProject(float3 p,float2 uv,float4 color,constant FrameUniforms &f){
    float3 view=float3(dot(p,f.right.xyz),dot(p,f.up.xyz),-dot(p,f.forward.xyz));
    return {f.projection*float4(view,1),uv,color,p,-view.z,0};
}
vertex ExhaustRaster flameVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant FrameUniforms &f [[buffer(0)]],
                                 constant EffectUniforms &e [[buffer(1)]],constant EmitterUniforms *emitters [[buffer(2)]]) {
    EmitterUniforms jet=emitters[instance];uint layer=id/(12*12*6),v=id%(12*12*6),ring=v/(12*6),side=(v/6)%12,corner=v%6;
    uint2 tri[6]={uint2(0,0),uint2(1,0),uint2(1,1),uint2(0,0),uint2(1,1),uint2(0,1)};
    float t=float(ring+tri[corner].y)/12.0f,angle=float(side+tri[corner].x)*(2*M_PI_F/12);
    float3 d=jet.directionRadius.xyz,a=exhaustBasis(d),b=cross(d,a);
    float diamonds=1+.075*cos(t*12*M_PI_F-e.clock.y*22)*(1-min(1.0f,jet.style.w*6));
    float radius=jet.directionRadius.w*sqrt(jet.positionLevel.w)*pow(max(.002f,1-t),layer?.7f:.4f)*(layer?.47f:1.0f);
    radius*=diamonds*(1+jet.style.w*t*5);
    float3 p=jet.positionLevel.xyz-e.offset.xyz+d*(t*jet.style.y*sqrt(jet.positionLevel.w))+(a*cos(angle)+b*sin(angle))*radius;
    float opacity=(layer?.30f:.10f)*pow(1-t,1.3f)*sqrt(jet.positionLevel.w);
    float3 color=layer?mix(float3(10,18,30),float3(.15,.8,3),t):float3(.15,1.1,5);
    return exhaustProject(p,float2(t,angle/(2*M_PI_F)),float4(color,opacity),f);
}
vertex ExhaustRaster particleVertex(uint id [[vertex_id]],uint instance [[instance_id]],constant FrameUniforms &f [[buffer(0)]],
                                    constant EffectUniforms &e [[buffer(1)]],const device ParticleUniforms *particles [[buffer(2)]]) {
    ParticleUniforms p=particles[instance];float2 quad[6]={float2(-1,-1),float2(1,-1),float2(1,1),float2(-1,-1),float2(1,1),float2(-1,1)};
    float age=p.positionAge.w/max(.001f,p.velocityLife.w),size=p.style.x*(.7+age*2);
    float3 flow=p.velocityLife.xyz-e.velocity.xyz;
    float2 screenFlow=float2(dot(flow,f.right.xyz),dot(flow,f.up.xyz));
    float2 along=length(screenFlow)>.001?normalize(screenFlow):float2(0,1),across=float2(-along.y,along.x);
    float2 corner=across*quad[id].x*size+along*quad[id].y*max(size,min(2.5f,length(flow)*.012f));
    float3 q=p.positionAge.xyz-e.offset.xyz+f.right.xyz*corner.x+f.up.xyz*corner.y;
    float alpha=p.positionAge.w>=0?.055f*sqrt(p.style.y)*pow(max(0.0f,1-age),1.7f):0;
    ExhaustRaster out=exhaustProject(q,quad[id],float4(.55,1.4,4,alpha),f);
    out.effect=1;if(alpha<=0)out.position=float4(2,2,2,1);return out;
}
fragment float4 exhaustFragment(ExhaustRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],
                                texture2d<float,access::read> depth [[texture(0)]],texture3d<float> noise [[texture(1)]]) {
    uint2 p=min(uint2(in.position.xy),uint2(depth.get_width()-1,depth.get_height()-1));
    float z=depth.read(p).r;float scene=z>0?.2/z:1e9;
    float alpha=in.color.a*saturate((scene-in.viewDepth)/.12f);
    if(in.effect>.5)alpha*=exp(-dot(in.uv,in.uv)*3.5);
    else {
        constexpr sampler s(filter::linear,address::repeat);
        float turbulence=noise.sample(s,float3(in.uv.x*1.8,in.uv.y,f.environment.w*.35)).g;
        alpha*=.55+.45*smoothstep(.2f,.8f,turbulence);
    }
    // Attenuate only cloud between the camera and the jet, rather than clouds behind it.
    if(f.environment.x*planetRadius<f.clouds.y+1000&&f.clouds.z>0){
        float lengthToJet=length(in.cameraRelative),optical=0;
        float3 origin=f.position.xyz*planetRadius;
        for(int i=0;i<4;++i)optical+=cloudDensity(origin+in.cameraRelative*((i+.5)/4.0f),f,noise)*lengthToJet*.25;
        alpha*=exp(-optical);
    }
    return float4(in.color.rgb,alpha);
}
kernel void extractBloom(texture2d<float> source [[texture(0)]],texture2d<float,access::write> output [[texture(1)]],uint2 id [[thread_position_in_grid]]){
    if(id.x>=output.get_width()||id.y>=output.get_height())return;
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 uv=(float2(id)+.5)/float2(output.get_width(),output.get_height());
    float3 c=source.sample(s,uv).rgb;output.write(float4(max(c-1.15f,0.0f),1),id);
}
kernel void blurBloom(texture2d<float> source [[texture(0)]],texture2d<float,access::write> output [[texture(1)]],constant uint &vertical [[buffer(0)]],uint2 id [[thread_position_in_grid]]){
    if(id.x>=output.get_width()||id.y>=output.get_height())return;
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 size=float2(output.get_width(),output.get_height()),uv=(float2(id)+.5)/size;
    float3 c=0;float total=0;
    for(int i=-5;i<=5;++i){float w=exp(-float(i*i)/12);c+=source.sample(s,uv+(vertical?float2(0,i):float2(i,0))/size).rgb*w;total+=w;}
    output.write(float4(c/total,1),id);
}
fragment float4 toneMap(SkyRaster in [[stage_in]],texture2d<float> scene [[texture(0)]],texture2d<float> bloom [[texture(1)]]){
    constexpr sampler s(filter::linear,address::clamp_to_edge);float2 uv=float2(in.uv.x,1-in.uv.y);
    float3 x=scene.sample(s,uv).rgb+bloom.sample(s,uv).rgb*.10;
    float3 color=saturate((x*(2.51*x+.03))/(x*(2.43*x+.59)+.14));
    return float4(color,1);
}

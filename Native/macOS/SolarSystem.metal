struct CelestialRaster {float4 position [[position]];};
vertex CelestialRaster celestialVertex(uint id [[vertex_id]],constant FrameUniforms &f [[buffer(0)]],constant CelestialUniforms &b [[buffer(1)]]){
    float2 quad[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
    float z=dot(b.directionRadius.xyz,f.forward.xyz),r=b.directionRadius.w*max(1.0f,b.rings.y);
    float2 center=float2(dot(b.directionRadius.xyz,f.right.xyz)/(f.screen.z*f.screen.x/f.screen.y),dot(b.directionRadius.xyz,f.up.xyz)/f.screen.z)/max(.001f,z);
    float2 extent=float2(r/(f.screen.z*f.screen.x/f.screen.y),r/f.screen.z)/max(.001f,z)*1.3;
    return {z>0?float4(center+quad[id]*extent,0,1):float4(2,2,2,1)};
}
fragment SkyOutput celestialFragment(CelestialRaster in [[stage_in]],constant FrameUniforms &f [[buffer(0)]],constant CelestialUniforms &b [[buffer(1)]],texture2d<float> map [[texture(0)]],texture2d<float> rings [[texture(1)]]){
    float3 ray=viewRay(in.position.xy/f.screen.xy,f),center=b.directionRadius.xyz;float radius=b.directionRadius.w;
    float projection=dot(ray,center),perpendicular=length(cross(ray,center)),disc=radius*radius-perpendicular*perpendicular;
    float distance=1e25;float3 color=0;float alpha=0;
    if(disc>=0&&projection>0){
        distance=projection-sqrt(disc);float3 normal=normalize(ray*distance-center);
        float3 equ=float3(dot(normal,b.axisX.xyz),dot(normal,b.pole.xyz),dot(normal,b.axisZ.xyz));
        float2 uv=float2(atan2(equ.z,equ.x)/(2*M_PI_F)+.5+b.axisX.w,acos(clamp(equ.y,-1.0f,1.0f))/M_PI_F);
        float3 surface=planetMaterial(normal,uv,b.material.rgb,int(b.material.w),b.axisZ.w>.5,map);
        float light=max(0.0f,dot(normal,b.light.xyz));color=surface*(.008+light);if(b.pole.w>1.5)color=surface*12;alpha=1;
    }
    if(b.rings.x>0){float den=dot(ray,b.pole.xyz);if(abs(den)>.00001){float t=dot(center,b.pole.xyz)/den;float3 point=(ray*t-center)/radius;float r=length(point);if(t>0&&t<distance&&r>b.rings.x&&r<b.rings.y){float4 ring=ringMaterial(point,ray,b.pole.xyz,b.rings.x,b.rings.y,b.light.xyz,rings);color=alpha>.99?mix(color,ring.rgb,ring.a):ring.rgb;alpha=max(alpha,ring.a);if(ring.a>.03)distance=t;}}}
    if(alpha<.01)discard_fragment();
    return {float4(color,alpha),.2/max(.0001f,distance*b.light.w*dot(ray,f.forward.xyz))};
}

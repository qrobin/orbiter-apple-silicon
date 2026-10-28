#pragma once
#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#define VFLOAT4 float4
#define VMATRIX float4x4
#else
#include <simd/simd.h>
#define VFLOAT4 simd_float4
#define VMATRIX simd_float4x4
#endif

// Shared CPU/Metal layouts; positions for geometry and exhaust are camera-relative metres.
struct FrameUniforms {
    VMATRIX projection;
    VFLOAT4 right,up,forward,position,sun,screen,environment;
    VFLOAT4 clouds; // base/top in metres, coverage, storm amount
    VFLOAT4 previousRight,previousUp,previousForward,previousPosition;
    VFLOAT4 body,haze,equatorX,pole,equatorZ,surfaceColor;
};
struct CelestialUniforms { VFLOAT4 directionRadius,axisX,pole,axisZ,light,material,rings; };
struct EmitterUniforms { VFLOAT4 positionLevel,directionRadius,style; };
struct ParticleUniforms { VFLOAT4 positionAge,velocityLife,style; };
struct EffectUniforms {
    VFLOAT4 clock; // simulation delta, time, previous time, emitter count
    VFLOAT4 translation; // old vessel origin minus current origin; reset flag
    VFLOAT4 velocity,offset,gravity;
};
#ifdef __METAL_VERSION__
struct SkyRaster { float4 position [[position]]; float2 uv; };
#endif
#undef VFLOAT4
#undef VMATRIX
#ifndef __METAL_VERSION__
static_assert(sizeof(FrameUniforms)==352 && sizeof(CelestialUniforms)==112 && sizeof(EmitterUniforms)==48 && sizeof(ParticleUniforms)==48 && sizeof(EffectUniforms)==80);
#endif

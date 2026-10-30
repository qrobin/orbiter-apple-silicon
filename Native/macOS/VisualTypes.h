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
    VFLOAT4 weather; // preset, local storm, rain and lightning pulse
    VFLOAT4 weatherWind; // air-relative velocity in world coordinates
    VFLOAT4 lightning; // ground strike relative to the camera, flash intensity
    VFLOAT4 previousRight,previousUp,previousForward,previousPosition;
    VFLOAT4 body,haze,equatorX,pole,equatorZ,surfaceColor;
    VFLOAT4 sunShape; // apparent solar angular radius; flare intensity; test halo disable
};
struct CelestialUniforms { VFLOAT4 directionRadius,axisX,pole,axisZ,light,material,rings; };
struct EmitterUniforms { VFLOAT4 positionLevel,directionRadius,style; };
struct TrailSegmentUniforms { VFLOAT4 startRadius,endRadius,opticalAge,noiseMode; };
struct EffectUniforms {
    VFLOAT4 clock; // simulation delta, visual time, unused, emitter count
    VFLOAT4 offset;
};
#ifdef __METAL_VERSION__
struct SkyRaster { float4 position [[position]]; float2 uv; };
#endif
#undef VFLOAT4
#undef VMATRIX
#ifndef __METAL_VERSION__
static_assert(sizeof(FrameUniforms)==416 && sizeof(CelestialUniforms)==112 && sizeof(EmitterUniforms)==48 && sizeof(TrailSegmentUniforms)==64 && sizeof(EffectUniforms)==32);
#endif

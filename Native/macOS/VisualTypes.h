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

struct VesselLight { VFLOAT4 positionRange,directionOuter,colorIntensity,attenuationInner; };

// Shared CPU/Metal layouts; positions for geometry and exhaust are camera-relative metres.
struct FrameUniforms {
    VMATRIX projection;
    VFLOAT4 right,up,forward,position,sun,screen,environment;
    VFLOAT4 clouds; // base/top in metres, coverage, storm amount
    VFLOAT4 weather; // preset, local storm, rain and lightning pulse
    VFLOAT4 weatherWind; // air-relative velocity in world coordinates
    VFLOAT4 rainMotion; // integrated air-relative rain displacement in world metres
    VFLOAT4 lightning; // ground strike relative to the camera, flash intensity
    VFLOAT4 previousRight,previousUp,previousForward,previousPosition;
    VFLOAT4 body,haze,equatorX,pole,equatorZ,surfaceColor;
    VFLOAT4 sunShape; // apparent solar radius; flare intensity; test halo disable; irradiance at camera (1 at 1 AU)
    VFLOAT4 terrainOriginHigh,terrainOriginLow; // body-fixed metres, split on a 4096 m grid; high.w enables the local frame
    VesselLight vesselLights[20]; // camera-relative positions; attenuationInner.w marks cockpit-only lights
    VFLOAT4 terrainAxisX,terrainAxisZ; // double-precision CPU rotation, rounded only after forming the axes
    VFLOAT4 reflectedLights[4]; // source position in receiver radii, irradiance at receiver center
    VFLOAT4 shadowOrigin,shadowAxisX,shadowAxisY; // camera-relative vessel, Sun-plane axes; origin.w enables the mask
};
struct CelestialUniforms { VFLOAT4 directionRadius,axisX,pole,axisZ,light,material,rings; VFLOAT4 reflectedLights[4]; };
struct EmitterUniforms { VFLOAT4 positionLevel,directionRadius,style,windPhase; };
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
static_assert(sizeof(FrameUniforms)==1888 && sizeof(CelestialUniforms)==176 && sizeof(EmitterUniforms)==64 && sizeof(TrailSegmentUniforms)==64 && sizeof(EffectUniforms)==32);
#endif

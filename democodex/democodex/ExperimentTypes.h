#ifndef ExperimentTypes_h
#define ExperimentTypes_h
#include <metal_stdlib>
using namespace metal;
struct ExperimentUniforms {
    float2 resolution, touch, gravity;
    float time, dt;
    uint count, side, steps, flags;
    float parameter, aspect;
    uint width, height;
};
struct GPUNode { float4 position; float4 velocity; };
inline uint experimentHash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; return x ^ (x >> 16); }
inline float random01(uint x) { return float(experimentHash(x) & 0x00ffffffu) / 16777216.0; }
inline float3 safeUnit(float3 v) { return v * rsqrt(max(dot(v,v), 1e-10f)); }
inline float2 safeUnit(float2 v) { return v * rsqrt(max(dot(v,v), 1e-10f)); }
struct ExperimentRaster { float4 position [[position]]; float2 uv; };
#endif

//
//  LiquidWaves.metal
//  demo
//
//  Deep water: three parallax wave layers (sum of sines), tilt and slosh from the CPU-side spring,
//  tap ripples travelling along the surface, foam, light shafts and caustics on the sea floor.
//
//  custom[0] = (surface slope, slosh speed, water level 0...1, unused)
//  blobs[i]  = ripple (x in pixels, start time, amplitude, unused)
//

#include "../../Effects/Core/ShaderCommon.h"

// Height of a wave layer above the bottom edge, in pixels.
static float liquidSurface(float x, constant EffectUniforms &u, float phase, float amplitude) {
    float unit = min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float slope = u.custom[0].x;
    float slosh = min(abs(u.custom[0].y), 2.0);
    float xn = x / unit;

    float h = 0.030 * sin(xn * 3.1 + t * 1.3 + phase)
            + 0.020 * sin(xn * 5.7 - t * 1.9 + phase * 1.3)
            + 0.012 * sin(xn * 11.3 + t * 2.7 + phase * 0.7)
            + 0.006 * sin(xn * 23.1 - t * 3.9 + phase * 2.1);
    h *= amplitude * (1.0 + slosh * 0.6);

    // Tap ripples: wave packets running away from the tap point and fading out.
    for (int i = 0; i < u.blobCount; i++) {
        float4 ripple = u.blobs[i];
        float age = t - ripple.y;
        float d = abs(x - ripple.x) / unit;
        float front = age * 0.8;
        float envelope = exp(-pow((d - front) * 5.0, 2.0)) * exp(-age * 0.9);
        h += ripple.z * 0.07 * envelope * cos((d - front) * 30.0);
    }

    float level = u.custom[0].z * u.resolution.y;
    return level + slope * (x - 0.5 * u.resolution.x) + h * unit;
}

// Bright network of light where two ridged noise layers cross.
static float caustics(float2 q, float t) {
    float a = 1.0 - abs(fbm(q * 5.0 + float2(t * 0.35, t * 0.2)) * 2.0 - 1.0);
    float b = 1.0 - abs(fbm(q * 5.7 + float2(-t * 0.3, t * 0.25) + 3.1) * 2.0 - 1.0);
    return pow(min(a, b), 8.0);
}

fragment float4 liquid_fragment(FullscreenVertexOut in [[stage_in]],
                                constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float y = u.resolution.y - px.y;
    float unit = min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float2 q = px / unit;

    // Night sky, then two translucent background wave layers for depth.
    float3 color = mix(float3(0.02, 0.03, 0.07), float3(0.06, 0.12, 0.20), in.uv.y);
    float back = liquidSurface(px.x, u, 2.3, 0.8) + 0.035 * unit;
    float middle = liquidSurface(px.x, u, 4.1, 0.9) + 0.017 * unit;
    color = mix(color, float3(0.05, 0.30, 0.45), smoothstep(-1.0, 1.0, back - y) * 0.6);
    color = mix(color, float3(0.06, 0.42, 0.58), smoothstep(-1.0, 1.0, middle - y) * 0.7);

    // Front layer: the water body.
    float front = liquidSurface(px.x, u, 0.0, 1.0);
    float d = front - y;
    float depth = saturate(d / (u.resolution.y * 0.6));
    float3 water = mix(float3(0.08, 0.70, 0.78), float3(0.01, 0.06, 0.22), sqrt(depth));

    // Light shafts slanting down from the surface.
    float shafts = pow(valueNoise(float2(q.x * 4.0 + q.y * 1.2 - t * 0.15, t * 0.1)), 3.0) * (1.0 - depth);
    water += float3(0.4, 0.8, 0.9) * shafts * 0.25;

    // Sandy floor lit by caustics; fainter caustics through the whole body.
    float floorHeight = u.resolution.y * 0.08 + valueNoise(float2(q.x * 3.0, 0.0)) * unit * 0.03;
    float onFloor = smoothstep(floorHeight + 1.0, floorHeight - 1.0, y);
    float3 sand = float3(0.22, 0.20, 0.16) * (0.8 + 0.2 * valueNoise(px * 0.2));
    water = mix(water, sand * 0.6, onFloor * 0.8);
    water += float3(0.55, 0.95, 1.0) * caustics(q, t) * (0.15 + 0.6 * onFloor) * (1.0 - depth * 0.6);

    float inWater = smoothstep(-1.0, 1.0, d);
    color = mix(color, water, inWater);

    // Foam on the crest, thicker while the water sloshes.
    float slosh = saturate(abs(u.custom[0].y) * 0.8);
    float foamNoise = fbm(float2(px.x / unit * 9.0 - t * 0.8, t * 0.5));
    float foamWidth = unit * (0.012 + 0.03 * foamNoise) * (1.0 + slosh * 1.5);
    float foam = (1.0 - smoothstep(0.0, foamWidth, d)) * (0.55 + 0.45 * foamNoise);
    float speck = step(0.72 - slosh * 0.1, valueNoise(px / unit * 40.0 + float2(-t * 2.0, 0.0)))
                * (1.0 - smoothstep(0.0, foamWidth * 2.5, d));
    color = mix(color, float3(0.92, 0.98, 1.0), saturate(foam * 0.85 + speck * 0.6) * inWater);

    return float4(color, 1.0);
}

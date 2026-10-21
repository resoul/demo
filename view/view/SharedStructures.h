#ifndef MATTER_SHARED_STRUCTURES_H
#define MATTER_SHARED_STRUCTURES_H

// This header is imported by both Swift (bridging header) and the Metal compiler.
// SIMD fields deliberately avoid Swift/Clang float3 padding disagreements.
#ifdef __METAL_VERSION__
#include <metal_stdlib>
typedef metal::float4 MEFloat4;
typedef metal::uint4 MEUInt4;
typedef metal::float4x4 MEMatrix4x4;
typedef unsigned int MEUInt;
#else
#include <simd/simd.h>
#include <stdint.h>
typedef simd_float4 MEFloat4;
typedef simd_uint4 MEUInt4;
typedef simd_float4x4 MEMatrix4x4;
typedef uint32_t MEUInt;
#endif

typedef struct {
    MEMatrix4x4 projection;
    MEMatrix4x4 view;
    MEFloat4 viewport; // drawable width, height, elapsed time, bloom strength
    MEFloat4 domain;   // visible minX, maxX, minY, maxY
    MEUInt4 counts;    // input points, hierarchy leaf count, LOD vertices, reserved
} ChartUniforms;

typedef struct {
    MEUInt minimumIndex;
    MEUInt maximumIndex;
} ChartRangeNode;

typedef struct {
    MEUInt4 range; // start inclusive, end exclusive, hierarchy leaf count, input count
} ChartReductionUniforms;

typedef struct {
    MEFloat4 state;    // progress, effect (0 noise / 1 ripple / 2 glitch / 3 fade), touch x/y
    MEFloat4 viewport; // drawable width, height, time, reverse direction
} TransitionUniforms;

typedef struct {
    MEFloat4 viewport;   // drawable width, height, time, speed
    MEUInt4 atlas;      // atlas columns, rows, glyph count, visible columns
    MEFloat4 appearance; // cell width, height, tail length, intensity
} RainUniforms;

#endif

#include <metal_stdlib>
#include "SharedStructures.h"
using namespace metal;

constant uint invalidChartIndex = 0xffffffffu;

// A binary min/max hierarchy is constructed once, then only dirty ancestors are
// updated for appended samples. It retains indices (and therefore chronological order).
ChartRangeNode mergeChartNodes(ChartRangeNode a, ChartRangeNode b,
                              device const float2 *points) {
    if (a.minimumIndex == invalidChartIndex) return b;
    if (b.minimumIndex == invalidChartIndex) return a;
    uint lo = points[a.minimumIndex].y <= points[b.minimumIndex].y ? a.minimumIndex : b.minimumIndex;
    uint hi = points[a.maximumIndex].y >= points[b.maximumIndex].y ? a.maximumIndex : b.maximumIndex;
    return {lo, hi};
}

kernel void chartWriteLeaves(device ChartRangeNode *nodes [[buffer(0)]],
                             constant ChartReductionUniforms &u [[buffer(1)]],
                             uint id [[thread_position_in_grid]]) {
    uint index = u.range.x + id;
    if (index >= u.range.y) return;
    uint sample = index < u.range.w ? index : invalidChartIndex;
    nodes[u.range.z + index] = {sample, sample};
}

kernel void chartReduceLevel(device const float2 *points [[buffer(0)]],
                              device ChartRangeNode *nodes [[buffer(1)]],
                              constant ChartReductionUniforms &u [[buffer(2)]],
                              uint id [[thread_position_in_grid]]) {
    uint index = u.range.x + id;
    if (index >= u.range.y) return;
    nodes[index] = mergeChartNodes(nodes[index * 2], nodes[index * 2 + 1], points);
}

uint chartLowerBound(device const float2 *points, uint count, float x, bool upper) {
    uint lo = 0, hi = count;
    while (lo < hi) {
        uint mid = lo + (hi - lo) / 2;
        if (points[mid].x < x || (upper && points[mid].x == x)) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

// One thread per physical pixel column. Binary search + hierarchy range queries
// cost O(log N) per column, not O(N) every frame. Both extrema survive downsampling.
// A vertex shader cannot compact/aggregate arbitrary input invocations by itself.
kernel void chartPixelLOD(device const float2 *points [[buffer(0)]],
                           device const ChartRangeNode *nodes [[buffer(1)]],
                           device float2 *lod [[buffer(2)]],
                           constant ChartUniforms &u [[buffer(3)]],
                           uint column [[thread_position_in_grid]]) {
    uint columns = u.counts.z / 2;
    if (column >= columns || u.counts.x < 2) return;
    float dx = (u.domain.y - u.domain.x) / float(columns);
    uint start = chartLowerBound(points, u.counts.x, u.domain.x + float(column) * dx, false);
    uint end = chartLowerBound(points, u.counts.x, u.domain.x + float(column + 1) * dx, true);
    // Include the boundary segments so clipping cannot cut off a crossing line.
    if (column == 0 && start > 0) start--;
    if (column + 1 == columns && end < u.counts.x) end++;
    if (start >= end) {
        uint index = min(start, u.counts.x - 1);
        lod[column * 2] = points[index];
        lod[column * 2 + 1] = points[index];
        return;
    }
    uint l = start + u.counts.y, r = end + u.counts.y;
    ChartRangeNode result = {invalidChartIndex, invalidChartIndex};
    while (l < r) {
        if (l & 1) result = mergeChartNodes(result, nodes[l++], points);
        if (r & 1) result = mergeChartNodes(result, nodes[--r], points);
        l >>= 1; r >>= 1;
    }
    uint first = min(result.minimumIndex, result.maximumIndex);
    uint last = max(result.minimumIndex, result.maximumIndex);
    lod[column * 2] = points[first];
    lod[column * 2 + 1] = points[last];
}

struct ChartVarying { float4 position [[position]]; float height; };
vertex ChartVarying chartLineVertex(uint id [[vertex_id]], device const float2 *lod [[buffer(0)]],
                                    constant ChartUniforms &u [[buffer(1)]]) {
    float2 point = lod[min(id, u.counts.z - 1)];
    // Subtract the visible origin before multiplying, avoiding large-coordinate
    // cancellation when zoomed far into a long Float32 time series.
    float4 normalized = u.view * float4(point - u.domain.xz, 0, 1);
    // Metal's homogeneous clip volume performs viewport/bounding-box clipping.
    // There is no misleading Early-Z claim: this is a 2D line pass without depth.
    return {u.projection * normalized, normalized.y};
}
vertex ChartVarying chartFillVertex(uint id [[vertex_id]], device const float2 *lod [[buffer(0)]],
                                    constant ChartUniforms &u [[buffer(1)]]) {
    float2 point = lod[min(id / 2, u.counts.z - 1)];
    if (id & 1) point.y = u.domain.z;
    float4 normalized = u.view * float4(point - u.domain.xz, 0, 1);
    return {u.projection * normalized, normalized.y};
}
fragment float4 chartLineFragment(ChartVarying v [[stage_in]]) {
    return float4(0.24, 1.5, 1.15, 1); // HDR energy for the bloom pass
}
fragment float4 chartFillFragment(ChartVarying v [[stage_in]]) {
    return float4(float3(0.025, 0.13, 0.12) * saturate(v.height), 1);
}

struct EngineQuad { float4 position [[position]]; float2 uv; };
vertex EngineQuad engineFullscreenVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p};
}

// Separable, normalized 9-tap Gaussian: horizontal into half-resolution ping,
// then vertical into pong. No CPU readback in the render loop.
float4 gaussianSample(texture2d<float, access::sample> source, float2 uv, float2 stepUV) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    constexpr float w[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};
    float4 sum = source.sample(s, uv) * w[0];
    for (int i = 1; i < 5; i++) {
        sum += (source.sample(s, uv + stepUV * float(i)) +
                source.sample(s, uv - stepUV * float(i))) * w[i];
    }
    return sum;
}
kernel void bloomHorizontal(texture2d<float, access::sample> source [[texture(0)]],
                            texture2d<float, access::write> target [[texture(1)]],
                            uint2 id [[thread_position_in_grid]]) {
    if (id.x >= target.get_width() || id.y >= target.get_height()) return;
    float2 size = float2(target.get_width(), target.get_height());
    target.write(gaussianSample(source, (float2(id) + 0.5) / size, float2(1.0 / size.x, 0)), id);
}
kernel void bloomVertical(texture2d<float, access::sample> source [[texture(0)]],
                          texture2d<float, access::write> target [[texture(1)]],
                          uint2 id [[thread_position_in_grid]]) {
    if (id.x >= target.get_width() || id.y >= target.get_height()) return;
    float2 size = float2(target.get_width(), target.get_height());
    target.write(gaussianSample(source, (float2(id) + 0.5) / size, float2(0, 1.0 / size.y)), id);
}
fragment float4 chartComposite(EngineQuad v [[stage_in]], texture2d<float> scene [[texture(0)]],
                               texture2d<float> bloom [[texture(1)]], constant ChartUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 cell = abs(fract(v.uv * float2(6, 4) + 0.5) - 0.5);
    float2 pixel = float2(6, 4) / u.viewport.xy;
    float grid = 1.0 - min(smoothstep(pixel.x * 0.5, pixel.x * 1.5, cell.x),
                           smoothstep(pixel.y * 0.5, pixel.y * 1.5, cell.y));
    float3 color = float3(0.025, 0.042, 0.052) + grid * float3(0.025, 0.040, 0.043);
    color += scene.sample(s, v.uv).rgb + bloom.sample(s, v.uv).rgb * u.viewport.w;
    return float4(1.0 - exp(-color), 1);
}

// Gradient Perlin noise: dot products with lattice gradients, quintic interpolation.
float engineHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float2 perlinGradient(float2 p) {
    uint h = uint(int(p.x)) * 0x8da6b343u ^ uint(int(p.y)) * 0xd8163841u;
    h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15;
    constexpr float2 gradients[8] = {float2(1, 0), float2(-1, 0), float2(0, 1), float2(0, -1),
        float2(0.707107, 0.707107), float2(-0.707107, 0.707107),
        float2(0.707107, -0.707107), float2(-0.707107, -0.707107)};
    return gradients[h & 7]; // no per-pixel trigonometric gradient construction
}
float perlinNoise(float2 p) {
    float2 i = floor(p), f = fract(p), w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(dot(perlinGradient(i), f), dot(perlinGradient(i + float2(1, 0)), f - float2(1, 0)), w.x),
               mix(dot(perlinGradient(i + float2(0, 1)), f - float2(0, 1)), dot(perlinGradient(i + 1.0), f - 1.0), w.x), w.y);
}
fragment float4 screenTransition(EngineQuad v [[stage_in]], texture2d<float> from [[texture(0)]],
                                 texture2d<float> to [[texture(1)]], constant TransitionUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float progress = clamp(u.state.x, 0.0, 1.0);
    // Exact endpoints, including the absence of residual glow/distortion.
    if (progress <= 0) return from.sample(s, v.uv);
    if (progress >= 1) return to.sample(s, v.uv);
    float phase = sin(progress * 3.141593);
    uint style = uint(u.state.y);
    if (style == 0) {
        float2 p = v.uv * float2(u.viewport.x / u.viewport.y, 1) * 7.0;
        float n = 0.5 + perlinNoise(p) * 0.55 + perlinNoise(p * 2.0) * 0.20;
        float threshold = mix(-0.25, 1.25, u.viewport.w > 0.5 ? 1.0 - progress : progress);
        float mask = smoothstep(threshold - 0.025, threshold + 0.025, n);
        if (u.viewport.w > 0.5) mask = 1.0 - mask;
        float edge = exp(-abs(n - threshold) * 80.0) * phase;
        return float4(mix(to.sample(s, v.uv).rgb, from.sample(s, v.uv).rgb, mask) + float3(0.3, 1, 0.72) * edge, 1);
    }
    if (style == 1) {
        float2 aspect = float2(u.viewport.x / u.viewport.y, 1);
        float2 dp = (v.uv - u.state.zw) * aspect;
        float d = length(dp);
        float wave = sin(d * 48.0 - progress * 22.0) * exp(-d * 2.0) * phase * 0.035;
        float2 offset = dp / max(d, 0.001) / aspect * wave;
        return mix(from.sample(s, v.uv + offset), to.sample(s, v.uv - offset * 0.3), smoothstep(0.2, 0.9, progress));
    }
    if (style == 2) {
        float tick = floor(u.viewport.z * 24.0);
        float row = floor(v.uv.y * 35.0);
        float block = (engineHash(float2(row, tick)) - 0.5) * step(0.65, engineHash(float2(row, tick + 9))) * 0.18 * phase;
        float2 q = v.uv + float2(block, 0);
        float split = (0.004 + abs(block) * 0.2) * phase;
        float mixValue = smoothstep(0.15, 0.85, progress);
        float r = mix(from.sample(s, q + float2(split, 0)).r, to.sample(s, q + float2(split, 0)).r, mixValue);
        float g = mix(from.sample(s, q).g, to.sample(s, q).g, mixValue);
        float b = mix(from.sample(s, q - float2(split, 0)).b, to.sample(s, q - float2(split, 0)).b, mixValue);
        return float4(float3(r, g, b) * (1.0 - phase * 0.08 * sin(v.uv.y * u.viewport.y)), 1);
    }
    return mix(from.sample(s, v.uv), to.sample(s, v.uv), progress);
}

struct RainVarying {
    float4 position [[position]];
    float2 uv;
    float brightness;
    float head;
};
// Each instance is a glyph quad; the CPU submits exactly one instanced draw.
vertex RainVarying matrixRainVertex(uint vertexIndex [[vertex_id]], uint instance [[instance_id]],
                                     constant RainUniforms &u [[buffer(0)]]) {
    constexpr float2 corners[6] = {float2(0, 0), float2(1, 0), float2(0, 1),
                                   float2(1, 0), float2(1, 1), float2(0, 1)};
    uint column = instance % u.atlas.w, row = instance / u.atlas.w;
    float rows = ceil(u.viewport.y / u.appearance.y);
    float seed = engineHash(float2(column, 17));
    float headRow = fmod(u.viewport.z * u.viewport.w * (0.7 + seed) + seed * (rows + u.appearance.z), rows + u.appearance.z);
    float distance = headRow - float(row);
    float brightness = step(0.0, distance) * (1.0 - smoothstep(0.0, u.appearance.z, distance));
    float head = (1.0 - smoothstep(0.0, 1.5, abs(distance))) * step(0.0, distance);
    float glyph = floor(engineHash(float2(float(instance), floor(u.viewport.z * 8.0 + seed * 6))) * float(u.atlas.z));
    float2 atlasCell = float2(fmod(glyph, float(u.atlas.x)), floor(glyph / float(u.atlas.x)));
    float2 corner = corners[vertexIndex];
    float2 pixel = (float2(column, row) + corner) * u.appearance.xy;
    return {float4(pixel / u.viewport.xy * float2(2, -2) + float2(-1, 1), 0, 1),
            (atlasCell + corner) / float2(u.atlas.xy), brightness * u.appearance.w, head};
}
fragment float4 matrixRainFragment(RainVarying v [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float ink = atlas.sample(s, v.uv).a;
    float2 texel = 1.0 / float2(atlas.get_width(), atlas.get_height());
    float glow = (atlas.sample(s, v.uv + float2(texel.x, 0)).a + atlas.sample(s, v.uv - float2(texel.x, 0)).a +
                  atlas.sample(s, v.uv + float2(0, texel.y)).a + atlas.sample(s, v.uv - float2(0, texel.y)).a) * 0.12;
    float3 color = mix(float3(0.08, 0.9, 0.34), float3(0.85, 1, 0.91), v.head);
    return float4(color * (ink + glow) * v.brightness, 1);
}

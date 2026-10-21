//
//  ReactionDiffusion.metal
//  demo
//
//  Gray–Scott reaction–diffusion: two chemicals U and V on a grid. Every step each cell reads its
//  3×3 neighbourhood, diffuses both chemicals and reacts U + 2V → 3V. Many steps run per frame,
//  ping-ponging between two rg16Float textures.
//

#include "../../Effects/Core/ShaderCommon.h"

// Mirrored by `ReactionParams` in ReactionDiffusionView.swift (32 bytes).
struct ReactionParams {
    float feed;
    float kill;
    float2 brushCenter;     // cells
    float brushRadius;      // cells
    float brushStrength;    // 0 when not touching
    uint seed;
    float padding;
};

static float2 cellAt(texture2d<float, access::read> grid, int2 position, int2 size) {
    return grid.read(uint2((position + size) % size)).xy;
}

kernel void reaction_seed(texture2d<float, access::write> grid [[texture(0)]],
                          constant ReactionParams &p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= grid.get_width() || gid.y >= grid.get_height()) return;
    // Sparse random blocks of V in a sea of U.
    float h = hash21(float2(gid / 10u) + float(p.seed % 1000u) * 0.37);
    float v = h > 0.985 ? 1.0 : 0.0;
    grid.write(float4(1.0 - 0.5 * v, v, 0.0, 0.0), gid);
}

kernel void reaction_step(texture2d<float, access::read> current [[texture(0)]],
                          texture2d<float, access::write> next [[texture(1)]],
                          constant ReactionParams &p [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(current.get_width(), current.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);

    float2 center = cellAt(current, c, size);
    float2 edges = cellAt(current, c + int2(1, 0), size) + cellAt(current, c + int2(-1, 0), size)
                 + cellAt(current, c + int2(0, 1), size) + cellAt(current, c + int2(0, -1), size);
    float2 corners = cellAt(current, c + int2(1, 1), size) + cellAt(current, c + int2(-1, 1), size)
                   + cellAt(current, c + int2(1, -1), size) + cellAt(current, c + int2(-1, -1), size);
    float2 laplacian = 0.2 * edges + 0.05 * corners - center;

    float u = center.x;
    float v = center.y;
    float reaction = u * v * v;
    u += 1.0 * laplacian.x - reaction + p.feed * (1.0 - u);
    v += 0.5 * laplacian.y + reaction - (p.feed + p.kill) * v;

    // The finger paints V.
    if (p.brushStrength > 0.0 && distance(float2(gid), p.brushCenter) < p.brushRadius) {
        v = max(v, 0.9 * p.brushStrength);
    }
    next.write(float4(saturate(u), saturate(v), 0.0, 0.0), gid);
}

fragment float4 reaction_fragment(FullscreenVertexOut in [[stage_in]],
                                  texture2d<float> grid [[texture(0)]]) {
    constexpr sampler linear(filter::linear, address::repeat);
    float2 texel = 1.0 / float2(grid.get_width(), grid.get_height());
    float v = grid.sample(linear, in.uv).y;

    // Embossed lighting from the V gradient.
    float vx = grid.sample(linear, in.uv + float2(texel.x, 0.0)).y - grid.sample(linear, in.uv - float2(texel.x, 0.0)).y;
    float vy = grid.sample(linear, in.uv + float2(0.0, texel.y)).y - grid.sample(linear, in.uv - float2(0.0, texel.y)).y;
    float3 normal = normalize(float3(-vx * 6.0, -vy * 6.0, 1.0));
    float light = saturate(dot(normal, normalize(float3(-0.4, -0.5, 0.75))));

    float3 color = mix(float3(0.02, 0.03, 0.08), float3(0.05, 0.50, 0.62), smoothstep(0.08, 0.25, v));
    color = mix(color, float3(0.95, 0.82, 0.52), smoothstep(0.25, 0.45, v));
    color *= 0.55 + 0.6 * light;
    color += pow(light, 24.0) * 0.25 * smoothstep(0.1, 0.3, v);
    return float4(color, 1.0);
}

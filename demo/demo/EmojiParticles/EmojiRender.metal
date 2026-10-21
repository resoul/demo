//
//  EmojiRender.metal
//  demo
//
//  Instanced emoji quads: one triangle strip of 4 vertices, one instance per particle, all in a
//  single draw call. The vertex shader rotates and scales the quad and picks the atlas cell.
//

#include "EmojiShared.h"

struct EmojiVertexOut {
    float4 position [[position]];
    float2 uv;
    float alpha;
};

vertex EmojiVertexOut emoji_vertex(const device EmojiParticle *particles [[buffer(0)]],
                                   constant EmojiUniforms &u [[buffer(1)]],
                                   uint vid [[vertex_id]],
                                   uint iid [[instance_id]]) {
    EmojiParticle p = particles[iid];
    float2 corner = float2(vid & 1, vid >> 1);          // (0,0) (1,0) (0,1) (1,1)

    // Pop in right after spawning, fade out at the end of life; unspawned particles collapse to 0.
    float spawned = p.lifetime > 0.0 ? 1.0 : 0.0;
    float age = p.lifetime - p.life;
    float size = p.size * smoothstep(0.0, 0.12, age) * spawned;

    float2 local = (corner - 0.5) * size;
    float c = cos(p.angle), s = sin(p.angle);
    local = float2(local.x * c - local.y * s, local.x * s + local.y * c);
    float2 clip = (p.position + local) / u.resolution * 2.0 - 1.0;

    EmojiVertexOut out;
    out.position = float4(clip.x, -clip.y, 0.0, 1.0);
    out.uv = float2((float(p.emoji) + corner.x) / float(u.atlasColumns), corner.y);
    out.alpha = smoothstep(0.0, 0.5, p.life) * spawned;
    return out;
}

fragment float4 emoji_fragment(EmojiVertexOut in [[stage_in]],
                               texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler linearMips(filter::linear, mip_filter::linear, address::clamp_to_edge);
    // The atlas holds premultiplied alpha, so scaling all four channels fades correctly.
    return atlas.sample(linearMips, in.uv) * in.alpha;
}

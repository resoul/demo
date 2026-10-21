#include "EmojiParticleTypes.h"

struct EmojiVertexOut {
    float4 position [[position]];
    float2 uv;
    float opacity;
};

vertex EmojiVertexOut emojiVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                   const device EmojiParticleState *particles [[buffer(0)]],
                                   constant EmojiRenderUniforms &u [[buffer(1)]]) {
    const float2 corners[] = {float2(-0.5,-0.5), float2(0.5,-0.5), float2(-0.5,0.5),
                              float2(-0.5,0.5), float2(0.5,-0.5), float2(0.5,0.5)};
    EmojiParticleState p = particles[instanceID];
    float2 local = corners[vertexID];
    float c = cos(p.angle), s = sin(p.angle);
    float2 rotated = float2(local.x * c - local.y * s, local.x * s + local.y * c);
    float2 position = p.position + rotated * u.spriteSize * p.size / max(u.resolution, float2(1));
    EmojiVertexOut out;
    out.position = float4(position.x * 2 - 1, 1 - position.y * 2, 0, 1);
    out.uv = float2((local.x + 0.5 + float(p.emojiIndex)) / float(max(u.atlasCount, 1u)), local.y + 0.5);
    out.opacity = smoothstep(0.0, 0.08, p.age) * smoothstep(0.0, 0.25, p.lifetime - p.age);
    return out;
}

fragment float4 emojiFragment(EmojiVertexOut in [[stage_in]], texture2d<float> atlas [[texture(0)]],
                               sampler sampling [[sampler(0)]]) {
    float4 color = atlas.sample(sampling, in.uv) * in.opacity;
    if (color.a < 0.005) discard_fragment();
    return color; // UIGraphics glyphs are premultiplied; blend uses One / OneMinusSrcAlpha.
}

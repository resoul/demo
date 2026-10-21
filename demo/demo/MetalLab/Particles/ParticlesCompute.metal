//
//  ParticlesCompute.metal
//  demo
//
//  Particle swarm: a compute kernel integrates up to a million particles per frame (ambient flow
//  field plus finger attraction / release burst), then every particle is drawn as an additive point.
//

#include "../../Effects/Core/ShaderCommon.h"

struct Particle {
    float2 position;    // pixels
    float2 velocity;    // pixels per second
};

// Mirrored by `ParticleUniforms` in MetalParticlesView.swift (32 bytes).
struct ParticleUniforms {
    float2 resolution;
    float2 touch;
    float touchStrength;    // > 0 attracts, < 0 pushes away
    float time;
    float deltaTime;
    uint count;
};

static float2 particleSeed(uint id) {
    return hash22(float2(id % 1024, id / 1024) + 0.5);
}

kernel void particles_init(device Particle *particles [[buffer(0)]],
                           constant ParticleUniforms &u [[buffer(1)]],
                           uint id [[thread_position_in_grid]]) {
    if (id >= u.count) return;
    particles[id].position = particleSeed(id) * u.resolution;
    particles[id].velocity = float2(0.0);
}

kernel void particles_update(device Particle *particles [[buffer(0)]],
                             constant ParticleUniforms &u [[buffer(1)]],
                             uint id [[thread_position_in_grid]]) {
    if (id >= u.count) return;
    Particle p = particles[id];
    float unit = min(u.resolution.x, u.resolution.y);
    float dt = u.deltaTime;
    float mass = 0.6 + 0.8 * particleSeed(id).x;

    // Ambient flow field: slow swirls so the swarm never settles.
    float2 q = p.position / unit * 3.0;
    float t = u.time;
    float2 flow = float2(sin(q.y * 1.7 + t * 0.6) + 0.5 * sin(q.y * 0.6 - t * 0.4),
                         cos(q.x * 1.3 - t * 0.5) + 0.5 * cos(q.x * 0.7 + t * 0.3));
    float2 force = flow * unit * 0.25;

    // Finger: holding pulls particles into an orbiting cloud; releasing blasts them outwards.
    float2 toTouch = u.touch - p.position;
    float dist = length(toTouch) + unit * 0.02;
    float2 dir = toTouch / dist;
    float falloff = unit / (dist + unit * 0.15);
    if (u.touchStrength > 0.0) {
        force += (dir + float2(-dir.y, dir.x) * 0.6) * u.touchStrength * unit * 4.0 * falloff;
    } else {
        force += dir * u.touchStrength * unit * 12.0 * falloff * falloff;
    }

    p.velocity += force / mass * dt;
    p.velocity *= exp(-dt * 1.5);
    p.position += p.velocity * dt;
    // Wrap around the edges.
    p.position = fmod(p.position + u.resolution, u.resolution);
    particles[id] = p;
}

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
};

vertex ParticleVertexOut particles_vertex(const device Particle *particles [[buffer(0)]],
                                          constant ParticleUniforms &u [[buffer(1)]],
                                          uint vid [[vertex_id]]) {
    Particle p = particles[vid];
    float2 clip = p.position / u.resolution * 2.0 - 1.0;

    // Color by speed: blue at rest, cyan when moving, pink when flung.
    float speed = saturate(length(p.velocity) / min(u.resolution.x, u.resolution.y) * 1.5);
    float3 color = mix(float3(0.15, 0.35, 1.0), float3(0.2, 1.0, 0.95), smoothstep(0.0, 0.5, speed));
    color = mix(color, float3(1.0, 0.45, 0.85), smoothstep(0.5, 1.0, speed));
    // Keep the total brightness similar from 10k to 1M additive points.
    float brightness = clamp(60000.0 / float(u.count), 0.08, 1.0);

    ParticleVertexOut out;
    out.position = float4(clip.x, -clip.y, 0.0, 1.0);
    out.pointSize = u.count > 200000 ? 1.0 : 2.0;
    out.color = color * brightness;
    return out;
}

fragment float4 particles_fragment(ParticleVertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}

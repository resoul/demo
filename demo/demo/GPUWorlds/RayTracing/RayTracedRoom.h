//
//  RayTracedRoom.h
//  demo
//
//  Scene description and shading shared by the two ray tracers of the room. The including file
//  first defines how rays meet the scene:
//    ROOM_SCENE_ARGS / ROOM_SCENE_PASS  extra parameters for the scene
//    roomIntersect(origin, direction, ROOM_SCENE_PASS) -> Hit
//    roomOccluded(origin, direction, maxDistance, ROOM_SCENE_PASS) -> bool
//  and then includes this file again with ROOM_TRACE defined to get `traceRoom`.
//

#ifndef ROOM_COMMON_INCLUDED
#define ROOM_COMMON_INCLUDED

#include <metal_stdlib>
using namespace metal;

// Mirrored by `RoomParams` in RayTracedRoomView.swift (176 bytes).
struct RoomParams {
    float4x4 inverseViewProjection;
    float4 cameraPosition;
    float4 light;           // xyz centre, w radius
    float4 spheres[3];      // glass, mirror, gold: xyz centre, w radius
    uint2 size;             // output pixels
    uint shadowSamples;
    uint maxBounces;
    float time;
    float padding0;
    float padding1;
    float padding2;
};

// Per-triangle data for the hardware path (32 bytes).
struct RoomPrimitive {
    float4 normal;          // flat normal for walls
    uint4 info;             // x material, y sphere index (3 = none)
};

enum RoomMaterial : uint {
    RoomWhite = 0,
    RoomRed = 1,
    RoomGreen = 2,
    RoomFloor = 3,
    RoomGlass = 4,
    RoomMirror = 5,
    RoomGold = 6,
};

struct Hit {
    float t;
    float3 normal;
    uint material;
};

constant float kNoHit = 1e9;
constant float3 kRoomMin = float3(-2.0, 0.0, -2.5);
constant float3 kRoomMax = float3(2.0, 3.0, 4.0);      // the front (z = 4) is open
constant float3 kLightColor = float3(6.0, 5.6, 5.0);
constant float kLightPower = 14.0;

static uint sphereMaterial(uint index) {
    return index == 0 ? RoomGlass : (index == 1 ? RoomMirror : RoomGold);
}

static float intersectSphere(float3 origin, float3 direction, float4 sphere) {
    float3 oc = origin - sphere.xyz;
    float b = dot(oc, direction);
    float c = dot(oc, oc) - sphere.w * sphere.w;
    float h = b * b - c;
    if (h < 0.0) return kNoHit;
    h = sqrt(h);
    float t = -b - h;
    if (t > 1e-3) return t;
    t = -b + h;
    return t > 1e-3 ? t : kNoHit;
}

static inline void testWall(thread Hit &hit, float3 origin, float3 direction, float3 normal, float offset, uint material) {
    float denominator = dot(normal, direction);
    if (denominator >= 0.0) return;
    float t = (offset - dot(normal, origin)) / denominator;
    if (t <= 1e-3 || t >= hit.t) return;
    float3 x = origin + direction * t;
    if (any(x < kRoomMin - 1e-3) || any(x > kRoomMax + 1e-3)) return;
    hit.t = t;
    hit.normal = normal;
    hit.material = material;
}

// Exact intersection with the five walls and the three spheres.
static inline Hit analyticIntersect(float3 origin, float3 direction, constant RoomParams &p) {
    Hit hit;
    hit.t = kNoHit;
    hit.normal = float3(0.0);
    hit.material = RoomWhite;
    testWall(hit, origin, direction, float3(0, 1, 0), kRoomMin.y, RoomFloor);
    testWall(hit, origin, direction, float3(0, -1, 0), -kRoomMax.y, RoomWhite);
    testWall(hit, origin, direction, float3(0, 0, 1), kRoomMin.z, RoomWhite);
    testWall(hit, origin, direction, float3(1, 0, 0), kRoomMin.x, RoomRed);
    testWall(hit, origin, direction, float3(-1, 0, 0), -kRoomMax.x, RoomGreen);
    for (uint i = 0; i < 3; i++) {
        float t = intersectSphere(origin, direction, p.spheres[i]);
        if (t < hit.t) {
            hit.t = t;
            hit.normal = normalize(origin + direction * t - p.spheres[i].xyz);
            hit.material = sphereMaterial(i);
        }
    }
    return hit;
}

static uint roomHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static float roomRandom(thread uint &state) {
    state = roomHash(state);
    return float(state) * (1.0 / 4294967296.0);
}

static float3 albedoOf(uint material, float3 x) {
    switch (material) {
        case RoomRed: return float3(0.72, 0.12, 0.10);
        case RoomGreen: return float3(0.12, 0.55, 0.20);
        case RoomFloor: {
            float2 tile = floor(x.xz * 2.0);
            return mix(float3(0.75), float3(0.18), fmod(abs(tile.x + tile.y), 2.0));
        }
        default: return float3(0.78);
    }
}

#endif  // ROOM_COMMON_INCLUDED

#if defined(ROOM_TRACE) && !defined(ROOM_TRACE_INCLUDED)
#define ROOM_TRACE_INCLUDED

// Follows one camera ray through mirrors and glass; diffuse surfaces get soft-shadowed direct
// light from the spherical lamp. `rays` counts every ray cast, shadow rays included.
static float3 traceRoom(float3 origin, float3 direction, uint2 pixel, thread uint &rays, ROOM_SCENE_ARGS) {
    float3 color = float3(0.0);
    float3 throughput = float3(1.0);
    uint seed = roomHash(pixel.x * 1973u + pixel.y * 9277u + 26699u);

    for (uint bounce = 0; bounce < p.maxBounces; bounce++) {
        rays++;
        Hit hit = roomIntersect(origin, direction, ROOM_SCENE_PASS);
        float lightT = intersectSphere(origin, direction, p.light);
        if (lightT < hit.t) {
            color += throughput * kLightColor;
            break;
        }
        if (hit.t >= kNoHit) break;     // out through the open front

        float3 x = origin + direction * hit.t;
        float3 n = hit.normal;

        if (hit.material <= RoomFloor) {
            float3 albedo = albedoOf(hit.material, x);
            float3 direct = float3(0.0);
            for (uint s = 0; s < p.shadowSamples; s++) {
                // A random point on the lamp's sphere gives soft shadow edges.
                float u = roomRandom(seed) * 2.0 - 1.0;
                float phi = roomRandom(seed) * 2.0 * M_PI_F;
                float3 onSphere = float3(sqrt(1.0 - u * u) * cos(phi), u, sqrt(1.0 - u * u) * sin(phi));
                float3 toLight = p.light.xyz + onSphere * p.light.w * 0.9 - x;
                float distance = length(toLight);
                toLight /= distance;
                float facing = dot(n, toLight);
                if (facing <= 0.0) continue;
                rays++;
                if (!roomOccluded(x + n * 1e-3, toLight, distance - p.light.w, ROOM_SCENE_PASS)) {
                    direct += facing / (distance * distance);
                }
            }
            direct *= kLightPower / float(max(p.shadowSamples, 1u));
            color += throughput * albedo * (direct * float3(1.0, 0.95, 0.85) + 0.05);
            // The floor is slightly glossy: keep following a faint reflection.
            if (hit.material != RoomFloor) break;
            throughput *= 0.18;
            origin = x + n * 1e-3;
            direction = reflect(direction, n);
        } else if (hit.material == RoomMirror || hit.material == RoomGold) {
            throughput *= hit.material == RoomGold ? float3(1.0, 0.78, 0.35) : float3(0.92);
            origin = x + n * 1e-3;
            direction = reflect(direction, n);
        } else {
            // Glass: Fresnel-weighted refraction plus the lamp's specular reflection.
            bool entering = dot(direction, n) < 0.0;
            float3 facingNormal = entering ? n : -n;
            float eta = entering ? 1.0 / 1.5 : 1.5;
            float cosine = -dot(direction, facingNormal);
            float fresnel = 0.04 + 0.96 * pow(1.0 - cosine, 5.0);
            float3 refracted = refract(direction, facingNormal, eta);
            if (dot(refracted, refracted) < 1e-6) {
                origin = x + facingNormal * 1e-3;
                direction = reflect(direction, facingNormal);
                continue;
            }
            float3 toLight = normalize(p.light.xyz - x);
            float highlight = pow(saturate(dot(reflect(direction, facingNormal), toLight)), 200.0);
            color += throughput * fresnel * highlight * kLightColor * 0.5;
            throughput *= (1.0 - fresnel) * float3(0.97, 0.99, 1.0);
            origin = x - facingNormal * 1e-3;
            direction = refracted;
        }
    }
    return color;
}

static float3 cameraRay(uint2 gid, constant RoomParams &p) {
    float2 ndc = (float2(gid) + 0.5) / float2(p.size) * 2.0 - 1.0;
    float4 world = p.inverseViewProjection * float4(ndc.x, -ndc.y, 1.0, 1.0);
    return normalize(world.xyz / world.w - p.cameraPosition.xyz);
}

static void countRays(uint rays, device atomic_uint *counter) {
    uint total = simd_sum(rays);
    if (simd_is_first()) {
        atomic_fetch_add_explicit(counter, total, memory_order_relaxed);
    }
}

#endif  // ROOM_TRACE

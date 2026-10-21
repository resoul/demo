//
//  RayTracedRoomAnalytic.metal
//  demo
//
//  Room ray tracer without ray-tracing hardware: rays are intersected with the exact walls and
//  spheres in shader code. Used when the device does not support Metal ray tracing.
//

#include "../../Effects/Core/ShaderCommon.h"
#include "RayTracedRoom.h"

#define ROOM_SCENE_ARGS constant RoomParams &p
#define ROOM_SCENE_PASS p

static Hit roomIntersect(float3 origin, float3 direction, ROOM_SCENE_ARGS) {
    return analyticIntersect(origin, direction, p);
}

static bool roomOccluded(float3 origin, float3 direction, float maxDistance, ROOM_SCENE_ARGS) {
    return analyticIntersect(origin, direction, p).t < maxDistance;
}

#define ROOM_TRACE
#include "RayTracedRoom.h"

kernel void room_trace_analytic(texture2d<float, access::write> output [[texture(0)]],
                                constant RoomParams &p [[buffer(0)]],
                                device atomic_uint *rayCounter [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= p.size.x || gid.y >= p.size.y) return;
    uint rays = 0;
    float3 color = traceRoom(p.cameraPosition.xyz, cameraRay(gid, p), gid, rays, ROOM_SCENE_PASS);
    output.write(float4(color, 1.0), gid);
    countRays(rays, rayCounter);
}

fragment float4 room_display_fragment(FullscreenVertexOut in [[stage_in]],
                                      texture2d<float> image [[texture(0)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float3 color = image.sample(linear, in.uv).rgb;
    color = 1.0 - exp(-color * 1.1);            // tone map
    return float4(pow(color, float3(1.0 / 2.2)), 1.0);
}

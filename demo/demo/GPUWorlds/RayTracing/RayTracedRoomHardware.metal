//
//  RayTracedRoomHardware.metal
//  demo
//
//  Room ray tracer on Metal ray tracing: the walls and tessellated spheres live in a primitive
//  acceleration structure (BVH) and every camera, reflection, refraction and shadow ray goes
//  through the intersector. The pipeline is only created on devices that support ray tracing.
//

#include <metal_raytracing>
#include "RayTracedRoom.h"

using namespace raytracing;

#define ROOM_SCENE_ARGS constant RoomParams &p, primitive_acceleration_structure scene, device const RoomPrimitive *primitives
#define ROOM_SCENE_PASS p, scene, primitives

static Hit roomIntersect(float3 origin, float3 direction, ROOM_SCENE_ARGS) {
    intersector<triangle_data> intersect;
    ray r(origin, direction, 1e-3, 1e8);
    auto result = intersect.intersect(r, scene);
    Hit hit;
    hit.t = kNoHit;
    hit.normal = float3(0.0);
    hit.material = RoomWhite;
    if (result.type == intersection_type::triangle) {
        RoomPrimitive primitive = primitives[result.primitive_id];
        hit.t = result.distance;
        hit.material = primitive.info.x;
        // Spheres use the exact normal, so the tessellation does not show in reflections.
        float3 x = origin + direction * hit.t;
        hit.normal = primitive.info.y < 3 ? normalize(x - p.spheres[primitive.info.y].xyz) : primitive.normal.xyz;
    }
    return hit;
}

static bool roomOccluded(float3 origin, float3 direction, float maxDistance, ROOM_SCENE_ARGS) {
    intersector<triangle_data> intersect;
    intersect.accept_any_intersection(true);
    ray r(origin, direction, 1e-3, max(maxDistance, 2e-3));
    return intersect.intersect(r, scene).type != intersection_type::none;
}

#define ROOM_TRACE
#include "RayTracedRoom.h"

kernel void room_trace_hardware(texture2d<float, access::write> output [[texture(0)]],
                                constant RoomParams &p [[buffer(0)]],
                                device atomic_uint *rayCounter [[buffer(1)]],
                                primitive_acceleration_structure scene [[buffer(2)]],
                                device const RoomPrimitive *primitives [[buffer(3)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= p.size.x || gid.y >= p.size.y) return;
    uint rays = 0;
    float3 color = traceRoom(p.cameraPosition.xyz, cameraRay(gid, p), gid, rays, ROOM_SCENE_PASS);
    output.write(float4(color, 1.0), gid);
    countRays(rays, rayCounter);
}

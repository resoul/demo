#include "ExperimentTypes.h"
inline bool pinned(uint i,uint side) { return i==side*(side-1) || i==side*side-1; }
kernel void clothSeed(device GPUNode *n [[buffer(0)]], constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i>=u.count)return;
    float2 uv=float2(i%u.side,i/u.side)/float(u.side-1);
    n[i]={float4((uv.x-0.5f)*1.6f,(uv.y-0.5f)*1.6f,0,1),float4(0,0,0,1)};
}
kernel void clothPredict(device const GPUNode *source [[buffer(0)]],device GPUNode *out [[buffer(1)]],device GPUNode *old [[buffer(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i>=u.count)return; GPUNode n=source[i]; old[i]=n;
    if(!pinned(i,u.side)) {
        n.velocity.xyz+=float3(sin(u.time*1.2f)*0.06f,-0.3f,0.22f*sin(n.position.x*4+u.time*1.7f))*u.dt;
        n.velocity.xyz*=0.99f;
        float2 screen=n.position.xy*0.5f+0.5f; float distanceToFinger=distance(screen,u.touch);
        if(u.flags&2) {
            if((u.flags&1) && distanceToFinger<0.07f) n.velocity.w=0;
            else if(!(u.flags&1)) n.velocity.xyz+=float3((u.touch-screen)*4,0.8f)*exp(-distanceToFinger*distanceToFinger*90)*u.dt*20;
        }
        n.position.xyz+=n.velocity.xyz*u.dt;
    }
    out[i]=n;
}
kernel void clothRelax(device const GPUNode *source [[buffer(0)]],device GPUNode *out [[buffer(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i>=u.count)return; GPUNode n=source[i]; if(pinned(i,u.side)||n.velocity.w<0.5f){out[i]=n;return;}
    int2 xy=int2(i%u.side,i/u.side); float rest=1.6f/float(u.side-1); float3 correction=0; float weight=0;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {
        if(!x&&!y)continue; int2 p=xy+int2(x,y); if(any(p<0)||any(p>=int(u.side)))continue;
        GPUNode other=source[p.y*u.side+p.x]; if(other.velocity.w<0.5f)continue;
        float3 d=other.position.xyz-n.position.xyz; float len=length(d); float desired=rest*((x&&y)?1.41421356f:1.0f);
        correction+=d*(len-desired)/max(len,1e-5f);weight++;
    }
    n.position.xyz+=correction/max(weight,1.0f)*0.9f;
    float3 sphere=float3(0,-0.25f,-0.22f), d=n.position.xyz-sphere;
    if(length(d)<0.39f)n.position.xyz=sphere+safeUnit(d)*0.39f;
    n.position.y=max(n.position.y,-0.9f); out[i]=n;
}
kernel void clothVelocity(device GPUNode *nodes [[buffer(0)]],device const GPUNode *old [[buffer(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint i [[thread_position_in_grid]]) {
    if(i<u.count)nodes[i].velocity.xyz=clamp((nodes[i].position.xyz-old[i].position.xyz)/u.dt,-2.0f,2.0f);
}
struct ClothRaster { float4 position [[position]];float3 world;float2 uv;float alive; };
vertex ClothRaster clothVertex(device const GPUNode *nodes [[buffer(0)]],constant ExperimentUniforms &u [[buffer(8)]],uint v [[vertex_id]]) {
    const uint2 offsets[6]={uint2(0,0),uint2(1,0),uint2(0,1),uint2(1,0),uint2(1,1),uint2(0,1)};
    uint cell=v/6;uint2 p=uint2(cell%(u.side-1),cell/(u.side-1))+offsets[v%6]; GPUNode n=nodes[p.y*u.side+p.x];
    float depth=2.4f-n.position.z;
    return {float4(n.position.x*1.8f/max(u.aspect,0.6f),n.position.y*1.8f,depth*0.1f,depth),n.position.xyz,float2(p)/float(u.side-1),n.velocity.w};
}
fragment float4 clothFragment(ClothRaster in [[stage_in]]) {
    if(in.alive<0.99f)discard_fragment();float3 normal=safeUnit(cross(dfdx(in.world),dfdy(in.world)));
    float light=0.25f+0.75f*abs(dot(normal,safeUnit(float3(-1,2,3))));
    float grid=step(0.1f,fract(in.uv.x*40))*step(0.1f,fract(in.uv.y*40));
    return float4(mix(float3(0.15,0.04,0.35),float3(0.65,0.26,1),grid)*light,1);
}

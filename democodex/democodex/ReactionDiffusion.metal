#include "ExperimentTypes.h"
kernel void reactionSeed(texture2d<float,access::write> field [[texture(0)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(p.x>=u.width||p.y>=u.height)return;float2 uv=(float2(p)+0.5f)/float2(u.width,u.height);float b=0;
    for(uint i=0;i<18;i++){float2 center=float2(random01(i*2+11),random01(i*2+12));if(distance(uv,center)<0.025f)b=0.8f;}
    field.write(float4(1-b*0.5f,b,0,1),p);
}
kernel void reactionStep(texture2d<float,access::read> source [[texture(0)]],texture2d<float,access::write> target [[texture(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(p.x>=u.width||p.y>=u.height)return;float2 value=source.read(p).xy,lap=-value;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){if(!x&&!y)continue;uint2 q=uint2((int2(p)+int2(x,y)+int2(u.width,u.height))%int2(u.width,u.height));lap+=source.read(q).xy*((x&&y)?0.05f:0.2f);}
    float feed=(u.flags&1)?0.025f:0.0367f,kill=(u.flags&1)?0.055f:0.0649f;
    float reaction=value.x*value.y*value.y;
    value+=float2(0.9f,0.45f)*lap+float2(-reaction+feed*(1-value.x),reaction-(kill+feed)*value.y);
    float2 uv=(float2(p)+0.5f)/float2(u.width,u.height);if((u.flags&2)&&distance(uv,u.touch)<0.025f)value=float2(0.4,0.9);
    target.write(float4(clamp(value,0.0f,1.0f),0,1),p);
}
fragment float4 reactionFragment(ExperimentRaster in [[stage_in]],texture2d<float,access::sample> field [[texture(0)]]) {
    constexpr sampler s(coord::normalized,address::repeat,filter::nearest);float2 ab=field.sample(s,in.uv).xy;
    float t=smoothstep(0.02f,0.38f,ab.y);float3 color=mix(float3(0.015,0.025,0.065),float3(0.08,0.9,0.8),t);
    color+=pow(t,4.0f)*float3(0.8,0.2,0.1);return float4(color,1);
}

#include "ExperimentTypes.h"
constexpr sampler inkSampler(coord::normalized,address::clamp_to_edge,filter::linear);
inline uint2 inkCell(int2 p,uint n){return uint2(clamp(p,int2(0),int2(n-1)));}
kernel void inkClear(texture2d<half,access::write> v [[texture(0)]],texture2d<half,access::write> dye [[texture(1)]],texture2d<half,access::write> pressure [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;v.write(half4(0),p);dye.write(half4(0),p);pressure.write(half4(0),p);
}
kernel void inkAdvect(texture2d<half,access::sample> velocity [[texture(0)]],texture2d<half,access::sample> dye [[texture(1)]],texture2d<half,access::write> outV [[texture(2)]],texture2d<half,access::write> outD [[texture(3)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;float2 uv=(float2(p)+0.5f)/float(u.side);float2 previous=uv-float2(velocity.sample(inkSampler,uv).xy)*u.dt;
    float4 color=float4(dye.sample(inkSampler,previous))*exp(-u.dt*0.12f);float2 v=float2(velocity.sample(inkSampler,previous).xy)*0.997f;
    float2 emitter=(u.flags&2)?u.touch:float2(0.5f+sin(u.time*0.8f)*0.24f,0.3f+cos(u.time*0.6f)*0.1f);
    float2 d=uv-emitter;float injection=exp(-dot(d,d)*1600)*u.dt*18;float3 tint=0.5f+0.5f*cos(u.time*0.8f+float3(0,2,4)+((u.flags&1)?3.0f:0.0f));
    color.rgb+=tint*injection;color.a+=injection;
    v+=float2(-d.y,d.x)*exp(-dot(d,d)*70)*u.dt*8;v.y+=color.a*u.dt*0.08f;
    if(p.x==0||p.x==u.side-1)v.x=0;if(p.y==0||p.y==u.side-1)v.y=0;
    outV.write(half4(half2(clamp(v,-1.0f,1.0f)),0,0),p);outD.write(half4(clamp(color,0.0f,8.0f)),p);
}
kernel void inkDivergence(texture2d<half,access::read> v [[texture(0)]],texture2d<half,access::write> out [[texture(1)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int2 q=int2(p);
    float div=float(v.read(inkCell(q+int2(1,0),u.side)).x-v.read(inkCell(q-int2(1,0),u.side)).x)+float(v.read(inkCell(q+int2(0,1),u.side)).y-v.read(inkCell(q-int2(0,1),u.side)).y);
    out.write(half4(half(div*0.5f/float(u.side))),p);
}
kernel void inkJacobi(texture2d<half,access::read> pressure [[texture(0)]],texture2d<half,access::read> div [[texture(1)]],texture2d<half,access::write> out [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int2 q=int2(p);float sum=float(pressure.read(inkCell(q+int2(1,0),u.side)).x)+float(pressure.read(inkCell(q-int2(1,0),u.side)).x)+float(pressure.read(inkCell(q+int2(0,1),u.side)).x)+float(pressure.read(inkCell(q-int2(0,1),u.side)).x);
    out.write(half4(half((sum-float(div.read(p).x))*0.25f)),p);
}
kernel void inkProject(texture2d<half,access::read> v [[texture(0)]],texture2d<half,access::read> pressure [[texture(1)]],texture2d<half,access::write> out [[texture(2)]],constant ExperimentUniforms &u [[buffer(8)]],uint2 p [[thread_position_in_grid]]) {
    if(any(p>=u.side))return;int2 q=int2(p);float2 grad=float2(pressure.read(inkCell(q+int2(1,0),u.side)).x-pressure.read(inkCell(q-int2(1,0),u.side)).x,pressure.read(inkCell(q+int2(0,1),u.side)).x-pressure.read(inkCell(q-int2(0,1),u.side)).x)*0.5f*float(u.side);
    float2 value=float2(v.read(p).xy)-grad;if(p.x==0||p.x==u.side-1)value.x=0;if(p.y==0||p.y==u.side-1)value.y=0;
    out.write(half4(half2(value),0,0),p);
}
fragment float4 fluidInkFragment(ExperimentRaster in [[stage_in]],texture2d<half,access::sample> dye [[texture(0)]]) {
    float3 color=float3(dye.sample(inkSampler,in.uv).rgb);return float4(1-exp(-color*1.7f)+float3(0.01,0.015,0.025),1);
}

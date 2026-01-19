//
//  File.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include <metal_stdlib>
using namespace metal;

struct RenderUniforms {
    float2 domainMin;
    float2 domainMax;
    float  pointRadius;
};

struct VSOut {
    float4 position [[position]];
    float  psize [[point_size]];
};

vertex VSOut vs_particles(
    const device float2* pos [[buffer(0)]],
    constant RenderUniforms& uni [[buffer(1)]],
    uint vid [[vertex_id]]
){
    float2 p = pos[vid];
    float2 L = uni.domainMax - uni.domainMin;
    float2 ndc = ((p - uni.domainMin) / L) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    VSOut o;
    o.position = float4(ndc, 0, 1);
    o.psize = max(1.0, uni.pointRadius * 200.0); // crude scale for now
    return o;
}

fragment float4 fs_particles(VSOut in [[stage_in]],
                             float2 pc [[point_coord]])
{
    float2 d = pc - float2(0.5);
    float r2 = dot(d, d);
    if (r2 > 0.25) discard_fragment();
    return float4(0.2, 0.6, 1.0, 1.0);
}

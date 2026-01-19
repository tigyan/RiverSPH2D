//
//  RenderParticles.metal
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
    float  maxSpeed;
    uint   colorMode;
    uint   pad0;
    float  particleAlpha;
    float  pad1;
};

struct VSOut {
    float4 position [[position]];
    float  psize [[point_size]];
    float  speedNorm;
    float  colorMode;
    float  particleAlpha;
};

vertex VSOut vs_particles(
    const device float2* pos [[buffer(0)]],
    constant RenderUniforms& uni [[buffer(1)]],
    const device float2* vel [[buffer(2)]],
    uint vid [[vertex_id]]
){
    float2 p = pos[vid];
    float2 L = uni.domainMax - uni.domainMin;
    float2 ndc = ((p - uni.domainMin) / L) * 2.0 - 1.0;
    ndc.y = -ndc.y;

    VSOut o;
    o.position = float4(ndc, 0, 1);
    o.psize = max(1.0, uni.pointRadius * 200.0); // crude scale for now
    float speed = length(vel[vid]);
    o.speedNorm = clamp(speed / max(uni.maxSpeed, 1e-3f), 0.0f, 1.0f);
    o.colorMode = (uni.colorMode != 0) ? 1.0f : 0.0f;
    o.particleAlpha = clamp(uni.particleAlpha, 0.0f, 1.0f);
    return o;
}

fragment float4 fs_particles(VSOut in [[stage_in]],
                             float2 pc [[point_coord]])
{
    float2 d = pc - float2(0.5);
    float r2 = dot(d, d);
    if (r2 > 0.25) discard_fragment();

    float3 base = float3(0.2, 0.6, 1.0);
    if (in.colorMode > 0.5) {
        float t = smoothstep(0.0, 1.0, in.speedNorm);
        float3 cold = float3(0.1, 0.4, 1.0);
        float3 hot = float3(1.0, 0.2, 0.1);
        base = mix(cold, hot, t);
    }
    base *= in.particleAlpha;
    return float4(base, 1.0);
}

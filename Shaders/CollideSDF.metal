//
//  File.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include "SPHTypes.metal"

kernel void collideSDF(
    device float2* pos [[buffer(0)]],
    device float2* vel [[buffer(1)]],
    constant GPUParams& gp [[buffer(2)]],
    texture2d<float, access::sample> sdfTex [[texture(0)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    constexpr sampler samp(address::repeat, filter::linear);

    float2 p = pos[id];
    float2 v = vel[id];

    float2 uv = worldToUV(p, gp);
    // uv.y не периодична
    uv.y = clamp(uv.y, 0.0f, 1.0f);

    float sdf = sdfTex.sample(samp, uv).r; // >0 в воде, <0 в твёрдом

    float penetration = gp.particleRadius - sdf;
    if (penetration <= 0.0f) return;

    // gradient by finite differences
    float du = 1.0f / float(sdfTex.get_width());
    float dv = 1.0f / float(sdfTex.get_height());

    float sx1 = sdfTex.sample(samp, uv + float2(du, 0)).r;
    float sx0 = sdfTex.sample(samp, uv - float2(du, 0)).r;
    float sy1 = sdfTex.sample(samp, uv + float2(0, dv)).r;
    float sy0 = sdfTex.sample(samp, uv - float2(0, dv)).r;

    float2 L = gp.domainMax - gp.domainMin;
    float gx = (sx1 - sx0) * float(sdfTex.get_width())  / (2.0f * L.x);
    float gy = (sy1 - sy0) * float(sdfTex.get_height()) / (2.0f * L.y);

    float2 n = safeNormalize(float2(gx, gy));

    // push out
    p += n * penetration;

    // friction: damp tangential component
    float vn = dot(v, n);
    float2 vt = v - vn * n;
    vt *= (1.0f - gp.friction);

    // no bounce in v0.1
    v = vn * n + vt;

    pos[id] = p;
    vel[id] = v;
}

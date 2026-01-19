//
//  AdvectWrap.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include "SPHTypes.metal"

kernel void advectWrap(
    device float2* pos [[buffer(0)]],
    device float2* vel [[buffer(1)]],
    constant GPUParams& gp [[buffer(2)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    float2 p = pos[id];
    float2 v = vel[id];

    // a = drive - k*v
    float2 a = float2(gp.driveAccel, 0.0f) - gp.dragK * v;

    v += a * gp.dt;
    p += v * gp.dt;

    // Periodic X
    p.x = wrapX(p.x - gp.domainMin.x, gp.Lx) + gp.domainMin.x;

    // Clamp Y (оставим базово; берега всё равно маской)
    p.y = clamp(p.y, gp.domainMin.y, gp.domainMax.y);

    pos[id] = p;
    vel[id] = v;
}

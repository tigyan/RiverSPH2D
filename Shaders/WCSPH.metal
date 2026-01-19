//
//  WCSPH.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include "SPHTypes.metal"

inline float2 deltaPeriodic(float2 a, float2 b, constant GPUParams& gp) {
    float2 d = a - b;
    d.x -= floor((d.x / gp.Lx) + 0.5f) * gp.Lx;
    return d;
}

inline int2 cellCoord(float2 p, constant GPUParams& gp) {
    float2 rel = p - gp.domainMin;
    rel.x = wrapX(rel.x, gp.Lx);
    rel.y = clamp(rel.y, 0.0f, gp.Ly - 1e-5f);
    int cx = int(floor(rel.x / gp.cellSize));
    int cy = int(floor(rel.y / gp.cellSize));
    cx = clamp(cx, 0, int(gp.gridSizeX) - 1);
    cy = clamp(cy, 0, int(gp.gridSizeY) - 1);
    return int2(cx, cy);
}

inline uint cellIndex(int2 c, constant GPUParams& gp) {
    return uint(c.y) * gp.gridSizeX + uint(c.x);
}

kernel void clearGridHeads(
    device atomic_int* gridHead [[buffer(0)]],
    constant GPUParams& gp [[buffer(1)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.gridCount) return;
    atomic_store_explicit(&gridHead[id], -1, memory_order_relaxed);
}

kernel void buildGrid(
    device const float2* pos [[buffer(0)]],
    device atomic_int* gridHead [[buffer(1)]],
    device int* gridNext [[buffer(2)]],
    constant GPUParams& gp [[buffer(3)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    float2 p = pos[id];
    int2 c = cellCoord(p, gp);
    uint cell = cellIndex(c, gp);
    int prev = atomic_exchange_explicit(&gridHead[cell], int(id), memory_order_relaxed);
    gridNext[id] = prev;
}

kernel void computeDensityPressure(
    device const float2* pos [[buffer(0)]],
    device float* density [[buffer(1)]],
    device float* pressure [[buffer(2)]],
    device atomic_int* gridHead [[buffer(3)]],
    device const int* gridNext [[buffer(4)]],
    device const float2* bPos [[buffer(5)]],
    device atomic_int* bGridHead [[buffer(6)]],
    device const int* bGridNext [[buffer(7)]],
    device const float* bPsi [[buffer(8)]],
    constant GPUParams& gp [[buffer(9)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    float h = max(gp.smoothingLength, 1e-5f);
    float h2 = h * h;
    float h4 = h2 * h2;
    float h8 = h4 * h4;
    float poly6 = 4.0f / (M_PI_F * h8);

    float2 p = pos[id];
    float rho = 0.0f;
    int2 c = cellCoord(p, gp);

    for (int oy = -1; oy <= 1; ++oy) {
        int ny = clamp(c.y + oy, 0, int(gp.gridSizeY) - 1);
        for (int ox = -1; ox <= 1; ++ox) {
            int nx = c.x + ox;
            if (nx < 0) nx += int(gp.gridSizeX);
            if (nx >= int(gp.gridSizeX)) nx -= int(gp.gridSizeX);

            uint cell = uint(ny) * gp.gridSizeX + uint(nx);
            int j = atomic_load_explicit(&gridHead[cell], memory_order_relaxed);
            while (j != -1) {
                float2 r = deltaPeriodic(p, pos[j], gp);
                float r2 = dot(r, r);
                if (r2 < h2) {
                    float t = h2 - r2;
                    rho += gp.particleMass * poly6 * t * t * t;
                }
                j = gridNext[j];
            }

            int jb = atomic_load_explicit(&bGridHead[cell], memory_order_relaxed);
            while (jb != -1) {
                float2 r = deltaPeriodic(p, bPos[jb], gp);
                float r2 = dot(r, r);
                if (r2 < h2) {
                    float t = h2 - r2;
                    rho += gp.boundaryStrength * bPsi[jb] * poly6 * t * t * t;
                }
                jb = bGridNext[jb];
            }
        }
    }

    float rhoSafe = max(rho, 0.5f * gp.restDensity);
    float pres = gp.stiffness * (pow(rhoSafe / gp.restDensity, gp.gamma) - 1.0f);
    // Mild negative pressure to reduce voids without tensile blowups.
    pres = clamp(pres, -0.1f * gp.stiffness, 1.5f * gp.stiffness);

    density[id] = rho;
    pressure[id] = pres;
}

kernel void computeDeltaDensity(
    device const float2* pos [[buffer(0)]],
    device float* density [[buffer(1)]],
    device float* pressure [[buffer(2)]],
    device atomic_int* gridHead [[buffer(3)]],
    device const int* gridNext [[buffer(4)]],
    constant GPUParams& gp [[buffer(5)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    if (gp.deltaSPH <= 1e-6f) return;

    float h = max(gp.smoothingLength, 1e-5f);
    float h2 = h * h;
    float h5 = h2 * h2 * h;
    float spikyGrad = -30.0f / (M_PI_F * h5);

    float2 p = pos[id];
    float rhoI = max(density[id], 0.5f * gp.restDensity);
    float sum = 0.0f;

    int2 c = cellCoord(p, gp);
    for (int oy = -1; oy <= 1; ++oy) {
        int ny = clamp(c.y + oy, 0, int(gp.gridSizeY) - 1);
        for (int ox = -1; ox <= 1; ++ox) {
            int nx = c.x + ox;
            if (nx < 0) nx += int(gp.gridSizeX);
            if (nx >= int(gp.gridSizeX)) nx -= int(gp.gridSizeX);

            uint cell = uint(ny) * gp.gridSizeX + uint(nx);
            int j = atomic_load_explicit(&gridHead[cell], memory_order_relaxed);
            while (j != -1) {
                if (j != int(id)) {
                    float2 r = deltaPeriodic(p, pos[j], gp);
                    float r2 = dot(r, r);
                    if (r2 < h2 && r2 > 1e-12f) {
                        float rlen = sqrt(r2);
                        float2 grad = spikyGrad * (h - rlen) * (h - rlen) * (r / rlen);
                        float rhoJ = max(density[j], 0.5f * gp.restDensity);
                        float term = (rhoJ - rhoI) / rhoJ;
                        float denom = r2 + 0.01f * h2;
                        sum += gp.particleMass * term * dot(r, grad) / denom;
                    }
                }
                j = gridNext[j];
            }
        }
    }

    float rhoNew = rhoI + 2.0f * gp.deltaSPH * gp.soundSpeed * h * sum * gp.dt;
    rhoNew = max(rhoNew, 0.5f * gp.restDensity);

    float pres = gp.stiffness * (pow(rhoNew / gp.restDensity, gp.gamma) - 1.0f);
    pres = clamp(pres, -0.1f * gp.stiffness, 1.5f * gp.stiffness);

    density[id] = rhoNew;
    pressure[id] = pres;
}

kernel void computeForcesIntegrate(
    device float2* pos [[buffer(0)]],
    device float2* vel [[buffer(1)]],
    device const float* density [[buffer(2)]],
    device const float* pressure [[buffer(3)]],
    device atomic_int* gridHead [[buffer(4)]],
    device const int* gridNext [[buffer(5)]],
    device const float2* bPos [[buffer(6)]],
    device atomic_int* bGridHead [[buffer(7)]],
    device const int* bGridNext [[buffer(8)]],
    device const float* bPsi [[buffer(9)]],
    constant GPUParams& gp [[buffer(10)]],
    uint id [[thread_position_in_grid]]
){
    if (id >= gp.particleCount) return;
    float h = max(gp.smoothingLength, 1e-5f);
    float h2 = h * h;
    float h4 = h2 * h2;
    float h5 = h4 * h;
    float h8 = h4 * h4;
    float poly6 = 4.0f / (M_PI_F * h8);
    float spikyGrad = -30.0f / (M_PI_F * h5);
    float viscLap = 40.0f / (M_PI_F * h5);

    float2 p = pos[id];
    float2 v = vel[id];
    float rhoI = max(density[id], 0.5f * gp.restDensity);
    float pI = pressure[id];

    float2 acc = float2(gp.driveAccel, 0.0f) - gp.dragK * v;
    float2 visc = float2(0.0f);
    float2 xsph = float2(0.0f);

    int2 c = cellCoord(p, gp);

    for (int oy = -1; oy <= 1; ++oy) {
        int ny = clamp(c.y + oy, 0, int(gp.gridSizeY) - 1);
        for (int ox = -1; ox <= 1; ++ox) {
            int nx = c.x + ox;
            if (nx < 0) nx += int(gp.gridSizeX);
            if (nx >= int(gp.gridSizeX)) nx -= int(gp.gridSizeX);

            uint cell = uint(ny) * gp.gridSizeX + uint(nx);
            int j = atomic_load_explicit(&gridHead[cell], memory_order_relaxed);
            while (j != -1) {
                float2 r = deltaPeriodic(p, pos[j], gp);
                float r2 = dot(r, r);
                if (r2 < h2 && r2 > 1e-12f) {
                    float rlen = sqrt(r2);
                    float2 grad = spikyGrad * (h - rlen) * (h - rlen) * (r / rlen);
                    float rhoJ = max(density[j], 0.5f * gp.restDensity);
                    float pJ = pressure[j];

                    acc -= gp.particleMass * (pI / (rhoI * rhoI) + pJ / (rhoJ * rhoJ)) * grad;

                    float lap = viscLap * (h - rlen);
                    visc += gp.particleMass * (vel[j] - v) / rhoJ * lap;

                    float t = h2 - r2;
                    float w = poly6 * t * t * t;
                    xsph += gp.particleMass * (vel[j] - v) / rhoJ * w;
                }
                j = gridNext[j];
            }

            int jb = atomic_load_explicit(&bGridHead[cell], memory_order_relaxed);
            while (jb != -1) {
                float2 r = deltaPeriodic(p, bPos[jb], gp);
                float r2 = dot(r, r);
                if (r2 < h2 && r2 > 1e-12f) {
                    float rlen = sqrt(r2);
                    float2 grad = spikyGrad * (h - rlen) * (h - rlen) * (r / rlen);

                    acc -= gp.boundaryStrength * bPsi[jb] * (pI / (rhoI * rhoI)) * grad;

                    float lap = viscLap * (h - rlen);
                    visc += gp.boundaryStrength * bPsi[jb] * (float2(0.0f) - v) / gp.restDensity * lap;

                    float t = h2 - r2;
                    float w = poly6 * t * t * t;
                    xsph += gp.boundaryStrength * bPsi[jb] * (float2(0.0f) - v) / gp.restDensity * w;
                }
                jb = bGridNext[jb];
            }
        }
    }

    acc += gp.viscosity * visc;

    v += acc * gp.dt;
    v += gp.xsph * xsph;
    float speed = length(v);
    if (speed > gp.maxSpeed && speed > 1e-6f) {
        v *= gp.maxSpeed / speed;
    }
    p += v * gp.dt;

    // Periodic X
    p.x = wrapX(p.x - gp.domainMin.x, gp.Lx) + gp.domainMin.x;
    p.y = clamp(p.y, gp.domainMin.y, gp.domainMax.y);

    pos[id] = p;
    vel[id] = v;
}

kernel void computeVelocityField(
    texture2d<float, access::write> fieldTex [[texture(0)]],
    texture2d<float, access::sample> sdfTex [[texture(1)]],
    device const float2* pos [[buffer(0)]],
    device const float2* vel [[buffer(1)]],
    device atomic_int* gridHead [[buffer(2)]],
    device const int* gridNext [[buffer(3)]],
    constant GPUParams& gp [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
){
    uint w = fieldTex.get_width();
    uint h = fieldTex.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float2 uv = (float2(gid) + 0.5f) / float2(w, h);
    float2 p = gp.domainMin + float2(uv.x * gp.Lx, uv.y * gp.Ly);

    constexpr sampler samp(address::repeat, filter::linear);
    float2 uvS = worldToUV(p, gp);
    uvS.y = clamp(uvS.y, 0.0f, 1.0f);
    float sdf = sdfTex.sample(samp, uvS).r;
    if (sdf < 0.0f) {
        fieldTex.write(float4(0.0f), gid);
        return;
    }

    float hlen = max(gp.smoothingLength, 1e-5f);
    float h2 = hlen * hlen;
    float h4 = h2 * h2;
    float h8 = h4 * h4;
    float poly6 = 4.0f / (M_PI_F * h8);

    float2 sumV = float2(0.0f);
    float sumW = 0.0f;

    int2 c = cellCoord(p, gp);
    for (int oy = -1; oy <= 1; ++oy) {
        int ny = clamp(c.y + oy, 0, int(gp.gridSizeY) - 1);
        for (int ox = -1; ox <= 1; ++ox) {
            int nx = c.x + ox;
            if (nx < 0) nx += int(gp.gridSizeX);
            if (nx >= int(gp.gridSizeX)) nx -= int(gp.gridSizeX);

            uint cell = uint(ny) * gp.gridSizeX + uint(nx);
            int j = atomic_load_explicit(&gridHead[cell], memory_order_relaxed);
            while (j != -1) {
                float2 r = deltaPeriodic(p, pos[j], gp);
                float r2 = dot(r, r);
                if (r2 < h2) {
                    float t = h2 - r2;
                    float wj = poly6 * t * t * t;
                    sumW += wj;
                    sumV += wj * vel[j];
                }
                j = gridNext[j];
            }
        }
    }

    float2 v = (sumW > 1e-6f) ? (sumV / sumW) : float2(0.0f);
    fieldTex.write(float4(v, 0.0f, 0.0f), gid);
}

//
//  File.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include <metal_stdlib>
using namespace metal;

struct GPUParams {
    float2 domainMin;
    float2 domainMax;
    float  Lx;
    float  Ly;

    float  dt;
    float  driveAccel;
    float  dragK;

    float  particleRadius;
    float  friction;

    float  restDensity;
    float  particleMass;
    float  smoothingLength;
    float  cellSize;

    float  stiffness;
    float  gamma;
    float  viscosity;
    float  xsph;

    uint   gridSizeX;
    uint   gridSizeY;
    uint   gridCount;

    uint   particleCount;
};

inline float wrapX(float x, float Lx) {
    return x - floor(x / Lx) * Lx;
}

inline float2 worldToUV(float2 p, constant GPUParams& gp) {
    float2 L = gp.domainMax - gp.domainMin;
    return (p - gp.domainMin) / L;
}

inline float2 safeNormalize(float2 v) {
    float len2 = dot(v, v);
    if (len2 < 1e-12f) return float2(0.0f, 1.0f);
    return v * rsqrt(len2);
}

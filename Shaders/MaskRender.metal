//
//  MaskRender.metal
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

#include <metal_stdlib>
using namespace metal;

struct MaskVSOut {
    float4 position [[position]];
    float2 uv;
};

inline float2 safeNormalize(float2 v) {
    float len2 = dot(v, v);
    if (len2 < 1e-10f) {
        return float2(0.0f, 0.0f);
    }
    return v * rsqrt(len2);
}

vertex MaskVSOut vs_mask(uint vid [[vertex_id]]) {
    float2 pos[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uv[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };

    MaskVSOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    o.uv = uv[vid];
    return o;
}

fragment float4 fs_mask(MaskVSOut in [[stage_in]],
                        texture2d<float, access::sample> sdfTex [[texture(0)]])
{
    constexpr sampler samp(address::repeat, filter::linear);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float sdf = sdfTex.sample(samp, uv).r;

    float water = step(0.0, sdf);
    float3 solidColor = float3(0.05, 0.06, 0.07);
    float3 waterColor = float3(0.06, 0.18, 0.28);
    float3 color = mix(solidColor, waterColor, water);

    return float4(color, 1.0);
}

struct FieldUniforms {
    float maxSpeed;
    float opacity;
    float2 pad;
};

fragment float4 fs_velocityField(MaskVSOut in [[stage_in]],
                                 texture2d<float, access::sample> velTex [[texture(0)]],
                                 constant FieldUniforms& uni [[buffer(0)]])
{
    constexpr sampler samp(address::repeat, filter::linear);
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float4 v4 = velTex.sample(samp, uv);
    float2 v = v4.xy;

    float speed = length(v);
    if (speed < 1e-4f) {
        return float4(0.0f);
    }

    float t = clamp(speed / max(uni.maxSpeed, 1e-3f), 0.0f, 1.0f);
    float3 cold = float3(0.1, 0.4, 1.0);
    float3 hot = float3(1.0, 0.2, 0.1);
    float3 color = mix(cold, hot, smoothstep(0.0f, 1.0f, t));
    return float4(color, uni.opacity);
}

struct ArrowUniforms {
    float4 fieldInfo; // xy = fieldSize, z = maxSpeed, w = opacity
    float4 arrowInfo; // x = arrowScale
};

struct ArrowVSOut {
    float4 position [[position]];
    float speedT;
};

vertex ArrowVSOut vs_velocityArrows(uint vid [[vertex_id]],
                                    texture2d<float, access::sample> velTex [[texture(0)]],
                                    constant ArrowUniforms& uni [[buffer(0)]])
{
    ArrowVSOut out;

    uint w = max(1u, uint(uni.fieldInfo.x));
    uint h = max(1u, uint(uni.fieldInfo.y));
    uint cellId = vid / 6;
    uint seg = (vid / 2) % 3;
    uint end = vid % 2;

    uint x = cellId % w;
    uint y = cellId / w;
    if (y >= h) {
        out.position = float4(2.0f, 2.0f, 0.0f, 1.0f);
        out.speedT = 0.0f;
        return out;
    }

    float2 uv = (float2(x, y) + 0.5f) / float2(w, h);
    float2 uvSample = uv;

    constexpr sampler samp(address::clamp_to_edge, filter::linear);
    float2 v = velTex.sample(samp, uvSample).xy;
    v.y = -v.y;

    float speed = length(v);
    float maxSpeed = max(uni.fieldInfo.z, 1e-3f);
    float t = clamp(speed / maxSpeed, 0.0f, 1.0f);
    if (t < 0.02f) {
        out.position = float4(2.0f, 2.0f, 0.0f, 1.0f);
        out.speedT = 0.0f;
        return out;
    }

    float2 dir = safeNormalize(v);
    float2 base = float2(uv.x * 2.0f - 1.0f, (1.0f - uv.y) * 2.0f - 1.0f);

    float2 cellNDC = float2(2.0f / float(w), 2.0f / float(h));
    float baseLen = min(cellNDC.x, cellNDC.y) * max(0.05f, uni.arrowInfo.x);
    float len = baseLen * t;
    float2 tip = base + dir * len;

    float headLen = len * 0.35f;
    float headWidth = len * 0.25f;
    float2 perp = float2(-dir.y, dir.x);
    float2 headBase = tip - dir * headLen;
    float2 headLeft = headBase + perp * headWidth;
    float2 headRight = headBase - perp * headWidth;

    float2 a;
    float2 b;
    if (seg == 0) {
        a = base;
        b = tip;
    } else if (seg == 1) {
        a = tip;
        b = headLeft;
    } else {
        a = tip;
        b = headRight;
    }

    float2 pos = (end == 0) ? a : b;
    out.position = float4(pos, 0.0f, 1.0f);
    out.speedT = t;
    return out;
}

fragment float4 fs_velocityArrows(ArrowVSOut in [[stage_in]],
                                  constant ArrowUniforms& uni [[buffer(0)]])
{
    if (in.speedT <= 0.0f) {
        return float4(0.0f);
    }
    float t = clamp(in.speedT, 0.0f, 1.0f);
    float3 cold = float3(0.1, 0.4, 1.0);
    float3 hot = float3(1.0, 0.2, 0.1);
    float3 color = mix(cold, hot, smoothstep(0.0f, 1.0f, t));
    return float4(color, uni.fieldInfo.w);
}

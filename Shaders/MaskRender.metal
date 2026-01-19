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

//
//  ObstacleAsset.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Metal

struct ObstacleAsset {
    let mask: MaskBinary
    let sdfTexture: MTLTexture
    let Ly: Float
}

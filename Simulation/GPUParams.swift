//
//  GPUParams.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import simd

struct GPUParams {
    var domainMin: SIMD2<Float>
    var domainMax: SIMD2<Float>
    var Lx: Float
    var Ly: Float

    var dt: Float
    var driveAccel: Float
    var dragK: Float

    var particleRadius: Float
    var friction: Float

    var restDensity: Float
    var particleMass: Float
    var smoothingLength: Float
    var cellSize: Float

    var stiffness: Float
    var gamma: Float
    var viscosity: Float
    var xsph: Float
    var maxSpeed: Float

    var gridSizeX: UInt32
    var gridSizeY: UInt32
    var gridCount: UInt32

    var particleCount: UInt32
}

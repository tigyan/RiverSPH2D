//
//  SPHParameters.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Foundation

struct SPHParameters: Codable, Equatable {
    struct Domain: Codable, Equatable {
        var Lx: Float = 20
    }
    struct Particles: Codable, Equatable {
        var count: Int = 1_000
    }
    struct Sph: Codable, Equatable {
        /// 2D rest density (mass per area)
        var restDensity: Float = 1000.0
        /// Viscosity coefficient (viscous force)
        var viscosity: Float = 0.35
        /// h = smoothingFactor * particleSpacing
        var smoothingFactor: Float = 2.0
        /// Equation of state exponent (Tait)
        var gamma: Float = 7.0
        /// Artificial sound speed (controls compressibility)
        var soundSpeed: Float = 20.0
        /// XSPH velocity smoothing (0..0.1)
        var xsph: Float = 0.08
        /// Safety clamp for extreme bursts
        var maxSpeed: Float = 12.0
        /// Boundary influence strength (0..2)
        var boundaryStrength: Float = 1.0
    }
    struct Flow: Codable, Equatable {
        /// Ускорение вправо (аналог g*S)
        var driveAccel: Float = 6.0
        /// Линейный drag: a -= k*v
        var dragK: Float = 0.8
    }
    struct Collide: Codable, Equatable {
        var particleRadius: Float = 0.02
        var friction: Float = 0.2
    }
    struct Time: Codable, Equatable {
        var fixedDt: Float = 1.0 / 60.0
        var substeps: Int = 4
    }

    var domain = Domain()
    var particles = Particles()
    var sph = Sph()
    var flow = Flow()
    var collide = Collide()
    var time = Time()

    static func defaultV0_1() -> SPHParameters { SPHParameters() }
}

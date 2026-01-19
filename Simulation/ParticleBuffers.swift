//
//  ParticleBuffers.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Metal

final class ParticleBuffers {
    let pos: MTLBuffer
    let vel: MTLBuffer
    let density: MTLBuffer
    let pressure: MTLBuffer
    let gridNext: MTLBuffer
    let count: Int

    init(device: MTLDevice, count: Int) {
        self.count = count
        let posSize = MemoryLayout<SIMD2<Float>>.stride * count
        let velSize = MemoryLayout<SIMD2<Float>>.stride * count
        let scalarSize = MemoryLayout<Float>.stride * count
        let nextSize = MemoryLayout<Int32>.stride * count

        guard let pos = device.makeBuffer(length: posSize, options: [.storageModeShared]),
              let vel = device.makeBuffer(length: velSize, options: [.storageModeShared]),
              let density = device.makeBuffer(length: scalarSize, options: [.storageModeShared]),
              let pressure = device.makeBuffer(length: scalarSize, options: [.storageModeShared]),
              let gridNext = device.makeBuffer(length: nextSize, options: [.storageModeShared]) else {
            fatalError("Failed to allocate particle buffers")
        }
        self.pos = pos
        self.vel = vel
        self.density = density
        self.pressure = pressure
        self.gridNext = gridNext
    }
}

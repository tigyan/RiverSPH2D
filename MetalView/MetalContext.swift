//
//  MetalContext.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Metal

final class MetalContext {
    static let shared = MetalContext()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary

    private init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal not available")
        }
        self.device = device
        self.queue = queue

        do {
            self.library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            fatalError("Failed to load default Metal library: \(error)")
        }
    }
}

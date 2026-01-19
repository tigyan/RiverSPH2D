//
//  SDFTextureBuilder.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Metal

enum SDFTextureBuilder {
    static func makeR32FloatTexture(device: MTLDevice, width: Int, height: Int, data: [Float]) throws -> MTLTexture {
        precondition(data.count == width * height)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared   // на Apple Silicon проще и без сюрпризов

        guard let tex = device.makeTexture(descriptor: desc) else {
            throw NSError(domain: "SDFTextureBuilder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
        }

        let bytesPerRow = width * MemoryLayout<Float>.stride
        data.withUnsafeBytes { ptr in
            tex.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        // ❌ tex.didModifyRange(...) — УБРАТЬ
        return tex
    }
}

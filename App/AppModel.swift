//
//  AppModel.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Foundation
import Metal
import Combine
import simd

final class AppModel: ObservableObject {
    @Published var params = SPHParameters.defaultV0_1()
    @Published var isRunning: Bool = true
    @Published var selectedMaskName: String = "river_mask.png"

    @Published var stats = SimulationStats()

    private(set) var engine: SPHEngine?
    private(set) var obstacle: ObstacleAsset?
    let availableMasks: [String] = [
        "river_mask.png",
        "river_straight.png",
        "river_meander.png",
        "river_chicane.png",
        "river_islands.png"
    ]

    func bootstrap() {
        let ctx = MetalContext.shared
        engine = SPHEngine(device: ctx.device, queue: ctx.queue, library: ctx.library)
        reset()
    }

    func reset() {
        guard let engine else { return }

        do {
            let mask: MaskBinary
            if let url = maskURL(named: selectedMaskName) {
                mask = try MaskBinary.load(url: url, threshold: 0.5)
            } else {
                print("Mask not found: \(selectedMaskName). Using procedural default mask.")
                mask = makeDefaultMask(width: 512, height: 256)
            }
            let mismatch = MaskValidation.tileMismatchX(mask: mask)
            if mismatch > 0.02 {
                print("WARNING: mask is not tileable in X. mismatch=\(mismatch)")
            }

            let Lx: Float = params.domain.Lx
            let sdf = SDFGenerator.buildPeriodicSDF(mask: mask, Lx: Lx)

            let sdfTex = try SDFTextureBuilder.makeR32FloatTexture(
                device: MetalContext.shared.device,
                width: sdf.width,
                height: sdf.height,
                data: sdf.sdf
            )

            let obstacle = ObstacleAsset(mask: mask, sdfTexture: sdfTex, Ly: sdf.Ly)
            self.obstacle = obstacle

            try engine.reset(params: params, obstacle: obstacle)

        } catch {
            print("Reset error: \(error)")
        }
    }

    private func maskURL(named name: String) -> URL? {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "png" : ns.pathExtension

        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Masks") {
            return url
        }
        if let url = Bundle.main.url(forResource: base, withExtension: ext) {
            return url
        }
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Masks/\(base).\(ext)")
        if FileManager.default.fileExists(atPath: cwdURL.path) {
            return cwdURL
        }
        return nil
    }

    private func makeDefaultMask(width: Int, height: Int) -> MaskBinary {
        let W = max(4, width)
        let H = max(4, height)
        var data = [UInt8](repeating: 0, count: W * H)

        let twoPi = Double.pi * 2.0
        for y in 0..<H {
            for x in 0..<W {
                let t = twoPi * Double(x) / Double(W)
                let center = 0.5 * Double(H) + sin(t) * 0.05 * Double(H)
                let half = 0.28 * Double(H) + sin(t * 2.0 + 1.3) * 0.06 * Double(H)
                let yMin = center - half
                let yMax = center + half

                let fluid = Double(y) >= yMin && Double(y) <= yMax
                data[y * W + x] = fluid ? 1 : 0
            }
        }
        return MaskBinary(width: W, height: H, data: data)
    }

    func updateEngineParams() {
        engine?.updateParams(params)
    }
}

struct SimulationStats {
    var fps: Double = 0
    var simMS: Double = 0
}

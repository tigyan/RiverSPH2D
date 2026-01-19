//
//  MaskBinary.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Foundation
import AppKit

struct MaskBinary {
    let width: Int
    let height: Int
    /// 0 = solid, 1 = fluid
    let data: [UInt8]

    func isFluid(x: Int, y: Int) -> Bool {
        data[y * width + x] == 1
    }

    static func load(url: URL, threshold: CGFloat) throws -> MaskBinary {
        guard let img = NSImage(contentsOf: url) else {
            throw NSError(domain: "MaskBinary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
        }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw NSError(domain: "MaskBinary", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed bitmap rep"])
        }

        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        var out = [UInt8](repeating: 0, count: w*h)

        for y in 0..<h {
            for x in 0..<w {
                let c = rep.colorAt(x: x, y: y) ?? .black
                let rgb = c.usingColorSpace(.deviceRGB)
                let gray = c.usingColorSpace(.deviceGray)
                let r: CGFloat
                let g: CGFloat
                let b: CGFloat
                if let rgb {
                    r = rgb.redComponent
                    g = rgb.greenComponent
                    b = rgb.blueComponent
                } else if let gray {
                    r = gray.whiteComponent
                    g = gray.whiteComponent
                    b = gray.whiteComponent
                } else {
                    r = 0
                    g = 0
                    b = 0
                }
                let luma = r * 0.299 + g * 0.587 + b * 0.114
                out[y*w + x] = (luma >= threshold) ? 1 : 0
            }
        }
        return MaskBinary(width: w, height: h, data: out)
    }
}

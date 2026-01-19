//
//  MaskValidation.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Foundation

enum MaskValidation {
    static func tileMismatchX(mask: MaskBinary) -> Double {
        let w = mask.width
        let h = mask.height
        var mism = 0
        for y in 0..<h {
            if mask.data[y*w + 0] != mask.data[y*w + (w-1)] {
                mism += 1
            }
        }
        return Double(mism) / Double(h)
    }
}

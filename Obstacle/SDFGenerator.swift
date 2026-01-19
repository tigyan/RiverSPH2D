//
//  SDFGenerator.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Foundation

enum SDFGenerator {
    private static let INF: Float = 1e20

    struct SDFResult {
        let sdf: [Float]
        let width: Int
        let height: Int
        let Ly: Float
    }

    static func buildPeriodicSDF(mask: MaskBinary, Lx: Float) -> SDFResult {
        let W = mask.width
        let H = mask.height
        let Ly = Lx * Float(H) / Float(W)
        let metersPerPixel = Lx / Float(W)

        // tile x3
        let W3 = W * 3
        var m3 = [UInt8](repeating: 0, count: W3 * H)
        for y in 0..<H {
            for x in 0..<W {
                let v = mask.data[y*W + x]
                m3[y*W3 + (x + 0*W)] = v
                m3[y*W3 + (x + 1*W)] = v
                m3[y*W3 + (x + 2*W)] = v
            }
        }

        // feature sets:
        // solid pixels: value==0
        // fluid pixels: value==1
        var fSolid = [Float](repeating: INF, count: W3*H)
        var fFluid = [Float](repeating: INF, count: W3*H)
        for i in 0..<(W3*H) {
            if m3[i] == 0 { fSolid[i] = 0 } else { fFluid[i] = 0 }
        }

        let dSolid2 = edt2dSquared(width: W3, height: H, f: fSolid)
        let dFluid2 = edt2dSquared(width: W3, height: H, f: fFluid)

        // crop middle tile, signed = ds - df
        var sdf = [Float](repeating: 0, count: W*H)
        for y in 0..<H {
            for x in 0..<W {
                let i3 = y*W3 + (x + W)
                let ds = sqrt(max(dSolid2[i3], 0)) * metersPerPixel
                let df = sqrt(max(dFluid2[i3], 0)) * metersPerPixel
                sdf[y*W + x] = ds - df
            }
        }

        return SDFResult(sdf: sdf, width: W, height: H, Ly: Ly)
    }

    // --- EDT (Felzenszwalb-Huttenlocher style) ---

    private static func dt1d(_ f: [Float]) -> [Float] {
        let n = f.count
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var d = [Float](repeating: 0, count: n)

        var k = 0
        v[0] = 0
        z[0] = -.infinity
        z[1] =  .infinity

        @inline(__always)
        func s(_ q: Int, _ p: Int) -> Float {
            return ((f[q] + Float(q*q)) - (f[p] + Float(p*p))) / (2 * Float(q - p))
        }

        if n > 1 {
            for q in 1..<n {
                var kk = k
                var ss = s(q, v[kk])
                while ss <= z[kk] {
                    kk -= 1
                    ss = s(q, v[kk])
                }
                k = kk + 1
                v[k] = q
                z[k] = ss
                z[k + 1] = .infinity
            }
        }

        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let p = v[k]
            let dq = q - p
            d[q] = Float(dq*dq) + f[p]
        }
        return d
    }

    private static func edt2dSquared(width: Int, height: Int, f: [Float]) -> [Float] {
        precondition(f.count == width*height)
        var g = [Float](repeating: 0, count: width*height)
        var d = [Float](repeating: 0, count: width*height)

        // rows
        for y in 0..<height {
            var row = [Float](repeating: 0, count: width)
            for x in 0..<width { row[x] = f[y*width + x] }
            let dt = dt1d(row)
            for x in 0..<width { g[y*width + x] = dt[x] }
        }

        // cols
        for x in 0..<width {
            var col = [Float](repeating: 0, count: height)
            for y in 0..<height { col[y] = g[y*width + x] }
            let dt = dt1d(col)
            for y in 0..<height { d[y*width + x] = dt[y] }
        }
        return d
    }
}

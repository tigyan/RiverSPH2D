//
//  SPHEngine.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import Metal
import simd

final class SPHEngine {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let lib: MTLLibrary

    private var clearGridPSO: MTLComputePipelineState!
    private var buildGridPSO: MTLComputePipelineState!
    private var densityPSO: MTLComputePipelineState!
    private var forcesPSO: MTLComputePipelineState!
    private var collidePSO: MTLComputePipelineState!

    private var buffers: ParticleBuffers!
    private var gridHead: MTLBuffer!
    private var boundaryPos: MTLBuffer!
    private var boundaryPsi: MTLBuffer!
    private var boundaryGridHead: MTLBuffer!
    private var boundaryGridNext: MTLBuffer!
    private var boundaryCount: Int = 0
    private var gpuParamsBuf: MTLBuffer!

    private var obstacle: ObstacleAsset!
    private var params: SPHParameters!

    private var domainMinV = SIMD2<Float>(0, 0)
    private var domainMaxV = SIMD2<Float>(20, 10)
    private var autoSubsteps: Int = 1
    private var pipelinesReady: Bool = false

    private struct DerivedSPH {
        var particleSpacing: Float
        var smoothingLength: Float
        var cellSize: Float
        var gridSizeX: Int
        var gridSizeY: Int
        var gridCount: Int
        var restDensity: Float
        var particleMass: Float
    }

    private var derived: DerivedSPH?

    init(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) {
        self.device = device
        self.queue = queue
        self.lib = library
        buildPSOs()
    }

    private func buildPSOs() {
        guard let fClear = lib.makeFunction(name: "clearGridHeads") else {
            print("Missing Metal function: clearGridHeads (check Shaders/WCSPH.metal in target)")
            pipelinesReady = false
            return
        }
        guard let fBuild = lib.makeFunction(name: "buildGrid") else {
            print("Missing Metal function: buildGrid (check Shaders/WCSPH.metal in target)")
            pipelinesReady = false
            return
        }
        guard let fDensity = lib.makeFunction(name: "computeDensityPressure") else {
            print("Missing Metal function: computeDensityPressure (check Shaders/WCSPH.metal in target)")
            pipelinesReady = false
            return
        }
        guard let fForces = lib.makeFunction(name: "computeForcesIntegrate") else {
            print("Missing Metal function: computeForcesIntegrate (check Shaders/WCSPH.metal in target)")
            pipelinesReady = false
            return
        }
        guard let fCollide = lib.makeFunction(name: "collideSDF") else {
            print("Missing Metal function: collideSDF (check Shaders/CollideSDF.metal in target)")
            pipelinesReady = false
            return
        }

        do {
            clearGridPSO = try device.makeComputePipelineState(function: fClear)
            buildGridPSO = try device.makeComputePipelineState(function: fBuild)
            densityPSO = try device.makeComputePipelineState(function: fDensity)
            forcesPSO = try device.makeComputePipelineState(function: fForces)
            collidePSO = try device.makeComputePipelineState(function: fCollide)
            pipelinesReady = true
        } catch {
            pipelinesReady = false
            print("Compute PSO error: \(error)")
        }
    }

    func reset(params: SPHParameters, obstacle: ObstacleAsset) throws {
        self.params = params
        self.obstacle = obstacle

        let Lx = params.domain.Lx
        let Ly = obstacle.Ly

        domainMinV = SIMD2<Float>(0, 0)
        domainMaxV = SIMD2<Float>(Lx, Ly)

        let fluidFraction = fluidAreaFraction(mask: obstacle.mask)
        let fluidArea = max(1e-6, fluidFraction * Lx * Ly)
        let spacing = sqrt(fluidArea / Float(max(1, params.particles.count)))
        let h = max(1e-4, params.sph.smoothingFactor * spacing)
        let cellSize = h
        let gridSizeX = max(1, Int(ceil(Lx / cellSize)))
        let gridSizeY = max(1, Int(ceil(Ly / cellSize)))
        let gridCount = gridSizeX * gridSizeY
        let restDensity = params.sph.restDensity
        let particleMass = restDensity * spacing * spacing

        derived = DerivedSPH(
            particleSpacing: spacing,
            smoothingLength: h,
            cellSize: cellSize,
            gridSizeX: gridSizeX,
            gridSizeY: gridSizeY,
            gridCount: gridCount,
            restDensity: restDensity,
            particleMass: particleMass
        )

        buffers = ParticleBuffers(device: device, count: params.particles.count)
        gridHead = device.makeBuffer(
            length: MemoryLayout<Int32>.stride * gridCount,
            options: [.storageModeShared]
        )

        // Spawn particles inside fluid area (CPU)
        spawnParticlesInFluid(mask: obstacle.mask, W: obstacle.mask.width, H: obstacle.mask.height, Lx: Lx, Ly: Ly)

        // Boundary particles (static)
        let boundaryPositions = makeBoundaryParticles(mask: obstacle.mask, Lx: Lx, Ly: Ly, spacing: spacing)
        boundaryCount = boundaryPositions.count
        let boundaryAlloc = max(1, boundaryCount)
        boundaryPos = device.makeBuffer(
            length: MemoryLayout<SIMD2<Float>>.stride * boundaryAlloc,
            options: [.storageModeShared]
        )
        boundaryPsi = device.makeBuffer(
            length: MemoryLayout<Float>.stride * boundaryAlloc,
            options: [.storageModeShared]
        )
        boundaryGridHead = device.makeBuffer(
            length: MemoryLayout<Int32>.stride * gridCount,
            options: [.storageModeShared]
        )
        boundaryGridNext = device.makeBuffer(
            length: MemoryLayout<Int32>.stride * boundaryAlloc,
            options: [.storageModeShared]
        )

        if boundaryCount > 0 {
            let ptr = boundaryPos.contents().bindMemory(to: SIMD2<Float>.self, capacity: boundaryCount)
            for i in 0..<boundaryCount {
                ptr[i] = boundaryPositions[i]
            }
            let psi = computeBoundaryPsi(positions: boundaryPositions)
            let psiPtr = boundaryPsi.contents().bindMemory(to: Float.self, capacity: boundaryCount)
            for i in 0..<boundaryCount {
                psiPtr[i] = psi[i]
            }
        }
        buildBoundaryGrid(positions: boundaryPositions)

        // GPU params buffer
        gpuParamsBuf = device.makeBuffer(length: MemoryLayout<GPUParams>.stride, options: [.storageModeShared])
        updateParams(params)
    }

    func updateParams(_ params: SPHParameters) {
        self.params = params
        guard let derived else { return }

        let Lx = domainMaxV.x - domainMinV.x
        let Ly = domainMaxV.y - domainMinV.y

        let baseDt = params.time.fixedDt
        let targetVel = params.flow.driveAccel / max(params.flow.dragK, 1e-3)
        let c0 = max(params.sph.soundSpeed, 1e-3)
        let dtCFL = 0.25 * derived.smoothingLength / max(c0 + targetVel, 1e-3)
        let minSub = max(1, params.time.substeps)
        let neededSub = Int(ceil(baseDt / max(dtCFL, 1e-6)))
        let sub = max(minSub, neededSub)
        autoSubsteps = sub
        let dt = baseDt / Float(sub)

        let gamma = max(params.sph.gamma, 1.0)
        let stiffness = derived.restDensity * c0 * c0 / gamma

        var gp = GPUParams(
            domainMin: domainMinV,
            domainMax: domainMaxV,
            Lx: Lx,
            Ly: Ly,
            dt: dt,
            driveAccel: params.flow.driveAccel,
            dragK: params.flow.dragK,
            particleRadius: params.collide.particleRadius,
            friction: params.collide.friction,
            restDensity: derived.restDensity,
            particleMass: derived.particleMass,
            smoothingLength: derived.smoothingLength,
            cellSize: derived.cellSize,
            stiffness: stiffness,
            gamma: gamma,
            viscosity: params.sph.viscosity,
            xsph: params.sph.xsph,
            maxSpeed: params.sph.maxSpeed,
            gridSizeX: UInt32(derived.gridSizeX),
            gridSizeY: UInt32(derived.gridSizeY),
            gridCount: UInt32(derived.gridCount),
            particleCount: UInt32(buffers.count)
        )
        memcpy(gpuParamsBuf.contents(), &gp, MemoryLayout<GPUParams>.stride)
    }

    func step(frameDt: Double) {
        guard let params = self.params,
              let obstacle = self.obstacle,
              let buffers = self.buffers,
              let derived = self.derived else {
            return
        }
        guard pipelinesReady else { return }
        let sub = max(1, autoSubsteps)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return }

        for _ in 0..<sub {
            // clear grid heads
            enc.setComputePipelineState(clearGridPSO)
            enc.setBuffer(gridHead, offset: 0, index: 0)
            enc.setBuffer(gpuParamsBuf, offset: 0, index: 1)
            dispatch(enc, count: derived.gridCount, pso: clearGridPSO)

            // build grid for fluid particles
            enc.setComputePipelineState(buildGridPSO)
            enc.setBuffer(buffers.pos, offset: 0, index: 0)
            enc.setBuffer(gridHead, offset: 0, index: 1)
            enc.setBuffer(buffers.gridNext, offset: 0, index: 2)
            enc.setBuffer(gpuParamsBuf, offset: 0, index: 3)
            dispatch(enc, count: buffers.count, pso: buildGridPSO)

            // density + pressure
            enc.setComputePipelineState(densityPSO)
            enc.setBuffer(buffers.pos, offset: 0, index: 0)
            enc.setBuffer(buffers.density, offset: 0, index: 1)
            enc.setBuffer(buffers.pressure, offset: 0, index: 2)
            enc.setBuffer(gridHead, offset: 0, index: 3)
            enc.setBuffer(buffers.gridNext, offset: 0, index: 4)
            enc.setBuffer(boundaryPos, offset: 0, index: 5)
            enc.setBuffer(boundaryGridHead, offset: 0, index: 6)
            enc.setBuffer(boundaryGridNext, offset: 0, index: 7)
            enc.setBuffer(boundaryPsi, offset: 0, index: 8)
            enc.setBuffer(gpuParamsBuf, offset: 0, index: 9)
            dispatch(enc, count: buffers.count, pso: densityPSO)

            // forces + integrate
            enc.setComputePipelineState(forcesPSO)
            enc.setBuffer(buffers.pos, offset: 0, index: 0)
            enc.setBuffer(buffers.vel, offset: 0, index: 1)
            enc.setBuffer(buffers.density, offset: 0, index: 2)
            enc.setBuffer(buffers.pressure, offset: 0, index: 3)
            enc.setBuffer(gridHead, offset: 0, index: 4)
            enc.setBuffer(buffers.gridNext, offset: 0, index: 5)
            enc.setBuffer(boundaryPos, offset: 0, index: 6)
            enc.setBuffer(boundaryGridHead, offset: 0, index: 7)
            enc.setBuffer(boundaryGridNext, offset: 0, index: 8)
            enc.setBuffer(boundaryPsi, offset: 0, index: 9)
            enc.setBuffer(gpuParamsBuf, offset: 0, index: 10)
            dispatch(enc, count: buffers.count, pso: forcesPSO)

            // SDF collision as a final safety clamp
            enc.setComputePipelineState(collidePSO)
            enc.setBuffer(buffers.pos, offset: 0, index: 0)
            enc.setBuffer(buffers.vel, offset: 0, index: 1)
            enc.setBuffer(gpuParamsBuf, offset: 0, index: 2)
            enc.setTexture(obstacle.sdfTexture, index: 0)

            dispatch(enc, count: buffers.count, pso: collidePSO)
        }

        enc.endEncoding()
        cmd.commit()
    }

    private func dispatch(_ enc: MTLComputeCommandEncoder, count: Int, pso: MTLComputePipelineState) {
        let w = pso.threadExecutionWidth
        let threadsPerTG = MTLSize(width: w, height: 1, depth: 1)
        let tgCount = MTLSize(width: (count + w - 1) / w, height: 1, depth: 1)
        enc.dispatchThreadgroups(tgCount, threadsPerThreadgroup: threadsPerTG)
    }

    func particlePositionBuffer() -> MTLBuffer { buffers.pos }
    func particleVelocityBuffer() -> MTLBuffer { buffers.vel }
    func particleCount() -> Int { buffers.count }

    func domainMin() -> SIMD2<Float> { domainMinV }
    func domainMax() -> SIMD2<Float> { domainMaxV }

    func isReady() -> Bool { buffers != nil }

    private func spawnParticlesInFluid(mask: MaskBinary, W: Int, H: Int, Lx: Float, Ly: Float) {
        let n = buffers.count
        let posPtr = buffers.pos.contents().bindMemory(to: SIMD2<Float>.self, capacity: n)
        let velPtr = buffers.vel.contents().bindMemory(to: SIMD2<Float>.self, capacity: n)

        var seed: UInt64 = 0x12345678
        func rng() -> Float {
            // xorshift64*
            seed &+= 0x9E3779B97F4A7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Float(z & 0xFFFFFF) / Float(0x1000000)
        }

        func wrapX(_ x: Float) -> Float {
            x - floor(x / Lx) * Lx
        }

        func isFluidWorld(x: Float, y: Float) -> Bool {
            let wx = wrapX(x)
            let wy = min(max(y, 0.0), Ly - 1e-5)
            let px = min(W - 1, max(0, Int((wx / Lx) * Float(W))))
            let py = min(H - 1, max(0, Int((wy / Ly) * Float(H))))
            return mask.isFluid(x: px, y: py)
        }

        // Стараемся спавнить на регулярной сетке, чтобы уменьшить слипание.
        if let derived = derived {
            let spacing = max(1e-4, derived.particleSpacing)
            let jitter = 0.35 * spacing
            var candidates: [SIMD2<Float>] = []
            candidates.reserveCapacity(n)

            var y: Float = 0.5 * spacing
            while y < Ly {
                var x: Float = 0.5 * spacing
                while x < Lx {
                    if isFluidWorld(x: x, y: y) {
                        candidates.append(SIMD2<Float>(x, y))
                    }
                    x += spacing
                }
                y += spacing
            }

            // Shuffle candidates (Fisher-Yates)
            if candidates.count > 1 {
                for i in stride(from: candidates.count - 1, through: 1, by: -1) {
                    let j = Int(rng() * Float(i + 1))
                    candidates.swapAt(i, j)
                }
            }

            var i = 0
            let take = min(n, candidates.count)
            while i < take {
                var p = candidates[i]
                let jx = (rng() * 2.0 - 1.0) * jitter
                let jy = (rng() * 2.0 - 1.0) * jitter
                let px = p.x + jx
                let py = p.y + jy
                if isFluidWorld(x: px, y: py) {
                    p = SIMD2<Float>(wrapX(px), min(max(py, 0.0), Ly))
                }
                posPtr[i] = p
                velPtr[i] = SIMD2<Float>(0, 0)
                i += 1
            }

            // Если клеток не хватило, добиваем через rejection.
            while i < n {
                let x = rng() * Lx
                let y = rng() * Ly
                if isFluidWorld(x: x, y: y) {
                    posPtr[i] = SIMD2<Float>(x, y)
                    velPtr[i] = SIMD2<Float>(0, 0)
                    i += 1
                }
            }
            return
        }

        // Fallback: rejection sampling.
        var i = 0
        while i < n {
            let x = rng() * Lx
            let y = rng() * Ly
            if isFluidWorld(x: x, y: y) {
                posPtr[i] = SIMD2<Float>(x, y)
                velPtr[i] = SIMD2<Float>(0, 0)
                i += 1
            }
        }
    }

    private func fluidAreaFraction(mask: MaskBinary) -> Float {
        let fluidCount = mask.data.reduce(0) { $0 + (Int($1) == 1 ? 1 : 0) }
        return Float(fluidCount) / Float(max(1, mask.width * mask.height))
    }

    private func makeBoundaryParticles(mask: MaskBinary, Lx: Float, Ly: Float, spacing: Float) -> [SIMD2<Float>] {
        let W = mask.width
        let H = mask.height
        let dx = Lx / Float(W)
        let dy = Ly / Float(H)
        let stepX = max(1, Int(round(spacing / max(dx, 1e-6))))
        let stepY = max(1, Int(round(spacing / max(dy, 1e-6))))

        func isBoundarySolid(x: Int, y: Int) -> Bool {
            if mask.isFluid(x: x, y: y) { return false }
            let xm = (x - 1 + W) % W
            let xp = (x + 1) % W
            let ym = max(0, y - 1)
            let yp = min(H - 1, y + 1)
            return mask.isFluid(x: xm, y: y) ||
                   mask.isFluid(x: xp, y: y) ||
                   mask.isFluid(x: x, y: ym) ||
                   mask.isFluid(x: x, y: yp)
        }

        var out: [SIMD2<Float>] = []
        out.reserveCapacity((W + H) * 2)

        var y = 0
        while y < H {
            var x = 0
            while x < W {
                if isBoundarySolid(x: x, y: y) {
                    let wx = (Float(x) + 0.5) / Float(W) * Lx
                    let wy = (Float(y) + 0.5) / Float(H) * Ly
                    out.append(SIMD2<Float>(wx, wy))
                }
                x += stepX
            }
            y += stepY
        }
        return out
    }

    private func buildBoundaryGrid(positions: [SIMD2<Float>]) {
        guard let derived else { return }
        let gridCount = derived.gridCount
        var head = [Int32](repeating: -1, count: gridCount)
        var next = [Int32](repeating: -1, count: max(1, positions.count))

        for (i, p) in positions.enumerated() {
            let cell = gridCellIndex(for: p, derived: derived)
            next[i] = head[cell]
            head[cell] = Int32(i)
        }

        head.withUnsafeBytes { raw in
            memcpy(boundaryGridHead.contents(), raw.baseAddress!, raw.count)
        }
        next.withUnsafeBytes { raw in
            memcpy(boundaryGridNext.contents(), raw.baseAddress!, raw.count)
        }
    }

    private func computeBoundaryPsi(positions: [SIMD2<Float>]) -> [Float] {
        guard let derived else { return [] }
        let count = positions.count
        if count == 0 { return [] }

        let h = max(derived.smoothingLength, 1e-5)
        let h2 = h * h
        let h4 = h2 * h2
        let h8 = h4 * h4
        let poly6: Float = 4.0 / (Float.pi * h8)

        var head = [Int](repeating: -1, count: derived.gridCount)
        var next = [Int](repeating: -1, count: count)
        for (i, p) in positions.enumerated() {
            let cell = gridCellIndex(for: p, derived: derived)
            next[i] = head[cell]
            head[cell] = i
        }

        var psi = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let p = positions[i]
            let (cx, cy) = gridCellCoord(for: p, derived: derived)
            var sumW: Float = 0

            for oy in -1...1 {
                let ny = min(max(cy + oy, 0), derived.gridSizeY - 1)
                for ox in -1...1 {
                    var nx = cx + ox
                    if nx < 0 { nx += derived.gridSizeX }
                    if nx >= derived.gridSizeX { nx -= derived.gridSizeX }
                    let cell = ny * derived.gridSizeX + nx
                    var j = head[cell]
                    while j != -1 {
                        let r = deltaPeriodic(p, positions[j])
                        let r2 = r.x * r.x + r.y * r.y
                        if r2 < h2 {
                            let t = h2 - r2
                            sumW += poly6 * t * t * t
                        }
                        j = next[j]
                    }
                }
            }

            if sumW > 1e-8 {
                psi[i] = derived.restDensity / sumW
            } else {
                psi[i] = derived.restDensity * derived.particleSpacing * derived.particleSpacing
            }
        }

        return psi
    }

    private func gridCellCoord(for p: SIMD2<Float>, derived: DerivedSPH) -> (Int, Int) {
        let Lx = domainMaxV.x - domainMinV.x
        let Ly = domainMaxV.y - domainMinV.y

        var rx = p.x - domainMinV.x
        rx = wrapX(rx, Lx: Lx)
        var ry = p.y - domainMinV.y
        ry = min(max(ry, 0.0), Ly - 1e-5)

        let cx = min(derived.gridSizeX - 1, max(0, Int(floor(rx / derived.cellSize))))
        let cy = min(derived.gridSizeY - 1, max(0, Int(floor(ry / derived.cellSize))))
        return (cx, cy)
    }

    private func gridCellIndex(for p: SIMD2<Float>, derived: DerivedSPH) -> Int {
        let (cx, cy) = gridCellCoord(for: p, derived: derived)
        return cy * derived.gridSizeX + cx
    }

    private func deltaPeriodic(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
        let Lx = domainMaxV.x - domainMinV.x
        var d = a - b
        d.x -= floor((d.x / Lx) + 0.5) * Lx
        return d
    }

    private func wrapX(_ x: Float, Lx: Float) -> Float {
        x - floor(x / Lx) * Lx
    }
}

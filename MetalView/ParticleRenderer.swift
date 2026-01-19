//
//  ParticleRenderer.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import MetalKit

final class ParticleRenderer: NSObject, MTKViewDelegate {
    private let model: AppModel
    private let device: MTLDevice
    private let queue: MTLCommandQueue

    private var renderPSO: MTLRenderPipelineState!
    private var maskPSO: MTLRenderPipelineState?
    private var renderReady: Bool = false
    private var lastTime: CFTimeInterval = CACurrentMediaTime()
    private var fpsEMA: Double = 60
    private var simMSEMA: Double = 0

    init(view: MTKView, model: AppModel) {
        self.model = model
        self.device = view.device!
        self.queue = MetalContext.shared.queue
        super.init()
        buildPipeline(view: view)
    }

    private func buildPipeline(view: MTKView) {
        let lib = MetalContext.shared.library
        guard let v = lib.makeFunction(name: "vs_particles") else {
            print("Missing Metal function: vs_particles (check Shaders/RenderParticles.metal in target)")
            renderReady = false
            return
        }
        guard let f = lib.makeFunction(name: "fs_particles") else {
            print("Missing Metal function: fs_particles (check Shaders/RenderParticles.metal in target)")
            renderReady = false
            return
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat

        do {
            renderPSO = try device.makeRenderPipelineState(descriptor: desc)
            renderReady = true
        } catch {
            renderReady = false
            print("Render PSO error: \(error)")
        }

        if let vMask = lib.makeFunction(name: "vs_mask"),
           let fMask = lib.makeFunction(name: "fs_mask") {
            let maskDesc = MTLRenderPipelineDescriptor()
            maskDesc.vertexFunction = vMask
            maskDesc.fragmentFunction = fMask
            maskDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            do {
                maskPSO = try device.makeRenderPipelineState(descriptor: maskDesc)
            } catch {
                print("Mask PSO error: \(error)")
                maskPSO = nil
            }
        } else {
            print("Mask shader not found in default library.")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer()
        else { return }

        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now

        let simStart = CACurrentMediaTime()
        if model.isRunning {
            model.engine?.step(frameDt: dt)
        }
        let simEnd = CACurrentMediaTime()

        // stats
        let fps = 1.0 / max(dt, 1e-6)
        fpsEMA = 0.9 * fpsEMA + 0.1 * fps
        simMSEMA = 0.9 * simMSEMA + 0.1 * ((simEnd - simStart) * 1000.0)
        model.stats.fps = fpsEMA
        model.stats.simMS = simMSEMA

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }
        enc.setRenderPipelineState(renderPSO)

        if let obstacle = model.obstacle, let maskPSO {
            enc.setRenderPipelineState(maskPSO)
            enc.setFragmentTexture(obstacle.sdfTexture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if renderReady, let engine = model.engine, engine.isReady() {
            enc.setRenderPipelineState(renderPSO)
            let posBuf = engine.particlePositionBuffer()
            enc.setVertexBuffer(posBuf, offset: 0, index: 0)

            var uni = RenderUniforms(
                domainMin: engine.domainMin(),
                domainMax: engine.domainMax(),
                pointRadius: model.params.collide.particleRadius
            )
            enc.setVertexBytes(&uni, length: MemoryLayout<RenderUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: engine.particleCount())
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

struct RenderUniforms {
    var domainMin: SIMD2<Float>
    var domainMax: SIMD2<Float>
    var pointRadius: Float
}

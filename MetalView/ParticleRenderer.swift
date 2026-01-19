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
    private var velocityPSO: MTLRenderPipelineState?
    private var arrowPSO: MTLRenderPipelineState?
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

        if let vMask = lib.makeFunction(name: "vs_mask"),
           let fField = lib.makeFunction(name: "fs_velocityField") {
            let fieldDesc = MTLRenderPipelineDescriptor()
            fieldDesc.vertexFunction = vMask
            fieldDesc.fragmentFunction = fField
            fieldDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            do {
                velocityPSO = try device.makeRenderPipelineState(descriptor: fieldDesc)
            } catch {
                print("Velocity field PSO error: \(error)")
                velocityPSO = nil
            }
        }

        if let vArrows = lib.makeFunction(name: "vs_velocityArrows"),
           let fArrows = lib.makeFunction(name: "fs_velocityArrows") {
            let arrowDesc = MTLRenderPipelineDescriptor()
            arrowDesc.vertexFunction = vArrows
            arrowDesc.fragmentFunction = fArrows
            arrowDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            if let attachment = arrowDesc.colorAttachments[0] {
                attachment.isBlendingEnabled = true
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            do {
                arrowPSO = try device.makeRenderPipelineState(descriptor: arrowDesc)
            } catch {
                print("Velocity arrows PSO error: \(error)")
                arrowPSO = nil
            }
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

        if model.showVelocityField,
           let engine = model.engine,
           let fieldTex = engine.velocityFieldTexture(),
           let velocityPSO {
            enc.setRenderPipelineState(velocityPSO)
            enc.setFragmentTexture(fieldTex, index: 0)
            var uni = FieldUniforms(maxSpeed: model.params.sph.maxSpeed, opacity: 0.55)
            enc.setFragmentBytes(&uni, length: MemoryLayout<FieldUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if renderReady, let engine = model.engine, engine.isReady() {
            enc.setRenderPipelineState(renderPSO)
            let posBuf = engine.particlePositionBuffer()
            let velBuf = engine.particleVelocityBuffer()
            enc.setVertexBuffer(posBuf, offset: 0, index: 0)
            enc.setVertexBuffer(velBuf, offset: 0, index: 2)

            var uni = RenderUniforms(
                domainMin: engine.domainMin(),
                domainMax: engine.domainMax(),
                pointRadius: model.params.collide.particleRadius,
                maxSpeed: max(1e-3, model.params.sph.maxSpeed),
                colorMode: model.colorBySpeed ? 1 : 0,
                particleAlpha: model.showVelocityArrows ? 0.15 : 1.0
            )
            enc.setVertexBytes(&uni, length: MemoryLayout<RenderUniforms>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: engine.particleCount())
        }

        if model.showVelocityArrows,
           let engine = model.engine,
           let fieldTex = engine.velocityFieldTexture(),
           let arrowPSO {
            enc.setRenderPipelineState(arrowPSO)
            enc.setVertexTexture(fieldTex, index: 0)
            var uni = ArrowUniforms(
                fieldInfo: SIMD4<Float>(
                    Float(fieldTex.width),
                    Float(fieldTex.height),
                    max(1e-3, model.params.sph.maxSpeed),
                    1.0
                ),
                arrowInfo: SIMD4<Float>(1.2, 0, 0, 0)
            )
            enc.setVertexBytes(&uni, length: MemoryLayout<ArrowUniforms>.stride, index: 0)
            enc.setFragmentBytes(&uni, length: MemoryLayout<ArrowUniforms>.stride, index: 0)
            let vertexCount = fieldTex.width * fieldTex.height * 6
            enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
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
    var maxSpeed: Float
    var colorMode: UInt32
    var pad0: UInt32 = 0
    var particleAlpha: Float = 1.0
    var pad1: Float = 0
}

struct FieldUniforms {
    var maxSpeed: Float
    var opacity: Float
    var pad: SIMD2<Float> = .zero
}

struct ArrowUniforms {
    var fieldInfo: SIMD4<Float>
    var arrowInfo: SIMD4<Float>
}

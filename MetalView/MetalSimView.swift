//
//  MetalSimView.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import SwiftUI
import MetalKit

struct MetalSimView: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MetalContext.shared.device
        view.clearColor = MTLClearColorMake(0.07, 0.07, 0.09, 1.0)
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        let renderer = ParticleRenderer(view: view, model: model)
        context.coordinator.renderer = renderer
        view.delegate = renderer
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: ParticleRenderer?
    }
}

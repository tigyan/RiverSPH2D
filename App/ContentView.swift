//
//  ContentView.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        HStack(spacing: 12) {
            MetalSimView(model: model)
                .frame(minWidth: 900, minHeight: 600)

            VStack(alignment: .leading, spacing: 10) {
                Text("RiverSPH2D v0.3").font(.headline)

                HStack {
                    Button(model.isRunning ? "Pause" : "Play") { model.isRunning.toggle() }
                    Button("Reset") { model.reset() }
                }

                GroupBox("Mask") {
                    Picker("Mask", selection: $model.selectedMaskName) {
                        ForEach(model.availableMasks, id: \.self) { name in
                            Text(name.replacingOccurrences(of: ".png", with: "")).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(6)
                }

                GroupBox("Particles") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Count")
                            Spacer()
                            Text("\(model.params.particles.count)")
                        }
                        Slider(
                            value: Binding(
                                get: { Double(model.params.particles.count) },
                                set: { model.params.particles.count = Int($0) }
                            ),
                            in: 1_000...100_000,
                            step: 1_000,
                            onEditingChanged: { isEditing in
                                if !isEditing { model.reset() }
                            }
                        )
                    }.padding(6)
                }

                GroupBox("Flow") {
                    VStack(alignment: .leading) {
                        HStack { Text("Drive gS"); Spacer()
                            Slider(value: $model.params.flow.driveAccel, in: 0...20)
                        }
                        HStack { Text("Drag k"); Spacer()
                            Slider(value: $model.params.flow.dragK, in: 0...5)
                        }
                    }.padding(6)
                }

                GroupBox("Collisions") {
                    VStack(alignment: .leading) {
                        HStack { Text("Radius"); Spacer()
                            Slider(value: $model.params.collide.particleRadius, in: 0.01...0.2)
                        }
                        HStack { Text("Friction"); Spacer()
                            Slider(value: $model.params.collide.friction, in: 0...1)
                        }
                    }.padding(6)
                }

                GroupBox("Stats") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Particles: \(model.params.particles.count)")
                        Text("Engine: \(model.engine?.isReady() == true ? "ready" : "not ready")")
                        Text("Mask: \(model.obstacle == nil ? "missing" : "ok")")
                        Text(String(format: "FPS: %.1f", model.stats.fps))
                        Text(String(format: "Sim ms: %.2f", model.stats.simMS))
                    }.padding(6)
                }

                Spacer()
            }
            .frame(width: 320)
            .padding()
        }
        .onChange(of: model.params) { oldValue, newValue in
            if oldValue.particles.count != newValue.particles.count {
                return
            }
            model.updateEngineParams()
        }
        .onChange(of: model.selectedMaskName) { _, _ in
            model.reset()
        }
        .onAppear { model.bootstrap() }
    }
}

//
//  ContentView.swift
//  RiverSPH2D
//
//  Created by Timofey Prokoshin on 19.01.2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showAdvanced: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RiverSPH2D v0.3.41")
                        .font(.headline)
                        .foregroundStyle(.primary)

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

                    GroupBox("View") {
                        Toggle("Color by speed", isOn: $model.colorBySpeed)
                            .help("Color particles based on velocity magnitude.")
                            .padding(6)
                    }

                    GroupBox("Particles") {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Count")
                                    .help("Total number of fluid particles. Higher = smoother, slower.")
                                Spacer()
                                Text("\(model.params.particles.count)")
                                    .foregroundStyle(.secondary)
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
                            HStack {
                                Text("Drive gS")
                                    .help("Constant acceleration along the river (energy slope).")
                                Spacer()
                                Text(String(format: "%.2f", model.params.flow.driveAccel))
                                    .foregroundStyle(.secondary)
                            }
                                Slider(value: $model.params.flow.driveAccel, in: 0...20)

                            HStack {
                                Text("Drag k")
                                    .help("Linear drag. Higher = slower steady flow.")
                                Spacer()
                                Text(String(format: "%.2f", model.params.flow.dragK))
                                    .foregroundStyle(.secondary)
                            }
                                Slider(value: $model.params.flow.dragK, in: 0...5)
                        }.padding(6)
                    }

                    GroupBox("Collisions") {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Radius")
                                    .help("Collision shell radius in world units.")
                                Spacer()
                                Text(String(format: "%.3f", model.params.collide.particleRadius))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.params.collide.particleRadius, in: 0.005...0.08)

                            HStack {
                                Text("Friction")
                                    .help("Tangential damping at walls (0..1).")
                                Spacer()
                                Text(String(format: "%.2f", model.params.collide.friction))
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $model.params.collide.friction, in: 0...1)
                        }.padding(6)
                    }

                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                        GroupBox("SPH") {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Rest density")
                                        .help("Target density (2D mass per area).")
                                    Spacer()
                                    Text(String(format: "%.0f", model.params.sph.restDensity))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.restDensity, in: 200...2000)

                                HStack {
                                    Text("Viscosity")
                                        .help("Viscous force strength; higher = smoother, slower.")
                                    Spacer()
                                    Text(String(format: "%.3f", model.params.sph.viscosity))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.viscosity, in: 0...1)

                                HStack {
                                    Text("Smoothing")
                                        .help("h = smoothingFactor * particleSpacing.")
                                    Spacer()
                                    Text(String(format: "%.2f", model.params.sph.smoothingFactor))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.smoothingFactor, in: 1.0...3.0)

                                HStack {
                                    Text("Gamma")
                                        .help("EOS exponent in Tait equation.")
                                    Spacer()
                                    Text(String(format: "%.1f", model.params.sph.gamma))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.gamma, in: 2...9)

                                HStack {
                                    Text("Sound speed")
                                        .help("Artificial sound speed; higher = stiffer, needs smaller dt.")
                                    Spacer()
                                    Text(String(format: "%.1f", model.params.sph.soundSpeed))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.soundSpeed, in: 5...60)

                                HStack {
                                    Text("XSPH")
                                        .help("Velocity smoothing (0..0.1).")
                                    Spacer()
                                    Text(String(format: "%.3f", model.params.sph.xsph))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.xsph, in: 0...0.1)

                                HStack {
                                    Text("Max speed")
                                        .help("Safety clamp for extreme bursts.")
                                    Spacer()
                                    Text(String(format: "%.2f", model.params.sph.maxSpeed))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.sph.maxSpeed, in: 2...30)
                            }.padding(6)
                        }

                        GroupBox("Time") {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Fixed dt")
                                        .help("Base simulation time step (s).")
                                    Spacer()
                                    Text(String(format: "%.4f", model.params.time.fixedDt))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.params.time.fixedDt, in: 1.0/240.0...1.0/30.0)

                                HStack {
                                    Text("Substeps")
                                        .help("Minimum substeps per frame; engine may increase for CFL.")
                                    Spacer()
                                    Text("\(model.params.time.substeps)")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(model.params.time.substeps) },
                                        set: { model.params.time.substeps = Int($0) }
                                    ),
                                    in: 1...8,
                                    step: 1
                                )
                            }.padding(6)
                        }
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
                .frame(width: 340)
                .padding()
            }
            .padding(.leading, 12)

            MetalSimView(model: model)
                .frame(minWidth: 900, minHeight: 600)
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

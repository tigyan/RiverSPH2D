# Architecture (v0.4.01)

## Modules
- App/UI (SwiftUI): parameters, play/pause, reset, stats
- MetalView: MTKView + ParticleRenderer (supports color-by-speed mode)
- Simulation: SPHEngine encodes compute kernels each frame
- Obstacle: loads PNG -> binary mask -> periodic SDF -> MTLTexture(R32Float)
- Boundary: samples mask edge -> static boundary particles + psi weights

## Frame loop
Renderer.draw():
1) engine.step(dt)
2) render points from position buffer

## Compute passes per substep
1) clearGridHeads: reset spatial hash
2) buildGrid: insert fluid particles into grid
3) computeDensityPressure: rho + p for each fluid particle
4) computeDeltaDensity: Delta-SPH diffusion to reduce voids/pressure noise
5) computeForcesIntegrate: pressure + viscosity + drive/drag, integrate
6) collideSDF: push out from solids using SDF gradient, apply friction

## Coordinate system
World domain:
- x in [0, Lx), periodic
- y in [0, Ly], clamped (mask defines actual banks/solids)

Mask mapping:
- u = x / Lx
- v = y / Ly
SDF texture is sampled in UV.

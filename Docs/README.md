# RiverSPH2D

macOS (SwiftUI + Metal) prototype for a 2D top-down "river" particle flow.
Version 0.3 focuses on WCSPH core:
- black/white PNG mask for banks + obstacles
- periodic boundary conditions in X (wrap-around)
- uniform grid neighbor search on GPU
- density/pressure + viscosity + XSPH smoothing
- boundary particles generated from mask edges
- optional SDF collision as a safety clamp
- GPU rendering of particles as point sprites

## Quick start
1. Create a macOS App project in Xcode (SwiftUI).
2. Add `.metal` files under `Shaders/` (ensure they compile into default library).
3. Put a black/white mask into `Resources/Masks/river_mask.png`.
   - White = water (fluid)
   - Black = solid (banks/obstacles)
   - The mask should be tileable in X for best results (left edge matches right edge).
4. Run.

## Controls
- Drive gS: acceleration to the right (models energy slope / pressure gradient)
- Drag k: linear drag a -= k*v
- Radius: collision radius (world units)
- Friction: tangential damping at solid boundaries

## Why periodic X?
The domain represents a repeating segment of a river channel. Particles wrap from x=Lx to x=0.

## Known limitations (v0.3)
- Weakly compressible (WCSPH), not strictly incompressible
- Boundary particles are uniform samples from the mask (no exact wall integration)
- Particle spawn uses CPU rejection sampling (reset-time only)

## Roadmap
See Docs/Roadmap.md

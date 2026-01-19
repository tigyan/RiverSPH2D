# RiverSPH2D

macOS (SwiftUI + Metal) prototype for a 2D top-down "river" particle flow (WCSPH).

## Features
- GPU compute for density/pressure/viscosity
- Periodic X boundary (wrap-around)
- Mask-defined banks and obstacles
- Optional color-by-speed rendering

## Requirements
- macOS 13+ (Apple Silicon recommended)
- Xcode 15+

## Quick start
1. Open `RiverSPH2D.xcodeproj` in Xcode.
2. Ensure `.metal` files in `Shaders/` are part of the target.
3. Run.

## Masks
Place black/white PNG masks in `Resources/Masks/` and select them in the UI.
White = water (fluid), black = solid (banks/obstacles).

## Docs
See `Docs/Overview.md` for details and architecture notes.

## License
MIT. See `LICENSE`.

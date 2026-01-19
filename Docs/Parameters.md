# Parameters (v0.4.01)

## domain.Lx
World length along the river (x-axis). X is periodic.

## particles.count
Number of particles. Particles are spawned uniformly in the fluid mask.

## sph.restDensity
Rest density (2D mass per area).

## sph.viscosity
Viscosity coefficient for the viscous force.

## sph.deltaSPH
Density diffusion coefficient (Delta-SPH) to reduce voids and pressure noise.

## sph.smoothingFactor
Smoothing length factor: h = smoothingFactor * particleSpacing.

## sph.gamma
Exponent in Tait equation of state.

## sph.soundSpeed
Artificial sound speed (controls compressibility).

## sph.xsph
XSPH velocity smoothing factor.

## sph.maxSpeed
Safety clamp for extreme bursts.

## sph.boundaryStrength
Scales boundary particle influence (0..2).

## flow.driveAccel
Constant acceleration to the right. Interpreted as a simplified "energy slope" term (like g*S).

## flow.dragK
Linear drag coefficient. Without drag, mean velocity grows indefinitely in periodic domain.

## collide.particleRadius
Collision shell radius. If sdf(p) < radius => penetration correction.

## collide.friction
Tangential damping at collision. 0 = no friction, 1 = fully stop tangent motion.

## time.fixedDt / time.substeps
Each frame runs `substeps` with dt = fixedDt/substeps. Engine may increase substeps to satisfy CFL stability.

# Physics notes (top-down river model)

In top-down 2D, gravity is out-of-plane. A river flows due to a pressure/energy gradient along the channel
(e.g. from free-surface slope). In depth-averaged shallow-water models this appears as a slope term ~ g*S
balanced by friction.

In this prototype we model the driving term as a constant acceleration:
  a_drive = (g*S, 0)

In a periodic domain, a steady state requires dissipation. We use a linear drag:
  a_drag = -k*v

This is a controllable stand-in for unresolved turbulent losses / bed friction.

## WCSPH core (2D)
We use weakly compressible SPH (WCSPH). Density is computed by kernel summation:
  rho_i = Σ m_j W(r_ij, h)

Pressure uses a Tait equation of state:
  p_i = k * ( (rho_i / rho0)^gamma - 1 )
  k = rho0 * c0^2 / gamma

Forces per particle:
  a_i = -Σ m_j (p_i/rho_i^2 + p_j/rho_j^2) ∇W(r_ij, h)
        + ν Σ m_j (v_j - v_i) / rho_j ∇^2 W(r_ij, h)
        + a_drive - k_drag * v_i

We also apply optional XSPH velocity smoothing:
  v_i += eps * Σ m_j (v_j - v_i)/rho_j * W(r_ij, h)

## Boundary particles
Solids are represented by static boundary particles sampled along the mask edge.
They contribute to density and pressure forces but do not move.
We use a psi weight per boundary particle (Akinci-style) computed from kernel sums,
so boundary influence matches the target rest density.

## Kernels
We use standard poly6 (density) + spiky gradient (pressure) + viscosity Laplacian (2D forms).

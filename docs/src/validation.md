# Validation — code-to-code comparison against TurTLE

!!! warning "Results pending"
    This page currently records the *protocol*: the physics point, the exact matching between the
    two codes, and the reproduction recipe. The results tables are placeholders, filled as each leg
    of the comparison completes. Nothing on this page is a measured claim yet.

The package is validated against **TurTLE** — an independent, production pseudo-spectral DNS code
(Lalescu, Bramas, Rampp & Wilczek,
[*An efficient particle tracking algorithm for large-scale parallel pseudo-spectral simulations of turbulence*](https://doi.org/10.1016/j.cpc.2022.108406),
*Comput. Phys. Commun.* **278**, 108406, 2022) — run at an identical physics point, with the same
time-stepping tableau, an exactly matched dealiasing filter, and the same initial state. Under
those conditions the two codes solve the same discrete system: their solutions separate only
through floating-point roundoff, which grows at the flow's Lyapunov rate from ``\sim 10^{-16}``.
That gives a finite window of turnovers over which even *individual particle trajectories* must
agree to within a predictable envelope — a much sharper test than statistics alone — followed by
statistical agreement (spectra, one-point moments, Lagrangian correlations) over the long run.

TurTLE version: **8.2.1** (its current release at the time of the comparison).

## The physics point

One forced, statistically stationary run of homogeneous isotropic turbulence:

| quantity | value | notes |
|:---|:---|:---|
| grid, box | ``128^3``, ``L = 2\pi`` | |
| precision | `Float64` both codes | |
| viscosity | ``\nu = 9.032 \times 10^{-3}`` | from the resolution criterion, see below |
| forcing | constant power ``\varepsilon_{\mathrm{inj}} = 1`` into shells 1–2 | ``\varepsilon = 1`` exactly at stationarity |
| dealiasing | smooth (Hou–Li) filter, exactly matched | see below |
| field scheme | `IFSSPRK3` ⇔ TurTLE's native SSPRK3 | same tableau, same stage arrangement |
| timestep | fixed ``\Delta t = 2 \times 10^{-3}`` | identical in both codes |
| particles | ``10^4`` tracers, AB4, cubic-spline interpolation | seeded after warm-up, see below |

The viscosity is set by the **resolved** resolution criterion ``\kappa_{\max}\eta = 1.5``: under
the smooth filter the resolved band ends at ``\kappa_{\mathrm{eff}} = 0.8\,\kappa_{\mathrm{Ny}} =
51.2`` (the per-step filter damping overtakes the viscous rate ``\nu\kappa^{2}`` there), so
``\eta = 1.5/51.2`` and ``\nu = (\varepsilon\eta^{4})^{1/3} = \eta^{4/3}``. The grid-band figure is
``\kappa_{\mathrm{Ny}}\eta = 1.875``. Because the forcing fixes the injection rate, ``\varepsilon``
is an *input*; the velocity scale ``u'`` and the Taylor-scale Reynolds number
``\mathrm{Re}_\lambda`` (expected ``\approx 79``) are *outputs* — their agreement between the two
codes is part of the test.

## Matching the smooth filter exactly

Both codes damp each mode by ``\exp(-s\,(\kappa/\kappa_{M})^{36})``, but they normalize
differently: TurTLE by ``\kappa_{M} = (N/2 - 1)`` (its highest mode with a nonzero conjugate
partner), this package by the Nyquist ``N/2``. The two filters are made *identical to machine
precision* by choosing this package's strength as

```math
s = 36\,\Bigl(1 - \frac{2}{N}\Bigr)^{-36},
```

which at ``N = 128`` gives ``s = 63.463`` — the value the run uses with
`HouLi(order = 36, strength = 63.463)`.

## The shared initial state

Both codes start the comparison window from **the same TurTLE-generated state**:

1. **Warm-up** (TurTLE): 50 large-eddy turnover times ``k/\varepsilon`` at the fixed timestep,
   from a random initial condition — long past the 15–20 turnovers the stationarity criteria
   require, leaving a stationary tail for reference statistics.
2. **Particle fill** (TurTLE): ``10^4`` tracers are seeded uniformly and advanced for a short
   segment (about 100 steps) so the fourth-order Adams–Bashforth integrator runs at full order
   with an authentic sample history — the low-order bootstrap values have long rotated out of its
   registers.
3. **Handoff**: the checkpoint at the end of the fill segment holds the complete joint state — the
   vorticity field in spectral representation, the tracer positions, and the four-slot
   Adams–Bashforth history. TurTLE continues from it natively; this package imports it (an axis
   permutation between the two storage layouts, the inverse curl
   ``\hat{\boldsymbol{u}} = \mathrm{i}\,\boldsymbol{\kappa} \times \hat{\boldsymbol{\omega}} / \lvert\boldsymbol{\kappa}\rvert^{2}``,
   and the particle history into the particle integrator's registers), with a round-trip witness
   pinning the conversion at machine precision.

Both codes interpolate the velocity to particle positions with the same scheme — the four-point
cubic spline (TurTLE's `I4O3`; this package's Catmull–Rom) — so the trajectory comparison tests
matched dynamics, not differing interpolants.

## Reproducing the comparison

*(Recipe to be completed alongside the results: the exact TurTLE launch commands, this package's
`Simulation` construction, the checkpoint-conversion script, and the shared analysis script.)*

- The warm-upped handoff state is published as a release asset (about 50 MiB):

  ```
  # placeholder — URL and SHA-256 recorded when the state is published
  curl -L -o warmup_checkpoint.h5 <release-asset-url>
  sha256sum warmup_checkpoint.h5   # must equal <sha256>
  ```

- TurTLE leg: build TurTLE 8.2.1 (`pip install .` in its source tree with MPI, parallel HDF5, and
  FFTW available), place the checkpoint, and continue with its `NSVEparticles` solver at the
  parameters above.
- This package's leg: construct the identical run and advance with fixed ``\Delta t``:

  ```julia
  using GBGIsotropicTurbulence
  sim = Simulation(grid_points_per_axis = 128, side_length = 2π,
                   viscosity = 9.032e-3,
                   dealiasing = HouLi(order = 36, strength = 63.463),
                   field_integration_scheme = IFSSPRK3(),
                   velocity_forcing = ConstantPower(injection_rate = 1.0,
                                                    lowest_shell = 1, highest_shell = 2))
  # state import and particle wiring: completed with the conversion script
  ```

## Results

### Stationary one-point statistics

Measured over the stationary tail of the comparison window. **Awaiting both legs.**

| quantity | this package | TurTLE | relative difference |
|:---|:---|:---|:---|
| ``u'`` | — | — | — |
| ``k`` | — | — | — |
| ``\varepsilon`` | — | — | — |
| ``\mathrm{Re}_\lambda`` | — | — | — |
| velocity-derivative skewness | — | — | — |

### Energy spectrum

Shell-by-shell comparison of ``E(\kappa)`` at matched output times. **Awaiting both legs.**

### Trajectory-level divergence

The maximum and mean particle-position separation as a function of time, against the
roundoff-seeded Lyapunov envelope. **Awaiting both legs.**

### Lagrangian velocity autocorrelation

Computed *post hoc* by one shared analysis script applied identically to both codes' trajectory
samples (neither code computes it in-run). **Awaiting both legs.**

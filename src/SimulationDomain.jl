# SimulationDomain — the discretized, periodic, cubic box a run lives on: the grid, the real–Fourier
# layout, the transform plans, the spectral multipliers, and the lazy per-mode kernels (|k|² and the
# dealias mask — compressed symbols, never materialized as arrays; decision 38).
# Reusable and read-only; precision and backend enter here (element_type / array_type) and flow
# everywhere from here. The concrete frame is `FixedDomain` (fixed, orthogonal, unsheared); a sheared
# (Rogallo) frame is deferred (ARCHITECTURE §7). Field-sized allocators (new_vector_field_spectral, …) build
# scratch fields sized to the domain.

"""
    SimulationDomain

The discretized periodic box a run lives on — the reusable, read-only frame:
- [`FixedDomain`](@ref) — the fixed, unsheared cubic box (grid, transform plans, spectral multipliers,
  and the lazy ``\\lvert\\boldsymbol{\\kappa}\\rvert^2`` and dealias kernels).
- [`DealiasingStrategy`](@ref) — the aliasing-control strategy, [`TwoThirds`](@ref), [`HouLi`](@ref), or
  [`PhaseShift`](@ref), and the two band edges it sets, [`max_retained_wavenumber`](@ref) and
  [`max_resolved_wavenumber`](@ref).
- [`new_vector_field_spectral`](@ref), [`new_vector_field_physical`](@ref),
  [`new_scalar_field_spectral`](@ref), [`new_scalar_field_physical`](@ref),
  [`new_tensor_field_spectral`](@ref), [`new_tensor_field_physical`](@ref) — the field allocators
  (a zeroed field of the named kind and representation, on the domain's backend and element type).
- [`truncate_to_band!`](@ref) — apply the dealias kernel to a field in spectral representation, in place.
- [`write_domain`](@ref) / [`read_domain`](@ref) — the domain's HDF5 persistence: one
  self-describing group of its defining parameters (available once `HDF5` is loaded).

Precision and backend enter here and flow everywhere from here.
"""
module SimulationDomain

using GBGPeriodicFields

export FixedDomain,
       new_vector_field_spectral, new_vector_field_physical, new_scalar_field_spectral, new_scalar_field_physical,
       new_tensor_field_spectral, new_tensor_field_physical,
       truncate_to_band!, DealiasingStrategy, TwoThirds, HouLi, PhaseShift,
       max_retained_wavenumber, max_resolved_wavenumber


# ── Dealiasing strategies ────────────────────────────────────────────────────────────────────────
# How the aliasing of the quadratic nonlinearity is controlled. Each strategy builds the `domain.dealias`
# kernel (applied by `truncate_to_band!`/`convolve!`) and declares the Nyquist fraction it keeps energetic,
# which sets the advective-CFL ceiling (see `recommended_cfl`).

"""
    DealiasingStrategy

How the aliasing of the quadratic nonlinearity is controlled. A [`FixedDomain`](@ref) is built
with one; it fixes the `domain.dealias` kernel and, through
[`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl), the advective-CFL
ceiling. They come in two families: a **mask** strategy
acts on the assembled product alone, while a **shift** strategy also changes how that product is
evaluated. The concrete strategies are [`TwoThirds`](@ref) (the sharp ``2/3`` rule, a mask),
[`HouLi`](@ref) (the smooth Hou–Li filter, a mask), and [`PhaseShift`](@ref) (the half-cell shift-average, a shift,
truncated spherically at ``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}``). The
[`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) constructor that builds a whole
run from a few keywords defaults to `TwoThirds`.
"""
abstract type DealiasingStrategy end

"""
    TwoThirds()

The sharp isotropic ``2/3``-rule truncation of Orszag (1971).
Keep the modes
``\\kappa \\le \\kappa_{\\max} = \\tfrac{2}{3}\\kappa_{\\mathrm{Ny}}`` and zero the rest, where
``\\kappa_{\\mathrm{Ny}} = \\tfrac{N}{2}\\cdot\\tfrac{2\\pi}{L}`` is the Nyquist wavenumber and
``\\kappa_{\\max}`` the dealiased maximum — two-thirds of the way out to Nyquist. It dealiases
the quadratic nonlinearity exactly, with the narrowest retained band of the three and no taper to evaluate.

# References
- Orszag, S. A. (1971). [*On the elimination of aliasing in finite-difference schemes by filtering high-wavenumber components*](https://doi.org/10.1175/1520-0469%281971%29028%3C1074:OTEOAI%3E2.0.CO;2). *J. Atmos. Sci.* **28**, 1074.
"""
struct TwoThirds <: DealiasingStrategy end

"""
    HouLi(; order = 36, strength = nothing, materialized = false)

The smooth spectral filter of Hou & Li (2007). Each mode is multiplied
by the transfer function
``\\exp\\bigl(- \\texttt{strength} (\\kappa/\\kappa_{\\mathrm{Ny}})^{\\texttt{order}}\\bigr)``,
applied isotropically in ``\\kappa``, with
``\\kappa_{\\mathrm{Ny}} = \\tfrac{N}{2}\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber. It keeps more
modes than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a
stabilization.

Because the filter retains energy out to the Nyquist wavenumber it takes a proportionally smaller
CFL step than the ``2/3`` rule — handled automatically by
[`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl).

# Arguments
- `order = 36` — the sharpness of the spectral roll-off; higher is closer to a sharp cutoff.
- `strength = nothing` — the damping at the Nyquist mode, which is multiplied by
  ``\\mathrm{e}^{-\\texttt{strength}}``. By default it is chosen for the domain's element type as
  ``-\\log`` of its machine epsilon — ``\\approx 36`` for
  [`Float64`](@extref Julia :jl:type:Core.Float64), ``\\approx 16`` for
  [`Float32`](@extref Julia :jl:type:Core.Float32) — so the Nyquist mode always damps to that
  precision's machine epsilon; pass a value to override.
- `materialized = false` — how the filter is *applied*, a memory-for-compute choice with no effect
  on the numbers. `false` keeps the filter as a closed-form radial symbol re-evaluated per mode in
  every pass: zero resident storage, the minimal-footprint side. `true` evaluates the same expression
  once into a stored coefficient array — one resident complex spectral scalar (``\\approx 17`` MB at
  ``128^3`` `Float64`, ``\\approx 136`` MB at ``256^3``) — that the passes then merely read. Because
  the coefficients are the same expression evaluated once, the two settings advance a run
  **bit-identically**.

Measured at ``128^3`` `Float64` on a GPU with `order = 36`: the on-the-fly evaluation costs
``\\approx 14\\%`` of the step, of which `materialized = true` recovers ``\\approx 7\\%`` — the
filter factor becomes an array read, while the integrating factor's own exponential remains.
Prefer `true` when compute is the scarce resource, `false` when memory is.

!!! note "Retained is not resolved"
    The filter keeps every mode energetic ([`max_retained_wavenumber`](@ref) is the Nyquist), but
    applying it every step adds a damping rate
    ``\\texttt{strength} (\\kappa/\\kappa_{\\mathrm{Ny}})^{\\texttt{order}}/\\Delta t`` that
    overtakes the viscous rate ``\\nu\\kappa^{2}`` near ``0.8 \\kappa_{\\mathrm{Ny}}`` at the
    default `order`; beyond that, mode amplitudes are set by the filter, not by Navier–Stokes.
    The resolution criterion ``\\kappa_{\\max}\\eta`` therefore uses
    [`max_resolved_wavenumber`](@ref), which is ``\\tfrac{4}{5} \\kappa_{\\mathrm{Ny}}`` under
    this strategy whatever the `order` — not the Nyquist (its docstring scopes the convention).

# References
- Hou, T. Y. & Li, R. (2007). [*Computing nearly singular solutions using pseudo-spectral methods*](https://doi.org/10.1016/j.jcp.2007.04.014). *J. Comput. Phys.* **226**, 379–397.

# Fields
The plain constructor `HouLi(order, strength, materialized)` takes the three fields directly:
- `order` — the exponent of the spectral roll-off.
- `strength` — the damping at the Nyquist mode, or `nothing` for the element-type default described
  above.
- `materialized` — whether the filter is stored coefficientwise rather than re-evaluated per mode.
"""
struct HouLi <: DealiasingStrategy
  order::Int
  strength::Union{Float64, Nothing}
  materialized::Bool
end
HouLi(; order::Integer = 36, strength::Union{Real, Nothing} = nothing,
        materialized::Bool = false) =
  HouLi(Int(order), isnothing(strength) ? nothing : Float64(strength), materialized)

"""
    PhaseShift()

Phase-shift dealiasing — Patterson & Orszag (1971), combined with the spherical truncation of
Rogallo (1981) — *Numerical experiments in homogeneous turbulence*, NASA TM-81315 (no DOI): assemble
each quadratic nonlinear term on the grid **and** on a grid displaced by half a cell, average the
two, and truncate spherically at
``\\kappa_{\\max} = \\tfrac{\\sqrt{2}}{3}N\\cdot\\tfrac{2\\pi}{L} = \\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}``
(with ``\\kappa_{\\mathrm{Ny}} = \\tfrac{N}{2}\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber).

The half-cell average cancels the aliasing images that wrap in an odd number of axes — the spurious
spectral replicas the under-resolved quadratic product folds back into the resolved band — and the
spherical cutoff removes the surviving two-axis images. It dealiases the quadratic **exactly** while
keeping the resolved band out to
``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}} \\approx 0.94 \\kappa_{\\mathrm{Ny}}`` — a factor ``\\sqrt{2}``
further than the [`TwoThirds`](@ref) rule's ``\\tfrac{2}{3}\\kappa_{\\mathrm{Ny}}``
(``\\approx 2.8\\times`` the modes in the retained sphere).

Use it when the recovered bulk of that discarded top third — out to
``\\approx 0.94\\kappa_{\\mathrm{Ny}}``, never the Nyquist-adjacent remainder — is worth the price: a **second** nonlinear-term transform
per stage (``2\\times`` the transforms) and the displaced-evaluation scratch (a field-scale
spectral-representation buffer per phase-shifted term). Because it retains energy out to
``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}`` it takes a proportionally smaller advective-CFL step
than the ``2/3`` rule — handled automatically by
[`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl).

!!! note "A half-cell shift attenuates the Nyquist mode"
    A half-cell displacement cannot translate the Nyquist mode of a real field — it *attenuates* it by
    ``\\cos(\\pi h_a/\\Delta x_a)``, which vanishes at half a cell. This never bites here: the spherical
    cutoff at ``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}} < \\kappa_{\\mathrm{Ny}}`` leaves the field with no
    Nyquist content to mistranslate.

# References
- Patterson, G. S. & Orszag, S. A. (1971). [*Spectral calculations of isotropic turbulence: efficient removal of aliasing interactions*](https://doi.org/10.1063/1.1693365). *Phys. Fluids* **14**, 2538–2541.
"""
struct PhaseShift <: DealiasingStrategy end

# The fraction of the Nyquist wavenumber a strategy keeps energetic — the retained band, which sets
# κ_max for the advective-CFL and bounds where seeding/forcing can put energy.
_retained_nyquist_fraction(::TwoThirds) = 2 // 3
_retained_nyquist_fraction(::HouLi) = 1 // 1
# Phase-shift keeps the spherical band to κ_max = √2·N/3·(2π/L) = (2√2/3)·κ_Ny (Rogallo).
_retained_nyquist_fraction(::PhaseShift) = 2 * sqrt(2) / 3

# The fraction of the Nyquist wavenumber a strategy RESOLVES — the band whose dynamics is genuine
# Navier–Stokes, the resolution criterion's κ_max (decision 82). For the sharp strategies the two
# fractions coincide (inside a sharp cutoff nothing is damped). Hou–Li's per-step filter is an extra
# damping rate strength·(κ/κ_Ny)^order/dt that crosses the viscous rate νκ² at
# κ/κ_Ny = (νκ_Ny²dt/strength)^(1/(order-2)); the 1/34 power (order 36) pins that crossover near
# 0.8 across any sane ν, dt, and strength — hence a constant 4/5 convention (also TurTLE's),
# not a per-run solve.
_resolved_nyquist_fraction(::TwoThirds) = 2 // 3
_resolved_nyquist_fraction(::HouLi) = 4 // 5
_resolved_nyquist_fraction(::PhaseShift) = 2 * sqrt(2) / 3


"""
    FixedDomain(; grid_points_per_axis, side_length, dealiasing, element_type,
                array_type, fft_flags = nothing, fft_timelimit = Inf)

The discretized periodic box a run lives on — the reusable, read-only frame: a cube of side length
`side_length` sampled with `grid_points_per_axis` points along each axis, holding everything the
pseudospectral method needs on that box.

# Arguments
All keyword; the five naming the box are required:
- `grid_points_per_axis` — grid points ``N`` along each axis (the box is ``N^{3}``).
- `side_length` — the physical side length ``L`` (the box is ``[0,L)^{3}``).
- `dealiasing` — the dealiasing strategy: [`TwoThirds`](@ref) (the sharp ``2/3`` rule) and [`HouLi`](@ref)
  (the smooth Hou–Li filter) apply [`truncate_to_band!`](@ref) as a coefficientwise multiply, while
  [`PhaseShift`](@ref) averages a half-cell-displaced evaluation (exact, keeping a fuller band at
  ``2\\times`` the transforms). It controls the aliasing of the quadratic nonlinearity and sets the
  advective-CFL ceiling through
  [`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl).
- `element_type` — the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) is GPU-friendly).
- `array_type` — the storage backend: [`Array`](@extref Julia :jl:type:Core.Array) (CPU) or
  [`CuArray`](@extref CUDA The-CuArray-type) / [`ROCArray`](@extref AMDGPU AMDGPU.ROCArray) (GPU);
  [Memory footprint on a GPU](@ref) sizes a run.
- `fft_flags = nothing`, `fft_timelimit = Inf` — the FFT planner request, forwarded to
  [`FieldTransformPlans`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldTransformPlans).
  On the CPU the default is FFTW's instant `ESTIMATE` heuristic, which can
  mis-plan single-precision transforms (measured 2–5× slow at ``256^3`` `Float32`; see the
  planner warning on `FieldTransformPlans`); for a long CPU run pass `FFTW.MEASURE` — the
  one-time plan search costs seconds. The GPU FFT libraries take no planner flag, so on a
  GPU backend the setting is inert.

# Examples

A default box, and one that keeps a wider band on the same grid:

```julia
domain = FixedDomain(; grid_points_per_axis = 128, side_length = 2π,
                       dealiasing = TwoThirds(), element_type = Float64,
                       array_type = Array)

wide = FixedDomain(; grid_points_per_axis = 128, side_length = 2π,
                     dealiasing = HouLi(), element_type = Float64, array_type = Array)
```

!!! note "Nothing here defaults"
    The grid, the box, the aliasing control, the precision and the storage backend are each a
    decision about the run; the
    [`Simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.Simulation) convenience constructor
    supplies them when you would rather not.

# Fields
The machinery types below are [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl)
objects, each linked to its own documentation.
- `grid`, `layout` — the [`Grid3D`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.Grid3D) and its
  [`RealFourierLayout`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.RealFourierLayout) memory layout.
- `transform_plans` — the real-to-complex
  [`FieldTransformPlans`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldTransformPlans),
  one pair for every field whatever its tensor order: the plans transform one component and are
  applied per component, so the velocity, the scalar, and the rank-2 strain tensor all use
  this one object.
- `multipliers` — the
  [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers),
  the spectral first-derivative operators.
- `squared_wavenumber_kernel` — ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` as a lazy
  [`RadialKernel`](@extref GBGPeriodicFields GBGPeriodicFields.Convolution.RadialKernel) (in spectral
  representation ``-\\nabla^{2}`` acts as multiplication by it) — the weight that turns a Parseval sum into a mean-square-gradient
  (Dirichlet-energy) sum, which the weighted spectral reductions take; never materialized — evaluated per mode from the multipliers,
  with no array allocated.
- `unit_kernel` — the constant weight ``1``, the same lazy form: the identity weight that lets a plain
  variance join a multi-weight fused reduction (one traversal answering several weighted sums at
  once), since ``\\langle f, 1\\cdot f\\rangle`` is the mean square — the variance of a
  mean-zero field.
- `storage_family` — the storage family (`Array` /
  `CuArray` / `ROCArray`) the run's arrays live in — a type,
  not an array; the allocators hand it to `GBGPeriodicFields`' family-taking field constructors.
- `dealias`, `dealiasing` — the dealias kernel (a compressed
  [`SpectralKernel`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.SpectralKernel), evaluated per
  mode) and the [`DealiasingStrategy`](@ref) that built it.
"""
struct FixedDomain{G, L, TP, M, SK, UK, D, DS, SF}
  grid::G
  layout::L
  transform_plans::TP              # ONE rank-blind plan pair (PF decision 76) — every field, every rank
  multipliers::M
  squared_wavenumber_kernel::SK    # |k|² as a lazy RadialKernel — the Dirichlet-energy weight for `weighted_inner`
  unit_kernel::UK                  # the constant-1 weight, same lazy form — lets a variance join a fused multi-weight reduction
  dealias::D                       # isotropic low-pass kernel (compressed, per-mode), built by `dealiasing`
  dealiasing::DS                   # the DealiasingStrategy that built `dealias` (TwoThirds / HouLi / PhaseShift)
  storage_family::SF               # the storage family (`Array`, `CuArray`, `ROCArray`) — a TYPE, not an array:
                                   # what the allocators hand PF's family-taking constructors (PF decision 74)
end


_zeros(array_type, ::Type{S}, dims::Tuple) where {S} = fill!(array_type{S}(undef, dims...), zero(S))


_unit_symbol(κ²) = one(κ²)


function FixedDomain(; grid_points_per_axis::Integer, side_length::Real,
                       dealiasing::DealiasingStrategy,
                       element_type::Type{T},
                       array_type,
                       fft_flags = nothing, fft_timelimit::Real = Inf) where {T<:AbstractFloat}
  N = Int(grid_points_per_axis)
  L = T(side_length)
  grid = Grid3D((N, N, N), (L, L, L))
  layout = RealFourierLayout()

  # ONE plan pair serves every field since PF's decision 76 made the plans rank-blind: they
  # transform a single component and are applied per component, so the velocity (3), the scalar (1)
  # and the strain tensor (9) share this object. Built from the storage family and the grid alone
  # (PF decision 93): the planner plans on one-component arrays of its own, so a timed planner
  # (`MEASURE`) clobbers nothing of the run's, and no template field is built here for it.
  transform_plans = FieldTransformPlans(array_type, grid, layout;
                                        fft_flags, fft_timelimit = Float64(fft_timelimit))
  # The multipliers from the storage family and the grid alone (PF decision 94): no template field.
  multipliers = FieldSpectralMultipliers(array_type, grid, layout)
  # |κ|² as the identity radial symbol — evaluated per mode from the multipliers' axis arrays, so it
  # occupies no field (the stored |κ|² arrays this frame once carried are gone with PF's decision 60).
  squared_wavenumber_kernel = radial_kernel(identity, multipliers)
  # The constant-1 symbol under the same lazy form, so a whole-field variance can ride the SAME
  # fused traversal as its weighted siblings (inner(f, f) == weighted_inner(f, unit), verified
  # against the backend). A named function, not a closure: the kernel's type is then a constant
  # across constructions, which keeps every downstream specialization stable.
  unit_kernel = radial_kernel(_unit_symbol, multipliers)
  dealias = _build_dealias(dealiasing, multipliers, N, L, T)

  return FixedDomain(grid, layout, transform_plans, multipliers, squared_wavenumber_kernel, unit_kernel, dealias, dealiasing, array_type)
end


# Build the `domain.dealias` kernel for a strategy — each a compressed radial kernel (a symbol of
# |κ|², evaluated per mode), so no strategy stores a field of coefficients.
# Both sharp strategies keep a ball of radius (retained fraction)·κ_Ny. The fraction is read from
# `_retained_nyquist_fraction` rather than re-spelled here, so the band this BUILDS and the cutoff
# `max_retained_wavenumber` REPORTS cannot drift apart.
# The retained cutoff, in ONE expression and ONE element type. Computing it as
# `T(fraction) * (N/2) * (2π/L)` here while `max_retained_wavenumber` reported
# `fraction * (N/2) * (2π/L)` in Float64 made the two disagree on a Float32 grid: rounding the
# fraction to Float32 FIRST lands slightly above the exact 2/3, so the band actually built was wider
# than the cutoff advertised — and κ_max·η, the resolution criterion a run is judged by, was
# computed from the advertised one.
_cutoff_wavenumber(strategy, N, L, ::Type{T}) where {T} =
  T(_retained_nyquist_fraction(strategy)) * T(N / 2) * T(2π / L)

# The resolved cutoff, same one-expression/one-element-type discipline, from the resolved fraction.
_resolved_wavenumber(strategy, N, L, ::Type{T}) where {T} =
  T(_resolved_nyquist_fraction(strategy)) * T(N / 2) * T(2π / L)

# Both sharp masks keep the CLOSED ball — boundary shell included — and that is EXACT for this
# formulation, not an oversight. The textbook worry: at cutoff N/3, a product of two boundary modes
# can alias back into the ball (N/3 + N/3 → −N/3). Expanded for THIS discretization, the only pair
# whose image lands inside the ball is the axis self-pair (N/3,0,0)+(N/3,0,0) — every other boundary
# pair either does not wrap past Nyquist or lands outside the mask — and that image is a PURE
# GRADIENT (the single-mode Lamb vector is −∇(|u|²/2), since u·∇u vanishes for one mode, and its alias stays gradient-shaped), which
# the Leray projection annihilates exactly; the scalar's aliased flux is transverse to its
# wavevector, so the divergence kills it the same way. Demonstrated against a 2N zero-padded oracle
# at N = 12 (3|N, every stored boundary mode populated): the closed ball matches to 1.5e-16 ON the
# boundary shell — the regression test pins it. A strict edge (√(N²−1)/3, after TurTLE) was tried
# 2026-08-23 and REVERTED: it buys no exactness here and shrinks the band; the references cut
# strictly below for their own formulations. PhaseShift's closed ball at √2·N/3 is likewise
# oracle-exact — the shift-average cancels the single-alias images outright.
_build_dealias(strategy::Union{TwoThirds, PhaseShift}, multipliers, N, L, ::Type{T}) where {T} =
  spectral_cutoff(multipliers, _cutoff_wavenumber(strategy, N, L, T))

function _build_dealias(strategy::HouLi, multipliers, N, L, ::Type{T}) where {T}
  # The smooth filter is a closed-form radial symbol; the closure captures VALUES only (a captured
  # `Type` is not a bitstype and a GPU launch rejects it — PF's radial-kernel contract).
  inverse_nyquist = one(T) / T((N / 2) * (2π / L))
  strength = T(isnothing(strategy.strength) ? -log(eps(T)) : strategy.strength)
  order = strategy.order
  kernel = radial_kernel(k2 -> exp(-strength * (sqrt(k2) * inverse_nyquist)^order), multipliers)
  # `materialized` trades one resident spectral scalar for the per-mode exp/power chain every
  # pass would otherwise re-evaluate (decision 84); the stored coefficients are the SAME closure
  # evaluated once, so the two forms advance a run bit-identically.
  return strategy.materialized ? materialize_kernel(kernel) : kernel
end


# Internal: the array type and element type are read off the multipliers' axis arrays — O(N) vectors
# that live on the domain's backend — so every scratch buffer lands on the same backend (CPU/GPU), the
# The element type is the grid's own — PF's family-taking constructors state that contract — and
# the backend is the stored family, so no borrowed array stands witness for either (the
# `_reference`/`_blank` composition this replaces read a multipliers axis vector off-label; PF
# decision 74 closed it at the source).
_real_type(domain::FixedDomain) = eltype(domain.grid.domain_size)



"""
    max_retained_wavenumber(domain)

The highest wavenumber magnitude `domain` (a [`FixedDomain`](@ref)) keeps energetic — the dealiasing
cutoff, the edge of the **retained** band

```math
\\kappa_{\\max}^{\\mathrm{ret}} = f_{\\mathrm{ret}} \\frac{N}{2} \\frac{2\\pi}{L},
```

with ``N`` the grid points per side, ``L`` the box side, ``f_{\\mathrm{ret}}`` the retained-Nyquist
fraction of the [`DealiasingStrategy`](@ref) (``2/3`` for `TwoThirds`, ``1`` for `HouLi`,
``\\tfrac{2\\sqrt{2}}{3}`` for `PhaseShift`). For the sharp strategies the cutoff sits strictly
**below** the grid Nyquist ``\\tfrac{N}{2}\\tfrac{2\\pi}{L}`` — they zero the modes above it each
step. `HouLi` is the exception its ``f_{\\mathrm{ret}} = 1`` implies: it zeroes nothing, damping
modes progressively as they approach the Nyquist (to machine epsilon there), so its retained band is
the whole representable band.

Retained is not resolved: a mode can carry energy while its dynamics is dominated by the filter
rather than by Navier–Stokes — [`max_resolved_wavenumber`](@ref) bounds the trusted band. The
retained cutoff is the one for everything that must see every energetic mode: the advective-CFL
step ([`recommended_cfl`](@ref GBGHomogeneousTurbulence.Propagator.recommended_cfl)), the random-seed
spectrum, and the empty-shell warnings of the forcing layer.
"""
function max_retained_wavenumber(domain::FixedDomain)
  N = field_physical_shape(domain.grid, Val(0))[1]
  L = domain.grid.domain_size[1]
  # Through the same expression, in the same element type, that `_build_dealias` truncates with —
  # so the number reported here is the band the domain actually keeps.
  return _cutoff_wavenumber(domain.dealiasing, N, L, typeof(L))
end


"""
    max_resolved_wavenumber(domain)

The highest wavenumber magnitude whose dynamics `domain` (a [`FixedDomain`](@ref)) resolves as
genuine Navier–Stokes — the **resolved**-band edge

```math
\\kappa_{\\max}^{\\mathrm{res}} = f_{\\mathrm{res}} \\frac{N}{2} \\frac{2\\pi}{L},
```

with ``N`` the grid points per side, ``L`` the box side, ``f_{\\mathrm{res}}`` the resolved-Nyquist
fraction of the [`DealiasingStrategy`](@ref) (``2/3`` for `TwoThirds`, ``4/5`` for `HouLi`,
``\\tfrac{2\\sqrt{2}}{3}`` for `PhaseShift`). This is the ``\\kappa_{\\max}`` of the resolution
criterion ``\\kappa_{\\max}\\eta`` — with ``\\eta`` the Kolmogorov (dissipation) microscale — that a
run is set up to meet.

For the sharp strategies resolved and retained coincide: inside a sharp cutoff no mode is damped.
Under `HouLi` they differ, because the filter applied every step acts as an extra damping rate
``\\mathrm{strength} (\\kappa/\\kappa_{\\mathrm{Ny}})^{\\mathrm{order}}/\\Delta t`` that overtakes
the viscous rate ``\\nu\\kappa^{2}`` near ``0.8 \\kappa_{\\mathrm{Ny}}`` at the default
`order = 36` — beyond that crossover the dynamics is filter-dominated and the energy there is
numerical residue, not resolved turbulence.

The ``4/5`` value is a convention, but a robust one: the crossover scales as the
``1/(\\mathrm{order} - 2)``-th power — the ``1/34``-th at the default — of
``\\nu \\kappa_{\\mathrm{Ny}}^{2} \\Delta t/\\mathrm{strength}``, so it stays near ``0.8`` for
any practical viscosity, timestep, and filter strength. The convention is pinned to the default
order: a `HouLi` built with another `order` still reports ``\\tfrac{4}{5}``, which overstates the
resolved range at a lower order (the crossover moves inward) and understates it at a higher one.
"""
function max_resolved_wavenumber(domain::FixedDomain)
  N = field_physical_shape(domain.grid, Val(0))[1]
  L = domain.grid.domain_size[1]
  return _resolved_wavenumber(domain.dealiasing, N, L, typeof(L))
end


"""
    new_vector_field_spectral(domain)

Allocate a single zeroed vector field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_vector_field_spectral(domain::FixedDomain) =
  (f = VectorFieldSpectral(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    new_vector_field_physical(domain)

Allocate a single zeroed vector field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_vector_field_physical(domain::FixedDomain) =
  (f = VectorFieldPhysical(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    new_scalar_field_spectral(domain)

Allocate a single zeroed scalar field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_scalar_field_spectral(domain::FixedDomain) =
  (f = ScalarFieldSpectral(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    new_scalar_field_physical(domain)

Allocate a single zeroed scalar field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_scalar_field_physical(domain::FixedDomain) =
  (f = ScalarFieldPhysical(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    new_tensor_field_spectral(domain)

Allocate a single zeroed second-order tensor field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_tensor_field_spectral(domain::FixedDomain) =
  (f = TensorFieldSpectral(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    new_tensor_field_physical(domain)

Allocate a single zeroed second-order tensor field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_tensor_field_physical(domain::FixedDomain) =
  (f = TensorFieldPhysical(domain.storage_family, domain.grid, domain.layout);
   fill!(field_data(f), zero(eltype(field_data(f)))); f)


"""
    truncate_to_band!(field, domain)

Apply the run's dealias low-pass kernel `domain.dealias` — `domain` a [`FixedDomain`](@ref) — to
`field` in place: a coefficientwise multiply that
controls the aliasing of the quadratic nonlinearity. The kernel is whatever the run's
[`DealiasingStrategy`](@ref) built: the sharp ``2/3`` cutoff ([`TwoThirds`](@ref), exact dealiasing),
the smooth [`HouLi`](@ref) filter (which only damps the aliasing), or the spherical
``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}`` truncation ([`PhaseShift`](@ref)). The `field` may be a vector or
scalar field in spectral representation. Returns `field`.

!!! note "This verb truncates; under PhaseShift that is half the dealiasing"
    For `TwoThirds` this call is the whole of it; for `HouLi` the taper damps the aliases rather than
    removing them. Under `PhaseShift` it is only the second half — a product assembled without the
    displaced-evaluation average stays aliased, so a hand-built assembly must pair the two as the
    generator does.
"""
truncate_to_band!(field, domain::FixedDomain) = convolve!(field, field, domain.dealias)



# ————————————————————————————————————————————————————————————————————————————————————————————————
# Display. Every concrete type of the package shows itself, on the field library's two-form
# convention (PF decision 82): the two-argument `show` is ONE self-delimiting line, `Type(body)`,
# the form containers, string interpolation, and error messages reach; the three-argument
# `MIME"text/plain"` form is the REPL's and may spend lines. The body carries what a check REFUSES
# on — two objects a constructor would reject together must render differently — in the one
# vocabulary `name value`, spelling a size `32×32×32` and a count `500 points`; the `name = value`
# form is reserved for a display that IS the constructor call (`HouLi(order = 24)`, which round-trips).
# A nested field-library object prints through its own `show`, so a domain, a state, or a buffer
# set never restates the grid the library already spells. NOTHING here reads an element: a display
# holds under `allowscalar(false)`, and never touches a device array. The gate is `test/display.jl`.

# The constructor call, printing only what departs from the defaults — `HouLi()` at the defaults.
function Base.show(io::IO, strategy::HouLi)
  default = HouLi()
  parts = String[]
  strategy.order == default.order || push!(parts, "order = $(strategy.order)")
  strategy.strength === default.strength || push!(parts, "strength = $(strategy.strength)")
  strategy.materialized == default.materialized || push!(parts, "materialized = $(strategy.materialized)")
  print(io, "HouLi(", join(parts, ", "), ")")
end

# The grid (size, extent, element type — the library's spelling) and the storage family, which a run
# checks a state against before adopting it (a tracer set against the storage family alone), and
# the dealiasing strategy, which decides what assembly scratch a generator is built with. The REPL
# form adds the resolved wavenumber the strategy leaves — the one number the resolution checks
# (``\kappa_{\max}\eta``) read a strategy through — beside the grid and strategy it derives from.
Base.show(io::IO, domain::FixedDomain) =
  print(io, "FixedDomain(", domain.grid, ", ", domain.dealiasing, ", ", nameof(domain.storage_family), ")")

function Base.show(io::IO, ::MIME"text/plain", domain::FixedDomain)
  print(io, "FixedDomain")
  print(io, "\n  grid        ", domain.grid)
  print(io, "\n  dealiasing  ", domain.dealiasing, ", max_resolved_wavenumber ", max_resolved_wavenumber(domain))
  print(io, "\n  storage     ", nameof(domain.storage_family))
end



# ————————————————————————————————————————————————————————————————————————————————————————————————
# HDF5 persistence. The bare generics live here so the docstrings and the docs build work without
# HDF5 in the environment; the methods live in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded automatically alongside the HDF5 package (the arrangement the field library's
# persistence pairs established).

export write_domain, read_domain


"""
    write_domain(parent::HDF5.H5DataStore, name::AbstractString, domain::FixedDomain)

Write the [`FixedDomain`](@ref) `domain` under `parent` as one self-describing HDF5 group — its
defining parameters (the grid points per axis, the side length, the element type, and the
dealiasing strategy with its settings), never the derived machinery (transform plans, multipliers,
kernels), which the reader rebuilds. Available once the `HDF5` package is loaded; opening and
closing the file is the caller's job.

# Arguments
- `parent` — the open HDF5 file or group to write under.
- `name` — the created group's name.
- `domain` — the `FixedDomain` to record.

Returns the created group. Reload with [`read_domain`](@ref).
"""
function write_domain end


"""
    read_domain(parent::HDF5.H5DataStore, name::AbstractString;
                array_type = Array) -> FixedDomain

Rebuild a [`FixedDomain`](@ref) from the group [`write_domain`](@ref) wrote — the recorded
parameters through the ordinary constructor, so the transform plans, multipliers and kernels are
rebuilt, never read. A group that was not written by `write_domain`, or was written by a newer
schema version, is refused with an `ArgumentError`. Available once the `HDF5` package is loaded.

# Arguments
- `parent` — the open HDF5 file or group holding the domain group.
- `name` — the group's name.
- `array_type = Array` — the storage backend the rebuilt domain lives on. The backend is
  deliberately not taken from the file: a checkpoint written on one backend loads on any other, so
  the reader, not the writer, names it.
"""
function read_domain end


end # module SimulationDomain

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
  [`PhaseShift`](@ref), and the cutoff it sets, [`max_wavenumber`](@ref).
- [`new_vector_field_spectral`](@ref), [`new_vector_field_physical`](@ref),
  [`new_scalar_field_spectral`](@ref), [`new_scalar_field_physical`](@ref),
  [`new_tensor_field_spectral`](@ref), [`new_tensor_field_physical`](@ref) — the field allocators
  (a zeroed field of the named kind and representation, on the domain's backend and element type).
- [`truncate_to_band!`](@ref) — apply the dealias kernel to a field in spectral representation, in place.

Precision and backend enter here and flow everywhere from here.
"""
module SimulationDomain

using GBGPeriodicFields

export FixedDomain,
       new_vector_field_spectral, new_vector_field_physical, new_scalar_field_spectral, new_scalar_field_physical,
       new_tensor_field_spectral, new_tensor_field_physical,
       truncate_to_band!, DealiasingStrategy, TwoThirds, HouLi, PhaseShift, max_wavenumber

# ── Dealiasing strategies ────────────────────────────────────────────────────────────────────────
# How the aliasing of the quadratic nonlinearity is controlled. Each strategy builds the `domain.dealias`
# kernel (applied by `truncate_to_band!`/`convolve!`) and declares the Nyquist fraction it keeps energetic,
# which sets the advective-CFL ceiling (see `recommended_cfl`).

"""
    DealiasingStrategy

How the aliasing of the quadratic nonlinearity is controlled. A [`FixedDomain`](@ref) is built
with one; it fixes the `domain.dealias` kernel and, through
[`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl), the advective-CFL
ceiling. They come in two families: a **mask** strategy
acts on the assembled product alone, while a **shift** strategy also changes how that product is
evaluated. Concrete strategies: [`TwoThirds`](@ref) (the sharp ``2/3`` rule, a mask),
[`HouLi`](@ref) (the smooth Hou–Li filter, a mask), and [`PhaseShift`](@ref) (the half-cell shift-average, a shift,
truncated spherically at ``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}``). The default is chosen
by the [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation)
constructor that builds a whole run from a few keywords — the **front door**.
"""
abstract type DealiasingStrategy end

"""
    TwoThirds()

The sharp isotropic ``2/3``-rule truncation of Orszag (1971) — *On the elimination of aliasing in
finite-difference schemes by filtering high-wavenumber components*, *J. Atmos. Sci.* **28**, 1074,
[*On the elimination of aliasing in finite-difference schemes by filtering high-wavenumber components*](https://doi.org/10.1175/1520-0469%281971%29028%3C1074:OTEOAI%3E2.0.CO;2).
Keep the modes
``\\kappa \\le \\kappa_{\\max} = \\tfrac{2}{3}\\kappa_{\\mathrm{Ny}}`` and zero the rest, where
``\\kappa_{\\mathrm{Ny}} = \\tfrac{N}{2}\\cdot\\tfrac{2\\pi}{L}`` is the Nyquist wavenumber and
``\\kappa_{\\max}`` the dealiased maximum — two-thirds of the way out to Nyquist. Exact dealiasing
of the quadratic nonlinearity, with the narrowest retained band of the three and no taper to evaluate.
"""
struct TwoThirds <: DealiasingStrategy end

"""
    HouLi(; order = 36, strength = nothing)

The smooth spectral filter of Hou & Li (2007) — *Computing nearly singular solutions using
pseudo-spectral methods*, *J. Comput. Phys.* **226**, 379–397,
[*Computing nearly singular solutions using pseudo-spectral methods*](https://doi.org/10.1016/j.jcp.2007.04.014). Each mode is multiplied
by the transfer function
``\\exp\\!\\bigl(- \\texttt{strength} (\\kappa/\\kappa_{\\mathrm{Ny}})^{\\texttt{order}}\\bigr)``,
applied isotropically in ``\\kappa``, with
``\\kappa_{\\mathrm{Ny}} = \\tfrac{N}{2}\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber. It keeps more
modes than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a
stabilization.

The `order` sets the sharpness of the spectral roll-off (higher is closer to a sharp cutoff). The
`strength` sets the damping at the Nyquist mode, which is multiplied by
``\\mathrm{e}^{-\\texttt{strength}}``. By default (`strength = nothing`) `strength` is chosen for the
domain's element type as ``-\\log`` of its machine epsilon — ``\\approx 36`` for
[`Float64`](@extref Julia :jl:type:Core.Float64), ``\\approx 16`` for
[`Float32`](@extref Julia :jl:type:Core.Float32) — so the Nyquist mode always damps to that
precision's machine epsilon; pass an explicit `strength` to override.

Because the filter retains energy out to the Nyquist wavenumber it takes a proportionally smaller
CFL step than the ``2/3`` rule — handled automatically by
[`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl).

# Fields
The plain constructor `HouLi(order, strength)` takes the two fields directly:
- `order` — the exponent of the spectral roll-off.
- `strength` — the damping at the Nyquist mode, or `nothing` for the element-type default described
  above.
"""
struct HouLi <: DealiasingStrategy
  order::Int
  strength::Union{Float64, Nothing}
end
HouLi(; order::Integer = 36, strength::Union{Real, Nothing} = nothing) =
  HouLi(Int(order), isnothing(strength) ? nothing : Float64(strength))

"""
    PhaseShift()

Phase-shift dealiasing — Patterson & Orszag (1971) — *Spectral calculations of isotropic turbulence:
efficient removal of aliasing interactions*, *Phys. Fluids* **14**, 2538–2541,
[*Spectral calculations of isotropic turbulence: efficient removal of aliasing interactions*](https://doi.org/10.1063/1.1693365), combined with the spherical truncation of
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

Use it when that top third of wavenumbers is worth the price: a **second** nonlinear-term transform
per stage (``2\\times`` the transforms) and the displaced-evaluation scratch (a field-scale
spectral-representation buffer per phase-shifted term). Because it retains energy out to
``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}}`` it takes a proportionally smaller advective-CFL step
than the ``2/3`` rule — handled automatically by
[`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl).

!!! note "A half-cell shift attenuates the Nyquist mode"
    A half-cell displacement cannot translate the Nyquist mode of a real field — it *attenuates* it by
    ``\\cos(\\pi h_a/\\Delta x_a)``, which vanishes at half a cell. This never bites here: the spherical
    cutoff at ``\\tfrac{2\\sqrt{2}}{3}\\kappa_{\\mathrm{Ny}} < \\kappa_{\\mathrm{Ny}}`` leaves the field with no
    Nyquist content to mistranslate.
"""
struct PhaseShift <: DealiasingStrategy end

# The fraction of the Nyquist wavenumber a strategy keeps energetic — sets κ_max for the advective-CFL.
_retained_nyquist_fraction(::TwoThirds) = 2 // 3
_retained_nyquist_fraction(::HouLi) = 1 // 1
# Phase-shift keeps the spherical band to κ_max = √2·N/3·(2π/L) = (2√2/3)·κ_Ny (Rogallo).
_retained_nyquist_fraction(::PhaseShift) = 2 * sqrt(2) / 3


"""
    FixedDomain(; grid_points_per_axis, side_length,
                dealiasing, element_type, array_type)

The discretized periodic box a run lives on — the reusable, read-only frame: a cube of side length
`side_length` sampled with `grid_points_per_axis` points along each axis, holding everything the
pseudospectral method needs on that box.

# Arguments
All keyword, all required:
- `grid_points_per_axis` — grid points ``N`` along each axis (the box is ``N^{3}``).
- `side_length` — the physical side length ``L`` (the box is ``[0,L)^{3}``).
- `dealiasing` — the dealiasing strategy: [`TwoThirds`](@ref) (the sharp ``2/3`` rule) and [`HouLi`](@ref)
  (the smooth Hou–Li filter) apply [`truncate_to_band!`](@ref) as a coefficientwise multiply, while
  [`PhaseShift`](@ref) averages a half-cell-displaced evaluation (exact, keeping a fuller band at
  ``2\\times`` the transforms). It controls the aliasing of the quadratic nonlinearity and sets the
  advective-CFL ceiling through
  [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl).
- `element_type` — the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) is GPU-friendly).
- `array_type` — the storage backend: [`Array`](@extref Julia :jl:type:Core.Array) (CPU) or
  [`CuArray`](@extref CUDA The-CuArray-type) / [`ROCArray`](@extref AMDGPU AMDGPU.ROCArray) (GPU).

# Examples

A default box, and one that keeps a wider band on the same grid:

```julia
domain = FixedDomain(; grid_points_per_axis = 128, side_length = 2π,
                       dealiasing = TwoThirds(), element_type = Float64, array_type = Array)

wide = FixedDomain(; grid_points_per_axis = 128, side_length = 2π,
                     dealiasing = HouLi(), element_type = Float64, array_type = Array)
```

!!! note "Nothing here defaults"
    The grid, the box, the aliasing control, the precision and the storage backend are each a
    decision about the run; the
    [`Simulation`](@ref GBGIsotropicTurbulence.SimulationRun.Simulation) convenience constructor
    supplies them for you when you do not want to make them.

# Fields
The machinery types below are [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl)
objects, each linked to its own documentation.
- `grid`, `layout` — the [`Grid3D`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.Grid3D) and its
  [`RealFourierLayout`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.RealFourierLayout) memory layout.
- `velocity_plans`, `scalar_plans`, `tensor_plans` — the real-to-complex
  [`FieldTransformPlans`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldTransformPlans), one per
  field rank: the velocity (a vector field), the scalar (a scalar field), and the rank-2 strain tensor the
  derivative-skewness diagnostic needs.
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
  once), since ``\\langle f, 1\\cdot f\\rangle`` is the variance itself.
- `dealias`, `dealiasing` — the dealias kernel (a compressed
  [`SpectralKernel`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.SpectralKernel), evaluated per
  mode) and the [`DealiasingStrategy`](@ref) that built it.
"""
struct FixedDomain{G, L, VP, SP, TP, M, SK, UK, D, DS}
  grid::G
  layout::L
  velocity_plans::VP
  scalar_plans::SP
  tensor_plans::TP                 # rank-2 transform plans (the strain-tensor diagnostic)
  multipliers::M
  squared_wavenumber_kernel::SK    # |k|² as a lazy RadialKernel — the Dirichlet-energy weight for `weighted_inner`
  unit_kernel::UK                  # the constant-1 weight, same lazy form — lets a variance join a fused multi-weight reduction
  dealias::D                       # isotropic low-pass kernel (compressed, per-mode), built by `dealiasing`
  dealiasing::DS                   # the DealiasingStrategy that built `dealias` (TwoThirds / HouLi / PhaseShift)
end


_zeros(array_type, ::Type{S}, dims::Tuple) where {S} = fill!(array_type{S}(undef, dims...), zero(S))


_unit_symbol(κ²) = one(κ²)


function FixedDomain(; grid_points_per_axis::Integer, side_length::Real,
                       dealiasing::DealiasingStrategy,
                       element_type::Type{T},
                       array_type) where {T<:AbstractFloat}
  N = Int(grid_points_per_axis)
  L = T(side_length)
  grid = Grid3D((N, N, N), (L, L, L))
  layout = RealFourierLayout()

  velocity_physical = VectorFieldPhysical((x, y, z) -> (zero(T), zero(T), zero(T)), grid; array_type)
  velocity_spectral = VectorFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
  scalar_physical_template = ScalarFieldPhysical((x, y, z) -> zero(T), grid; array_type)
  scalar_spectral_storage = ScalarFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)

  velocity_plans = FieldTransformPlans(velocity_physical, velocity_spectral)
  scalar_plans = FieldTransformPlans(scalar_physical_template, scalar_spectral_storage)
  tensor_physical_template = TensorFieldPhysical(_zeros(array_type, T, physical_field_shape(grid, Val(2))), grid)
  tensor_spectral_template = TensorFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid)
  tensor_plans = FieldTransformPlans(tensor_physical_template, tensor_spectral_template)
  multipliers = FieldSpectralMultipliers(velocity_spectral)
  # |κ|² as the identity radial symbol — evaluated per mode from the multipliers' axis arrays, so it
  # occupies no field (the stored |κ|² arrays this frame once carried are gone with PF's decision 60).
  squared_wavenumber_kernel = radial_kernel(identity, multipliers)
  # The constant-1 symbol under the same lazy form, so a whole-field variance can ride the SAME
  # fused traversal as its weighted siblings (inner(f, f) == weighted_inner(f, unit), verified
  # against the backend). A named function, not a closure: the kernel's type is then a constant
  # across constructions, which keeps every downstream specialization stable.
  unit_kernel = radial_kernel(_unit_symbol, multipliers)
  dealias = _build_dealias(dealiasing, velocity_spectral, multipliers, N, L, T)

  return FixedDomain(grid, layout, velocity_plans, scalar_plans, tensor_plans, multipliers, squared_wavenumber_kernel, unit_kernel, dealias, dealiasing)
end


# Build the `domain.dealias` kernel for a strategy — each a compressed radial kernel (a symbol of
# |κ|², evaluated per mode), so no strategy stores a field of coefficients.
# Both sharp strategies keep a ball of radius (retained fraction)·κ_Ny. The fraction is read from
# `_retained_nyquist_fraction` rather than re-spelled here, so the band this BUILDS and the cutoff
# `max_wavenumber` REPORTS cannot drift apart.
# The retained cutoff, in ONE expression and ONE element type. Computing it as
# `T(fraction) * (N/2) * (2π/L)` here while `max_wavenumber` reported `fraction * (N/2) * (2π/L)` in
# Float64 made the two disagree on a Float32 grid: rounding the fraction to Float32 FIRST lands
# slightly above the exact 2/3, so the band actually built was wider than the cutoff advertised —
# and κ_max·η, the resolution criterion a run is judged by, was computed from the advertised one.
_cutoff_wavenumber(strategy, N, L, ::Type{T}) where {T} =
  T(_retained_nyquist_fraction(strategy)) * T(N / 2) * T(2π / L)

# Both sharp masks keep the CLOSED ball — boundary shell included — and that is EXACT for this
# formulation, not an oversight. The textbook worry: at cutoff N/3, a product of two boundary modes
# can alias back into the ball (N/3 + N/3 → −N/3). Expanded for THIS discretization, the only pair
# whose image lands inside the ball is the axis self-pair (N/3,0,0)+(N/3,0,0) — every other boundary
# pair either does not wrap past Nyquist or lands outside the mask — and that image is a PURE
# GRADIENT (the single-mode Lamb vector is ∇(|u|²/2), and its alias stays gradient-shaped), which
# the Leray projection annihilates exactly; the scalar's aliased flux is transverse to its
# wavevector, so the divergence kills it the same way. Demonstrated against a 2N zero-padded oracle
# at N = 12 (3|N, every stored boundary mode populated): the closed ball matches to 1.5e-16 ON the
# boundary shell — the regression test pins it. A strict edge (√(N²−1)/3, after TurTLE) was tried
# 2026-08-23 and REVERTED: it buys no exactness here and shrinks the band; the references cut
# strictly below for their own formulations. PhaseShift's closed ball at √2·N/3 is likewise
# oracle-exact — the shift-average cancels the single-alias images outright.
_build_dealias(strategy::Union{TwoThirds, PhaseShift}, reference, multipliers, N, L, ::Type{T}) where {T} =
  spectral_cutoff(multipliers, _cutoff_wavenumber(strategy, N, L, T))

function _build_dealias(strategy::HouLi, reference, multipliers, N, L, ::Type{T}) where {T}
  # The smooth filter is a closed-form radial symbol; the closure captures VALUES only (a captured
  # `Type` is not a bitstype and a GPU launch rejects it — PF's radial-kernel contract).
  inverse_nyquist = one(T) / T((N / 2) * (2π / L))
  strength = T(isnothing(strategy.strength) ? -log(eps(T)) : strategy.strength)
  order = strategy.order
  return radial_kernel(k2 -> exp(-strength * (sqrt(k2) * inverse_nyquist)^order), multipliers)
end


# Internal: the array type and element type are read off the multipliers' axis arrays — O(N) vectors
# that live on the domain's backend — so every scratch buffer lands on the same backend (CPU/GPU), the
# GBGPeriodicFields `similar(reference, …)` allocation discipline (its invariant 6). The dealias
# kernel no longer serves as the template: a compressed kernel stores no field-sized array.
_reference(domain::FixedDomain) = domain.multipliers.squared_wavenumber_1
_real_type(domain::FixedDomain) = eltype(_reference(domain))
_complex_type(domain::FixedDomain) = complex(_real_type(domain))
_blank(domain::FixedDomain, ::Type{S}, dims) where {S} = fill!(similar(_reference(domain), S, dims), zero(S))



"""
    max_wavenumber(domain)

The highest wavenumber magnitude `domain` (a [`FixedDomain`](@ref)) treats as resolved signal — the
dealiasing cutoff

```math
\\kappa_{\\max} = f \\frac{N}{2} \\frac{2\\pi}{L},
```

with ``N`` the grid points per side, ``L`` the box side, ``f`` the retained-Nyquist fraction of the
[`DealiasingStrategy`](@ref) (``2/3`` for `TwoThirds`, ``1`` for `HouLi`, ``\\tfrac{2\\sqrt{2}}{3}`` for `PhaseShift`).
For the sharp strategies the cutoff sits strictly **below** the grid Nyquist
``\\tfrac{N}{2}\\tfrac{2\\pi}{L}`` — they zero the modes above it each step. `HouLi` is the exception
its ``f = 1`` implies: its cutoff *is* the Nyquist, so there is no band above to zero, and it instead
damps modes as they approach it (to machine epsilon at Nyquist). It fixes both the advective-CFL step
([`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl)) and the resolution
criterion
``\\kappa_{\\max}\\eta`` — with ``\\eta`` the Kolmogorov (dissipation) microscale — that a run is set
up to meet.
"""
function max_wavenumber(domain::FixedDomain)
  N = physical_field_shape(domain.grid, Val(0))[1]
  L = domain.grid.domain_size[1]
  # Through the same expression, in the same element type, that `_build_dealias` truncates with —
  # so the number reported here is the band the domain actually keeps.
  return _cutoff_wavenumber(domain.dealiasing, N, L, typeof(L))
end


"""
    new_vector_field_spectral(domain)

Allocate a single zeroed vector field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_vector_field_spectral(domain::FixedDomain) =
  VectorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(1))), domain.grid, domain.layout)


"""
    new_vector_field_physical(domain)

Allocate a single zeroed vector field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_vector_field_physical(domain::FixedDomain) =
  VectorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(1))), domain.grid, domain.layout)


"""
    new_scalar_field_spectral(domain)

Allocate a single zeroed scalar field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_scalar_field_spectral(domain::FixedDomain) =
  ScalarFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(0))), domain.grid, domain.layout)


"""
    new_scalar_field_physical(domain)

Allocate a single zeroed scalar field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_scalar_field_physical(domain::FixedDomain) =
  ScalarFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(0))), domain.grid, domain.layout)


"""
    new_tensor_field_spectral(domain)

Allocate a single zeroed second-order tensor field in spectral representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_tensor_field_spectral(domain::FixedDomain) =
  TensorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(2))), domain.grid, domain.layout)


"""
    new_tensor_field_physical(domain)

Allocate a single zeroed second-order tensor field in physical representation on the [`FixedDomain`](@ref) `domain`'s backend and element type.
"""
new_tensor_field_physical(domain::FixedDomain) =
  TensorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(2))), domain.grid, domain.layout)


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

end # module SimulationDomain

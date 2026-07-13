# SimulationDomain — the discretised, periodic, cubic box a run lives on: the grid, the real–Fourier
# layout, the transform plans, the spectral multipliers, the |k|² field, and the de-alias kernel.
# Reusable and read-only; precision and backend enter here (scalar_type / array_type) and flow
# everywhere from here. The concrete frame is `FixedDomain` (fixed, orthogonal, unsheared); a sheared
# (Rogallo) frame is deferred (ARCHITECTURE §7). Field-sized allocators (spectral_vector, …) build
# scratch fields sized to the domain.

"""
    SimulationDomain

The discretised periodic box a run lives on — the reusable, read-only frame:
- [`FixedDomain`](@ref) — the fixed, unsheared cubic box (grid, transform plans, spectral multipliers,
  squared-wavenumber field, de-alias kernel).
- [`DealiasingStrategy`](@ref) — the aliasing-control strategy, [`TwoThirds`](@ref), [`HouLi`](@ref), or
  [`PhaseShift`](@ref), and the cutoff it sets, [`max_wavenumber`](@ref).
- [`spectral_vector`](@ref), [`scalar_spectral`](@ref), … — the field-sized scratch allocators.
- [`dealias!`](@ref) — apply the de-alias kernel to a field in spectral representation, in place.

Precision and backend enter here and flow everywhere from here.
"""
module SimulationDomain

using GBGPeriodicFields

export FixedDomain,
       spectral_vector, physical_vector, scalar_spectral, scalar_physical,
       tensor_spectral, tensor_physical,
       dealias!, DealiasingStrategy, TwoThirds, HouLi, PhaseShift, max_wavenumber

# ── De-aliasing strategies ────────────────────────────────────────────────────────────────────────
# How the aliasing of the quadratic nonlinearity is controlled. Each strategy builds the `domain.dealias`
# kernel (applied by `dealias!`/`convolve!`) and declares the Nyquist fraction it keeps energetic,
# which sets the advective-CFL ceiling (see `recommended_cfl`).

"""
    DealiasingStrategy

How the aliasing of the quadratic nonlinearity is controlled. A [`FixedDomain`](@ref) is built
with one; it fixes the `domain.dealias` kernel and, through `recommended_cfl`, the advective-CFL
ceiling. Concrete strategies: [`TwoThirds`](@ref) (the sharp ``2/3`` rule, the default) and
[`HouLi`](@ref) (the smooth Hou–Li filter).
"""
abstract type DealiasingStrategy end

"""
    TwoThirds()

The sharp isotropic ``2/3``-rule truncation: keep the modes
``\\kappa \\le \\kappa_{\\max} = \\tfrac23\\kappa_{\\mathrm{Ny}}`` and zero the rest, where
``\\kappa_{\\mathrm{Ny}} = \\tfrac N2\\cdot\\tfrac{2\\pi}{L}`` is the Nyquist wavenumber and
``\\kappa_{\\max}`` the dealiased maximum — two-thirds of the way out to Nyquist. Exact de-aliasing
of the quadratic nonlinearity, and the lean, GPU-friendly default.
"""
struct TwoThirds <: DealiasingStrategy end

"""
    HouLi(; order = 36, strength = nothing)

The smooth Hou–Li spectral filter, transfer function
``\\exp\\!\\big(-\\,\\texttt{strength}\\,(\\kappa/\\kappa_{\\mathrm{Ny}})^{\\texttt{order}}\\big)``,
with ``\\kappa_{\\mathrm{Ny}} = \\tfrac N2\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber. The `order`
sets the sharpness of the spectral roll-off (higher is closer to a sharp cutoff); the `strength` sets the
damping at the Nyquist mode, which is multiplied by ``\\mathrm{e}^{-\\texttt{strength}}``. By default
(`strength = nothing`) `strength` is chosen for the domain's element type as ``-\\log`` of its machine
epsilon — ``\\approx 36`` for [`Float64`](@extref Julia :jl:type:Core.Float64), ``\\approx 16`` for
[`Float32`](@extref Julia :jl:type:Core.Float32) — so the Nyquist mode always damps
to that precision's machine epsilon; pass an explicit `strength` to override. It keeps more modes
than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a stabilisation,
hence an opt-in, not the default. Applied isotropically in ``\\kappa``. Because it retains energy out to
the Nyquist wavenumber it takes a proportionally smaller CFL step than the ``2/3`` rule — handled
automatically by `recommended_cfl`.
"""
struct HouLi <: DealiasingStrategy
  order::Int
  strength::Union{Float64, Nothing}
end
HouLi(; order::Integer = 36, strength::Union{Real, Nothing} = nothing) =
  HouLi(Int(order), isnothing(strength) ? nothing : Float64(strength))

"""
    PhaseShift()

Phase-shift de-aliasing: assemble each quadratic nonlinear term on the grid **and** on a grid displaced
by half a cell, average the two, and truncate spherically at
``\\kappa_{\\max} = \\tfrac{\\sqrt2}{3}N\\cdot\\tfrac{2\\pi}{L} = \\tfrac{2\\sqrt2}{3}\\kappa_{\\mathrm{Ny}}``
(with ``\\kappa_{\\mathrm{Ny}} = \\tfrac N2\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber). The half-cell
average cancels the aliasing images that wrap in an odd number of axes; the spherical cutoff removes the
surviving two-axis images. It de-aliases the quadratic **exactly** while keeping the resolved band out to
``\\tfrac{2\\sqrt2}{3}\\kappa_{\\mathrm{Ny}} \\approx 0.94\\,\\kappa_{\\mathrm{Ny}}`` — a factor ``\\sqrt2``
further than the [`TwoThirds`](@ref) rule's ``\\tfrac23\\kappa_{\\mathrm{Ny}}`` (``\\approx 2.8\\times`` the
modes in the retained sphere).

Use it when that top third of wavenumbers is worth the price: a **second** nonlinear-term transform per
stage (``2\\times`` the transforms) and the displaced-evaluation scratch (a spectral field per phase-shifted
term). Opt-in, not the default. Because it retains energy out to
``\\tfrac{2\\sqrt2}{3}\\kappa_{\\mathrm{Ny}}`` it takes a proportionally smaller advective-CFL step than the
``2/3`` rule — handled automatically by `recommended_cfl`.

!!! note "The Nyquist mode is untouched"
    A half-cell displacement cannot translate the Nyquist mode of a real field — it *attenuates* it by
    ``\\cos(\\pi h_a/\\Delta x_a)``, which vanishes at half a cell. This never bites here: the spherical
    cutoff at ``\\tfrac{2\\sqrt2}{3}\\kappa_{\\mathrm{Ny}} < \\kappa_{\\mathrm{Ny}}`` leaves the field with no
    Nyquist content to mistranslate.

Phase-shift de-aliasing follows Patterson & Orszag (1971); the combination with spherical truncation is
Rogallo (1981).
"""
struct PhaseShift <: DealiasingStrategy end

# The fraction of the Nyquist wavenumber a strategy keeps energetic — sets κ_max for the advective CFL.
_retained_nyquist_fraction(::TwoThirds) = 2 // 3
_retained_nyquist_fraction(::HouLi) = 1 // 1
# Phase-shift keeps the spherical band to κ_max = √2·N/3·(2π/L) = (2√2/3)·κ_Ny (Rogallo).
_retained_nyquist_fraction(::PhaseShift) = 2 * sqrt(2) / 3


"""
    FixedDomain(grid_points_per_axis, side_length = 2π; dealiasing = TwoThirds(),
                      scalar_type = Float64, array_type = Array)

The discretised periodic box a run lives on — the reusable, read-only frame: a cube of side length
`side_length` sampled with `grid_points_per_axis` points along each axis, holding everything the
pseudospectral method needs on that box.

# Arguments
- `grid_points_per_axis` — grid points ``N`` along each axis (the box is ``N^{3}``).
- `side_length = 2π` — the physical side length ``L`` (the box is ``[0,L)^{3}``).
- `dealiasing = TwoThirds()` — the de-aliasing strategy: [`TwoThirds`](@ref) (the sharp ``2/3`` rule,
  the default) and [`HouLi`](@ref) (the smooth Hou–Li filter) apply [`dealias!`](@ref) as a coefficientwise
  multiply, while [`PhaseShift`](@ref) averages a half-cell-displaced evaluation (exact, keeping a fuller
  band at ``2\\times`` the transforms). It controls the aliasing of the quadratic nonlinearity and sets the
  advective-CFL ceiling through `recommended_cfl`.
- `scalar_type = Float64` — the real element type ([`Float32`](@extref Julia :jl:type:Core.Float32) is GPU-friendly).
- `array_type = Array` — the storage backend: [`Array`](@extref Julia :jl:type:Core.Array) (CPU) or
  [`CuArray`](@extref CUDA The-CuArray-type) / [`ROCArray`](@extref AMDGPU AMDGPU.ROCArray) (GPU).

# Fields
- `grid`, `layout` — the [`Grid3D`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.Grid3D) and its
  real–Fourier memory layout.
- `velocity_plans`, `scalar_plans`, `tensor_plans` — the real-to-complex transform plans, one per field
  rank: the velocity (a vector field), the scalar (a scalar field), and the rank-2 strain tensor the
  derivative-skewness diagnostic needs.
- `multipliers` — the
  [`FieldSpectralMultipliers`](@extref GBGPeriodicFields GBGPeriodicFields.Fields.FieldSpectralMultipliers),
  the spectral first-derivative operators.
- `squared_wavenumber`, `squared_wavenumber_kernel` — ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (in
  spectral representation ``-\\nabla^{2}`` acts as multiplication by it), kept both as a real array and as
  a scalar-field kernel for weighted spectral reductions.
- `dealias`, `dealiasing` — the de-alias kernel and the [`DealiasingStrategy`](@ref) that built it.
"""
struct FixedDomain{G, L, VP, SP, TP, M, K, SK, D, DS}
  grid::G
  layout::L
  velocity_plans::VP
  scalar_plans::SP
  tensor_plans::TP                 # rank-2 transform plans (the strain-tensor diagnostic)
  multipliers::M
  squared_wavenumber::K            # |k|² as a real array
  squared_wavenumber_kernel::SK    # |k|² as a ScalarFieldSpectral — the Dirichlet-energy weight for `weighted_inner`
  dealias::D                       # isotropic low-pass kernel (ScalarFieldSpectral), built by `dealiasing`
  dealiasing::DS                   # the DealiasingStrategy that built `dealias` (TwoThirds / HouLi / PhaseShift)
end


_zeros(array_type, ::Type{S}, dims::Tuple) where {S} = fill!(array_type{S}(undef, dims...), zero(S))


function FixedDomain(grid_points_per_axis::Integer, side_length::Real = 2π;
                           dealiasing::DealiasingStrategy = TwoThirds(),
                           scalar_type::Type{T} = Float64,
                           array_type = Array) where {T<:AbstractFloat}
  N = Int(grid_points_per_axis)
  L = T(side_length)
  grid = Grid3D((N, N, N), (L, L, L))
  layout = RealFourierLayout()

  velocity_physical = VectorFieldPhysical((x, y, z) -> (zero(T), zero(T), zero(T)), grid; array_type)
  velocity_spectral = VectorFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
  scalar_physical = ScalarFieldPhysical((x, y, z) -> zero(T), grid; array_type)
  scalar_spectral_storage = ScalarFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)

  velocity_plans = FieldTransformPlans(velocity_physical, velocity_spectral)
  scalar_plans = FieldTransformPlans(scalar_physical, scalar_spectral_storage)
  tensor_physical_template = TensorFieldPhysical(_zeros(array_type, T, physical_field_shape(grid, Val(2))), grid)
  tensor_spectral_template = TensorFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(2))), grid)
  tensor_plans = FieldTransformPlans(tensor_physical_template, tensor_spectral_template)
  multipliers = FieldSpectralMultipliers(velocity_spectral)
  squared_wavenumber_kernel = squared_wavenumber_field(scalar_spectral_storage, multipliers)
  squared_wavenumber = real.(field_data(squared_wavenumber_kernel))
  dealias = _build_dealias(dealiasing, velocity_spectral, multipliers, squared_wavenumber, N, L, T)

  return FixedDomain(grid, layout, velocity_plans, scalar_plans, tensor_plans, multipliers, squared_wavenumber, squared_wavenumber_kernel, dealias, dealiasing)
end


# Build the `domain.dealias` kernel (a scalar low-pass in spectral representation) for a strategy.
_build_dealias(::TwoThirds, reference, multipliers, squared_wavenumber, N, L, ::Type{T}) where {T} =
  spectral_cutoff(reference, multipliers, T(2 // 3) * (N / 2) * (2π / L))

# Phase-shift: the spherical truncation that removes the two-axis aliases the half-cell average leaves.
_build_dealias(::PhaseShift, reference, multipliers, squared_wavenumber, N, L, ::Type{T}) where {T} =
  spectral_cutoff(reference, multipliers, T(2 * sqrt(2) / 3) * (N / 2) * (2π / L))

function _build_dealias(strategy::HouLi, reference, multipliers, squared_wavenumber, N, L, ::Type{T}) where {T}
  kernel = spectral_cutoff(reference, multipliers, T(2) * (N / 2) * (2π / L))    # all-pass ⇒ correct shape/backend
  k_nyquist = T((N / 2) * (2π / L))
  strength = isnothing(strategy.strength) ? -log(eps(T)) : strategy.strength
  field_data(kernel) .= Complex{T}.(exp.(-T(strength) .* (sqrt.(squared_wavenumber) ./ k_nyquist) .^ strategy.order))
  return kernel
end


# Internal: the array type and element types are read off the de-alias kernel's storage, so every
# scratch buffer lands on the same backend (CPU/GPU) — the GBGPeriodicFields `similar(field_data(ref), …)`
# allocation discipline (its invariant 6).
_reference(domain::FixedDomain) = field_data(domain.dealias)
_real_type(domain::FixedDomain) = real(eltype(_reference(domain)))
_complex_type(domain::FixedDomain) = complex(_real_type(domain))
_blank(domain::FixedDomain, ::Type{S}, dims) where {S} = fill!(similar(_reference(domain), S, dims), zero(S))


"""
    max_wavenumber(domain)

The highest wavenumber magnitude that `domain` actually evolves — the de-aliasing cutoff

```math
\\kappa_{\\max} = f\\,\\frac N2\\,\\frac{2\\pi}{L},
```

with ``N`` the grid points per side, ``L`` the box side, and ``f`` the retained-Nyquist fraction of the
[`DealiasingStrategy`](@ref) (``2/3`` for `TwoThirds`, ``1`` for `HouLi`, ``2\\sqrt2/3`` for `PhaseShift`).
It is the cutoff the
de-aliasing sets — **not** the grid Nyquist ``\\tfrac N2\\tfrac{2\\pi}{L}`` itself; the modes above it are
zeroed each step. It fixes both the advective-CFL step (`recommended_cfl`) and the resolution criterion
``\\kappa_{\\max}\\eta`` that a run is set up to meet.
"""
function max_wavenumber(domain::FixedDomain)
  N = physical_field_shape(domain.grid, Val(0))[1]
  return _retained_nyquist_fraction(domain.dealiasing) * (N / 2) * (2π / domain.grid.domain_size[1])
end


"""
    spectral_vector(domain)

Allocate a single zeroed vector field in spectral representation on `domain`'s backend and element type.
"""
spectral_vector(domain::FixedDomain) =
  VectorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(1))), domain.grid)


"""
    physical_vector(domain)

Allocate a single zeroed vector field in physical representation on `domain`'s backend and element type.
"""
physical_vector(domain::FixedDomain) =
  VectorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(1))), domain.grid)


"""
    scalar_spectral(domain)

Allocate a single zeroed scalar field in spectral representation on `domain`'s backend and element type.
"""
scalar_spectral(domain::FixedDomain) =
  ScalarFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(0))), domain.grid)


"""
    scalar_physical(domain)

Allocate a single zeroed scalar field in physical representation on `domain`'s backend and element type.
"""
scalar_physical(domain::FixedDomain) =
  ScalarFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(0))), domain.grid)


"""
    tensor_spectral(domain)

Allocate a single zeroed second-order tensor field in spectral representation on `domain`'s backend and element type.
"""
tensor_spectral(domain::FixedDomain) =
  TensorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(2))), domain.grid)


"""
    tensor_physical(domain)

Allocate a single zeroed second-order tensor field in physical representation on `domain`'s backend and element type.
"""
tensor_physical(domain::FixedDomain) =
  TensorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(2))), domain.grid)


"""
    dealias!(field, domain)

Apply the run's de-alias low-pass `domain.dealias` to `field` in place — a coefficientwise multiply that
controls the aliasing of the quadratic nonlinearity. The kernel is whatever the run's
[`DealiasingStrategy`](@ref) built: the sharp ``2/3`` cutoff ([`TwoThirds`](@ref), exact de-aliasing)
or the smooth [`HouLi`](@ref) filter (which only damps the aliasing). The `field` may be a vector or
scalar field in spectral representation.
"""
dealias!(field, domain::FixedDomain) = convolve!(field, field, domain.dealias)

end # module SimulationDomain

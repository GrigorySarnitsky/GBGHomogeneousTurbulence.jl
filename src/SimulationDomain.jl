# SimulationDomain — the discretised, periodic, cubic box a run lives on: the grid, the real–Fourier
# layout, the transform plans, the spectral multipliers, the |k|² field, and the de-alias kernel.
# Reusable and read-only; precision and backend enter here (scalar_type / array_type) and flow
# everywhere from here. The concrete frame is `FixedDomain` (fixed, orthogonal, unsheared); a sheared
# (Rogallo) frame is deferred (ARCHITECTURE §7). Field-sized allocators (spectral_vector, …) build
# scratch fields sized to the domain.

"""
    SimulationDomain

The discretised periodic box a run lives on — the reusable, read-only frame. Provides [`FixedDomain`](@ref)
(the fixed, unsheared cubic box: grid, transform plans, spectral multipliers, squared-wavenumber field, and
the de-alias kernel built by a [`DealiasingStrategy`](@ref) — [`TwoThirds`](@ref) or [`HouLi`](@ref)); the
field-sized allocators ([`spectral_vector`](@ref), [`scalar_spectral`](@ref), …); [`max_wavenumber`](@ref);
and [`dealias!`](@ref), which applies the de-alias kernel to a spectral field in place. Precision and
backend enter here and flow everywhere from here.
"""
module SimulationDomain

using GBGPeriodicFields

export FixedDomain,
       spectral_vector, physical_vector, scalar_spectral, scalar_physical,
       tensor_spectral, tensor_physical,
       dealias!, DealiasingStrategy, TwoThirds, HouLi, max_wavenumber

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
with ``\\kappa_{\\mathrm{Ny}} = \\tfrac N2\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber. `order`
sets the sharpness of the spectral roll-off (higher is closer to a sharp cutoff); `strength` sets the
damping at the Nyquist mode, which is multiplied by ``\\mathrm{e}^{-\\texttt{strength}}``. By default
(`strength = nothing`) `strength` is chosen for the domain's element type as ``-\\log`` of its machine
epsilon — ``\\approx 36`` for `Float64`, ``\\approx 16`` for `Float32` — so the Nyquist mode always damps
to that precision's machine epsilon; pass an explicit `strength` to override. It keeps more modes
than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a stabilisation,
hence an opt-in, not the default. Applied isotropically in ``\\kappa`` (the filter TurTLE uses, there
per-axis). Because it retains energy out to the Nyquist wavenumber it takes a proportionally smaller
CFL step than the ``2/3`` rule — handled automatically by `recommended_cfl`.
"""
struct HouLi <: DealiasingStrategy
  order::Int
  strength::Union{Float64, Nothing}
end
HouLi(; order::Integer = 36, strength::Union{Real, Nothing} = nothing) =
  HouLi(Int(order), isnothing(strength) ? nothing : Float64(strength))

# The fraction of the Nyquist wavenumber a strategy keeps energetic — sets κ_max for the advective CFL.
_retained_nyquist_fraction(::TwoThirds) = 2 // 3
_retained_nyquist_fraction(::HouLi) = 1 // 1


"""
    FixedDomain(grid_points_per_axis, side_length = 2π; dealiasing = TwoThirds(),
                      scalar_type = Float64, array_type = Array)

The reusable, read-only spectral machinery for a cubic homogeneous-isotropic-turbulence run — a periodic
box of side length `side_length` sampled with `grid_points_per_axis` points along each side: the `Grid3D`, the real-to-complex transform
plans (one for the velocity, a vector field; one for the scalar ``\\varphi``; and one for the rank-2
strain tensor of the derivative-skewness diagnostic), the
`FieldSpectralMultipliers`, the squared-wavenumber array ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` (with
``\\boldsymbol{\\kappa}`` the wavenumber vector — the symbol of ``-\\nabla^{2}``; kept both as a real array
and as a scalar-field kernel for weighted spectral reductions), and the de-alias kernel `dealias`.

`dealias` is built by the `dealiasing` strategy — [`TwoThirds`](@ref) (the sharp ``2/3`` rule, the
default) or [`HouLi`](@ref) (the smooth Hou–Li filter). Both are applied by [`dealias!`](@ref) as a
coefficientwise multiply to control the aliasing error of the quadratic nonlinearity; the choice also
sets the advective-CFL ceiling through `recommended_cfl`.

`array_type` selects the storage backend (`Array` for CPU, `ROCArray`/`CuArray` for GPU) and
`scalar_type` the real element type (`Float32` is GPU-friendly).
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
  dealiasing::DS                   # the DealiasingStrategy that built `dealias` (TwoThirds / HouLi)
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

with ``N`` the resolution, ``L`` the box side, and ``f`` the retained-Nyquist fraction of the
[`DealiasingStrategy`](@ref) (``2/3`` for `TwoThirds`, ``1`` for `HouLi`). It is the cutoff the
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

Allocate a single zeroed vector field in spectral representation on `domain`'s backend and element type
(a scratch buffer for the time loop).
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

Allocate a single zeroed scalar field in spectral representation on `domain`'s backend and element type
(used for the scalar ``\\varphi``, the integrating factor, and kernel scratch).
"""
scalar_spectral(domain::FixedDomain) =
  ScalarFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(0))), domain.grid)


"""
    scalar_physical(domain)

Allocate a single zeroed scalar field in physical representation on `domain`'s backend and element type
(used for the scalar ``\\varphi`` in physical space).
"""
scalar_physical(domain::FixedDomain) =
  ScalarFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(0))), domain.grid)


"""
    tensor_spectral(domain)

Allocate a single zeroed second-order tensor field in spectral representation (scratch for the
strain-rate tensor ``\\boldsymbol{S} = \\operatorname{sym}\\nabla\\boldsymbol{u}``).
"""
tensor_spectral(domain::FixedDomain) =
  TensorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(2))), domain.grid)


"""
    tensor_physical(domain)

Allocate a single zeroed second-order tensor field in physical representation.
"""
tensor_physical(domain::FixedDomain) =
  TensorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(2))), domain.grid)


"""
    dealias!(field, domain)

Apply the run's de-alias low-pass `domain.dealias` to `field` in place — a coefficientwise multiply that
controls the aliasing of the quadratic nonlinearity. The kernel is whatever the run's
[`DealiasingStrategy`](@ref) built: the sharp ``2/3`` cutoff ([`TwoThirds`](@ref), exact de-aliasing)
or the smooth [`HouLi`](@ref) filter (which only damps the aliasing). `field` may be a vector or
scalar field in spectral representation.
"""
dealias!(field, domain::FixedDomain) = convolve!(field, field, domain.dealias)

end # module SimulationDomain

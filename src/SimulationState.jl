# SimulationState — the spectral machinery and preallocated buffers a HIST run advances.
#
# `SimulationDomain` bundles the reusable, read-only machinery (grid, transform plans, spectral
# multipliers, the |k|² field, and the de-alias kernel). `FieldBuffers` holds the
# preallocated scratch the velocity time step writes into, so a step allocates no field-sized memory
# — the GPU hot-loop discipline inherited from GBGPeriodicFields (its invariant 13). Everything is
# allocated through the field reference's array type, so a run is CPU/GPU-agnostic (pass
# `array_type = ROCArray` for AMD).

"""
    SimulationState

The spectral machinery and preallocated buffers a run advances: [`SimulationDomain`](@ref) (the
read-only grid, transform plans, multipliers, squared-wavenumber field, and the de-alias kernel built
by a [`DealiasingStrategy`](@ref) — [`TwoThirds`](@ref) or [`HouLi`](@ref)), the scratch allocators,
[`FieldBuffers`](@ref), and the random initial conditions ([`random_solenoidal_velocity!`](@ref) for the
divergence-free velocity, [`random_scalar!`](@ref) for the mean-zero scalar ``\\varphi``).
[`dealias!`](@ref) applies the de-alias kernel to a spectral field in place.
"""
module SimulationState

using GBGPeriodicFields
using Random

export SimulationDomain, FieldBuffers,
       spectral_vector, physical_vector, scalar_spectral, scalar_physical,
       tensor_spectral, tensor_physical,
       random_solenoidal_velocity!, random_scalar!, dealias!,
       DealiasingStrategy, TwoThirds, HouLi, max_wavenumber


# ── De-aliasing strategies ────────────────────────────────────────────────────────────────────────
# How the aliasing of the quadratic nonlinearity is controlled. Each strategy builds the `domain.dealias`
# kernel (applied by `dealias!`/`convolve!`) and declares the Nyquist fraction it keeps energetic,
# which sets the advective-CFL ceiling (see `recommended_cfl`).

"""
    DealiasingStrategy

How the aliasing of the quadratic nonlinearity is controlled. A [`SimulationDomain`](@ref) is built
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
    HouLi(; order = 36, strength = 36)

The smooth Hou–Li spectral filter, transfer function
``\\exp\\!\\big(-\\,\\texttt{strength}\\,(\\kappa/\\kappa_{\\mathrm{Ny}})^{\\texttt{order}}\\big)``,
with ``\\kappa_{\\mathrm{Ny}} = \\tfrac N2\\cdot\\tfrac{2\\pi}{L}`` the Nyquist wavenumber. `order`
sets the sharpness of the spectral roll-off (higher is closer to a sharp cutoff); `strength` sets the
damping at the Nyquist mode, which is multiplied by ``\\mathrm{e}^{-\\texttt{strength}}`` (defaults
``36, 36``, so that mode falls to ``\\mathrm{e}^{-36}\\approx`` machine epsilon). It keeps more modes
than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a stabilisation,
hence an opt-in, not the default. Applied isotropically in ``\\kappa`` (the filter TurTLE uses, there
per-axis). Because it retains energy out to the Nyquist wavenumber it takes a proportionally smaller
CFL step than the ``2/3`` rule — handled automatically by `recommended_cfl`.
"""
struct HouLi <: DealiasingStrategy
  order::Int
  strength::Float64
end
HouLi(; order::Integer = 36, strength::Real = 36) = HouLi(Int(order), Float64(strength))

# The fraction of the Nyquist wavenumber a strategy keeps energetic — sets κ_max for the advective CFL.
_retained_nyquist_fraction(::TwoThirds) = 2 // 3
_retained_nyquist_fraction(::HouLi) = 1 // 1


"""
    SimulationDomain(grid_points_per_axis, side_length = 2π; dealiasing = TwoThirds(),
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
struct SimulationDomain{G, L, VP, SP, TP, M, K, SK, D, DS}
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


function SimulationDomain(grid_points_per_axis::Integer, side_length::Real = 2π;
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

  return SimulationDomain(grid, layout, velocity_plans, scalar_plans, tensor_plans, multipliers, squared_wavenumber, squared_wavenumber_kernel, dealias, dealiasing)
end


# Build the `domain.dealias` kernel (a scalar low-pass in spectral representation) for a strategy.
_build_dealias(::TwoThirds, reference, multipliers, squared_wavenumber, N, L, ::Type{T}) where {T} =
  spectral_cutoff(reference, multipliers, T(2 // 3) * (N / 2) * (2π / L))

function _build_dealias(strategy::HouLi, reference, multipliers, squared_wavenumber, N, L, ::Type{T}) where {T}
  kernel = spectral_cutoff(reference, multipliers, T(2) * (N / 2) * (2π / L))    # all-pass ⇒ correct shape/backend
  k_nyquist = T((N / 2) * (2π / L))
  field_data(kernel) .= Complex{T}.(exp.(-T(strategy.strength) .* (sqrt.(squared_wavenumber) ./ k_nyquist) .^ strategy.order))
  return kernel
end


# Internal: the array type and element types are read off the de-alias kernel's storage, so every
# scratch buffer lands on the same backend (CPU/GPU) — the GBGPeriodicFields `similar(field_data(ref), …)`
# allocation discipline (its invariant 6).
_reference(domain::SimulationDomain) = field_data(domain.dealias)
_real_type(domain::SimulationDomain) = real(eltype(_reference(domain)))
_complex_type(domain::SimulationDomain) = complex(_real_type(domain))
_blank(domain::SimulationDomain, ::Type{S}, dims) where {S} = fill!(similar(_reference(domain), S, dims), zero(S))


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
function max_wavenumber(domain::SimulationDomain)
  N = physical_field_shape(domain.grid, Val(0))[1]
  return _retained_nyquist_fraction(domain.dealiasing) * (N / 2) * (2π / domain.grid.domain_size[1])
end


"""
    spectral_vector(domain)

Allocate a single zeroed vector field in spectral representation on `domain`'s backend and element type
(a scratch buffer for the time loop).
"""
spectral_vector(domain::SimulationDomain) =
  VectorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(1))), domain.grid)


"""
    physical_vector(domain)

Allocate a single zeroed vector field in physical representation on `domain`'s backend and element type.
"""
physical_vector(domain::SimulationDomain) =
  VectorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(1))), domain.grid)


"""
    scalar_spectral(domain)

Allocate a single zeroed scalar field in spectral representation on `domain`'s backend and element type
(used for the scalar ``\\varphi``, the integrating factor, and kernel scratch).
"""
scalar_spectral(domain::SimulationDomain) =
  ScalarFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(0))), domain.grid)


"""
    scalar_physical(domain)

Allocate a single zeroed scalar field in physical representation on `domain`'s backend and element type
(used for the scalar ``\\varphi`` in physical space).
"""
scalar_physical(domain::SimulationDomain) =
  ScalarFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(0))), domain.grid)


"""
    tensor_spectral(domain)

Allocate a single zeroed second-order tensor field in spectral representation (scratch for the
strain-rate tensor ``\\boldsymbol{S} = \\operatorname{sym}\\nabla\\boldsymbol{u}``).
"""
tensor_spectral(domain::SimulationDomain) =
  TensorFieldSpectral(_blank(domain, _complex_type(domain), spectral_field_shape(domain.grid, domain.layout, Val(2))), domain.grid)


"""
    tensor_physical(domain)

Allocate a single zeroed second-order tensor field in physical representation.
"""
tensor_physical(domain::SimulationDomain) =
  TensorFieldPhysical(_blank(domain, _real_type(domain), physical_field_shape(domain.grid, Val(2))), domain.grid)


"""
    FieldBuffers(domain)

Preallocated scratch for one coupled integrating-factor step of the velocity and the passive scalar
``\\varphi``. The velocity buffers are the spectral vorticity, two Runge–Kutta stage registers
(buffers holding a stage's state and accumulator), the predictor field, a velocity copy (the in-place
inverse transform consumes its source), a general spectral scratch, the nonlinear-term buffer, and the
physical velocity / start-of-step vorticity / per-stage vorticity / predictor / Lamb-vector
(``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``). The scalar buffers are two stage registers, a
predictor, the nonlinear-term buffer, a copy, the shared integrating factor, and the physical scalar;
the scalar flux ``\\boldsymbol{u}\\varphi`` reuses the physical and spectral velocity scratch. Two
real per-mode linear-forcing-rate arrays ``A(\\boldsymbol{\\kappa})`` — one for the velocity, one for
``\\varphi`` — are folded into the integrating factor. Sized so a step allocates no field-sized
memory.
"""
struct FieldBuffers{VS, SS, VP, SP, RK}
  vorticity_spectral::VS
  stage1::VS
  stage2::VS
  velocity_star_spectral::VS
  velocity_copy::VS
  scratch::VS
  nonlinear::VS
  integrating_factor::SS
  scalar_stage1::SS
  scalar_stage2::SS
  scalar_star_spectral::SS
  scalar_nonlinear::SS
  scalar_copy::SS
  velocity::VP
  vorticity_start::VP
  vorticity_physical::VP
  velocity_star::VP
  lamb::VP
  scalar_field::SP
  velocity_rate::RK              # per-mode linear forcing rate A(k) (real), folded into E_ν
  scalar_rate::RK                # per-mode linear forcing rate for φ, folded into E_κ
end


function FieldBuffers(domain::SimulationDomain)
  rate() = fill!(similar(domain.squared_wavenumber), zero(eltype(domain.squared_wavenumber)))
  return FieldBuffers(
    spectral_vector(domain), spectral_vector(domain), spectral_vector(domain),
    spectral_vector(domain), spectral_vector(domain), spectral_vector(domain), spectral_vector(domain),
    scalar_spectral(domain), scalar_spectral(domain), scalar_spectral(domain),
    scalar_spectral(domain), scalar_spectral(domain), scalar_spectral(domain),
    physical_vector(domain), physical_vector(domain), physical_vector(domain),
    physical_vector(domain), physical_vector(domain),
    scalar_physical(domain),
    rate(), rate(),
  )
end


"""
    dealias!(field, domain)

Apply the run's de-alias low-pass `domain.dealias` to `field` in place — a coefficientwise multiply that
controls the aliasing of the quadratic nonlinearity. The kernel is whatever the run's
[`DealiasingStrategy`](@ref) built: the sharp ``2/3`` cutoff ([`TwoThirds`](@ref), exact de-aliasing)
or the smooth [`HouLi`](@ref) filter (which only damps the aliasing). `field` may be a vector or
scalar field in spectral representation.
"""
dealias!(field, domain::SimulationDomain) = convolve!(field, field, domain.dealias)


"""
    random_solenoidal_velocity!(û, domain; energy = 0.5, peak_wavenumber = 2.0,
                                spectrum = nothing, rng = default_rng())

Fill `û` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` of a chosen energy spectrum, de-aliased and rescaled so the kinetic energy
``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals `energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.

By default (`spectrum = nothing`) the velocity is concentrated at large scales by the Gaussian envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`).
Pass `spectrum`, a function ``\\kappa \\mapsto E(\\kappa)`` giving a target radial energy spectrum, to
seed that shape instead: each mode is scaled by ``\\sqrt{E(\\kappa)}/\\kappa``, so the shell-summed
spectrum is ``\\propto \\kappa^{2}(\\sqrt{E}/\\kappa)^{2} = E(\\kappa)`` (the ``\\kappa^{2}`` is the
shell's mode count) and the overall amplitude is fixed by the `energy` rescaling. The run layer bridges
a `Phenomenology` model spectrum into this function.

`domain` is the [`SimulationDomain`](@ref) supplying the grid, backend, wavenumber multipliers, and
de-alias kernel; `rng` is the random stream (defaults to `Random.default_rng()`).
"""
function random_solenoidal_velocity!(û, domain::SimulationDomain;
                                     energy::Real = 0.5, peak_wavenumber::Real = 2.0,
                                     spectrum = nothing, rng = Random.default_rng())
  T = _real_type(domain)
  noise = physical_vector(domain)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(domain.grid, Val(1))...))
  to_spectral!(û, noise, domain.velocity_plans)

  envelope = scalar_spectral(domain)
  if isnothing(spectrum)
    inverse_peak_squared = one(T) / T(peak_wavenumber)^2
    field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* domain.squared_wavenumber))
  else
    # Match a target radial spectrum E(κ): a per-mode amplitude √(E(κ))/κ yields a shell-summed
    # spectrum ∝ κ²·(√E/κ)² = E(κ) (the κ² is the shell's mode count); the DC mode stays at 0.
    shape = k2 -> k2 > 0 ? T(sqrt(max(spectrum(sqrt(k2)), zero(k2))) / sqrt(k2)) : zero(T)
    field_data(envelope) .= complex.(shape.(domain.squared_wavenumber))
  end
  convolve!(û, û, envelope)

  helmholtz_projection!(û, û, domain.multipliers)
  convolve!(û, û, domain.dealias)

  current_energy = 0.5 * inner(û, û)
  current_energy > 0 && (field_data(û) .*= sqrt(T(energy) / current_energy))
  return û
end


"""
    random_scalar!(φ̂, domain; variance = 1.0, peak_wavenumber = 2.0, rng = default_rng())

Fill `φ̂` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar
concentrated at large scales by the envelope ``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)``
(``k_p`` is `peak_wavenumber`), de-aliased, and rescaled so the variance
``\\langle\\varphi^{2}\\rangle`` equals `variance`. The physical noise is made mean-zero before the
transform, so the ``\\boldsymbol{\\kappa}=\\boldsymbol 0`` (mean) mode vanishes.

`domain` is the [`SimulationDomain`](@ref) supplying the grid, backend, wavenumber multipliers, and
de-alias kernel; `rng` is the random stream (defaults to `Random.default_rng()`).
"""
function random_scalar!(φ̂, domain::SimulationDomain;
                        variance::Real = 1.0, peak_wavenumber::Real = 2.0,
                        rng = Random.default_rng())
  T = _real_type(domain)
  noise = scalar_physical(domain)
  data = randn(rng, T, physical_field_shape(domain.grid, Val(0))...)
  data .-= sum(data) / length(data)                            # zero the spatial mean
  copyto!(field_data(noise), data)
  to_spectral!(φ̂, noise, domain.scalar_plans)

  inverse_peak_squared = one(T) / T(peak_wavenumber)^2
  envelope = scalar_spectral(domain)
  field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* domain.squared_wavenumber))
  convolve!(φ̂, φ̂, envelope)
  convolve!(φ̂, φ̂, domain.dealias)

  current_variance = inner(φ̂, φ̂)                         # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 && (field_data(φ̂) .*= sqrt(T(variance) / current_variance))
  return φ̂
end


end # module SimulationState

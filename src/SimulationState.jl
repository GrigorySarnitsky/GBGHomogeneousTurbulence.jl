# SimulationState — the spectral machinery and preallocated buffers a HIST run advances.
#
# `SpectralOperators` bundles the reusable, read-only machinery (grid, transform plans, spectral
# multipliers, the |k|² field, and the 2/3-rule de-alias kernel). `Workspace` holds the
# preallocated scratch the velocity time step writes into, so a step allocates no field-sized memory
# — the GPU hot-loop discipline inherited from GBGPeriodicFields (its invariant 13). Everything is
# allocated through the field reference's array type, so a run is CPU/GPU-agnostic (pass
# `array_type = ROCArray` for AMD).

"""
    SimulationState

The spectral machinery and preallocated buffers a run advances: `SpectralOperators` (the read-only
grid, transform plans, multipliers, squared-wavenumber field, and de-alias kernel), the scratch
allocators, `Workspace`, and the random divergence-free initial condition.
"""
module SimulationState

using GBGPeriodicFields
using Random

export SpectralOperators, Workspace,
       spectral_vector, physical_vector, scalar_spectral, scalar_physical,
       random_solenoidal_velocity!, random_scalar!, dealias!,
       DealiasingStrategy, TwoThirds, HouLi


# ── De-aliasing strategies ────────────────────────────────────────────────────────────────────────
# How the aliasing of the quadratic nonlinearity is controlled. Each strategy builds the `ops.dealias`
# kernel (applied by `dealias!`/`convolve!`) and declares the Nyquist fraction it keeps energetic,
# which sets the advective-CFL ceiling (see `recommended_cfl`).

"""
    DealiasingStrategy

How the aliasing of the quadratic nonlinearity is controlled. A [`SpectralOperators`](@ref) is built
with one; it fixes the `ops.dealias` kernel and, through `recommended_cfl`, the advective-CFL
ceiling. Concrete strategies: [`TwoThirds`](@ref) (the sharp ``2/3`` rule, the default) and
[`HouLi`](@ref) (the smooth Hou–Li filter).
"""
abstract type DealiasingStrategy end

"""
    TwoThirds()

The sharp isotropic ``2/3``-rule truncation: keep the modes
``\\kappa \\le \\tfrac23 \\kappa_{\\max}`` and zero the rest (``\\kappa_{\\max}`` the Nyquist
wavenumber). Exact de-aliasing of the quadratic nonlinearity, and the lean, GPU-friendly default.
"""
struct TwoThirds <: DealiasingStrategy end

"""
    HouLi(; order = 36, strength = 36)

The smooth Hou–Li spectral filter, transfer function
``\\exp\\!\\big(-\\,\\texttt{strength}\\,(\\kappa/\\kappa_{\\max})^{\\texttt{order}}\\big)``
(defaults ``36, 36``, damping the Nyquist mode to ``\\mathrm{e}^{-36}\\approx`` machine epsilon). It
keeps more modes than the ``2/3`` rule but only *damps* aliasing rather than removing it exactly — a
stabilisation, hence an opt-in, not the default. Applied isotropically in ``\\kappa``
(the filter TurTLE uses, there per-axis). Because it retains energy out to the Nyquist wavenumber it
takes a proportionally smaller CFL step than the ``2/3`` rule — handled automatically by
`recommended_cfl`.
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
    SpectralOperators(resolution, box = 2π; dealiasing = TwoThirds(),
                      scalar_type = Float64, array_type = Array)

The reusable, read-only spectral machinery for a cubic homogeneous-isotropic-turbulence run on a grid
of `resolution` points per side, in a periodic box of side `box`: the `Grid3D`, the real-to-complex transform
plans (one for the velocity, a vector field; one for the scalar ``\\varphi``), the
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
struct SpectralOperators{G, L, VP, SP, M, K, SK, D, DS}
  grid::G
  layout::L
  velocity_plans::VP
  scalar_plans::SP
  multipliers::M
  squared_wavenumber::K            # |k|² as a real array
  squared_wavenumber_kernel::SK    # |k|² as a ScalarFieldSpectral — the Dirichlet-energy weight for `weighted_inner`
  dealias::D                       # isotropic low-pass kernel (ScalarFieldSpectral), built by `dealiasing`
  dealiasing::DS                   # the DealiasingStrategy that built `dealias` (TwoThirds / HouLi)
end


_zeros(array_type, ::Type{S}, dims::Tuple) where {S} = fill!(array_type{S}(undef, dims...), zero(S))


function SpectralOperators(resolution::Integer, box::Real = 2π;
                           dealiasing::DealiasingStrategy = TwoThirds(),
                           scalar_type::Type{T} = Float64,
                           array_type = Array) where {T<:AbstractFloat}
  N = Int(resolution)
  L = T(box)
  grid = Grid3D((N, N, N), (L, L, L))
  layout = RealFourierLayout()

  velocity_physical = VectorFieldPhysical((x, y, z) -> (zero(T), zero(T), zero(T)), grid; array_type)
  velocity_spectral = VectorFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(1))), grid)
  scalar_physical = ScalarFieldPhysical((x, y, z) -> zero(T), grid; array_type)
  scalar_spectral_storage = ScalarFieldSpectral(_zeros(array_type, Complex{T}, spectral_field_shape(grid, layout, Val(0))), grid)

  velocity_plans = FieldTransformPlans(velocity_physical, velocity_spectral)
  scalar_plans = FieldTransformPlans(scalar_physical, scalar_spectral_storage)
  multipliers = FieldSpectralMultipliers(velocity_spectral)
  squared_wavenumber_kernel = squared_wavenumber_field(scalar_spectral_storage, multipliers)
  squared_wavenumber = real.(field_data(squared_wavenumber_kernel))
  dealias = _build_dealias(dealiasing, velocity_spectral, multipliers, squared_wavenumber, N, L, T)

  return SpectralOperators(grid, layout, velocity_plans, scalar_plans, multipliers, squared_wavenumber, squared_wavenumber_kernel, dealias, dealiasing)
end


# Build the `ops.dealias` kernel (a scalar low-pass in spectral representation) for a strategy.
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
_reference(ops::SpectralOperators) = field_data(ops.dealias)
_real_type(ops::SpectralOperators) = real(eltype(_reference(ops)))
_complex_type(ops::SpectralOperators) = complex(_real_type(ops))
_blank(ops::SpectralOperators, ::Type{S}, dims) where {S} = fill!(similar(_reference(ops), S, dims), zero(S))


"""
    spectral_vector(ops)

Allocate a single zeroed vector field in spectral representation on `ops`'s backend and element type
(a scratch buffer for the time loop).
"""
spectral_vector(ops::SpectralOperators) =
  VectorFieldSpectral(_blank(ops, _complex_type(ops), spectral_field_shape(ops.grid, ops.layout, Val(1))), ops.grid)


"""
    physical_vector(ops)

Allocate a single zeroed vector field in physical representation on `ops`'s backend and element type.
"""
physical_vector(ops::SpectralOperators) =
  VectorFieldPhysical(_blank(ops, _real_type(ops), physical_field_shape(ops.grid, Val(1))), ops.grid)


"""
    scalar_spectral(ops)

Allocate a single zeroed scalar field in spectral representation on `ops`'s backend and element type
(used for the scalar ``\\varphi``, the integrating factor, and kernel scratch).
"""
scalar_spectral(ops::SpectralOperators) =
  ScalarFieldSpectral(_blank(ops, _complex_type(ops), spectral_field_shape(ops.grid, ops.layout, Val(0))), ops.grid)


"""
    scalar_physical(ops)

Allocate a single zeroed scalar field in physical representation on `ops`'s backend and element type
(used for the scalar ``\\varphi`` in physical space).
"""
scalar_physical(ops::SpectralOperators) =
  ScalarFieldPhysical(_blank(ops, _real_type(ops), physical_field_shape(ops.grid, Val(0))), ops.grid)


"""
    Workspace(ops)

Preallocated scratch for one coupled integrating-factor step of the velocity and the passive scalar
``\\varphi``. The velocity buffers are the spectral vorticity, two Runge–Kutta stage registers, the
predictor field, a velocity copy (the in-place inverse transform consumes its source), a general
spectral scratch, the nonlinear-term buffer, and the physical velocity / vorticity / predictor /
Lamb-vector (``\\boldsymbol{u}\\times\\boldsymbol{\\omega}``). The scalar buffers are two stage
registers, a predictor, the nonlinear-term buffer, a copy, the shared integrating factor, and the
physical scalar; the scalar flux ``\\boldsymbol{u}\\varphi`` reuses the physical and spectral velocity
scratch. Sized so a step allocates no field-sized memory.
"""
struct Workspace{VS, SS, VP, SP, RK}
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


function Workspace(ops::SpectralOperators)
  rate() = fill!(similar(ops.squared_wavenumber), zero(eltype(ops.squared_wavenumber)))
  return Workspace(
    spectral_vector(ops), spectral_vector(ops), spectral_vector(ops),
    spectral_vector(ops), spectral_vector(ops), spectral_vector(ops), spectral_vector(ops),
    scalar_spectral(ops), scalar_spectral(ops), scalar_spectral(ops),
    scalar_spectral(ops), scalar_spectral(ops), scalar_spectral(ops),
    physical_vector(ops), physical_vector(ops), physical_vector(ops),
    physical_vector(ops), physical_vector(ops),
    scalar_physical(ops),
    rate(), rate(),
  )
end


"""
    dealias!(field, ops)

Apply the ``2/3``-rule low-pass `ops.dealias` to `field` in place (a coefficientwise, alias-safe
multiply by the de-alias kernel; `field` may be in vector or scalar spectral representation).
"""
dealias!(field, ops::SpectralOperators) = convolve!(field, field, ops.dealias)


"""
    random_solenoidal_velocity!(uh, ops; energy = 0.5, peak_wavenumber = 2.0, rng = default_rng())

Fill `uh` (a velocity field in spectral representation) with a random, divergence-free velocity
``\\boldsymbol{u}`` concentrated at large scales by the envelope
``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)`` (``k_p`` is `peak_wavenumber`),
de-aliased, and rescaled so the kinetic energy
``\\tfrac12\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` equals `energy`. The Leray–Helmholtz
projection ``\\mathbb{P}`` enforces ``\\nabla\\cdot\\boldsymbol{u} = 0``.
"""
function random_solenoidal_velocity!(uh, ops::SpectralOperators;
                                     energy::Real = 0.5, peak_wavenumber::Real = 2.0,
                                     rng = Random.default_rng())
  T = _real_type(ops)
  noise = physical_vector(ops)
  copyto!(field_data(noise), randn(rng, T, physical_field_shape(ops.grid, Val(1))...))
  to_spectral!(uh, noise, ops.velocity_plans)

  inverse_peak_squared = one(T) / T(peak_wavenumber)^2
  envelope = scalar_spectral(ops)
  field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* ops.squared_wavenumber))
  convolve!(uh, uh, envelope)

  helmholtz_projection!(uh, uh, ops.multipliers)
  convolve!(uh, uh, ops.dealias)

  current_energy = 0.5 * inner(uh, uh)
  current_energy > 0 && (field_data(uh) .*= sqrt(T(energy) / current_energy))
  return uh
end


"""
    random_scalar!(phih, ops; variance = 1.0, peak_wavenumber = 2.0, rng = default_rng())

Fill `phih` (the scalar ``\\varphi`` in spectral representation) with a random, mean-zero scalar
concentrated at large scales by the envelope ``\\exp\\!\\big(-\\lvert\\boldsymbol{\\kappa}\\rvert^{2}/k_p^{2}\\big)``
(``k_p`` is `peak_wavenumber`), de-aliased, and rescaled so the variance
``\\langle\\varphi^{2}\\rangle`` equals `variance`. The physical noise is made mean-zero before the
transform, so the ``\\boldsymbol{\\kappa}=\\boldsymbol 0`` (mean) mode vanishes.
"""
function random_scalar!(phih, ops::SpectralOperators;
                        variance::Real = 1.0, peak_wavenumber::Real = 2.0,
                        rng = Random.default_rng())
  T = _real_type(ops)
  noise = scalar_physical(ops)
  data = randn(rng, T, physical_field_shape(ops.grid, Val(0))...)
  data .-= sum(data) / length(data)                            # zero the spatial mean
  copyto!(field_data(noise), data)
  to_spectral!(phih, noise, ops.scalar_plans)

  inverse_peak_squared = one(T) / T(peak_wavenumber)^2
  envelope = scalar_spectral(ops)
  field_data(envelope) .= complex.(exp.((-inverse_peak_squared) .* ops.squared_wavenumber))
  convolve!(phih, phih, envelope)
  convolve!(phih, phih, ops.dealias)

  current_variance = inner(phih, phih)                         # ⟨φ²⟩ for a mean-zero field
  current_variance > 0 && (field_data(phih) .*= sqrt(T(variance) / current_variance))
  return phih
end


end # module SimulationState

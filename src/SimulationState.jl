# SimulationState — the spectral machinery and preallocated buffers a HIST run advances.
#
# `SpectralOperators` bundles the reusable, read-only machinery (grid, transform plans, spectral
# multipliers, the |k|² field, and the 2/3-rule de-alias kernel). `VelocityWorkspace` holds the
# preallocated scratch the velocity time step writes into, so a step allocates no field-sized memory
# — the GPU hot-loop discipline inherited from GBGPeriodicFields (its invariant 13). Everything is
# allocated through the field reference's array type, so a run is CPU/GPU-agnostic (pass
# `array_type = ROCArray` for AMD).

module SimulationState

using GBGPeriodicFields
using Random

export SpectralOperators, VelocityWorkspace,
       spectral_vector, physical_vector, scalar_spectral,
       random_solenoidal_velocity!, dealias!


"""
    SpectralOperators(resolution, box = 2π; dealias_fraction = 2//3,
                      scalar_type = Float64, array_type = Array)

The reusable, read-only spectral machinery for a cubic HIST run on a `resolution³` grid in a
`box³` periodic domain: the `Grid3D`, the real-to-complex transform plans (vector and scalar),
the `FieldSpectralMultipliers`, the `|k|²` array (the symbol of `-∇²`), and the isotropic sharp
low-pass `dealias` kernel at `dealias_fraction · k_Nyquist` (the 2/3 rule by default).

`array_type` selects the storage backend (`Array` for CPU, `ROCArray`/`CuArray` for GPU) and
`scalar_type` the real element type (`Float32` is GPU-friendly).
"""
struct SpectralOperators{G, L, VP, SP, M, K, D}
  grid::G
  layout::L
  velocity_plans::VP
  scalar_plans::SP
  multipliers::M
  squared_wavenumber::K            # |k|² as a real array
  dealias::D                       # 2/3-rule isotropic low-pass kernel (ScalarFieldSpectral)
end


_zeros(array_type, ::Type{S}, dims::Tuple) where {S} = fill!(array_type{S}(undef, dims...), zero(S))


function SpectralOperators(resolution::Integer, box::Real = 2π;
                           dealias_fraction::Real = 2 // 3,
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
  squared_wavenumber = real.(field_data(squared_wavenumber_field(velocity_spectral, multipliers)))
  k_cutoff = T(dealias_fraction) * (N / 2) * (2π / L)
  dealias = spectral_cutoff(velocity_spectral, multipliers, k_cutoff)

  return SpectralOperators(grid, layout, velocity_plans, scalar_plans, multipliers, squared_wavenumber, dealias)
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
    physical_vector(ops)
    scalar_spectral(ops)

Allocate a single zeroed scratch field (vector in spectral representation, vector in physical
representation, or scalar in spectral representation) on `ops`'s backend and element type.
"""
spectral_vector(ops::SpectralOperators) =
  VectorFieldSpectral(_blank(ops, _complex_type(ops), spectral_field_shape(ops.grid, ops.layout, Val(1))), ops.grid)
physical_vector(ops::SpectralOperators) =
  VectorFieldPhysical(_blank(ops, _real_type(ops), physical_field_shape(ops.grid, Val(1))), ops.grid)
scalar_spectral(ops::SpectralOperators) =
  ScalarFieldSpectral(_blank(ops, _complex_type(ops), spectral_field_shape(ops.grid, ops.layout, Val(0))), ops.grid)


"""
    VelocityWorkspace(ops)

Preallocated scratch for one integrating-factor velocity step: the spectral vorticity, the two RK
stage slopes, the predictor field, a velocity copy (transforms consume their source), a general
spectral scratch, and the nonlinear-term buffer; the scalar integrating factor; and the physical
velocity / vorticity / predictor / Lamb-vector (`u × ω`) buffers. Sized so a step allocates no
field-sized memory.
"""
struct VelocityWorkspace{VS, SS, VP}
  vorticity_spectral::VS
  stage1::VS
  stage2::VS
  velocity_star_spectral::VS
  velocity_copy::VS
  scratch::VS
  nonlinear::VS
  integrating_factor::SS
  velocity::VP
  vorticity_start::VP
  vorticity_physical::VP
  velocity_star::VP
  lamb::VP
end


function VelocityWorkspace(ops::SpectralOperators)
  return VelocityWorkspace(
    spectral_vector(ops), spectral_vector(ops), spectral_vector(ops),
    spectral_vector(ops), spectral_vector(ops), spectral_vector(ops), spectral_vector(ops),
    scalar_spectral(ops),
    physical_vector(ops), physical_vector(ops), physical_vector(ops),
    physical_vector(ops), physical_vector(ops),
  )
end


"""
    dealias!(field, ops)

Apply the 2/3-rule low-pass `ops.dealias` to `field` in place (coefficientwise, alias-safe).
"""
dealias!(field, ops::SpectralOperators) = convolve!(field, field, ops.dealias)


"""
    random_solenoidal_velocity!(uh, ops; energy = 0.5, peak_wavenumber = 2.0, rng = default_rng())

Fill `uh` (a field in spectral representation) with a random, divergence-free velocity concentrated
at large scales by the envelope `exp(-|k|²/k_p²)` (`k_p = peak_wavenumber`), de-aliased, and rescaled
so its kinetic energy `½⟨|u|²⟩` equals `energy`. The Leray–Helmholtz projection makes it solenoidal.
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


end # module SimulationState

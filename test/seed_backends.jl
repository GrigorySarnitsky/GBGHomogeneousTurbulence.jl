# A seed determines the realization, whatever the backend (decision 107): a run on the CPU and one on a
# GPU, given the same seed, draw the same random numbers. Every random draw HT makes is checked here —
# the initial velocity and scalar fields, the tracers' initial positions, and `StochasticOU`'s forcing
# over a few steps — on the CPU and on the first functional GPU backend, from one seed each.
#
# What is compared, and how closely: a draw that reaches the run untransformed (the tracers'
# positions) must agree bitwise; one the run sees only through a transform (the seeded fields, the
# forcing's process) must agree to round-off, since the two backends' FFT libraries differ. The bound
# is stated in units of the element type's epsilon and was measured before it was frozen.
#
# A GPU is hardware, so this cannot be a plain `@test` on CI: with no functional backend the check is
# recorded as skipped, visibly, never as passed (the memory audit's device leg does the same). The
# GBGCodingTools session asked for this check to exist and run in HT before the property becomes a
# harness contract (2026-10-01).
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: prepare_forcing!
using GBGPeriodicFields: field_data, point_positions, CatmullRom
using Random

# Resolved at include time, as in the memory audit: a backend loaded inside a function is invisible
# to that function's world age.
const DEVICE_BACKEND = let found = nothing
  for (mod, arr) in (("CUDA", :CuArray), ("AMDGPU", :ROCArray))
    id = Base.identify_package(mod)
    id === nothing && continue
    m = try Base.require(id) catch; nothing end
    m === nothing && continue
    ok = try Base.invokelatest(getproperty(m, :functional)) catch; false end
    if ok
      found = (mod, getproperty(m, arr))
      break
    end
  end
  found
end

const N = 32
const SEED = 2026
# Agreement after a transform, in units of eps(T), relative to the largest magnitude. Measured
# 2026-10-01 on the RTX 5070 Ti: 1.03 / 1.05 / 2.28 eps in Float64 and 2.43 / 1.66 / 2.24 in Float32
# for the velocity, the scalar and the forcing. Frozen at about three times the largest.
const ROUNDOFF_EPS = 8

# Every random draw of a run, from one seed, brought back to the host for comparison.
function draws(array_type, T; seed = SEED)
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = T, array_type = array_type)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.5, envelope_wavenumber = 3.0,
                                       rng = Xoshiro(seed))
  φ̂ = new_scalar_field_spectral(domain)
  random_scalar_spectral!(φ̂, domain; scalar_variance = 1.0, envelope_wavenumber = 3.0,
                          rng = Xoshiro(seed + 1))
  tracers = Tracers(domain; number_of_particles = 64, interpolation_scheme = CatmullRom,
                    rng = Xoshiro(seed + 2))
  ou = StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5, seed = seed + 3)
  state = initial_forcing_state(ou, û, domain)
  for _ in 1:5
    prepare_forcing!(ou, state, û, domain, 1e-2)
  end
  return (velocity = Array(field_data(û)), scalar = Array(field_data(φ̂)),
          positions = Array(point_positions(tracers.positions)),
          forcing = Array(field_data(state.process)))
end

relative_eps(a, b, T) = maximum(abs, a .- b) / maximum(abs, a) / eps(T)


@testset "a seed determines the realization on every backend" begin
  if DEVICE_BACKEND === nothing
    @warn "seed check: no functional GPU backend in this environment, so the CPU/GPU comparison of " *
          "decision 107 did not run. It is SKIPPED, not passed."
    @test_skip false
  else
    name, device_array = DEVICE_BACKEND
    for T in (Float64, Float32)
      host, device = draws(Array, T), draws(device_array, T)
      @test host.positions == device.positions                     # untransformed: bitwise
      for part in (:velocity, :scalar, :forcing)
        e = relative_eps(getproperty(host, part), getproperty(device, part), T)
        @info "seed check on $name, $T: $part agrees to $(round(e; digits = 2)) eps"
        @test e <= ROUNDOFF_EPS                                     # transformed: round-off
      end
    end
    # The check can fail: a GPU run from a different seed is refused on every draw.
    host, other = draws(Array, Float64), draws(device_array, Float64; seed = SEED + 100)
    @test host.positions != other.positions
    @test all(part -> relative_eps(getproperty(host, part), getproperty(other, part), Float64) > ROUNDOFF_EPS,
              (:velocity, :scalar, :forcing))
  end
end

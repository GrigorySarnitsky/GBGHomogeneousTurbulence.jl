# A seed determines the realization, whatever the backend (decision 107): a run on the CPU and one on a
# GPU, given the same seed, draw the same random numbers. HT declares this as the harness contract
# RULE.TEST.SEED_PARITY by calling the tool's engine, `TestHarness.seed_parity`, with every random draw
# it makes — the initial velocity and scalar fields, the tracers' initial positions, and
# `StochasticOU`'s forcing over a few steps.
#
# A draw the run uses as drawn (the positions) is `exact`: bitwise equal on every backend. One it sees
# only through a transform (the seeded fields, the forcing's process) is `rounded`: within the bound,
# in machine epsilon, since the backends' FFT libraries differ. The engine also requires a run from
# another seed to be told apart on every draw. HT measured the bound before the contract existed
# (2026-10-01, RTX 5070 Ti, 32³): at most 2.43 eps, so 8.
#
# A GPU is hardware: with no functional backend the engine records a visible skip, never a pass.
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: prepare_forcing!
using GBGPeriodicFields: field_data, point_positions, CatmullRom
using Random
import GBGCodingTools

# Resolved at include time, as in the memory audit: a backend loaded inside a function is invisible
# to that function's world age.
const DEVICE_ARRAY = let found = nothing
  for (mod, arr) in (("CUDA", :CuArray), ("AMDGPU", :ROCArray))
    id = Base.identify_package(mod)
    id === nothing && continue
    m = try Base.require(id) catch; nothing end
    m === nothing && continue
    ok = try Base.invokelatest(getproperty(m, :functional)) catch; false end
    if ok
      found = getproperty(m, arr)
      break
    end
  end
  found
end
const BACKENDS = DEVICE_ARRAY === nothing ? [Array] : [Array, DEVICE_ARRAY]

const N = 32

# Every random draw of a run from `seed`, on the storage family `backend`, in element type `T`.
function draws(seed, backend, T)
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = T, array_type = backend)
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
  return (exact = (; positions = point_positions(tracers.positions)),
          rounded = (; velocity = field_data(û), scalar = field_data(φ̂),
                       forcing = field_data(state.process)))
end


@testset "a seed determines the realization on every backend" begin
  for T in (Float64, Float32)
    measured = GBGCodingTools.TestHarness.seed_parity((seed, backend) -> draws(seed, backend, T), BACKENDS;
                                                      seed = 2026, other_seed = 2126, bound = 8)
    measured === nothing ||
      @info "seed parity, $T: transformed draws within (eps)" measured.rounded
  end
end

# Witness — CLAUDE.md invariant 4: "the hot loop (`step!`) is in-place and allocation-free over the
# preallocated buffers". This asserts the invariant literally: a warmed-up `step!` on a preallocated
# state / buffers / cache must allocate nothing, for every scheme, with NoForcing and no tracers.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


function step_allocation(scheme, N::Int)
  T = Float64
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(scheme, domain; scalar = false)
  conditions = FlowConditions(viscosity = 5.0e-2, velocity_forcing = NoForcing(),
                              schmidt = 1.0, scalar_forcing = NoForcing())
  generator = ResolvedGenerator(domain, conditions; scalar = false)

  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.6,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(42))
  truncate_to_band!(û, domain)
  state = ResolvedFields(û, nothing)
  cache = ObservablesCache(domain; scalar = false)
  deposit!(cache, state, domain, buffers)

  dt = 1.0e-3
  for _ in 1:2                                    # warm up: compile, and settle the cache/registers
    step!(scheme, state, generator, domain, buffers, cache, dt)
    deposit!(cache, state, domain, buffers)
  end
  bytes = @allocated step!(scheme, state, generator, domain, buffers, cache, dt)
  deposit!(cache, state, domain, buffers)
  return bytes
end


@testset "step! is allocation-free over the preallocated buffers (invariant 4)" begin
  for scheme in (IFLowStorageRK3(), IFRK2())
    for N in (8, 16, 32)
      bytes = step_allocation(scheme, N)
      @info "step! allocation" scheme N bytes
      @test bytes == 0
    end
  end
end

# Witness: an announced out-of-band change to the resolved fields must not leave the multistep
# particle integration scheme extrapolating over Lagrangian samples taken in the abandoned flow.
#
# The package states the invariant for the position case (`restart!` / `particles_modified!`:
# "integrating over those would blend the old path with the new one"). A reseeded velocity field
# abandons the flow those samples measured in exactly the same way, and the sanctioned reseed
# protocol documented on `random_solenoidal_velocity_spectral!` — reseed, `fields_modified!`,
# `deposit!` — is the only sequence a user is told to run.

using Test
using GBGPeriodicFields: point_positions
using Random: MersenneTwister
using GBGHomogeneousTurbulence

function warmed_run(seed)
  s = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 6,
                 particle_integration_scheme = AdamsBashforth(order = 4), rng = MersenneTwister(seed))
  for _ in 1:6
    advance!(s; dt = 2e-3)
  end
  return s
end

function announced_reseed!(s)
  random_solenoidal_velocity_spectral!(s.state.velocity_spectral, s.domain;
                                       kinetic_energy = 1.5, envelope_wavenumber = 3.0,
                                       rng = MersenneTwister(99))
  fields_modified!(s.cache)
  deposit!(s)
  return s
end

@testset "an announced out-of-band field change must not feed pre-mutation Lagrangian samples into the next multistep tracer update" begin
  a = warmed_run(3)
  b = warmed_run(3)
  @test a.cache.history_filled == 3                       # AB4 is past its bootstrap
  @test point_positions(a.tracers.positions) == point_positions(b.tracers.positions)

  announced_reseed!(a)                                    # the documented protocol, nothing more
  announced_reseed!(b)
  restart!(b.particle_integration_scheme, b.particle_buffers)       # b additionally discards the stale history

  advance!(a; dt = 2e-3)
  advance!(b; dt = 2e-3)

  Xa, Xb = point_positions(a.tracers.positions), point_positions(b.tracers.positions)
  @info "witness" history_after_reseed_a = a.cache.history_filled max_difference = maximum(abs, Xa .- Xb)
  # The invariant: the update after an announced reseed may depend only on post-reseed measurements,
  # so discarding the pre-reseed history must change nothing.
  @test Xa == Xb
end

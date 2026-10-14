# Witness: an announced out-of-band replacement of the velocity field must not leave the
# Adams–Bashforth trajectory history holding samples measured in the field that was replaced.
#
# `random_solenoidal_velocity_spectral!`'s own note (src/State.jl:88-98) sanctions the sequence
# "seed into a live run → `fields_modified!` → `deposit!` → advance again".  `deposit!(sim)`
# re-records the CURRENT Lagrangian sample from the new field, but `fields_modified!`
# (src/Cache.jl:352) advances the fields epoch only: `cache.velocity_at_particles_history` keeps the
# samples interpolated from the DISCARDED field, and `advect!(::AdamsBashforth, …)` — which decides
# on `cache.history_filled` alone — blends them into the next position update at full weight
# (equal steps, order 4: 55/24·fₙ − 59/24·f₁ + 37/24·f₂ − 9/24·f₃).
#
# The assertion below is physical, not stylistic: over one CFL-limited step a tracer displacement
# must be the explicit-Euler displacement h·u(Xₙ) up to the field's own change over that step,
# i.e. the relative departure must be O(h/τ) ≪ 1 — whatever the particle integration scheme.  A control run
# that takes the identical step with an intact history calibrates that number.
#
# Measured on the tree of 2026-08-20: departure_control = 0.0475, departure_reseed = 1.750 — the
# post-reseed displacement is off by 175% of the Euler displacement, a 37x degradation.
#
# The fix is NOT to clear the history inside `fields_modified!` as it stands: `step!` calls that
# same verb (src/Propagator.jl:327, 430), so the history could never fill.  It is the split the
# particle side already made — a private `advance_fields_epoch!` for the run's own step, with
# `fields_modified!` the out-of-band verb that also discards the history, mirroring
# `advance_particles_epoch!` / `particles_modified!` (src/Cache.jl:388-397).  Verified: with that
# split applied, departure_reseed falls to 0.0372 and this file passes.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions
using Random
using Test

const N = 16
const K = 4
const M = 8

fresh_sim() = Simulation(grid_points_per_axis = N, viscosity = 0.05,
                         particles = ParticleTracking(number_of_particles = M,
                                                      particle_integration_scheme = AdamsBashforth(order = K)),
                         rng = MersenneTwister(3))

# Relative departure of one tracer step from the explicit-Euler displacement built on the velocity
# the tracers actually sample in the field they are moving in.  Dimensionless, and small for any
# consistent trajectory integrator at a CFL-limited step.
function euler_departure!(sim, h)
  L  = Float64(sim.domain.grid.domain_size[1])
  X0 = copy(Array(point_positions(sim.tracers.positions)))
  f0 = copy(Array(velocity_at_particles(sim.cache)))
  advance!(sim; dt = h)
  d  = copy(Array(point_positions(sim.tracers.positions))) .- X0
  d .= d .- L .* round.(d ./ L)                    # undo the periodic wrap
  return maximum(abs.(d .- h .* f0)) / (h * maximum(abs.(f0)))
end


@testset "a reseeded velocity field must not be integrated against the old field's tracer samples" begin
  # ---- control: the same step, taken with a history that belongs to the field it is used in ----
  control = fresh_sim()
  for _ in 1:5
    advance!(control)
  end
  @test control.cache.history_filled == K - 1        # precondition: steady multistep operation
  h = control.cache.history_steps[1]                  # keep stepping at the size the run has settled on
  departure_control = euler_departure!(control, h)

  # ---- the sanctioned out-of-band reseed, exactly as the seeder's note prescribes ----
  sim = fresh_sim()
  for _ in 1:5
    advance!(sim)
  end
  @test sim.cache.history_filled == K - 1
  random_solenoidal_velocity_spectral!(sim.state.velocity_spectral, sim.domain, 1.5; envelope_wavenumber = 2.0,
                                       rng = MersenneTwister(999))
  fields_modified!(sim.cache)                        # announce …
  deposit!(sim)                                      # … and restore the cache
  departure_reseed = euler_departure!(sim, h)

  @info "one-step departure from the Euler displacement" departure_control departure_reseed

  # The step after the reseed must be as faithful to the new field as an ordinary step is to its
  # own — the history either belongs to the field or is discarded, and either way this holds.
  @test departure_reseed <= 5 * departure_control
end

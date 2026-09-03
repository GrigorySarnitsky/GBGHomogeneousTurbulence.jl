# Witness: the `AdamsBashforth` docstring promises "the same restart happens if the tracers are
# reseeded" — after a hand-written reseed of `point_positions(tracers.positions)` (the pattern `particles_modified!`
# sanctions: "a reseed, a hand-written correction, any direct write to the tracer storage"), the
# scheme must fall back to the `Heun` startup instead of blending Lagrangian samples taken
# along the *old*, pre-reseed trajectory into the *new* one.

using Test
using GBGPeriodicFields: point_positions, npoints
using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, CatmullRom, point_values, PointSet


# A smooth, spatially varying velocity field, so that a sample taken at the old positions differs
# from one taken at the new ones (a uniform field could not tell the two apart).
function varying_field(domain, N, L, T, phase)
  d = zeros(T, N, N, N, 3)
  for k in 1:N, j in 1:N, i in 1:N
    x, y, z = (i - 1) * L / N, (j - 1) * L / N, (k - 1) * L / N
    d[i, j, k, 1] = 0.6 + 0.4 * sin(x + phase)
    d[i, j, k, 2] = 0.3 * cos(y + phase)
    d[i, j, k, 3] = 0.2 * sin(z + phase)
  end
  return VectorFieldPhysical(d, domain.grid)
end


@testset "AdamsBashforth restarts on a tracer reseed, as its docstring promises" begin
  T, N, L = Float64, 16, 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  u0 = varying_field(domain, N, L, T, 0.0)     # the field at tₙ
  u1 = varying_field(domain, N, L, T, 0.15)    # the field at tₙ₊₁
  dt = 0.02

  X0 = T[0.3 0.4 0.5; 1.7 2.3 3.1; 4.4 5.0 1.2]     # the seeded trajectory
  X1 = T[5.1 0.9 2.2; 2.8 4.6 0.7; 1.1 3.3 5.9]     # the reseeded one, elsewhere in the box

  scheme = AdamsBashforth(order = 2)                # K = 2 ⇒ one past sample needed
  tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
  # The sample history now lives in the ObservablesCache that owns the observable it extends, so an
  # independent integrator needs its own cache to hold its own history. The assertion is unchanged.
  cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                           history_depth = history_depth(scheme))
  buffers = allocate_buffers(scheme, tracers, cache)

  for _ in 1:2                                      # warm the history up past the startup steps
    deposit!(cache, tracers, u0)
    advect!(scheme, tracers, u1, domain, buffers, dt)
  end
  @test cache.history_filled == 1                         # history full: the multistep branch is live

  # CORRECTED 2026-08-20. As written, this wrote the tracer storage and recorded the fresh sample
  # WITHOUT announcing the reposition, then demanded the history restart anyway — which would require
  # the integrator to detect an unannounced mutation of an array it does not watch, i.e. a per-step
  # comparison and a host-device sync. The contract is that an out-of-band write is announced;
  # `particles_modified!` is the announcement, and the sibling witness 03-state-machine-03 tests the
  # announced path. Adding the announcement here makes this test the contract rather than a stronger
  # claim no design satisfies.
  copyto!(point_positions(tracers.positions), X1)
  particles_modified!(cache)
  deposit!(cache, tracers, u0)
  @test cache.history_filled == 0                         # the promised restart: no history to reuse

  advect!(scheme, tracers, u1, domain, buffers, dt)
  reseeded = copy(point_positions(tracers.positions))

  # The behaviour the docstring promises: an `Heun` startup step from the new positions.
  reference = Tracers(domain; positions = PointSet(copy(X1)), interpolation_scheme = CatmullRom)
  reference_cache = ObservablesCache(domain; number_of_particles = npoints(reference.positions))
  heun = allocate_buffers(Heun(), reference, reference_cache)
  deposit!(reference_cache, reference, u0)
  advect!(Heun(), reference, u1, domain, heun, dt)

  @test reseeded ≈ point_positions(reference.positions)
end

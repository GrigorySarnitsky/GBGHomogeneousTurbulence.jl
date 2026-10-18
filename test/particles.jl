# Lagrangian tracer tests. Key checks: a uniform velocity advects tracers exactly; the Heun-in-time
# integration is second-order (a time-varying uniform field, so the only error is temporal);
# positions wrap periodically; the interpolation scheme is pluggable; sampling reads a field along
# the trajectories; and the two-verb push (record + advect) allocates nothing per step.

using GBGHomogeneousTurbulence
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, ScalarFieldPhysical, field_data, to_physical, PointSet,
                         CatmullRom, LagrangeSpline, point_values
using Random
using Test


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)


@testset "particles" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_family = Array)
  uniform = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

  @testset "uniform field advects exactly" begin
    X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0; 2.0 3.0 4.0]
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    buffers = allocate_buffers(Heun(), tracers, cache)
    c = 0.5
    set_uniform_x!(uniform, c)
    nsteps, dt = 20, 0.005
    for _ in 1:nsteps
      deposit!(cache, tracers, uniform)
      advect!(Heun(), tracers, uniform, domain, buffers, dt)
    end
    X = point_positions(tracers.positions)
    @test X[:, 1] ≈ mod.(X0[:, 1] .+ c * nsteps * dt, L)     # moved at constant speed
    @test X[:, 2] ≈ X0[:, 2]                                  # transverse components unchanged
    @test X[:, 3] ≈ X0[:, 3]
  end

  @testset "Heun-in-time is second order" begin
    ω = 1.0
    Tfinal = 0.5
    X0 = T[1.0 1.0 1.0]
    exact_x = X0[1, 1] + sin(ω * Tfinal) / ω                  # ∫₀ᵀ cos(ωt) dt

    final_x(nsteps) = begin
      tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
      cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
      buffers = allocate_buffers(Heun(), tracers, cache)
      u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      dt = Tfinal / nsteps
      for n in 0:nsteps-1
        set_uniform_x!(u_start, cos(ω * n * dt))
        set_uniform_x!(u_end, cos(ω * (n + 1) * dt))
        deposit!(cache, tracers, u_start)
        advect!(Heun(), tracers, u_end, domain, buffers, dt)
      end
      point_positions(tracers.positions)[1, 1]
    end

    error_coarse = abs(final_x(8) - exact_x)
    error_fine = abs(final_x(16) - exact_x)
    @test 3.0 < error_coarse / error_fine < 6.0               # ≈ 4 ⇒ second order
  end

  @testset "positions wrap into [0, L)" begin
    X0 = T[6.2 6.2 6.2]                                        # near the upper boundary (L = 2π ≈ 6.283)
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
    cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions))
    buffers = allocate_buffers(Heun(), tracers, cache)
    set_uniform_x!(uniform, 1.0)
    for _ in 1:30
      deposit!(cache, tracers, uniform)
      advect!(Heun(), tracers, uniform, domain, buffers, 0.02)
    end
    X = point_positions(tracers.positions)
    @test all(0 .<= X .< L)                                    # wrapped, still in the box
  end

  @testset "pluggable scheme" begin
    set_uniform_x!(uniform, 0.3)
    for scheme in (CatmullRom, LagrangeSpline(6))
      tracers = Tracers(domain; number_of_particles = 50, interpolation_scheme = scheme, rng = MersenneTwister(1))
      cache = ObservablesCache(domain; number_of_particles = 50)
      buffers = allocate_buffers(Heun(), tracers, cache)
      for _ in 1:10
        deposit!(cache, tracers, uniform)
        advect!(Heun(), tracers, uniform, domain, buffers, 0.01)
      end
      X = point_positions(tracers.positions)
      @test all(isfinite, X) && all(0 .<= X .< L)
    end
  end

  @testset "interpolate_at_particles! reads a field along trajectories" begin
    tracers = Tracers(domain; number_of_particles = 40, interpolation_scheme = CatmullRom, rng = MersenneTwister(2))
    constant = ScalarFieldPhysical(Array, (x, y, z) -> 2.5, domain.grid)
    samples = new_scalar_point_values(tracers)
    interpolate_at_particles!(samples, constant, tracers)
    @test all(≈(2.5), point_values(samples))                  # a constant field samples exactly
  end

  @testset "advect in a real HIT velocity field" begin
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.05,
                      velocity_forcing = VarianceRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain, 0.5; envelope_wavenumber = 2.0, rng = MersenneTwister(4))
    truncate_to_band!(û, domain)
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true, number_of_particles = 200)
    deposit!(cache, state, domain, buffers)
    tracers = Tracers(domain; number_of_particles = 200, interpolation_scheme = CatmullRom, rng = MersenneTwister(5))
    push_buffers = allocate_buffers(Heun(), tracers, cache)   # the particle integration scheme's registers,
                                                               # distinct from the field scheme's

    Δx = L / N
    for _ in 1:50
      u = velocity_physical(cache)
      dt = 0.4 * Δx / max(max_speed(cache), 1e-6)
      deposit!(cache, tracers, u)                           # u(tₙ), onto the tracers
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
      advect!(Heun(), tracers, velocity_physical(cache), domain, push_buffers, dt)   # u(tₙ₊₁), the closing deposit
    end
    @test all(isfinite, point_positions(tracers.positions)) && all(0 .<= point_positions(tracers.positions) .< L)
    @test all(isfinite, point_values(cache.velocity_at_particles))

    # allocation-free advection step — both verbs of the push
    u = velocity_physical(cache)
    bytes = @allocated (deposit!(cache, tracers, u);
                        advect!(Heun(), tracers, u, domain, push_buffers, 0.001))
    @test bytes < 4096
  end
end

# Adams–Bashforth: the variable-step weights are the machinery, so they are pinned against the
# classical constants they must reduce to at uniform step — and the bootstrap/handover is pinned
# end to end, since a multistep scheme that silently never leaves its startup would still "work".
@testset "AdamsBashforth" begin
  # The solve writes into caller-supplied scratch (the hot loop is allocation-free), so the test
  # wrapper supplies it and returns the filled weights.
  AB(h, steps, k) = GBGHomogeneousTurbulence.Particles._adams_bashforth_weights(
                      zeros(Float64, k), zeros(Float64, k), h, steps, k)

  @testset "variable-step weights reduce to the classical coefficients" begin
    @test AB(1.0, [1.0, 1.0, 1.0], 4) ≈ [55, -59, 37, -9] ./ 24
    @test AB(1.0, [1.0, 1.0], 3)      ≈ [23, -16, 5] ./ 12
    @test AB(1.0, [1.0], 2)           ≈ [3, -1] ./ 2
    @test AB(1.0, Float64[], 1)       ≈ [1.0]
    # a weight set must reproduce a constant exactly, whatever the step history
    @test sum(AB(0.7, [0.3, 0.9, 0.2], 4)) ≈ 0.7
  end

  @testset "the history fills and the scheme takes over" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 32,
                                                  particle_integration_scheme = AdamsBashforth(order = 4)),
                     rng = MersenneTwister(7))
    # The sample history is the cache's: it holds earlier values of a deposited observable, so an
    # announced reposition invalidates it where the epoch lives rather than in the scheme's registers.
    @test sim.particle_buffers isa ParticleIntegratorBuffers
    @test sim.cache.history_filled == 0               # nothing recorded before the first step
    advance!(sim)
    @test sim.cache.history_filled == 1               # still starting up
    for _ in 1:4; advance!(sim); end
    @test sim.cache.history_filled == 3               # history full: AB4 from here on

    # The run's own advance must NOT be read as a reposition made outside the iteration: it announces the tracer
    # push every step, and clearing the history there would pin the scheme in its bootstrap forever.
    advance!(sim)
    @test sim.cache.history_filled == 3

    # An announced reposition does clear it, through the cache that owns both the epoch and the
    # samples — no second call, and no reference from the cache to the scheme's registers.
    particles_modified!(sim.cache)
    @test sim.cache.history_filled == 0
    @test all(isfinite, point_positions(sim.tracers.positions))
  end

  @testset "positions stay in the box and tracers actually move" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 32,
                                                  particle_integration_scheme = AdamsBashforth(order = 2)),
                     rng = MersenneTwister(8))
    X0 = copy(point_positions(sim.tracers.positions))
    for _ in 1:5; advance!(sim); end
    X = point_positions(sim.tracers.positions)
    @test !isapprox(X0, X)
    @test all(0 .<= X .< sim.domain.grid.domain_size[1])
  end

  # Decision 86: the traversal order reorders the gathers' visits and changes no value, so a run
  # with it must be BITWISE the run without it — the witness that the wiring passed the order to
  # the right gathers and nothing else. Under `:manual` the order goes stale as the tracers move,
  # which the field library documents as never wrong; the identical assertion holds unrebuilt.
  @testset "the traversal order is a value-preserving accelerator (decision 86)" begin
    function tracked(mode; scheme = Heun(), steps = 6, M = 300)
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(3),
                       particles = ParticleTracking(number_of_particles = M, unwrapped = true,
                                                    particle_integration_scheme = scheme,
                                                    traversal_mode = mode))
      for _ in 1:steps; advance!(sim); end
      sim
    end
    for scheme in (Heun(), AdamsBashforth(order = 3))
      off = tracked(:none; scheme)
      for mode in (:automatic, :manual)
        on = tracked(mode; scheme)
        @test point_positions(on.tracers.positions) == point_positions(off.tracers.positions)
        @test point_positions(unwrapped_positions(on.tracers)) ==
              point_positions(unwrapped_positions(off.tracers))
        @test velocity_at_particles(on.cache) == velocity_at_particles(off.cache)
        @test on.particle_traversal isa ParticleTraversal
        @test on.particle_traversal.automatic == (mode !== :manual)
      end
      @test off.particle_traversal === nothing
    end

    # A caller's gather takes the same order, with the same values.
    on = tracked(:automatic); off = tracked(:none)
    a = new_vector_point_values(on.tracers); b = new_vector_point_values(off.tracers)
    interpolate_at_particles!(a, velocity_physical(on.cache), on.tracers;
                              traversal = on.particle_traversal)
    interpolate_at_particles!(b, velocity_physical(off.cache), off.tracers)
    @test point_values(a) == point_values(b)

    # A rebuilt order agrees with a freshly built one from the same positions.
    man = tracked(:manual)
    rebuild_traversal!(man)
    fresh = ParticleTraversal(man.domain, man.tracers)
    @test Array(man.particle_traversal.order.indices) == Array(fresh.order.indices)
    @test sort(Int.(Array(fresh.order.indices))) == 1:300

    # A reposition then an advance still matches the run without an order: the automatic rebuild
    # reads the start-of-step positions, so an announced reseed needs no traversal verb of its own.
    on = tracked(:automatic; steps = 2); off = tracked(:none; steps = 2)
    for s in (on, off)
      copyto!(point_positions(s.tracers.positions),
              s.domain.grid.domain_size[1] .* rand(MersenneTwister(11), 300, 3))
      particles_modified!(s); deposit!(s); advance!(s)
    end
    @test point_positions(on.tracers.positions) == point_positions(off.tracers.positions)
  end

  @testset "the traversal order adds no per-step allocation that scales with M" begin
    alloc(M) = (sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                 particles = ParticleTracking(number_of_particles = M),
                                 rng = MersenneTwister(1));
                advance!(sim); advance!(sim); @allocated advance!(sim))
    # Tenfold in M, both above the count where a threaded run's CPU kernels stop adding tasks (the
    # task setup grows with M up to a cap and then stays flat, measured 2026-10-09; one thread is flat
    # throughout), so any growth left is an M-sized buffer.
    small, large = alloc(40_000), alloc(400_000)
    @test large <= small + 512               # constant launch bookkeeping, not an M-sized buffer
  end

  @testset "the traversal setting is refused by name where it cannot apply" begin
    # Since 2026-10-14 the mode travels inside `ParticleTracking`, so it cannot be written for a
    # tracer-free run at all; a mode that is not one of the three is refused where it is named.
    @test_throws MethodError Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                        traversal_mode = :manual)
    @test_throws ArgumentError ParticleTracking(number_of_particles = 8, traversal_mode = :sometimes)
    @test_throws ArgumentError ParticleTracking(number_of_particles = 0)
    @test_throws ArgumentError rebuild_traversal!(Simulation(grid_points_per_axis = 16, viscosity = 0.05))
    @test_throws ArgumentError rebuild_traversal!(Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                                             particles = ParticleTracking(number_of_particles = 8,
                                                                                          traversal_mode = :none)))
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 8, traversal_mode = :manual))
    @test rebuild_traversal!(sim) === sim
  end
end

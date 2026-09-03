# Lagrangian tracer tests. Key checks: a uniform velocity advects tracers exactly; the Heun-in-time
# integration is second-order (a time-varying uniform field, so the only error is temporal);
# positions wrap periodically; the interpolation scheme is pluggable; sampling reads a field along
# the trajectories; and the two-verb push (record + advect) allocates nothing per step.

using GBGIsotropicTurbulence
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
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_type = Array)
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
    for scheme in (CatmullRom, LagrangeSpline(2))
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
    constant = ScalarFieldPhysical((x, y, z) -> 2.5, domain.grid)
    samples = new_scalar_point_values(tracers)
    interpolate_at_particles!(samples, constant, tracers)
    @test all(≈(2.5), point_values(samples))                  # a constant field samples exactly
  end

  @testset "advect in a real HIT velocity field" begin
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.05,
                      velocity_forcing = VarianceRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(4))
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
  AB(h, steps, k) = GBGIsotropicTurbulence.Particles._adams_bashforth_weights(
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
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 32,
                     particle_integration_scheme = AdamsBashforth(order = 4), rng = MersenneTwister(7))
    # The sample history is the cache's: it holds earlier values of a deposited observable, so an
    # announced reposition invalidates it where the epoch lives rather than in the scheme's registers.
    @test sim.particle_buffers isa ParticleIntegratorBuffers
    @test sim.cache.history_filled == 0               # nothing recorded before the first step
    advance!(sim)
    @test sim.cache.history_filled == 1               # still starting up
    for _ in 1:4; advance!(sim); end
    @test sim.cache.history_filled == 3               # history full: AB4 from here on

    # The run's own advance must NOT be read as an out-of-band reposition: it announces the tracer
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
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 32,
                     particle_integration_scheme = AdamsBashforth(order = 2), rng = MersenneTwister(8))
    X0 = copy(point_positions(sim.tracers.positions))
    for _ in 1:5; advance!(sim); end
    X = point_positions(sim.tracers.positions)
    @test !isapprox(X0, X)
    @test all(0 .<= X .< sim.domain.grid.domain_size[1])
  end
end

# Lagrangian tracer tests. Key checks: a uniform velocity advects tracers exactly; the Heun-in-time
# integration is second-order (a time-varying uniform field, so the only error is temporal);
# positions wrap periodically; the interpolation scheme is pluggable; sampling reads a field along
# the trajectories; and the two-verb push (record + advect) allocates nothing per step.

using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorFieldPhysical, ScalarFieldPhysical, field_data, to_physical,
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
    tracers = Tracers(domain; positions = copy(X0), interpolation_scheme = CatmullRom)
    buffers = allocate_buffers(EndpointHeun(), tracers)
    c = 0.5
    set_uniform_x!(uniform, c)
    nsteps, dt = 20, 0.005
    for _ in 1:nsteps
      record_particle_velocities!(tracers, uniform)
      advect!(EndpointHeun(), tracers, uniform, domain, buffers, dt)
    end
    X = particle_positions(tracers)
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
      tracers = Tracers(domain; positions = copy(X0), interpolation_scheme = CatmullRom)
      buffers = allocate_buffers(EndpointHeun(), tracers)
      u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      dt = Tfinal / nsteps
      for n in 0:nsteps-1
        set_uniform_x!(u_start, cos(ω * n * dt))
        set_uniform_x!(u_end, cos(ω * (n + 1) * dt))
        record_particle_velocities!(tracers, u_start)
        advect!(EndpointHeun(), tracers, u_end, domain, buffers, dt)
      end
      particle_positions(tracers)[1, 1]
    end

    error_coarse = abs(final_x(8) - exact_x)
    error_fine = abs(final_x(16) - exact_x)
    @test 3.0 < error_coarse / error_fine < 6.0               # ≈ 4 ⇒ second order
  end

  @testset "positions wrap into [0, L)" begin
    X0 = T[6.2 6.2 6.2]                                        # near the upper boundary (L = 2π ≈ 6.283)
    tracers = Tracers(domain; positions = copy(X0), interpolation_scheme = CatmullRom)
    buffers = allocate_buffers(EndpointHeun(), tracers)
    set_uniform_x!(uniform, 1.0)
    for _ in 1:30
      record_particle_velocities!(tracers, uniform)
      advect!(EndpointHeun(), tracers, uniform, domain, buffers, 0.02)
    end
    X = particle_positions(tracers)
    @test all(0 .<= X .< L)                                    # wrapped, still in the box
  end

  @testset "pluggable scheme" begin
    set_uniform_x!(uniform, 0.3)
    for scheme in (CatmullRom, LagrangeSpline(2))
      tracers = Tracers(domain; number_of_particles = 50, interpolation_scheme = scheme, rng = MersenneTwister(1))
      buffers = allocate_buffers(EndpointHeun(), tracers)
      for _ in 1:10
        record_particle_velocities!(tracers, uniform)
        advect!(EndpointHeun(), tracers, uniform, domain, buffers, 0.01)
      end
      X = particle_positions(tracers)
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
                      velocity_forcing = BandRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(4))
    truncate_to_band!(û, domain)
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    deposit!(cache, state, domain, buffers)
    tracers = Tracers(domain; number_of_particles = 200, interpolation_scheme = CatmullRom, rng = MersenneTwister(5))
    push_buffers = allocate_buffers(EndpointHeun(), tracers)   # the trajectory scheme's registers,
                                                               # distinct from the field scheme's

    Δx = L / N
    for _ in 1:50
      u = velocity_physical(cache)
      dt = 0.4 * Δx / max(max_speed(cache), 1e-6)
      record_particle_velocities!(tracers, u)                           # u(tₙ), onto the tracers
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
      advect!(EndpointHeun(), tracers, velocity_physical(cache), domain, push_buffers, dt)   # u(tₙ₊₁), the closing deposit
    end
    @test all(isfinite, particle_positions(tracers)) && all(0 .<= particle_positions(tracers) .< L)
    @test all(isfinite, point_values(tracers.particle_velocities))

    # allocation-free advection step — both verbs of the push
    u = velocity_physical(cache)
    bytes = @allocated (record_particle_velocities!(tracers, u);
                        advect!(EndpointHeun(), tracers, u, domain, push_buffers, 0.001))
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
                     trajectory_scheme = AdamsBashforth(order = 4), rng = MersenneTwister(7))
    @test sim.particle_buffers isa MultistepBuffers
    @test sim.particle_buffers.filled == 0            # nothing recorded before the first step
    advance!(sim)
    @test sim.particle_buffers.filled == 1            # still starting up
    for _ in 1:4; advance!(sim); end
    @test sim.particle_buffers.filled == 3            # history full: AB4 from here on
    @test all(isfinite, particle_positions(sim.tracers))
  end

  @testset "positions stay in the box and tracers actually move" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, number_of_particles = 32,
                     trajectory_scheme = AdamsBashforth(order = 2), rng = MersenneTwister(8))
    X0 = copy(particle_positions(sim.tracers))
    for _ in 1:5; advance!(sim); end
    X = particle_positions(sim.tracers)
    @test !isapprox(X0, X)
    @test all(0 .<= X .< sim.domain.grid.domain_size[1])
  end
end

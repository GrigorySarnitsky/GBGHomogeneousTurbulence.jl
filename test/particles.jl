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
    tracers = Tracers(domain, copy(X0); scheme = CatmullRom)
    c = 0.5
    set_uniform_x!(uniform, c)
    nsteps, dt = 20, 0.005
    for _ in 1:nsteps
      record_trajectory_velocity!(tracers, uniform)
      advect!(tracers, uniform, domain, dt)
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
      tracers = Tracers(domain, copy(X0); scheme = CatmullRom)
      u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      u_end = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
      dt = Tfinal / nsteps
      for n in 0:nsteps-1
        set_uniform_x!(u_start, cos(ω * n * dt))
        set_uniform_x!(u_end, cos(ω * (n + 1) * dt))
        record_trajectory_velocity!(tracers, u_start)
        advect!(tracers, u_end, domain, dt)
      end
      particle_positions(tracers)[1, 1]
    end

    error_coarse = abs(final_x(8) - exact_x)
    error_fine = abs(final_x(16) - exact_x)
    @test 3.0 < error_coarse / error_fine < 6.0               # ≈ 4 ⇒ second order
  end

  @testset "positions wrap into [0, L)" begin
    X0 = T[6.2 6.2 6.2]                                        # near the upper boundary (L = 2π ≈ 6.283)
    tracers = Tracers(domain, copy(X0); scheme = CatmullRom)
    set_uniform_x!(uniform, 1.0)
    for _ in 1:30
      record_trajectory_velocity!(tracers, uniform)
      advect!(tracers, uniform, domain, 0.02)
    end
    X = particle_positions(tracers)
    @test all(0 .<= X .< L)                                    # wrapped, still in the box
  end

  @testset "pluggable scheme" begin
    set_uniform_x!(uniform, 0.3)
    for scheme in (CatmullRom, LagrangeSpline(2))
      tracers = Tracers(domain, 50; scheme = scheme, rng = MersenneTwister(1))
      for _ in 1:10
        record_trajectory_velocity!(tracers, uniform)
        advect!(tracers, uniform, domain, 0.01)
      end
      X = particle_positions(tracers)
      @test all(isfinite, X) && all(0 .<= X .< L)
    end
  end

  @testset "interpolate_at_particles! reads a field along trajectories" begin
    tracers = Tracers(domain, 40; scheme = CatmullRom, rng = MersenneTwister(2))
    constant = ScalarFieldPhysical((x, y, z) -> 2.5, domain.grid)
    samples = new_scalar_point_values(tracers)
    interpolate_at_particles!(samples, constant, tracers)
    @test all(≈(2.5), point_values(samples))                  # a constant field samples exactly
  end

  @testset "advect in a real HIT velocity field" begin
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.05,
                      velocity_forcing = BandRescaling(domain; target = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(4))
    truncate_to_band!(û, domain)
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    deposit!(cache, state, domain, buffers)
    tracers = Tracers(domain, 200; scheme = CatmullRom, rng = MersenneTwister(5))

    Δx = L / N
    for _ in 1:50
      u = velocity_physical(cache)
      dt = 0.4 * Δx / max(max_speed(cache), 1e-6)
      record_trajectory_velocity!(tracers, u)                           # u(tₙ), onto the tracers
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
      advect!(tracers, velocity_physical(cache), domain, dt)          # u(tₙ₊₁), the closing deposit
    end
    @test all(isfinite, particle_positions(tracers)) && all(0 .<= particle_positions(tracers) .< L)
    @test all(isfinite, point_values(tracers.trajectory_velocity))

    # allocation-free advection step — both verbs of the push
    u = velocity_physical(cache)
    bytes = @allocated (record_trajectory_velocity!(tracers, u); advect!(tracers, u, domain, 0.001))
    @test bytes < 4096
  end
end

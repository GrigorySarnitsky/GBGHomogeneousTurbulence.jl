# Lagrangian tracer tests. Key checks: a uniform velocity advects tracers exactly; the Heun-in-time
# integration is second-order (a time-varying uniform field, so the only error is temporal);
# positions wrap periodically; the interpolation scheme is pluggable; sampling reads a field along
# the trajectories; and advect! allocates nothing per step.

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
  domain = FixedDomain(N, L; element_type = T, dealiasing = TwoThirds(), array_type = Array)
  uniform = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

  @testset "uniform field advects exactly" begin
    X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0; 2.0 3.0 4.0]
    tracers = Tracers(domain, copy(X0); scheme = CatmullRom)
    c = 0.5
    set_uniform_x!(uniform, c)
    nsteps, dt = 20, 0.005
    for _ in 1:nsteps
      advect!(tracers, uniform, uniform, domain, dt)
    end
    X = tracer_positions(tracers)
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
        advect!(tracers, u_start, u_end, domain, dt)
      end
      tracer_positions(tracers)[1, 1]
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
      advect!(tracers, uniform, uniform, domain, 0.02)
    end
    X = tracer_positions(tracers)
    @test all(0 .<= X .< L)                                    # wrapped, still in the box
  end

  @testset "pluggable scheme" begin
    set_uniform_x!(uniform, 0.3)
    for scheme in (CatmullRom, LagrangeSpline(2))
      tracers = Tracers(domain, 50; scheme = scheme, rng = MersenneTwister(1))
      for _ in 1:10
        advect!(tracers, uniform, uniform, domain, 0.01)
      end
      X = tracer_positions(tracers)
      @test all(isfinite, X) && all(0 .<= X .< L)
    end
  end

  @testset "sample! reads a field along trajectories" begin
    tracers = Tracers(domain, 40; scheme = CatmullRom, rng = MersenneTwister(2))
    constant = ScalarFieldPhysical((x, y, z) -> 2.5, domain.grid)
    samples = scalar_buffer(tracers)
    sample!(samples, constant, tracers)
    @test all(≈(2.5), point_values(samples))                  # a constant field samples exactly
  end

  @testset "advect in a real HIT velocity field" begin
    buffers = IntegratorBuffers(domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.05,
                      velocity_forcing = BandRescaling(domain; target = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = spectral_vector(domain)
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(4))
    dealias!(û, domain)
    φ̂ = scalar_spectral(domain)
    tracers = Tracers(domain, 200; scheme = CatmullRom, rng = MersenneTwister(5))
    u_start = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)

    Δx = L / N
    for _ in 1:50
      velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
      dt = 0.4 * Δx / max(max_speed(buffers.velocity_physical), 1e-6)
      copyto!(field_data(u_start), field_data(buffers.velocity_physical))           # u(tₙ)
      step!(IFLowStorageRK3(), ResolvedFields(û, φ̂), domain, buffers, conditions, dt)
      u_end = to_physical(û, domain.velocity_plans)                     # u(tₙ₊₁)
      advect!(tracers, u_start, u_end, domain, dt)
    end
    @test all(isfinite, tracer_positions(tracers)) && all(0 .<= tracer_positions(tracers) .< L)
    @test all(isfinite, tracer_velocities(tracers))

    # allocation-free advection step
    bytes = @allocated advect!(tracers, u_start, u_start, domain, 0.001)
    @test bytes < 4096
  end
end

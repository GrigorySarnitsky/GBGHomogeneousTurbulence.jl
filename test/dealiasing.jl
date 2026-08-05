# De-aliasing-strategy tests: the sharp `TwoThirds` (default), the smooth `HouLi`, and the exact
# `PhaseShift` (checked against a zero-padded oracle) kernels, and the CFL ceiling auto-scaling to the
# active strategy (a strategy that keeps more modes takes a smaller step).

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, materialize_kernel
using Random
using Test

@testset "dealiasing" begin
  L = 2π
  N = 16

  @testset "TwoThirds sharp kernel is the default" begin
    domain = FixedDomain(N, L; element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    @test domain.dealiasing isa TwoThirds
    mask = real.(field_data(materialize_kernel(domain.dealias).field))
    @test all(m -> m == 0 || m == 1, mask)             # sharp 0/1 truncation
    @test any(==(1), mask) && any(==(0), mask)         # both kept and cut modes present
  end

  @testset "HouLi smooth filter" begin
    domain = FixedDomain(N, L; dealiasing = HouLi(), element_type = Float64, array_type = Array)
    @test domain.dealiasing isa HouLi
    g = real.(field_data(materialize_kernel(domain.dealias).field))
    @test all(x -> -1e-12 ≤ x ≤ 1 + 1e-12, g)          # a transfer function in [0,1]
    @test maximum(g) ≈ 1 rtol = 1e-6                    # ≈ 1 at the mean (k = 0)
    @test any(x -> 0.01 < x < 0.99, g)                 # genuinely smooth intermediate values, not 0/1
    zeros_houli = count(==(0), g)
    zeros_23 = count(==(0), real.(field_data(materialize_kernel(FixedDomain(N, L; dealiasing = TwoThirds(), element_type = Float64, array_type = Array).dealias).field)))
    @test zeros_houli < zeros_23                        # keeps more modes than the 2/3 rule
  end

  @testset "auto-CFL scales with the dealiasing" begin
    ops23 = FixedDomain(N, L; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)
    opsHL = FixedDomain(N, L; dealiasing = HouLi(), element_type = Float64, array_type = Array)
    rk3 = IFLowStorageRK3()
    base = recommended_cfl(rk3, ops23)                               # the 2/3 rule sets the base ceiling
    @test recommended_cfl(rk3, opsHL) ≈ base * 2 / 3                 # HouLi keeps to Nyquist ⇒ ×2/3
    @test recommended_cfl(rk3, opsHL) < base                         # a tighter step
  end

  @testset "a HouLi simulation runs and stays finite" begin
    domain = FixedDomain(N, L; dealiasing = HouLi(), element_type = Float64, array_type = Array)
    sim = Simulation(domain; viscosity = 0.03,
                     velocity_forcing = ConstantPower(target = 0.1), scalar = false,
                     rng = MersenneTwister(7))
    @test sim.cfl ≈ recommended_cfl(IFLowStorageRK3(), sim.domain)    # the domain-aware CFL flowed in
    run!(sim; steps = 10)
    @test isfinite(kinetic_energy(sim.state.velocity)) && kinetic_energy(sim.state.velocity) > 0
    # the resolution front door threads `dealiasing` through to the domain
    sim2 = Simulation(grid_points_per_axis = N, viscosity = 0.05; dealiasing = HouLi(), scalar = false,
                      rng = MersenneTwister(8))
    @test sim2.domain.dealiasing isa HouLi
  end

  @testset "PhaseShift spherical cutoff and CFL" begin
    domain = FixedDomain(N, L; dealiasing = PhaseShift(), element_type = Float64, array_type = Array)
    @test domain.dealiasing isa PhaseShift
    mask = real.(field_data(materialize_kernel(domain.dealias).field))
    @test all(m -> m == 0 || m == 1, mask)                          # a sharp spherical truncation
    @test max_wavenumber(domain) ≈ (2 * sqrt(2) / 3) * (N / 2) * (2π / L)   # κ_max = √2·N/3·(2π/L)
    @test count(==(1), mask) > count(==(1), real.(field_data(materialize_kernel(FixedDomain(N, L; dealiasing = TwoThirds(), element_type = Float64, array_type = Array).dealias).field)))  # keeps more than 2/3
    rk3 = IFLowStorageRK3()
    base = recommended_cfl(rk3, FixedDomain(N, L; dealiasing = TwoThirds(), element_type = Float64, array_type = Array))
    @test recommended_cfl(rk3, domain) ≈ base / sqrt(2)                     # tighter step for the wider band
  end

  @testset "PhaseShift de-aliases exactly (vs a zero-padded oracle)" begin
    # A field band-limited to the PhaseShift band |k| ≤ √2·N/3 has a quadratic product that aliases INTO
    # that retained band. Phase-shift must reproduce the exact term a 2N zero-padded grid gives (no
    # aliasing there), across the whole band; the raw N-grid product must not.
    Np = 12
    dps = FixedDomain(Np, L; dealiasing = PhaseShift(), element_type = Float64, array_type = Array)
    d2  = FixedDomain(2Np, L; dealiasing = TwoThirds(), element_type = Float64, array_type = Array)                                        # 2N oracle grid (raw product, no dealias)
    SD  = GBGIsotropicTurbulence.SimulationDomain
    GEN = GBGIsotropicTurbulence.Generator
    û = SD.spectral_vector(dps)
    random_solenoidal_velocity!(û, dps; kinetic_energy = 0.5, peak_wavenumber = 4.0, rng = MersenneTwister(3))  # energy near the edge
    half = Np ÷ 2
    mapidx(i) = i ≤ half + 1 ? i : i + Np                           # fft-freq index map, N → 2N
    embed(A) = (B = zeros(eltype(A), Np + 1, 2Np, 2Np, 3);          # zero-pad ×(2N/N)³ = 8
                for c in 1:3, i3 in 1:Np, i2 in 1:Np, i1 in 1:half+1
                  B[i1, mapidx(i2), mapidx(i3), c] = 8 * A[i1, i2, i3, c]
                end; B)
    restrict(B) = [B[i1, mapidx(i2), mapidx(i3), c] / 8
                   for i1 in 1:half+1, i2 in 1:Np, i3 in 1:Np, c in 1:3]
    function nlt(domain, ûf, phaseshift::Bool)
      u = SD.physical_vector(domain); ω = SD.physical_vector(domain)
      tmp = SD.spectral_vector(domain)
      velocity_to_physical!(u, ûf, domain, tmp)
      vorticity_to_physical!(ω, ûf, domain, tmp)
      out = SD.spectral_vector(domain)
      if phaseshift
        unforced = FlowConditions(viscosity = 1.0, schmidt = 1.0,
                                  velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
        velocity_rhs!(out, ResolvedGenerator(domain, unforced), ûf, u, ω, domain)
      else
        GEN._velocity_lamb!(out, u, ω, domain, SD.physical_vector(domain), SD.spectral_vector(domain))
      end
      field_data(out)
    end
    Nps, Nraw = nlt(dps, û, true), nlt(dps, û, false)
    û2 = SD.spectral_vector(d2); field_data(û2) .= embed(field_data(û))
    oracle = restrict(nlt(d2, û2, false))
    m = dps.multipliers   # |κ|² from the axis vectors — the stored array is gone (decision 38)
    κ² = reshape(m.squared_wavenumber_1, :, 1, 1) .+ reshape(m.squared_wavenumber_2, 1, :, 1) .+
         reshape(m.squared_wavenumber_3, 1, 1, :)
    mask = sqrt.(κ²) .≤ (2 * sqrt(2) / 3) * (Np / 2)
    bmax(a, b) = maximum(maximum(abs.(view(a, :, :, :, c) .- view(b, :, :, :, c)) .* mask) for c in 1:3)
    ref = maximum(abs.(oracle) .* reshape(mask, size(mask)..., 1))
    @test bmax(Nps, oracle) / ref < 1e-10          # phase-shift reproduces the exact de-aliased term
    @test bmax(Nraw, oracle) / ref > 1e-2          # raw is genuinely aliased (the test is non-trivial)
  end

  @testset "temporal convergence is scheme-order under PhaseShift (coupled scalar)" begin
    # Self-convergence (Cauchy) ratios ‖q(Δt)−q(Δt/2)‖/‖q(Δt/2)−q(Δt/4)‖ ≈ 2^p on BOTH fields.
    # Guards the stage-ordering contract: both nonlinear terms must be assembled at the stage state
    # before either field is updated — the PhaseShift displaced evaluations read û (and φ̂), so an
    # assembly after the velocity update degrades the scalar to first order (ratio ≈ 2, not ≈ 8).
    Nc = 16
    domain = FixedDomain(Nc, L; element_type = Float64, dealiasing = PhaseShift(), array_type = Array)
    û0 = GBGIsotropicTurbulence.SimulationDomain.spectral_vector(domain)
    random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(1))
    φ̂0 = GBGIsotropicTurbulence.SimulationDomain.scalar_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 1.0, peak_wavenumber = 2.0, rng = MersenneTwister(2))
    conditions = FlowConditions(viscosity = 0.1, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())

    function integrate(integrator, dt, nsteps)
      b = allocate_buffers(integrator, domain; scalar = true)
      generator = ResolvedGenerator(domain, conditions; scalar = true)
      derived = ObservablesCache(domain)
      û = GBGIsotropicTurbulence.SimulationDomain.spectral_vector(domain)
      φ̂ = GBGIsotropicTurbulence.SimulationDomain.scalar_spectral(domain)
      copyto!(field_data(û), field_data(û0))
      copyto!(field_data(φ̂), field_data(φ̂0))
      state = ResolvedFields(û, φ̂)
      for _ in 1:nsteps
        step!(integrator, state, generator, domain, b, derived, dt)
      end
      return û, φ̂
    end
    diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))
    function ratios(integrator)
      Tfinal = 0.4; n = 8
      u1, p1 = integrate(integrator, Tfinal / n, n)
      u2, p2 = integrate(integrator, Tfinal / 2n, 2n)
      u4, p4 = integrate(integrator, Tfinal / 4n, 4n)
      return diffnorm(u1, u2) / diffnorm(u2, u4), diffnorm(p1, p2) / diffnorm(p2, p4)
    end

    rk3_velocity, rk3_scalar = ratios(IFLowStorageRK3())
    @test 5.0 < rk3_velocity < 12.0        # third order ⇒ ≈ 8
    @test 5.0 < rk3_scalar < 12.0          # the scalar must match — the stage-ordering guard
    rk2_velocity, rk2_scalar = ratios(IFRK2())
    @test 3.0 < rk2_velocity < 6.0         # second order ⇒ ≈ 4
    @test 3.0 < rk2_scalar < 6.0
  end

  @testset "a PhaseShift simulation runs and stays finite" begin
    sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; dealiasing = PhaseShift(), scalar = true,
                     velocity_forcing = ConstantPower(target = 0.1), rng = MersenneTwister(9))
    @test sim.domain.dealiasing isa PhaseShift
    @test sim.generator.phase_shift !== nothing                      # the displaced-evaluation scratch was built
    @test sim.cfl ≈ recommended_cfl(IFLowStorageRK3(), sim.domain)
    run!(sim; steps = 8)
    @test isfinite(kinetic_energy(sim.state.velocity)) && kinetic_energy(sim.state.velocity) > 0
    @test isfinite(scalar_variance(sim.state.scalar)) && scalar_variance(sim.state.scalar) > 0
  end
end

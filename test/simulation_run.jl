# Run-layer tests. Key checks: the `Simulation` front door assembles and seeds a case; `warmup!` and
# `run!` advance the clock and keep the state finite; a `run!` callback fires and can read the
# diagnostics; tracers move and stay in the box; forced runs sustain energy while free decay loses
# it; and the bring-your-own-domain constructor and fixed-`dt` `advance!` work.

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU   # archived (un-exported); kept tested for the re-add
using GBGIsotropicTurbulence.Phenomenology.Scalings: Li2008, stationary_dissipation
using GBGIsotropicTurbulence.Phenomenology: FlowParameters, kolmogorov_length
using GBGIsotropicTurbulence.Phenomenology.Spectra: VonKarman1948
using GBGPeriodicFields: field_data
using Random
using Logging
using Test


@testset "simulation run" begin
  L = 2π

  @testset "assemble, warm up, run (forced) with tracers" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.02;
                     velocity_forcing = domain -> ConstantPower(domain; injection_rate = 0.1),
                     scalar = true, number_of_particles = 50, rng = MersenneTwister(1))
    @test current_time(sim) == 0.0
    @test current_step(sim) == 0
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0
    @test isfinite(scalar_variance(sim.state.scalar_spectral)) && scalar_variance(sim.state.scalar_spectral) > 0

    # A fixed eddy-turnover budget is a three-line observation: accumulate Δt·ε/k, stop at the target.
    let elapsed = Ref(0.0), last_t = Ref(current_time(sim))
      run!(sim) do s
        ε = dissipation(s.state.velocity_spectral, s.domain, s.generator.conditions.viscosity)
        elapsed[] += (current_time(s) - last_t[]) * ε / kinetic_energy(s.state.velocity_spectral)
        last_t[] = current_time(s)
        elapsed[] < 2.0
      end
    end
    @test current_step(sim) > 0 && current_time(sim) > 0
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0

    samples = Float64[]                                        # a coarser cadence is the callback's own business
    t0 = current_time(sim)
    let next = Ref(t0)
      run!(sim) do s
        current_time(s) ≥ next[] && (push!(samples, kinetic_energy(s.state.velocity_spectral)); next[] += 0.05)
        current_time(s) < t0 + 0.3
      end
    end
    @test !isempty(samples) && all(isfinite, samples)          # the cadenced observation fired
    @test current_time(sim) ≥ t0 + 0.3
    @test all(0 .<= particle_positions(sim.tracers) .< L)        # tracers advected, still in the box
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && isfinite(scalar_variance(sim.state.scalar_spectral))
  end

  @testset "free decay loses energy" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05;
                     scalar = false, velocity_forcing = NoForcing(), rng = MersenneTwister(2))
    k0 = kinetic_energy(sim.state.velocity_spectral)
    run!(s -> current_step(s) < 40, sim)
    @test current_step(sim) == 40
    @test isfinite(kinetic_energy(sim.state.velocity_spectral))
    @test kinetic_energy(sim.state.velocity_spectral) < k0                             # unforced ⇒ decays
  end

  @testset "grid-resolved viscosity (grid mode)" begin
    # No `viscosity`: ν is chosen so the grid resolves κ_max·η = κ_max_η, forced-and-stationary.
    sim = Simulation(grid_points_per_axis = 32; rng = MersenneTwister(3))
    ν = sim.generator.conditions.viscosity
    ε = stationary_dissipation(Li2008(), 1.5, L)               # kinetic_energy = 1.5, side_length = L
    η = (ν^3 / ε)^(1 / 4)
    @test isapprox(max_wavenumber(sim.domain) * η, 2.0; rtol = 1e-6)   # κ_max·η = 2 (default)
    # Forced by default, and by the CONTROLLER since 2026-08-22: the default was `VarianceRescaling`,
    # a post-step projection, which is Lie–Trotter splitting and held every default run to first
    # order in time (measured 1.02 against 3.01). `VarianceController` holds the same quantity
    # through a rate the scheme integrates, so a default run is now third order.
    @test sim.generator.conditions.velocity_forcing isa VarianceController
    @test ν > 0

    @test Simulation(grid_points_per_axis = 32, κ_max_η = 3; rng = MersenneTwister(3)).generator.conditions.viscosity > ν
    # The two set ν by different routes, so supplying both is an error rather than a silent drop.
    @test_throws ArgumentError Simulation(grid_points_per_axis = 32, viscosity = 0.01, κ_max_η = 5)
    @test Simulation(grid_points_per_axis = 32, viscosity = 0.01).generator.conditions.viscosity == 0.01
  end

  @testset "initial condition from a spectrum" begin
    sim = Simulation(grid_points_per_axis = 48, viscosity = 0.01,
                     initial_spectrum = VonKarman1948(), rng = MersenneTwister(4))
    κ, E = energy_spectrum(sim.state.velocity_spectral, sim.domain)
    @test all(≥(0), E)
    @test isapprox(sum(E), kinetic_energy(sim.state.velocity_spectral); rtol = 1e-5)   # shape normalized to `energy`
    @test κ[argmax(E)] < κ[end] / 2                            # energy concentrated at large scales

    # a raw κ -> E(κ) function is also accepted
    sim2 = Simulation(grid_points_per_axis = 32, viscosity = 0.02,
                      initial_spectrum = κ -> κ^4 * exp(-κ), rng = MersenneTwister(4))
    @test kinetic_energy(sim2.state.velocity_spectral) > 0
    @test isapprox(sum(last(energy_spectrum(sim2.state.velocity_spectral, sim2.domain))) * (2π / sim2.domain.grid.domain_size[1]), kinetic_energy(sim2.state.velocity_spectral); rtol = 1e-5)
  end

  @testset "the observation fires after every iteration — n iterations, n+1 observations" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(7))
    count = Ref(0)
    run!(sim) do s
      count[] += 1
      current_step(s) < 5
    end
    @test count[] == 6                              # t₀ and the stopping instant both observed
    @test current_step(sim) == 5
  end

  @testset "bring-your-own domain + fixed dt" begin
    domain = FixedDomain(grid_points_per_axis = 16, side_length = L, element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    sim = Simulation(domain; viscosity = 0.02, rng = MersenneTwister(3))
    advance!(sim; dt = 0.001)
    @test current_step(sim) == 1
    @test current_time(sim) ≈ 0.001
  end

  @testset "Float32 case runs" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05; element_type = Float32,
                     scalar = false, rng = MersenneTwister(4))
    run!(s -> current_step(s) < 10, sim)
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0
  end

  @testset "the observation must decide — a non-Bool return throws" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(5))
    @test_throws ArgumentError run!(s -> nothing, sim)     # recorded but did not decide
    @test current_step(sim) == 0                           # nothing advanced
  end

  @testset "domain-free forcing spec" begin
    for spec in (ConstantPower(injection_rate = 0.1), Linear(rate = 0.5),
                 VarianceRescaling(target = 0.5, over = :band), StochasticOU(variance = 1.0, correlation_time = 0.3))
      @test spec isa DeferredForcing
    end
    # ConstantPower(power=0.1) — no domain — works as a Simulation forcing
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(injection_rate = 0.1), scalar = false,
                     rng = MersenneTwister(20))
    run!(s -> current_step(s) < 5, sim)
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0
  end

  @testset "stationarity detector (unit)" begin
    D = GBGIsotropicTurbulence.SimulationRun
    turn = collect(0.0:0.1:10.0)
    @test D._is_flat(turn, fill(2.0, length(turn)) .+ 0.001 .* sin.(turn), 10.0, 4.0, 0.05)  # flat
    @test !D._is_flat(turn, 1.0 .+ 0.1 .* turn, 10.0, 4.0, 0.05)                              # drifting
    mon(; gk = false) = D.StationarityMonitor(; min_turnovers = 3, window_turnovers = 3, tol = 0.05,
                                              gate_scalar = false, gate_skewness = gk, skew_floor = 0.1)
    # flat ε converges; drifting ε does not
    mflat = mon()
    for et in 0.0:0.05:12.0; D._push_and_test!(mflat, et, 2.0 + 0.001 * sin(et), 0.0, 0.0); end
    @test mflat.converged
    mdrift = mon()
    conv = false
    for et in 0.0:0.05:12.0; conv = D._push_and_test!(mdrift, et, 1.0 + 0.2 * et, 0.0, 0.0); end
    @test !conv
    # skewness gate: a still-rising S does NOT converge; a plateau at −0.45 does; a plateau near 0 does not
    mrise = mon(; gk = true)
    for et in 0.0:0.05:12.0; D._push_and_test!(mrise, et, 2.0, 0.0, -0.04 * et); end
    @test !mrise.converged
    mplat = mon(; gk = true)
    for et in 0.0:0.05:12.0; D._push_and_test!(mplat, et, 2.0, 0.0, -0.45 + 0.001 * sin(et)); end
    @test mplat.converged
    mzero = mon(; gk = true)
    for et in 0.0:0.05:12.0; D._push_and_test!(mzero, et, 2.0, 0.0, 0.001 * sin(et)); end
    @test !mzero.converged                                                # flat but below skew_floor
  end

  @testset "warmup! detects stationarity" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(injection_rate = 0.1), scalar = false,
                     rng = MersenneTwister(21))
    warmup!(sim; gate_skewness = false, min_turnovers = 2, window_turnovers = 2, tol = 0.3, max_turnovers = 10)
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0
    @test current_step(sim) > 0
    # the criterion is an ordinary run! observation
    sim2 = Simulation(grid_points_per_axis = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(22))
    run!(StationarityCriterion(; gate_skewness = false, min_turnovers = 1, window_turnovers = 1,
                               tol = 0.5, max_turnovers = 4), sim2)
    @test current_step(sim2) > 0
  end

  @testset "warmup! gates on the scalar" begin
    D = GBGIsotropicTurbulence.SimulationRun
    forced = Simulation(grid_points_per_axis = 16, viscosity = 0.03;
                        velocity_forcing = ConstantPower(injection_rate = 0.1),
                        scalar_forcing = StochasticOU(variance = 1.0, correlation_time = 0.3),
                        scalar = true, rng = MersenneTwister(23))
    @test D._scalar_forced(forced)                                        # scalar gate active
    warmup!(forced; gate_skewness = false, min_turnovers = 2, window_turnovers = 2, tol = 0.35, max_turnovers = 10)
    @test isfinite(scalar_variance(forced.state.scalar_spectral)) && scalar_variance(forced.state.scalar_spectral) > 0
    @test current_step(forced) > 0
    plain = Simulation(grid_points_per_axis = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(24))
    @test !D._scalar_forced(plain)                                        # unforced scalar not gated
  end

  @testset "derivative skewness" begin
    domain = FixedDomain(grid_points_per_axis = 24, side_length = 2π, element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(30))
    truncate_to_band!(û, domain)
    S0 = derivative_skewness(û, domain)
    @test isfinite(S0) && abs(S0) < 0.15          # random-phase (Gaussian) field ⇒ S ≈ 0

    # develop turbulence, then the coordinate-free skewness ⇒ the negative K41 value S ≈ −0.5
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    cache = ObservablesCache(domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.02, velocity_forcing = ConstantPower(domain; injection_rate = 0.15), schmidt = 1.0, scalar_forcing = NoForcing())
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    deposit!(cache, state, domain, buffers)
    for _ in 1:80
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, 0.012)
      deposit!(cache, state, domain, buffers)
    end
    S = derivative_skewness(û, domain)
    @test isfinite(S) && -1.5 < S < -0.05
  end

  @testset "warmup! skewness gate runs" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(injection_rate = 0.15), scalar = false,
                     rng = MersenneTwister(31))
    warmup!(sim; min_turnovers = 2, window_turnovers = 2, tol = 0.3, skew_floor = 0.1, max_turnovers = 8)
    @test isfinite(kinetic_energy(sim.state.velocity_spectral)) && kinetic_energy(sim.state.velocity_spectral) > 0
    @test isfinite(derivative_skewness(sim.state.velocity_spectral, sim.domain))
    @test current_step(sim) > 0
  end

  @testset "VarianceRescaling over = :total pins total energy" begin
    # :total rescales the band to make the whole-field energy equal the target each step
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05;
                     velocity_forcing = VarianceRescaling(target = 0.8, over = :total),
                     scalar = false, kinetic_energy = 0.5, rng = MersenneTwister(40))
    advance!(sim; dt = 0.01)
    @test kinetic_energy(sim.state.velocity_spectral) ≈ 0.8 rtol = 1e-3
    # :band (default) holds the band energy; the total is free to float
    simb = Simulation(grid_points_per_axis = 16, viscosity = 0.05;
                      velocity_forcing = VarianceRescaling(target = 0.3, over = :band),
                      scalar = false, kinetic_energy = 0.5, rng = MersenneTwister(40))
    advance!(simb; dt = 0.01)
    @test isfinite(kinetic_energy(simb.state.velocity_spectral)) && kinetic_energy(simb.state.velocity_spectral) > 0
    # the target symbol is validated at construction
    domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
    @test_throws ArgumentError VarianceRescaling(domain; target = 0.5, over = :bogus)
  end
end


# The grid-mode ν solve is `kolmogorov_length`'s law inverted, spelled as bare arithmetic because no
# inverse exists to call. That is a duplication a maintainer could break from either side, so the two
# are pinned together here: solve for ν through the constructor, then measure η through the canonical
# law and recover the κ_max·η that was asked for. A change to either spelling alone fails this.
@testset "grid mode inverts kolmogorov_length, and the round trip closes" begin
  k = 1.5                                    # passed explicitly, not inherited from the default
  for target in (1.0, 1.5, 2.0, 3.0)
    sim = Simulation(grid_points_per_axis = 32, κ_max_η = target, kinetic_energy = k,
                     velocity_forcing = ConstantPower(injection_rate = 0.1))
    ν = sim.generator.conditions.viscosity
    # The constructor solved with the Li2008 stationary ESTIMATE, not the measured dissipation of
    # the seeded state, so the round trip must use the same estimate.
    ε_design = stationary_dissipation(Li2008(), k, sim.domain.grid.domain_size[1])
    η = kolmogorov_length(FlowParameters(; viscosity = ν, dissipation = ε_design,
                                         rms_velocity = sqrt(2k / 3), integral_scale = 1.0,
                                         schmidt = 1.0))
    @test max_wavenumber(sim.domain) * η ≈ target rtol = 1e-10
  end


  @testset "the default run holds the kinetic energy grid mode calibrated it against" begin
    # Grid mode chooses ν from the ASSUMED kinetic energy, so κ_max·η is self-consistent only if the
    # run really holds k there. That makes this an end-to-end check of a *precondition*, not a
    # forcing unit test: it is the only place the calibration's assumption is confronted with the
    # integrated trajectory. It caught nothing when written, because it did not exist — the audit
    # measured k settling ~30% high under a controller restoring toward the band instead of the field.
    for k_target in (1.5, 0.8)
      sim = Simulation(grid_points_per_axis = 24, kinetic_energy = k_target)
      for _ in 1:200; advance!(sim); end
      k = kinetic_energy(sim.state.velocity_spectral)
      @test isapprox(k, k_target; rtol = 0.05)
    end

    # And it converges TO the target rather than merely starting there. The initial condition is
    # seeded well below the controller's target — through the constructor, since the cache refuses a
    # state mutated behind its back — so the run has to climb, which a band-restoring controller
    # would not do to the whole field.
    sim = Simulation(grid_points_per_axis = 24, viscosity = 0.05, kinetic_energy = 0.4,
                     velocity_forcing = VarianceController(target = 1.5))
    û = sim.state.velocity_spectral
    @test kinetic_energy(û) < 0.6
    for _ in 1:600; advance!(sim); end
    @test isapprox(kinetic_energy(û), 1.5; rtol = 0.1)
  end


  @testset "the constructor warns when the scalar is clearly under-resolved, and only then" begin
    # Grid mode resolves the VELOCITY at κ_max·η; a scalar at Sc > 1 lives down to η_B = η/√Sc, so
    # the same grid resolves it worse by √Sc. The check fires when the run's actual κ_max·η_B falls
    # below 1.5 — the same floor the docstring calls well-resolved for the velocity — which at the
    # grid-mode default κ_max·η = 2 means Sc > (2/1.5)² ≈ 1.78. It must fire in BOTH ν modes, and
    # never without a scalar: the defect it closes was a wrong `scalar_dissipation` with no signal.
    fires(; kw...) = begin
      buf = IOBuffer()
      Logging.with_logger(Logging.SimpleLogger(buf, Logging.Warn)) do
        Simulation(grid_points_per_axis = 16; kw...)
      end
      occursin("under-resolved", String(take!(buf)))
    end
    @test !fires(; scalar = true)                                       # Sc = 1: resolved
    @test !fires(; scalar = true, schmidt = 1.5)                        # κ_max·η_B ≈ 1.63: above floor
    @test fires(; scalar = true, schmidt = 2.0)                         # ≈ 1.41: below floor
    @test fires(; scalar = true, schmidt = 7.0)                         # ≈ 0.76: clearly under-resolved
    @test !fires(; schmidt = 7.0)                                       # no scalar, nothing to resolve
    @test fires(; scalar = true, schmidt = 7.0, viscosity = 0.08)       # explicit ν is checked too
  end
end

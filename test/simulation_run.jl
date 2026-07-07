# Run-layer tests. Key checks: the `Simulation` front door assembles and seeds a case; `warmup!` and
# `run!` advance the clock and keep the state finite; a `run!` callback fires and can read the
# diagnostics; tracers move and stay in the box; forced runs sustain energy while free decay loses
# it; and the bring-your-own-operators constructor and fixed-`dt` `advance!` work.

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


@testset "simulation run" begin
  L = 2π

  @testset "assemble, warm up, run (forced) with tracers" begin
    sim = Simulation(resolution = 16, viscosity = 0.02;
                     velocity_forcing = ops -> ConstantPower(ops; power = 0.1),
                     scalar = true, ntracers = 50, rng = MersenneTwister(1))
    @test current_time(sim) == 0.0
    @test current_step(sim) == 0
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
    @test isfinite(scalar_variance(sim)) && scalar_variance(sim) > 0

    warmup!(sim; turnovers = 2)
    @test current_step(sim) > 0 && current_time(sim) > 0
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0

    samples = Float64[]
    t0 = current_time(sim)
    run!(sim; time = 0.3, every = 0.05) do s
      push!(samples, kinetic_energy(s))
    end
    @test !isempty(samples) && all(isfinite, samples)          # the interval callback fired
    @test current_time(sim) ≥ t0 + 0.3
    @test all(0 .<= tracer_positions(sim.tracers) .< L)        # tracers advected, still in the box
    @test isfinite(kinetic_energy(sim)) && isfinite(scalar_variance(sim))
  end

  @testset "free decay loses energy" begin
    sim = Simulation(resolution = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(2))
    k0 = kinetic_energy(sim)
    run!(sim; steps = 40)
    @test current_step(sim) == 40
    @test isfinite(kinetic_energy(sim))
    @test kinetic_energy(sim) < k0                             # unforced ⇒ decays
  end

  @testset "callback fires every step without `every`" begin
    sim = Simulation(resolution = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(7))
    count = Ref(0)
    run!(sim; steps = 5) do _
      count[] += 1
    end
    @test count[] == 5
  end

  @testset "bring-your-own operators + fixed dt" begin
    ops = SpectralOperators(16, L; scalar_type = Float64)
    sim = Simulation(ops; viscosity = 0.02, rng = MersenneTwister(3))
    advance!(sim; dt = 0.001)
    @test current_step(sim) == 1
    @test current_time(sim) ≈ 0.001
  end

  @testset "Float32 case runs" begin
    sim = Simulation(resolution = 16, viscosity = 0.05; scalar_type = Float32,
                     scalar = false, rng = MersenneTwister(4))
    run!(sim; steps = 10)
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
  end

  @testset "stopping-condition guard" begin
    sim = Simulation(resolution = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(5))
    @test_throws ArgumentError run!(sim)                                  # none given
    @test_throws ArgumentError run!(sim; steps = 3, time = 0.1)           # two given
  end

  @testset "ops-free forcing spec" begin
    for spec in (ConstantPower(power = 0.1), Linear(rate = 0.5),
                 BandRescaling(energy = 0.5), StochasticOU(variance = 1.0, correlation_time = 0.3))
      @test spec isa ForcingSpec
    end
    # ConstantPower(power=0.1) — no operators — works as a Simulation forcing
    sim = Simulation(resolution = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(power = 0.1), scalar = false,
                     rng = MersenneTwister(20))
    run!(sim; steps = 5)
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
  end

  @testset "stationarity detector (unit)" begin
    D = GBGIsotropicTurbulence.SimulationRun
    turn = collect(0.0:0.1:10.0)
    @test D._is_flat(turn, fill(2.0, length(turn)) .+ 0.001 .* sin.(turn), 10.0, 4.0, 0.05)  # flat
    @test !D._is_flat(turn, 1.0 .+ 0.1 .* turn, 10.0, 4.0, 0.05)                              # drifting
    mon(; gk = false) = D.StationarityMonitor(; min_turnovers = 3, window_turnovers = 3, tol = 0.05,
                                              gate_scalar = false, gate_skew = gk, skew_floor = 0.1)
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
    sim = Simulation(resolution = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(power = 0.1), scalar = false,
                     rng = MersenneTwister(21))
    warmup!(sim; gate_skewness = false, min_turnovers = 2, window_turnovers = 2, tol = 0.3, max_turnovers = 10)
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
    @test current_step(sim) > 0
    # explicit budget still runs the fixed-budget path
    sim2 = Simulation(resolution = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(22))
    warmup!(sim2; turnovers = 2)
    @test current_step(sim2) > 0
  end

  @testset "warmup! gates on the scalar" begin
    D = GBGIsotropicTurbulence.SimulationRun
    forced = Simulation(resolution = 16, viscosity = 0.03;
                        velocity_forcing = ConstantPower(power = 0.1),
                        scalar_forcing = StochasticOU(variance = 1.0, correlation_time = 0.3),
                        scalar = true, rng = MersenneTwister(23))
    @test D._scalar_forced(forced)                                        # scalar gate active
    warmup!(forced; gate_skewness = false, min_turnovers = 2, window_turnovers = 2, tol = 0.35, max_turnovers = 10)
    @test isfinite(scalar_variance(forced)) && scalar_variance(forced) > 0
    @test current_step(forced) > 0
    plain = Simulation(resolution = 16, viscosity = 0.05; scalar = false, rng = MersenneTwister(24))
    @test !D._scalar_forced(plain)                                        # unforced scalar not gated
  end

  @testset "derivative skewness" begin
    ops = SpectralOperators(24, 2π; scalar_type = Float64)
    ws = Workspace(ops)
    û = spectral_vector(ops)
    random_solenoidal_velocity!(û, ops; energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(30))
    dealias!(û, ops)
    S0 = derivative_skewness(û, ops)
    @test isfinite(S0) && abs(S0) < 0.15          # random-phase (Gaussian) field ⇒ S ≈ 0

    # develop turbulence, then the coordinate-free skewness ⇒ the negative K41 value S ≈ −0.5
    φ̂ = scalar_spectral(ops)
    physics = Physics(viscosity = 0.02, velocity_forcing = ConstantPower(ops; power = 0.15))
    for _ in 1:80
      velocity_vorticity!(ws.velocity, ws.vorticity_start, û, ops, ws)
      step!(IFLowStorageRK3(), û, φ̂, ops, ws, physics, 0.012)
    end
    S = derivative_skewness(û, ops)
    @test isfinite(S) && -1.5 < S < -0.05
  end

  @testset "warmup! skewness gate runs" begin
    sim = Simulation(resolution = 16, viscosity = 0.03;
                     velocity_forcing = ConstantPower(power = 0.15), scalar = false,
                     rng = MersenneTwister(31))
    warmup!(sim; min_turnovers = 2, window_turnovers = 2, tol = 0.3, skew_floor = 0.1, max_turnovers = 8)
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
    @test isfinite(derivative_skewness(sim.velocity, sim.operators))
    @test current_step(sim) > 0
  end

  @testset "BandRescaling target = :total pins total energy" begin
    # :total rescales the band to make the whole-field energy equal the target each step
    sim = Simulation(resolution = 16, viscosity = 0.05;
                     velocity_forcing = BandRescaling(energy = 0.8, target = :total),
                     scalar = false, energy = 0.5, rng = MersenneTwister(40))
    advance!(sim; dt = 0.01)
    @test kinetic_energy(sim) ≈ 0.8 rtol = 1e-3
    # :band (default) holds the band energy; the total is free to float
    simb = Simulation(resolution = 16, viscosity = 0.05;
                      velocity_forcing = BandRescaling(energy = 0.3, target = :band),
                      scalar = false, energy = 0.5, rng = MersenneTwister(40))
    advance!(simb; dt = 0.01)
    @test isfinite(kinetic_energy(simb)) && kinetic_energy(simb) > 0
    # the target symbol is validated at construction
    ops = SpectralOperators(16, 2π; scalar_type = Float64)
    @test_throws ArgumentError BandRescaling(ops; energy = 0.5, target = :bogus)
  end
end

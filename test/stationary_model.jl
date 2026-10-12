# The stationary-state model and its use by the run layer: k̃ = k/(εL)^{2/3} and k_band/k as functions
# of the forcing, the prediction `predicted_stationary_state` built on them, the strengths `Simulation`
# fills from it, and the refusals where the model has no value (decisions 101, 105).
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Forcing: DeferredForcing
using Logging
using Random

quietly(f) = with_logger(f, NullLogger())
domain_of(N) = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_family = Array)


@testset "the model: k̃ and k_band/k per forcing band" begin
  # The placeholder values, one per band, the same for every strategy and for built and deferred forms.
  d = domain_of(24)
  for (h, k̃) in ((2, 0.72), (4, 0.56), (Inf, 0.47))
    for f in (ConstantPower(; highest_shell = h), Linear(; rate = 0.3, highest_shell = h),
              VarianceRescaling(; over = :total, highest_shell = h), VarianceController(; highest_shell = h),
              VarianceRescaling(d; target = 1.0, over = :band, highest_shell = h))
      @test kinetic_energy_in_box_units(f; reynolds_box = 500) == k̃
    end
  end
  # Between the measured bands, linear in 1/highest_shell: shell 3 lies between 1/2 and 1/4.
  @test kinetic_energy_in_box_units(ConstantPower(; highest_shell = 3); reynolds_box = 500) ≈
        0.56 + (0.72 - 0.56) * (1 / 3 - 1 / 4) / (1 / 2 - 1 / 4)
  # Flat in the Reynolds number, by either keyword, until the dependence is measured.
  f = ConstantPower()
  @test kinetic_energy_in_box_units(f; reynolds_box = 10) == kinetic_energy_in_box_units(f; reynolds_box = 1e6) ==
        kinetic_energy_in_box_units(f; reynolds_taylor = 60)

  # k_band/k: the inertial-tail estimate, written out; exactly 1 when every mode is forced.
  for h in (2, 3, 4)
    k̃ = kinetic_energy_in_box_units(ConstantPower(; highest_shell = h); reynolds_box = 500)
    @test band_energy_fraction(ConstantPower(; highest_shell = h); reynolds_box = 500) ≈
          1 - 1.5 * 1.5 / (k̃ * (2π * (h + 0.5))^(2 / 3))
  end
  @test band_energy_fraction(ConstantPower(; highest_shell = 2); reynolds_box = 500) ≈ 0.50 atol = 0.01
  @test band_energy_fraction(ConstantPower(; highest_shell = Inf); reynolds_box = 500) == 1

  # Refusals: no stationary state, no band, a band the model has no value for, and the Reynolds keywords.
  @test_throws ArgumentError kinetic_energy_in_box_units(NoForcing(); reynolds_box = 500)
  @test_throws ArgumentError kinetic_energy_in_box_units(ConstantPower(; lowest_shell = 2, highest_shell = 3);
                                                         reynolds_box = 500)
  @test_throws ArgumentError kinetic_energy_in_box_units(ConstantPower(; highest_shell = 1); reynolds_box = 500)
  @test_throws ArgumentError kinetic_energy_in_box_units(f)
  @test_throws ArgumentError kinetic_energy_in_box_units(f; reynolds_box = 500, reynolds_taylor = 60)
  @test_throws ArgumentError kinetic_energy_in_box_units(f; reynolds_box = -1)
  @test_throws ArgumentError band_energy_fraction(NoForcing(); reynolds_taylor = 60)
end


@testset "the prediction: derived and explicit ν describe one state" begin
  d = domain_of(48)
  L, κ_max = 2π, max_resolved_wavenumber(d)
  for forcing in (ConstantPower(), VarianceController(; highest_shell = 4), Linear(; highest_shell = Inf))
    p = predicted_stationary_state(d; velocity_forcing = forcing, κ_max_η = 1.5)
    # the stated default k, and ε from it through k̃
    @test p.kinetic_energy == 1.5
    @test p.dissipation ≈ (p.kinetic_energy / p.kinetic_energy_in_box_units)^(3 / 2) / L rtol = 1e-12
    # the resolution holds: κ_max·η with η = (ν³/ε)^{1/4}, and Re_box = (L/η)^{4/3}
    η = (p.viscosity^3 / p.dissipation)^(1 / 4)
    @test κ_max * η ≈ 1.5 rtol = 1e-12
    @test p.reynolds_box ≈ (L / η)^(4 / 3) rtol = 1e-12
    @test p.reynolds_box ≈ reynolds_box(L, p.dissipation, p.viscosity) rtol = 1e-12
    @test p.reynolds_taylor ≈ reynolds_taylor(p.kinetic_energy, p.dissipation, p.viscosity) rtol = 1e-12
    @test p.band_kinetic_energy ≈ band_energy_fraction(forcing; reynolds_box = p.reynolds_box) * p.kinetic_energy
    # the explicit-ν prediction of the same ν returns the same state (the ε solve inverts the forward map)
    q = predicted_stationary_state(d; velocity_forcing = forcing, viscosity = p.viscosity)
    for name in keys(p)
      @test getfield(q, name) ≈ getfield(p, name) rtol = 1e-9
    end
  end
  # Stating ε instead: k follows through k̃.
  p = predicted_stationary_state(d; dissipation = 0.4, κ_max_η = 2)
  @test p.kinetic_energy ≈ p.kinetic_energy_in_box_units * (0.4 * L)^(2 / 3) rtol = 1e-12
  # A forcing's own target states the state, and a second statement is refused.
  @test predicted_stationary_state(d; velocity_forcing = ConstantPower(injection_rate = 0.3)).dissipation == 0.3
  @test_throws ArgumentError predicted_stationary_state(d; velocity_forcing = ConstantPower(injection_rate = 0.3),
                                                        kinetic_energy = 1.0)
  @test_throws ArgumentError predicted_stationary_state(d; kinetic_energy = 1.0, dissipation = 0.3)
  @test_throws ArgumentError predicted_stationary_state(d; κ_max_η = 1.5, viscosity = 0.01)
  @test_throws ArgumentError predicted_stationary_state(d; velocity_forcing = NoForcing(), viscosity = 0.01)
  # The prediction is returned in the domain's precision (its side is the Float32 2π, hence the rtol).
  d32 = FixedDomain(grid_points_per_axis = 48, side_length = 2π, dealiasing = TwoThirds(),
                    element_type = Float32, array_family = Array)
  p64, p32 = predicted_stationary_state(d; κ_max_η = 1.5), predicted_stationary_state(d32; κ_max_η = 1.5)
  @test all(v -> v isa Float64, p64) && all(v -> v isa Float32, p32)
  @test all(name -> isapprox(getfield(p32, name), getfield(p64, name); rtol = 1e-6), keys(p64))
end


@testset "the run fills each omitted strength from the prediction" begin
  d = domain_of(24)
  p(forcing) = predicted_stationary_state(d; velocity_forcing = forcing, κ_max_η = 1.5)
  run(forcing) = quietly(() -> Simulation(d; κ_max_η = 1.5, velocity_forcing = forcing)).generator.conditions.velocity_forcing

  # Linear: the rate that injects the predicted ε into the predicted band energy, ε = 2A k_band.
  s = p(Linear())
  @test run(Linear()).rate ≈ s.dissipation / (2 * s.band_kinetic_energy) rtol = 1e-12
  # VarianceRescaling: the whole field's k under :total, the band's own k_band under :band.
  @test run(VarianceRescaling(; over = :total)).target ≈ s.kinetic_energy rtol = 1e-12
  @test run(VarianceRescaling(; over = :band)).target ≈ p(VarianceRescaling(; over = :band)).band_kinetic_energy rtol = 1e-12
  # VarianceController: the target k and the settling time 2k/3ε of the predicted state.
  c = run(VarianceController())
  @test c.target ≈ s.kinetic_energy rtol = 1e-12
  @test c.turnover_time ≈ 2 * s.kinetic_energy / (3 * s.dissipation) rtol = 1e-12
  # StochasticOU: the correlation time is converted from box units once, T_L = θ (L²/ε)^{1/3}, and the
  # variance injects ε: σ² = ε/T_L.
  ou = run(StochasticOU(; correlation_time_in_box_units = 0.3))
  @test ou.correlation_time ≈ 0.3 * cbrt((2π)^2 / s.dissipation) rtol = 1e-12
  @test ou.forcing_variance ≈ s.dissipation / ou.correlation_time rtol = 1e-12
  # A stated strength is kept, not overwritten.
  @test run(Linear(rate = 0.25)).rate == 0.25
  # The deferred StochasticOU needs the run to convert its time; built alone it is refused by name.
  @test_throws ArgumentError StochasticOU(; correlation_time_in_box_units = 0.3)(d)
end


@testset "a run the model does not cover predicts nothing" begin
  d = domain_of(16)
  # A derived ν has no stationary state to be solved from.
  @test_throws ArgumentError Simulation(d; velocity_forcing = NoForcing())
  @test_throws ArgumentError Simulation(d; velocity_forcing = ConstantPower(injection_rate = 0.1,
                                                                            lowest_shell = 2, highest_shell = 3))
  # With an explicit ν the seed takes the stated k; an unforced run may state ε too.
  sim = quietly(() -> Simulation(d; viscosity = 0.05, velocity_forcing = NoForcing(), kinetic_energy = 0.8,
                                 dissipation = 0.3, rng = MersenneTwister(1)))
  @test kinetic_energy(sim.state.velocity_spectral) ≈ 0.8 rtol = 1e-10
  # A forced run the model does not cover still states its state once.
  @test_throws ArgumentError Simulation(d; viscosity = 0.05, kinetic_energy = 1.0,
                                        velocity_forcing = ConstantPower(injection_rate = 0.1, lowest_shell = 2,
                                                                         highest_shell = 3))
  # A model initial spectrum needs a dissipation rate, and none is predicted here.
  model = GBGHomogeneousTurbulence.Phenomenology.Spectra.VonKarman1948()
  @test_throws ArgumentError Simulation(d; viscosity = 0.05, velocity_forcing = NoForcing(),
                                        initial_spectrum = model)
  # The scalar check measures the seeded field's ε instead of predicting one, and still runs.
  @test (quietly(() -> Simulation(d; viscosity = 0.05, velocity_forcing = NoForcing(), scalar = true));
         true)
end

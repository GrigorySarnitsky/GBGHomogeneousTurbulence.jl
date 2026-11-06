# Box scaling: a run on a box of side L = 0.02 is the run on L = 2π with every quantity rescaled by its
# dimension. With σ = L/2π, lengths and velocities scale by σ, k, ε and ν by σ², wavenumbers by 1/σ,
# and time and the scalar not at all, so the two runs must agree to rounding once rescaled. Nothing
# else in the suite runs off the 2π box, where 2π/L = 1 lets a dropped fundamental pass unseen: the
# seed's envelope was such a case, shell 2 on L = 2π and an underflow on the 2 cm box. The oracle is
# the scaling itself, not the package's own output, and the box is far from 2π so that any
# hidden 2π fails by orders of magnitude.
using Test, Random, HDF5
using GBGHomogeneousTurbulence
using GBGPeriodicFields: CatmullRom, PointSet, point_positions, field_data


const L = 0.02
const σ = L / 2π
box(side; dealiasing = TwoThirds()) =
  FixedDomain(; grid_points_per_axis = 16, side_length = side, dealiasing, element_type = Float64,
              array_family = Array)
relative_error(a, b) = maximum(abs, a .- b) / maximum(abs, a)


# The reference run's state, rescaled onto the small box: û by σ, φ̂ unchanged.
function rescaled_state(reference, domain)
  û = new_vector_field_spectral(domain)
  copyto!(field_data(û), field_data(reference.state.velocity_spectral) .* σ)
  φ̂ = reference.state.scalar_spectral === nothing ? nothing : new_scalar_field_spectral(domain)
  φ̂ === nothing || copyto!(field_data(φ̂), field_data(reference.state.scalar_spectral))
  return ResolvedFields(û, φ̂)
end


@testset "the seed through Simulation is the same field on every box" begin
  reference = Simulation(box(2π); viscosity = 0.02, velocity_forcing = NoForcing(),
                         kinetic_energy = 1.5, rng = MersenneTwister(1))
  small = Simulation(box(L); viscosity = 0.02σ^2, velocity_forcing = NoForcing(),
                     kinetic_energy = 1.5σ^2, rng = MersenneTwister(1))
  @test relative_error(field_data(reference.state.velocity_spectral),
                       field_data(small.state.velocity_spectral) ./ σ) < 1e-13
end


@testset "fixed steps: dealiasing, forcings and the scalar ($(nameof(typeof(dealiasing))))" for dealiasing in
    (TwoThirds(), PhaseShift(), HouLi())
  variance = VarianceRescaling(target = 1.0, over = :total)
  cases = (("NoForcing", NoForcing(), NoForcing(), nothing),
           ("ConstantPower", ConstantPower(injection_rate = 0.3), ConstantPower(injection_rate = 0.3σ^2), nothing),
           ("Linear", Linear(rate = 0.2), Linear(rate = 0.2), nothing),
           ("VarianceRescaling", variance, VarianceRescaling(target = 1.0σ^2, over = :total), nothing),
           ("VarianceController", VarianceController(target = 1.5, turnover_time = 1.0),
            VarianceController(target = 1.5σ^2, turnover_time = 1.0), nothing),
           ("ConstantPower with a scalar", ConstantPower(injection_rate = 0.3),
            ConstantPower(injection_rate = 0.3σ^2), PassiveScalar(schmidt = 1.0, variance = 1.0, forcing = variance)))
  for (name, forcing_reference, forcing_small, scalar) in cases
    @testset "$name" begin
      reference = Simulation(box(2π; dealiasing); viscosity = 0.02, velocity_forcing = forcing_reference,
                             scalar, rng = MersenneTwister(1))
      domain = box(L; dealiasing)
      small = Simulation(domain; viscosity = 0.02σ^2, velocity_forcing = forcing_small, scalar,
                         state = rescaled_state(reference, domain), rng = MersenneTwister(1))
      for _ in 1:4
        advance!(reference; dt = 0.002)
        advance!(small; dt = 0.002)
      end
      @test relative_error(field_data(reference.state.velocity_spectral),
                           field_data(small.state.velocity_spectral) ./ σ) < 1e-13
      scalar === nothing ||
        @test relative_error(field_data(reference.state.scalar_spectral),
                             field_data(small.state.scalar_spectral)) < 1e-13
    end
  end
end


@testset "adaptive steps, a stochastic forcing, tracers, and the observables" begin
  positions = rand(MersenneTwister(9), 20, 3) .* 2π
  tracking(domain, X) = ParticleTracking(Tracers(domain; interpolation_scheme = CatmullRom,
                                                 positions = PointSet(X), unwrapped = true),
                                         particle_integration_scheme = AdamsBashforth(order = 3))
  reference = Simulation(box(2π); viscosity = 0.02,
                         velocity_forcing = StochasticOU(forcing_variance = 0.5, correlation_time = 0.7, seed = 5),
                         particles = tracking(box(2π), copy(positions)), rng = MersenneTwister(1))
  domain = box(L)
  small = Simulation(domain; viscosity = 0.02σ^2,
                     velocity_forcing = StochasticOU(forcing_variance = 0.5σ^2, correlation_time = 0.7, seed = 5),
                     particles = tracking(domain, positions .* σ), state = rescaled_state(reference, domain),
                     rng = MersenneTwister(1))
  for _ in 1:8
    advance!(reference)
    advance!(small)
  end
  @test current_time(small) ≈ current_time(reference) rtol = 1e-13    # the CFL step is box-free
  ûR, ûL = reference.state.velocity_spectral, small.state.velocity_spectral
  @test relative_error(field_data(ûR), field_data(ûL) ./ σ) < 1e-13
  @test point_positions(small.tracers.positions) ./ σ ≈ point_positions(reference.tracers.positions) rtol = 1e-13
  @test point_positions(unwrapped_positions(small.tracers)) ./ σ ≈
        point_positions(unwrapped_positions(reference.tracers)) rtol = 1e-13

  ν = 0.02
  εR, εL = dissipation(ûR, reference.domain, ν), dissipation(ûL, domain, ν * σ^2)
  @test kinetic_energy(ûL) ≈ σ^2 * kinetic_energy(ûR) rtol = 1e-13
  @test εL ≈ σ^2 * εR rtol = 1e-13
  @test reynolds_box(L, εL, ν * σ^2) ≈ reynolds_box(2π, εR, ν) rtol = 1e-13
  @test integral_length(ûL, domain) ≈ σ * integral_length(ûR, reference.domain) rtol = 1e-13
  @test derivative_skewness(ûL, domain) ≈ derivative_skewness(ûR, reference.domain) rtol = 1e-12
  @test max_resolved_wavenumber(domain) * kolmogorov_length(εL, ν * σ^2) ≈
        max_resolved_wavenumber(reference.domain) * kolmogorov_length(εR, ν) rtol = 1e-13
  κR, ER = energy_spectrum(ûR, reference.domain)
  κL, EL = energy_spectrum(ûL, domain)
  @test κL .* σ ≈ κR rtol = 1e-13
  @test EL ./ σ^3 ≈ ER rtol = 1e-12                                   # a density: σ² over 1/σ
  below_R = kinetic_energy_and_dissipation_below_scale(ûR, reference.domain, ν)
  below_L = kinetic_energy_and_dissipation_below_scale(ûL, domain, ν * σ^2)
  @test below_L.scales ./ σ ≈ below_R.scales rtol = 1e-13
  @test below_L.kinetic_energy ./ σ^2 ≈ below_R.kinetic_energy rtol = 1e-12
  @test below_L.dissipation ./ σ^2 ≈ below_R.dissipation rtol = 1e-12
end


@testset "the predicted stationary state and the derived settings" begin
  forcings = (ConstantPower(), VarianceController(), VarianceRescaling(over = :total), Linear(),
              StochasticOU(correlation_time_in_box_units = 0.5))
  for forcing in forcings, setting in ((; κ_max_η = 2.0), (; viscosity = 0.05))
    small_setting = haskey(setting, :viscosity) ? (; viscosity = 0.05σ^2) : setting
    reference = predicted_stationary_state(box(2π); velocity_forcing = forcing, kinetic_energy = 1.5, setting...)
    small = predicted_stationary_state(box(L); velocity_forcing = forcing, kinetic_energy = 1.5σ^2, small_setting...)
    @test small.dissipation ≈ σ^2 * reference.dissipation rtol = 1e-12
    @test small.viscosity ≈ σ^2 * reference.viscosity rtol = 1e-12
    @test small.band_kinetic_energy ≈ σ^2 * reference.band_kinetic_energy rtol = 1e-12
    @test small.reynolds_box ≈ reference.reynolds_box rtol = 1e-12
    @test small.κ_max_η ≈ reference.κ_max_η rtol = 1e-12
  end
  reference = Simulation(box(2π); velocity_forcing = VarianceController(), kinetic_energy = 1.5,
                         rng = MersenneTwister(1))
  small = Simulation(box(L); velocity_forcing = VarianceController(), kinetic_energy = 1.5σ^2,
                     rng = MersenneTwister(1))
  @test small.generator.conditions.viscosity ≈ σ^2 * reference.generator.conditions.viscosity rtol = 1e-12
  @test small.generator.conditions.velocity_forcing.turnover_time ≈
        reference.generator.conditions.velocity_forcing.turnover_time rtol = 1e-12
end


@testset "a checkpoint keeps the box" begin
  sim = Simulation(box(L); viscosity = 1e-4, velocity_forcing = ConstantPower(injection_rate = 1.0),
                   particles = ParticleTracking(number_of_particles = 5), rng = MersenneTwister(1))
  for _ in 1:3
    advance!(sim)
  end
  path = tempname() * ".h5"
  h5open(io -> write_simulation(io, "sim", sim), path, "w")
  restored = h5open(io -> read_simulation(io, "sim"), path, "r")
  rm(path)
  @test restored.domain.grid.domain_size == (L, L, L)
  advance!(sim)
  advance!(restored)
  @test field_data(restored.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  @test point_positions(restored.tracers.positions) == point_positions(sim.tracers.positions)
end

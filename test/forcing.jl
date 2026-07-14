# Forcing tests for the linear (rate-folded-into-integrating-factor) strategies: Linear and
# ConstantPower. Checks (1) the rate amplitudes are set correctly — Linear gives A on the band,
# ConstantPower gives A = ε/(2E_band) so the injection rate equals the target; (2) the physical
# effect — Linear injects energy, scalar Linear builds variance; (3) the forced velocity stays
# divergence-free (the linear rate, folded into E_ν, preserves solenoidality).

using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU   # archived (un-exported); kept tested for the re-add
using GBGPeriodicFields: divergence, l2norm, field_data, spectral_band, convolve!, inner
using Random
using Test


@testset "forcing" begin
  T = Float64
  N = 24
  L = 2π
  ν = 0.05
  domain = FixedDomain(N, L; element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)

  û0 = spectral_vector(domain)
  random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(11))
  dealias!(û0, domain)

  run_velocity(conditions, nsteps; dt = 0.01) = begin
    û = spectral_vector(domain); copyto!(field_data(û), field_data(û0))
    φ̂ = scalar_spectral(domain)
    for _ in 1:nsteps
      velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
      step!(IFLowStorageRK3(), ResolvedFields(û, φ̂), domain, buffers, conditions, dt)
    end
    û
  end

  k0 = 2π / L
  band = spectral_band(scalar_spectral(domain), domain.multipliers, 0.5 * k0, 2.5 * k0)   # shells 1–2
  band_energy(field) = (tmp = spectral_vector(domain); convolve!(tmp, field, band); 0.5 * inner(tmp, tmp))

  @testset "Linear rate amplitude" begin
    A = 0.7
    forcing = Linear(domain; rate = A, lowest_shell = 1, highest_shell = 2)
    fill!(buffers.velocity_rate, 0.0)
    @test set_forcing_rate!(forcing, buffers.velocity_rate, û0, domain, buffers)
    @test maximum(buffers.velocity_rate) ≈ A        # A on the band
    @test minimum(buffers.velocity_rate) == 0       # zero outside the band
  end

  @testset "ConstantPower sets injection rate = power" begin
    power = 0.3
    forcing = ConstantPower(domain; target = power, lowest_shell = 1, highest_shell = 2)
    E_band = band_energy(û0)
    set_forcing_rate!(forcing, buffers.velocity_rate, û0, domain, buffers)
    A = maximum(buffers.velocity_rate)
    @test A * 2 * E_band ≈ power                # ⟨u·f⟩ = A·2E_band = ε_target
  end

  @testset "Linear injects energy, stays solenoidal" begin
    unforced = run_velocity(FlowConditions(viscosity = ν, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing()), 60)
    forced = run_velocity(FlowConditions(viscosity = ν,
                                  velocity_forcing = Linear(domain; rate = 1.0, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing()), 60)
    @test kinetic_energy(forced) > kinetic_energy(unforced)
    rel_div = l2norm(divergence(forced, domain.multipliers)) / (l2norm(forced) + 1e-30)
    @test rel_div < 1e-8
  end

  @testset "ConstantPower bounded and solenoidal" begin
    conditions = FlowConditions(viscosity = ν,
                      velocity_forcing = ConstantPower(domain; target = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = run_velocity(conditions, 100)
    @test isfinite(kinetic_energy(û)) && kinetic_energy(û) > 0
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8
  end

  @testset "scalar Linear forcing builds variance" begin
    û_zero = spectral_vector(domain)             # no velocity ⇒ pure linear growth of the scalar band
    φ̂0 = scalar_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 0.1, peak_wavenumber = 2.0, rng = MersenneTwister(9))
    conditions = FlowConditions(viscosity = ν,
                      scalar_forcing = Linear(domain; rate = 1.0, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, velocity_forcing = NoForcing())
    φ̂ = scalar_spectral(domain); copyto!(field_data(φ̂), field_data(φ̂0))
    for _ in 1:40
      velocity_to_physical!(buffers.velocity_physical, û_zero, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_start, û_zero, domain, buffers.vorticity_spectral)
      step!(IFLowStorageRK3(), ResolvedFields(û_zero, φ̂), domain, buffers, conditions, 0.01)
    end
    @test scalar_variance(φ̂) > scalar_variance(φ̂0)
  end

  @testset "StochasticOU stationary variance and solenoidality" begin
    target_variance = 0.4
    ou = StochasticOU(domain; variance = target_variance, correlation_time = 0.5,
                      lowest_shell = 1, highest_shell = 2, seed = 123)
    û = spectral_vector(domain)                              # velocity reference ⇒ solenoidal forcing
    samples = T[]
    for n in 1:1000
      prepare_forcing!(ou, û, domain, buffers, 0.01)
      n > 500 && push!(samples, inner(ou.state, ou.state))
    end
    @test 0.6 * target_variance < sum(samples) / length(samples) < 1.6 * target_variance
    rel_div = l2norm(divergence(ou.state, domain.multipliers)) / (l2norm(ou.state) + 1e-30)
    @test rel_div < 1e-8                                   # the forcing state is divergence-free
  end

  @testset "StochasticOU reproducible from seed" begin
    a = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 7)
    b = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 7)
    û = spectral_vector(domain)
    for n in 1:20
      prepare_forcing!(a, û, domain, buffers, 0.01)
      prepare_forcing!(b, û, domain, buffers, 0.01)
    end
    @test field_data(a.state) == field_data(b.state)
  end

  @testset "StochasticOU sustains velocity energy" begin
    ou = StochasticOU(domain; variance = 1.0, correlation_time = 0.3, lowest_shell = 1, highest_shell = 2, seed = 5)
    conditions = FlowConditions(viscosity = ν, velocity_forcing = ou, schmidt = 1.0, scalar_forcing = NoForcing())
    û = spectral_vector(domain)
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.1, peak_wavenumber = 2.0, rng = MersenneTwister(3))
    dealias!(û, domain)
    φ̂ = scalar_spectral(domain)
    for n in 1:200
      velocity_to_physical!(buffers.velocity_physical, û, domain, buffers.velocity_copy)
      vorticity_to_physical!(buffers.vorticity_start, û, domain, buffers.vorticity_spectral)
      dt = 0.4 * (L / N) / max(max_speed(buffers.velocity_physical), 1e-6)
      step!(IFLowStorageRK3(), ResolvedFields(û, φ̂), domain, buffers, conditions, dt)
    end
    @test isfinite(kinetic_energy(û)) && kinetic_energy(û) > 0.05   # forcing kept it from decaying away
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8
  end
end

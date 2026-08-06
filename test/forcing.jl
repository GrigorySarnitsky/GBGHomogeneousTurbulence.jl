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


# A forcing that implements the rate hook but forgets to declare it — the mistake the constructor
# guard exists to catch (defined at top level: a struct cannot be declared inside a testset body).
struct UndeclaredRateForcing <: AbstractForcing end
GBGIsotropicTurbulence.Forcing.set_forcing_rate!(::UndeclaredRateForcing, rate, field,
                                                 domain::FixedDomain) = (rate .= 1; true)


@testset "forcing" begin
  T = Float64
  N = 24
  L = 2π
  ν = 0.05
  domain = FixedDomain(N, L; element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)

  û0 = new_vector_field_spectral(domain)
  random_solenoidal_velocity!(û0, domain; kinetic_energy = 0.5, peak_wavenumber = 2.0, rng = MersenneTwister(11))
  dealias!(û0, domain)

  run_velocity(conditions, nsteps; dt = 0.01) = begin
    û = new_vector_field_spectral(domain); copyto!(field_data(û), field_data(û0))
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    derived = ObservablesCache(domain; scalar = true)
    deposit!(derived, state, domain, buffers)
    for _ in 1:nsteps
      step!(IFLowStorageRK3(), state, generator, domain, buffers, derived, dt)
      deposit!(derived, state, domain, buffers)
    end
    û
  end

  k0 = 2π / L
  band = spectral_band(new_scalar_field_spectral(domain), domain.multipliers, 0.5 * k0, 2.5 * k0)   # shells 1–2
  band_energy(field) = (tmp = new_vector_field_spectral(domain); convolve!(tmp, field, band); 0.5 * inner(tmp, tmp))

  @testset "Linear rate amplitude" begin
    A = 0.7
    forcing = Linear(domain; rate = A, lowest_shell = 1, highest_shell = 2)
    rate = new_scalar_field_spectral(domain)                  # the generator's rate slot: a scalar field in spectral representation
    @test set_forcing_rate!(forcing, rate, û0, domain)
    @test maximum(real.(field_data(rate))) ≈ A      # A on the band
    @test minimum(real.(field_data(rate))) == 0     # zero outside the band
  end

  @testset "ConstantPower sets injection rate = power" begin
    power = 0.3
    forcing = ConstantPower(domain; target = power, lowest_shell = 1, highest_shell = 2)
    E_band = band_energy(û0)
    rate = new_scalar_field_spectral(domain)
    set_forcing_rate!(forcing, rate, û0, domain)
    A = maximum(real.(field_data(rate)))
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
    û_zero = new_vector_field_spectral(domain)             # no velocity ⇒ pure linear growth of the scalar band
    φ̂0 = new_scalar_field_spectral(domain)
    random_scalar!(φ̂0, domain; scalar_variance = 0.1, peak_wavenumber = 2.0, rng = MersenneTwister(9))
    conditions = FlowConditions(viscosity = ν,
                      scalar_forcing = Linear(domain; rate = 1.0, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, velocity_forcing = NoForcing())
    φ̂ = new_scalar_field_spectral(domain); copyto!(field_data(φ̂), field_data(φ̂0))
    state = ResolvedFields(û_zero, φ̂)
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    derived = ObservablesCache(domain; scalar = true)
    deposit!(derived, state, domain, buffers)
    for _ in 1:40
      step!(IFLowStorageRK3(), state, generator, domain, buffers, derived, 0.01)
      deposit!(derived, state, domain, buffers)
    end
    @test scalar_variance(φ̂) > scalar_variance(φ̂0)
  end

  @testset "StochasticOU stationary variance and solenoidality" begin
    target_variance = 0.4
    ou = StochasticOU(domain; variance = target_variance, correlation_time = 0.5,
                      lowest_shell = 1, highest_shell = 2, seed = 123)
    û = new_vector_field_spectral(domain)                              # velocity reference ⇒ solenoidal forcing
    samples = T[]
    for n in 1:1000
      prepare_forcing!(ou, û, domain, 0.01)
      n > 500 && push!(samples, inner(ou.state, ou.state))
    end
    @test 0.6 * target_variance < sum(samples) / length(samples) < 1.6 * target_variance
    rel_div = l2norm(divergence(ou.state, domain.multipliers)) / (l2norm(ou.state) + 1e-30)
    @test rel_div < 1e-8                                   # the forcing state is divergence-free
  end

  @testset "StochasticOU reproducible from seed" begin
    a = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 7)
    b = StochasticOU(domain; variance = 0.3, correlation_time = 0.4, seed = 7)
    û = new_vector_field_spectral(domain)
    for n in 1:20
      prepare_forcing!(a, û, domain, 0.01)
      prepare_forcing!(b, û, domain, 0.01)
    end
    @test field_data(a.state) == field_data(b.state)
  end

  @testset "StochasticOU sustains velocity energy" begin
    ou = StochasticOU(domain; variance = 1.0, correlation_time = 0.3, lowest_shell = 1, highest_shell = 2, seed = 5)
    conditions = FlowConditions(viscosity = ν, velocity_forcing = ou, schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity!(û, domain; kinetic_energy = 0.1, peak_wavenumber = 2.0, rng = MersenneTwister(3))
    dealias!(û, domain)
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    derived = ObservablesCache(domain; scalar = true)
    deposit!(derived, state, domain, buffers)
    for n in 1:200
      dt = 0.4 * (L / N) / max(max_speed(derived), 1e-6)
      step!(IFLowStorageRK3(), state, generator, domain, buffers, derived, dt)
      deposit!(derived, state, domain, buffers)
    end
    @test isfinite(kinetic_energy(û)) && kinetic_energy(û) > 0.05   # forcing kept it from decaying away
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8
  end

  @testset "a rate array exists exactly where a forcing declares one" begin
    # The storage tracks the physics: only a forcing that drives its field through a linear per-mode
    # rate gets an A(κ) array. A post-step projection (BandRescaling — the run layer's default), a
    # stochastic source, and no forcing at all carry none.
    rate_driven = (Linear(domain; rate = 0.5), ConstantPower(domain; target = 0.1))
    other = (NoForcing(), BandRescaling(domain; target = 0.5),
             StochasticOU(domain; variance = 0.1, correlation_time = 0.5))
    generator(f) = ResolvedGenerator(domain, FlowConditions(; viscosity = ν, schmidt = 1.0,
                     velocity_forcing = f, scalar_forcing = NoForcing()); scalar = false)

    for f in rate_driven
      @test uses_linear_rate(f)
      @test generator(f).velocity_rate !== nothing
    end
    for f in other
      @test !uses_linear_rate(f)
      @test generator(f).velocity_rate === nothing
    end

    # The declaration is a contract, and breaking it is loud: a forcing that fills a rate without
    # declaring one would be handed nothing and go silently unapplied, so construction rejects it.
    @test_throws ArgumentError generator(UndeclaredRateForcing())
  end
end

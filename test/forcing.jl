# Forcing tests for the linear (rate-folded-into-integrating-factor) strategies: Linear and
# ConstantPower. Checks (1) the rate amplitudes are set correctly — Linear gives A on the band,
# ConstantPower gives A = ε/(2E_band) so the injection rate equals the target; (2) the physical
# effect — Linear injects energy, scalar Linear builds variance; (3) the forced velocity stays
# divergence-free (the linear rate, folded into E_ν, preserves solenoidality).

using GBGHomogeneousTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data, spectral_band, convolve!, inner, weighted_inner, field_scalar_type,
                         reality_residual, VectorFieldSpectral
using GBGHomogeneousTurbulence.Forcing: add_forcing_source!
using Logging


# The two weighted reductions the controller's own kernel performs, written out here rather than
# reached for, so the witness cannot be satisfied by reusing the code under test.
inner_band(f, band) = weighted_inner(f, band)
inner_kappa2(f, domain) = weighted_inner(f, domain.squared_wavenumber_kernel)
_probe_band(domain) = getfield(GBGHomogeneousTurbulence.Forcing, :_shell_band)(domain, 1, 2)
using Random
using Test


# A forcing that implements the rate hook but forgets to declare it — the mistake the constructor
# guard exists to catch (defined at top level: a struct cannot be declared inside a testset body).
struct UndeclaredRateForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.set_forcing_rate!(::UndeclaredRateForcing, rate, field,
                                                 domain::FixedDomain) = (rate .= 1; true)


# A forcing written to the source hook's pre-2026-09-18 five-argument form, before the forcing's
# evolving state reached it. Dispatch would fall straight through to the do-nothing default, so the
# forcing would be silently ignored.
struct StaleSourceForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.add_forcing_source!(::StaleSourceForcing, N̂, field, domain, diffusivity) = N̂


# A forcing written to the prepare hook's pre-2026-09-17 four-argument form, before the forcing's
# evolving state moved into the run's state. Also silently ignored, so also refused.
struct StalePrepareForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.prepare_forcing!(::StalePrepareForcing, field, domain, dt) = nothing


# The two shapes the arity guard must NOT reject: an idiomatic optional trailing argument (Julia
# auto-generates a short stub alongside the real method) and a strategy keeping a legacy overload for
# its own harness. Both dispatch correctly on the run-shaped five-argument call.
struct OptionalArgForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.add_forcing_source!(::OptionalArgForcing, forcing_state, N̂, field,
                                                   domain, diffusivity = 0.0) = N̂
struct KeptLegacyForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.add_forcing_source!(::KeptLegacyForcing, forcing_state, N̂, field,
                                                   domain, diffusivity) = N̂
GBGHomogeneousTurbulence.Forcing.add_forcing_source!(::KeptLegacyForcing, N̂, field, domain, diffusivity) = N̂


# A forcing whose rate tracks the state — the pre-2026-08-22 `ConstantPower` — but which declares it
# steady. Folded into the integrating factor it is frozen for the step, and the scheme silently drops
# to first order; measured at 1.05 against 3.01. Nothing about the values looks wrong, which is why
# the declaration is measured rather than trusted.
struct LyingRateForcing{K} <: AbstractForcing
  band::K
end


# Declares the steady rate and never implements the hook — the run would be silently unforced.
struct DeclaredNotImplementedForcing <: AbstractForcing end
GBGHomogeneousTurbulence.Forcing.uses_steady_linear_rate(::DeclaredNotImplementedForcing) = true
GBGHomogeneousTurbulence.Forcing.uses_steady_linear_rate(::LyingRateForcing) = true
function GBGHomogeneousTurbulence.Forcing.set_forcing_rate!(forcing::LyingRateForcing, rate, field,
                                                          domain::FixedDomain)
  amplitude = 0.1 / (2 * max(weighted_inner(field, forcing.band), 1e-30))
  field_data(rate) .= field_scalar_type(rate)(amplitude)
  return rate
end


@testset "forcing" begin
  T = Float64
  N = 24
  L = 2π
  ν = 0.05
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)

  û0 = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û0, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(11))
  truncate_to_band!(û0, domain)

  run_velocity(conditions, nsteps; dt = 0.01) = begin
    û = new_vector_field_spectral(domain); copyto!(field_data(û), field_data(û0))
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    deposit!(cache, state, domain, buffers)
    for _ in 1:nsteps
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
    end
    û
  end

  k0 = 2π / L
  band = spectral_band(domain.multipliers, 0.5 * k0, 2.5 * k0)   # shells 1–2
  band_energy(field) = (tmp = new_vector_field_spectral(domain); convolve!(tmp, field, band); 0.5 * inner(tmp, tmp))

  @testset "Linear rate amplitude" begin
    A = 0.7
    forcing = Linear(domain; rate = A, lowest_shell = 1, highest_shell = 2)
    rate = new_scalar_field_spectral(domain)                  # the generator's rate slot: a scalar field in spectral representation
    @test set_forcing_rate!(forcing, rate, û0, domain) === rate   # the hook returns its mutated argument
    @test maximum(real.(field_data(rate))) ≈ A      # A on the band
    @test minimum(real.(field_data(rate))) == 0     # zero outside the band
  end

  @testset "ConstantPower injects exactly its injection rate, through the per-stage source" begin
    # The property is unchanged — ⟨u·f⟩ = ε_target — but the route is. `ConstantPower`'s rate depends
    # on the band energy and so is NOT steady, which is why it left the integrating factor (folding a
    # varying A into the exponent integrates ∫A dt by a left-endpoint rectangle rule and costs the
    # scheme its order). The source hook receives the STAGE field, which is the point.
    power = 0.3
    forcing = ConstantPower(domain; injection_rate = power, lowest_shell = 1, highest_shell = 2)
    E_band = band_energy(û0)
    N̂ = new_vector_field_spectral(domain)
    field_data(N̂) .= 0
    add_forcing_source!(forcing, nothing, N̂, û0, domain, ν)
    # ⟨u·f⟩ over the band, with f the source just added: the injected power.
    @test real(inner(û0, N̂)) ≈ power  rtol = 1e-8
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
                      velocity_forcing = ConstantPower(domain; injection_rate = 0.5, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = run_velocity(conditions, 100)
    @test isfinite(kinetic_energy(û)) && kinetic_energy(û) > 0
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8
  end

  @testset "scalar Linear forcing builds variance" begin
    û_zero = new_vector_field_spectral(domain)             # no velocity ⇒ pure linear growth of the scalar band
    φ̂0 = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂0, domain; scalar_variance = 0.1, envelope_wavenumber = 2.0, rng = MersenneTwister(9))
    conditions = FlowConditions(viscosity = ν,
                      scalar_forcing = Linear(domain; rate = 1.0, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, velocity_forcing = NoForcing())
    φ̂ = new_scalar_field_spectral(domain); copyto!(field_data(φ̂), field_data(φ̂0))
    state = ResolvedFields(û_zero, φ̂)
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    deposit!(cache, state, domain, buffers)
    for _ in 1:40
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, 0.01)
      deposit!(cache, state, domain, buffers)
    end
    @test scalar_variance(φ̂) > scalar_variance(φ̂0)
  end

  # The force of one step as a field in spectral representation, through the same additive write a
  # stage uses — so the tests below judge the field the equations actually receive.
  function ou_force(ou, state, field)
    f̂ = field isa VectorFieldSpectral ? new_vector_field_spectral(domain) : new_scalar_field_spectral(domain)
    fill!(field_data(f̂), 0)
    add_forcing_source!(ou, state, f̂, field, domain, ν)
    return f̂
  end
  # the process's mean square, and the band's lattice modes counted here rather than reached for
  mean_square(state) = inner(state.process, state.process)
  band_modes = let k0 = 2π / L
    count(0.5 * k0 <= k0 * sqrt(i^2 + j^2 + k^2) <= 2.5 * k0 for i in -8:8, j in -8:8, k in -8:8)
  end

  @testset "StochasticOU: a real, divergence-free force with the stationary mean square" begin
    σ² = 0.4
    for field in (new_vector_field_spectral(domain), new_scalar_field_spectral(domain))
      ou = StochasticOU(domain; forcing_variance = σ², correlation_time = 0.5, seed = 123)
      state = initial_forcing_state(ou, field, domain)
      # A step of ten correlation times makes successive draws effectively independent (α = e⁻¹⁰),
      # so the ensemble mean converges at the rate of independent samples.
      samples = T[]
      for n in 1:4000
        prepare_forcing!(ou, state, field, domain, 5.0)
        push!(samples, mean_square(state))
      end
      average = sum(samples) / length(samples)
      @test abs(average / σ² - 1) < 0.02
      # Independent Gaussian modes make ⟨|f|²⟩ itself fluctuate, a χ² over D real degrees of freedom
      # (two per mode for the velocity after the transverse projection, one for the scalar), with
      # relative spread √(2/D). Scaling each increment by its realized norm pins it and fails here.
      D = (field isa VectorFieldSpectral ? 2 : 1) * band_modes
      spread = sqrt(sum(abs2, samples .- average) / (length(samples) - 1)) / average
      @test abs(spread / sqrt(2 / D) - 1) < 0.1
      f̂ = ou_force(ou, state, field)
      # the transfer between resolutions preserves the physical amplitude, so the force the run's
      # equations receive has exactly the mean square the process holds
      @test inner(f̂, f̂) ≈ samples[end] rtol = 1e-12
      @test reality_residual(f̂) == 0                          # a real force
      field isa VectorFieldSpectral && @test l2norm(divergence(f̂, domain.multipliers)) < 1e-12 * l2norm(f̂)
    end
  end

  @testset "StochasticOU: independent modes, equal shares, exact transition" begin
    σ², T_L, dt = 1.0, 0.5, 0.05
    α = exp(-dt / T_L)
    for û in (new_vector_field_spectral(domain), new_scalar_field_spectral(domain))
      ou = StochasticOU(domain; forcing_variance = σ², correlation_time = T_L, seed = 9)
      state = initial_forcing_state(ou, û, domain)
      process = field_data(state.process)
      # per MODE, summed over components: the transverse projection makes the share of a single
      # component depend on the mode's direction, while the mode's own share must not
      mode_share(c) = ndims(c) == 4 ? dropdims(sum(abs2, c; dims = 4), dims = 4) : abs2.(c)
      per_mode = zeros(size(process)[1:3])
      lagged = 0.0; power = 0.0
      previous = copy(process)
      for n in 1:20000
        prepare_forcing!(ou, state, û, domain, dt)
        per_mode .+= mode_share(process)
        lagged += real(sum(process .* conj.(previous))); power += sum(abs2, previous)
        previous .= process
      end
      # every forced mode holds the same share of the mean square, and every unforced one is empty
      per_mode ./= 20000
      forced = per_mode[per_mode .> 0]
      @test length(forced) > 0 && maximum(forced) / minimum(forced) - 1 < 0.2
      @test abs(lagged / power - α) < 0.01                      # the lag-one correlation is e^(−Δt/T_L)
    end
  end

  @testset "StochasticOU: the stream is fixed by the seed, the draw count, and the field" begin
    û = new_vector_field_spectral(domain)
    φ̂ = new_scalar_field_spectral(domain)
    a = StochasticOU(domain; forcing_variance = 0.3, correlation_time = 0.4, seed = 7)
    b = StochasticOU(domain; forcing_variance = 0.3, correlation_time = 0.4, seed = 7)
    c = StochasticOU(domain; forcing_variance = 0.3, correlation_time = 0.4, seed = 8)
    sa, sb, sc = (initial_forcing_state(f, û, domain) for f in (a, b, c))
    amplitudes(state) = copy(field_data(state.process))
    for n in 1:20, (f, s) in ((a, sa), (b, sb), (c, sc))
      prepare_forcing!(f, s, û, domain, 0.01)
    end
    @test amplitudes(sa) == amplitudes(sb) && sa.draws == 21
    @test amplitudes(sa) != amplitudes(sc)                   # the seed reaches the stream
    # every 64 bits of the seed reach it: a negative seed builds, draws, and differs from its magnitude
    # (a seed packed without widening, or cast rather than reinterpreted, fails one of these)
    negative = StochasticOU(domain; forcing_variance = 0.3, correlation_time = 0.4, seed = -7)
    @test amplitudes(initial_forcing_state(negative, û, domain)) != amplitudes(initial_forcing_state(a, û, domain))
    # a state resumes from its amplitudes and draw count alone: nothing else carries the stream
    resumed = StochasticOUState(deepcopy(sa.process), sa.draws)
    prepare_forcing!(a, sa, û, domain, 0.01)
    prepare_forcing!(c, resumed, û, domain, 0.01)            # another instance, same parameters but the seed…
    @test amplitudes(resumed) != amplitudes(sa)
    resumed = StochasticOUState(deepcopy(sb.process), sb.draws)
    prepare_forcing!(b, sb, û, domain, 0.01)
    prepare_forcing!(a, resumed, û, domain, 0.01)            # …and one with the same seed continues exactly
    @test amplitudes(resumed) == amplitudes(sb)
    # the velocity and the scalar of one seed draw different numbers
    sφ = initial_forcing_state(a, φ̂, domain)
    @test amplitudes(initial_forcing_state(a, û, domain))[:, :, :, 1] != amplitudes(sφ)
    # a hand-built record without the state is refused, not silently left unforced
    @test_throws ArgumentError prepare_forcing!(a, nothing, û, domain, 0.01)
    @test_throws ArgumentError prepare_forcing!(a, sφ, û, domain, 0.01)   # a scalar state on the velocity
  end

  @testset "StochasticOU: a band past the dealias cutoff is refused" begin
    # N = 24 under the 2/3 rule keeps |κ| ≤ 8; shells to 8 reach |κ| = 8.5 in the band's corners.
    @test_throws ArgumentError StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5,
                                            lowest_shell = 7, highest_shell = 8)
    @test StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5, lowest_shell = 6,
                       highest_shell = 7) isa StochasticOU
  end

  @testset "StochasticOU sustains velocity energy" begin
    ou = StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.3, lowest_shell = 1, highest_shell = 2, seed = 5)
    conditions = FlowConditions(viscosity = ν, velocity_forcing = ou, schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.1, envelope_wavenumber = 2.0, rng = MersenneTwister(3))
    truncate_to_band!(û, domain)
    φ̂ = new_scalar_field_spectral(domain)
    state = ResolvedFields(û, φ̂, (velocity_forcing = initial_forcing_state(ou, û, domain), scalar_forcing = nothing))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    deposit!(cache, state, domain, buffers)
    for n in 1:200
      dt = 0.4 * (L / N) / max(max_speed(cache), 1e-6)
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
    end
    @test isfinite(kinetic_energy(û)) && kinetic_energy(û) > 0.05   # forcing kept it from decaying away
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8
  end

  @testset "a rate array exists exactly where a forcing declares one" begin
    # The storage tracks the physics: only a forcing that drives its field through a linear per-mode
    # rate gets an A(κ) array. A post-step projection (VarianceRescaling — the run layer's default), a
    # stochastic source, and no forcing at all carry none.
    # Only `Linear` has a rate that is BOTH linear in the field and steady in time, so only `Linear`
    # earns the integrating factor. `ConstantPower` and `VarianceController` are linear but not
    # steady — their A tracks the band energy — and go through the per-stage source instead.
    rate_driven = (Linear(domain; rate = 0.5),)
    other = (NoForcing(), VarianceRescaling(domain; target = 0.5, over = :band),
             ConstantPower(domain; injection_rate = 0.1), VarianceController(domain; target = 0.5),
             StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5))
    generator(f) = ResolvedGenerator(domain, FlowConditions(; viscosity = ν, schmidt = 1.0,
                     velocity_forcing = f, scalar_forcing = NoForcing()); scalar = false)

    for f in rate_driven
      @test uses_steady_linear_rate(f)
      @test generator(f).velocity_rate !== nothing
    end
    for f in other
      @test !uses_steady_linear_rate(f)
      @test generator(f).velocity_rate === nothing
    end

    # The declaration is a contract, and breaking it is loud: a forcing that fills a rate without
    # declaring one would be handed nothing and go silently unapplied, so construction rejects it.
    @test_throws ArgumentError generator(UndeclaredRateForcing())

    # The same contract on the other hook: a strategy still written to the three-argument source
    # form defines a method the run never calls, so construction refuses it rather than integrating
    # an unforced run that reports nothing wrong. Every real strategy must pass unchallenged.
    @test_throws ArgumentError generator(StaleSourceForcing())
    @test_throws ArgumentError generator(StalePrepareForcing())

    # …but only that shape. The guard asks whether a CALLABLE five-argument method exists, not
    # whether every method in the table is one, so neither of these is locked out.
    @test generator(OptionalArgForcing()) isa ResolvedGenerator
    @test generator(KeptLegacyForcing()) isa ResolvedGenerator

    # `uses_steady_linear_rate` carries a semantic conjunct the arity guards cannot see, so it is
    # measured: the hook is armed from two different states and must give the same rate.
    @test_throws ArgumentError generator(LyingRateForcing(_probe_band(domain)))

    # …and the mirror: DECLARING the rate without IMPLEMENTING the hook leaves the do-nothing
    # default, whose zeroed rate is trivially steady — absence must be refused before steadiness.
    @test_throws ArgumentError generator(DeclaredNotImplementedForcing())
    for f in (NoForcing(), VarianceRescaling(domain; target = 0.5, over = :band),
              ConstantPower(domain; injection_rate = 0.1), VarianceController(domain; target = 0.5),
              Linear(domain; rate = 0.1), StochasticOU(domain; forcing_variance = 0.1, correlation_time = 0.5))
      @test generator(f) isa ResolvedGenerator
    end
  end


  @testset "VarianceController holds the WHOLE-field variance, normalizing by the band it forces" begin
    # Bassenne et al. (2016) Eq. 20 puts two DIFFERENT reductions in two places: the forcing acts on
    # the band, so the amplitude is normalized by k_f; the quantity held is the whole field, so the
    # restoring term measures k. Using k_f in both holds the band instead and lets k settle wherever
    # the cascade puts it — which is what this package shipped once, ~30% above the requested value.
    # The witness works on the amplitude directly, so it cannot be satisfied by a lucky steady state.
    target = 0.5
    forcing = VarianceController(domain; target, gain = 1.0)
    û = new_vector_field_spectral(domain); copyto!(field_data(û), field_data(û0))
    N̂ = new_vector_field_spectral(domain); fill!(field_data(N̂), 0)
    add_forcing_source!(forcing, nothing, N̂, û, domain, ν)

    k_whole = 0.5 * inner(û, û)
    k_band = 0.5 * inner_band(û, forcing.band)
    ε = ν * inner_kappa2(û, domain)
    expected = (ε - forcing.gain * (k_whole - target) / forcing.turnover_time) / (2 * k_band)

    # Recover the amplitude the hook applied: N̂ = A·𝟙_band·û, so compare against A·(band-projected û).
    probe = new_vector_field_spectral(domain); copyto!(field_data(probe), field_data(û))
    convolve!(probe, probe, forcing.band, one(T), zero(T))
    applied = inner(N̂, probe) / inner(probe, probe)
    @test isapprox(applied, expected; rtol = 1e-10)

    # The discriminating half: with k_whole ≠ k_band the two models differ, and they do here.
    wrong = (ε - forcing.gain * (k_band - target) / forcing.turnover_time) / (2 * k_band)
    @test !isapprox(applied, wrong; rtol = 1e-3)
  end


  @testset "the stationary-dissipation estimate is ε = (k/G)^{3/2}/L at the provisional G = 0.7" begin
    # One estimate serves the controller's default relaxation time and the run layer's derived
    # viscosity, so the two agree on what "stationary for this box" means by construction — they
    # disagreed by a factor of 2.68 when each spelled its own copy. G = 0.7 is the package's own
    # provisional measurement.
    estimate = getfield(GBGHomogeneousTurbulence.Forcing, :_stationary_dissipation_estimate)
    for k in (0.5, 1.5, 3.0), L in (1.0, 2π, 4.0)
      @test estimate(k, L) ≈ (k / 0.7)^(3 / 2) / L
    end
  end


  @testset "VarianceController preserves a Float32 run's element type" begin
    # The house rule `_target_factor` states and this constructor has to keep: a bare Float64 literal
    # in a default or a constant promotes the whole strategy off a Float32 run's element type. The
    # controller is the DEFAULT velocity forcing, so the leak would be on every run's path.
    for T in (Float32, Float64)
      d = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = T,
                      dealiasing = TwoThirds(), array_type = Array)
      @test typeof(VarianceController(d; target = T(1.5))).parameters[2] === T
      @test typeof(VarianceController(d; target = T(1.5), gain = 2, turnover_time = 3)).parameters[2] === T
    end
  end


  @testset "gain = 0 is the marginal law: k conserved, and NEVER restored" begin
    # The discriminating property, not just "it constructs": with the restoring term gone the rate
    # reinjects exactly the instantaneous dissipation, so k is conserved at its INITIAL value and
    # `target` never enters. A controller restores toward target; the marginal law must not. Seeding
    # k = 0.5 against target = 1.5 separates the two models by 3x — a drift could not fake it.
    # A starting energy away from the held one is an adopted `state`, not a second statement of the
    # stationary state (`kinetic_energy` alongside a forcing target is refused as stating it twice).
    marginal = VarianceController(domain; target = 1.5, gain = 0)
    seeded = ResolvedFields(domain)
    random_solenoidal_velocity_spectral!(seeded.velocity_spectral, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(3))
    sim = Simulation(domain; viscosity = 0.05, velocity_forcing = marginal, state = seeded)
    k0 = kinetic_energy(sim.state.velocity_spectral)
    for _ in 1:150; advance!(sim); end
    k = kinetic_energy(sim.state.velocity_spectral)
    @test isapprox(k, k0; rtol = 0.05)          # conserved (up to the uncorrected discrete bias)
    @test abs(k - 1.5) > 0.8                    # and nowhere near target: nothing restores

    # The guard's new boundary: zero in, negative and non-finite out.
    @test_throws ArgumentError VarianceController(domain; target = 1.5, gain = -1)
    @test_throws ArgumentError VarianceController(domain; target = 1.5, gain = Inf)
  end


  @testset "a band above the dealias cutoff warns: inert is legal but never silent" begin
    # The mask holds super-cutoff modes empty and every band forcing is field-proportional, so a
    # band up there multiplies zero forever — measured as exactly 0.0 injected over 100 steps. The
    # construction warns (entirely above: "will do NOTHING"; partially: "retained part"), and the
    # default band stays silent. N = 16 under TwoThirds puts the cutoff at shell ≈ 5.3.
    d16 = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                      dealiasing = TwoThirds(), array_type = Array)
    warns(f) = begin
      buf = IOBuffer()
      Logging.with_logger(Logging.SimpleLogger(buf, Logging.Warn)) do; f(); end
      String(take!(buf))
    end
    @test occursin("will do NOTHING", warns(() -> Linear(d16; rate = 0.1, lowest_shell = 6, highest_shell = 7)))
    @test occursin("retained part", warns(() -> Linear(d16; rate = 0.1, lowest_shell = 5, highest_shell = 6)))
    @test isempty(warns(() -> Linear(d16; rate = 0.1)))                          # the default band
    @test isempty(warns(() -> VarianceController(d16; target = 1.5)))            # every strategy routes through _shell_band
  end


  @testset "highest_shell = Inf forces every mode but the mean, on any grid" begin
    # The band-free form a physical-space code applies, stated once for every N. On each grid it must
    # be the whole-field rescale u ← u·√(target/k) mode by mode — and so identical for :band and
    # :total — reach every stored mode but κ = 0, draw no warning, and store Inf rather than the
    # corner shell it resolved to, which would mean "all modes" only on the grid it came from.
    quiet(f) = begin
      buf = IOBuffer()
      value = Logging.with_logger(Logging.SimpleLogger(buf, Logging.Warn)) do; f(); end
      value, String(take!(buf))
    end
    for n in (16, 24)                 # even and not a power of two: the corner shell differs
      d = FixedDomain(grid_points_per_axis = n, side_length = 2π, element_type = Float64,
                      dealiasing = TwoThirds(), array_type = Array)
      u = new_vector_field_spectral(d)
      random_solenoidal_velocity_spectral!(u, d; kinetic_energy = 0.7, envelope_wavenumber = 3.0,
                                           rng = MersenneTwister(n))
      expected = field_data(u) .* sqrt(1.3 / kinetic_energy(u))
      for over in (:band, :total)
        forcing, log = quiet(() -> VarianceRescaling(d; target = 1.3, over, highest_shell = Inf))
        @test isempty(log)
        @test forcing.highest_shell === Inf
        v = deepcopy(u)
        GBGHomogeneousTurbulence.Forcing.project_forcing!(forcing, v, d)
        @test kinetic_energy(v) ≈ 1.3 rtol = 1e-12
        @test maximum(abs.(field_data(v) .- expected)) <= 1e-12 * maximum(abs.(expected))
      end
      linear, log = quiet(() -> Linear(d; rate = 0.1, highest_shell = Inf))
      @test isempty(log)
      @test count(iszero, linear.indicator) == 1          # every stored mode but κ = 0
      @test linear.indicator[1, 1, 1] == 0
    end
    # The deferred form carries it through to whichever grid the run builds.
    d16 = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                      dealiasing = TwoThirds(), array_type = Array)
    @test VarianceController(; target = 1.0, highest_shell = Inf)(d16).highest_shell === Inf
    @test occursin("shells 1 to Inf", repr(ConstantPower(d16; injection_rate = 0.1, highest_shell = Inf)))
    # An integer-valued float is that shell — `[2, 4, Inf]` promotes 2 to 2.0 — and must never
    # read as `Inf`: it builds the same band and stores the integer.
    sweep = [2, 4, Inf]
    @test eltype(sweep) == Float64
    as_float = VarianceRescaling(d16; target = 1.0, over = :band, highest_shell = sweep[1])
    @test as_float.highest_shell === 2
    @test repr(as_float) == repr(VarianceRescaling(d16; target = 1.0, over = :band, highest_shell = 2))
    @test StochasticOU(d16; forcing_variance = 0.1, correlation_time = 0.5, highest_shell = 2.0).highest_shell === 2
    # Nothing between the integers, and no stochastic forcing of every mode.
    for bad in (2.5, -Inf, NaN)
      @test_throws ArgumentError ConstantPower(d16; injection_rate = 0.1, highest_shell = bad)
    end
    @test_throws ArgumentError StochasticOU(d16; forcing_variance = 0.1, correlation_time = 0.5,
                                            highest_shell = Inf)
  end


  @testset "VarianceController's in-line scalar dissipation matches scalar_dissipation" begin
    # The controller re-derives the field's dissipation mid-reduction (it cannot call the
    # `Observables` reduction without a second traversal) — a duplicated spelling the file's own
    # duplicate-then-pin rule demands a pin for. The velocity branch is pinned above through the
    # ν·⟨û,|κ|²û⟩ route; this is the scalar branch's 2ϰ convention. With `gain = 0` the restoring
    # term vanishes, so the controller's amplitude is exactly ε_φ/(2⟨φ²⟩_band) — the same amplitude
    # `ConstantPower` computes when handed `injection_rate = ε_φ`. Same band, same field: if the
    # controller's spelling drifted from `scalar_dissipation` (a lost 2, a wrong factor), the two
    # amplitudes part.
    domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                         dealiasing = TwoThirds(), array_type = Array)
    φ̂ = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂, domain; scalar_variance = 0.4, envelope_wavenumber = 2.0,
                            rng = MersenneTwister(31))
    ϰ = 0.05 / 0.7
    εφ = scalar_dissipation(φ̂, domain, ϰ)

    apply(forcing, diffusivity) = begin
      N̂ = new_scalar_field_spectral(domain); fill!(field_data(N̂), 0)
      add_forcing_source!(forcing, nothing, N̂, φ̂, domain, diffusivity)
      # N̂ = A·𝟙_band·φ̂; read A off the κ = (1,0,0) mode, which the default band [1,2] contains.
      real(field_data(N̂)[2, 1, 1] / field_data(φ̂)[2, 1, 1])
    end
    A_controller = apply(VarianceController(domain; target = 1.0, gain = 0), ϰ)
    A_constant = apply(ConstantPower(domain; injection_rate = εφ), ϰ)
    @test isapprox(A_controller, A_constant; rtol = 1e-12)
    # The discriminating half: halve the diffusivity and the controller's amplitude halves with
    # the dissipation it re-derives — a drifted spelling with a constant offset would not.
    @test isapprox(apply(VarianceController(domain; target = 1.0, gain = 0), ϰ / 2),
                   A_constant / 2; rtol = 1e-12)
  end
end

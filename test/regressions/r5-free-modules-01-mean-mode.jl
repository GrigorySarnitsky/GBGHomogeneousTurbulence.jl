# The mean velocity ⟨u⟩ — the κ = 0 Fourier coefficient of û — is EXACTLY conserved by the
# triple-periodic incompressible Navier–Stokes equations. In rotational form the statement is
# ⟨u × ω⟩ = 0: writing u × ω = ∇(½|u|²) − u·∇u, both means vanish over a periodic box (a gradient
# and a divergence). Discretely the same identity holds mode by mode,
#     FFT(u × ω)(0) = Σ_κ û(κ) × conj(ω̂(κ)) = −i Σ_κ κ |û(κ)|²  (using κ·û = 0),
# which cancels between the ±κ pairs; with the 2/3 rule no aliased triad reaches κ = 0 either.
# So the assembled velocity RHS must vanish identically at κ = 0, and a run seeded with ⟨u⟩ = 0 (the
# envelope zeroes that mode by construction) must keep ⟨u⟩ = 0 for all time.
#
# Nothing in the package enforces it: the Leray projection leaves κ = 0 untouched (ℙ(0) = I, not 0),
# so the FFT's round-off residual at κ = 0 enters the RHS, and the integrating factor
# exp(−ν|κ|²τ) = 1 there gives that mode zero damping. The residual is therefore integrated with no
# restoring term, and — because the flow is chaotic — is amplified at the Lyapunov rate rather than
# merely random-walking.
using Test, GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, to_physical!
using Random


# The κ = 0 coefficient of a vector field in spectral representation, as a plain 3-vector.
mean_mode(û) = Array(field_data(û))[1, 1, 1, :]
mean_mode_of(sim) = mean_mode(sim.state.velocity_spectral)


@testset "the κ=0 velocity mode is exactly conserved: ⟨u⟩ stays 0 in a run seeded with ⟨u⟩=0" begin

  @testset "the assembled velocity RHS vanishes identically at κ=0 (⟨u×ω⟩ = 0)" begin
    N = 32
    domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                         array_type = Array, dealiasing = TwoThirds())
    conditions = FlowConditions(viscosity = 0.02, schmidt = 1.0,
                                velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    generator = ResolvedGenerator(domain, conditions)
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.5, envelope_wavenumber = 4,
                                         rng = MersenneTwister(1))
    u = new_vector_field_physical(domain)
    ω = new_vector_field_physical(domain)
    N̂ = new_vector_field_spectral(domain)
    scratch = new_vector_field_spectral(domain)

    # With and without an imposed uniform sweep: the conservation law holds for either.
    for U in (0.0, 1.0)
      field_data(û)[1, 1, 1, 1] = U * N^3          # a uniform mean flow U in x
      to_physical!(u, û, domain.transform_plans, scratch)
      vorticity_physical!(ω, û, domain, scratch)
      prepare!(generator, ResolvedFields(û, nothing), domain, 0.005)
      velocity_rhs!(N̂, generator, û, u, ω, domain)
      @test all(iszero, mean_mode(N̂))
    end
  end

  @testset "an unforced Float64 run keeps ⟨u⟩ = 0 exactly" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.02,
                     velocity_forcing = NoForcing(), rng = MersenneTwister(1))
    @test all(iszero, mean_mode_of(sim))           # the seed: the envelope zeroes κ = 0
    advance!(sim)
    @test all(iszero, mean_mode_of(sim))
    for _ in 1:99
      advance!(sim)
    end
    @test all(iszero, mean_mode_of(sim))
  end

  @testset "a forced run keeps ⟨u⟩ = 0 exactly, in both precisions" begin
    for (T, steps) in ((Float64, 1000), (Float32, 1000))
      domain = FixedDomain(grid_points_per_axis = 32, side_length = 2π, element_type = T,
                           array_type = Array, dealiasing = TwoThirds())
      sim = Simulation(domain; viscosity = 0.02,
                       velocity_forcing = ConstantPower(injection_rate = 0.1),
                       rng = MersenneTwister(1))
      @test all(iszero, mean_mode_of(sim))
      for _ in 1:steps
        advance!(sim)
      end
      # The physical mean velocity is the κ = 0 coefficient divided by the grid-point count.
      drift = sqrt(sum(abs2, mean_mode_of(sim))) / 32^3
      u_rms = sqrt(2 * kinetic_energy(sim.state.velocity_spectral) / 3)
      @info "spurious mean flow after $steps steps" T mean_flow = drift u_rms ratio = drift / u_rms
      @test all(iszero, mean_mode_of(sim))
    end
  end
end

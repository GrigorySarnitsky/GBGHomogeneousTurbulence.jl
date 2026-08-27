# Integrator tests — the decisive check is temporal convergence order: IFLowStorageRK3 must be
# third-order and IFHeun second-order in Δt. Measured by self-convergence (Cauchy): integrating the
# same unforced decay to a fixed time with steps Δt, Δt/2, Δt/4, the ratio ‖u(Δt)−u(Δt/2)‖ /
# ‖u(Δt/2)−u(Δt/4)‖ ≈ 2^p for order p (≈8 for RK3, ≈4 for RK2). Plus RK3 forced-HIT invariants and
# the per-scheme CFL. (Velocity-only: the scalar is carried inert at zero.)

using GBGIsotropicTurbulence
using GBGPeriodicFields: divergence, l2norm, field_data
using Random
using Test


# Integrate the velocity from a copy of `û0` with a fixed `dt` for `nsteps`, carrying a zero scalar.
function integrate_fixed(scheme, domain, û0, conditions, dt, nsteps)
  buffers = allocate_buffers(scheme, domain; scalar = true)
  generator = ResolvedGenerator(domain, conditions; scalar = true)
  cache = ObservablesCache(domain; scalar = true)
  û = new_vector_field_spectral(domain)
  copyto!(field_data(û), field_data(û0))
  state = ResolvedFields(û, new_scalar_field_spectral(domain))
  deposit!(cache, state, domain, buffers)                 # the seeding deposit
  for _ in 1:nsteps
    step!(scheme, state, generator, domain, buffers, cache, dt)
    deposit!(cache, state, domain, buffers)               # the closing deposit ends the iteration
  end
  return û
end

diffnorm(a, b) = sqrt(sum(abs2, field_data(a) .- field_data(b)))


@testset "integrators" begin
  T = Float64
  N = 16
  L = 2π
  ν = 0.1
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_type = Array)
  buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)

  û0 = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û0, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0, rng = MersenneTwister(7))
  truncate_to_band!(û0, domain)

  Tfinal = 0.5
  n = 8

  @testset "temporal convergence order" begin
    unforced = FlowConditions(viscosity = ν, schmidt = 1.0, velocity_forcing = NoForcing(), scalar_forcing = NoForcing())
    rk3 = IFLowStorageRK3()
    u1 = integrate_fixed(rk3, domain, û0, unforced, Tfinal / n, n)
    u2 = integrate_fixed(rk3, domain, û0, unforced, Tfinal / (2n), 2n)
    u4 = integrate_fixed(rk3, domain, û0, unforced, Tfinal / (4n), 4n)
    rk3_ratio = diffnorm(u1, u2) / diffnorm(u2, u4)

    rk2 = IFHeun()
    v1 = integrate_fixed(rk2, domain, û0, unforced, Tfinal / n, n)
    v2 = integrate_fixed(rk2, domain, û0, unforced, Tfinal / (2n), 2n)
    v4 = integrate_fixed(rk2, domain, û0, unforced, Tfinal / (4n), 4n)
    rk2_ratio = diffnorm(v1, v2) / diffnorm(v2, v4)

    ssp = IFSSPRK3()
    w1 = integrate_fixed(ssp, domain, û0, unforced, Tfinal / n, n)
    w2 = integrate_fixed(ssp, domain, û0, unforced, Tfinal / (2n), 2n)
    w4 = integrate_fixed(ssp, domain, û0, unforced, Tfinal / (4n), 4n)
    ssp_ratio = diffnorm(w1, w2) / diffnorm(w2, w4)

    @test 5.0 < rk3_ratio < 12.0      # third order ⇒ ≈ 8
    @test 5.0 < ssp_ratio < 12.0      # third order ⇒ ≈ 8 (same order, different error constants)
    @test 3.0 < rk2_ratio < 6.0       # second order ⇒ ≈ 4
    @test rk3_ratio > rk2_ratio       # RK3 converges faster than RK2
    # The two RK3s are DIFFERENT tableaux: they must agree at Δt→0 (same equation) while their
    # single-Δt states differ (different error constants) — the pair pins "same order, distinct
    # scheme", which a convergence ratio alone cannot.
    @test diffnorm(u4, w4) < diffnorm(u1, w1)
    @test diffnorm(u1, w1) > 0
  end

  @testset "IFLowStorageRK3 forced-HIT invariants" begin
    conditions = FlowConditions(viscosity = ν,
                      velocity_forcing = VarianceRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    scheme = IFLowStorageRK3()
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    cache = ObservablesCache(domain; scalar = true)
    û = new_vector_field_spectral(domain)
    copyto!(field_data(û), field_data(û0))
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    deposit!(cache, state, domain, buffers)
    Δx = L / N
    cfl = recommended_cfl(scheme, domain)
    energies = T[]
    for _ in 1:200
      u = velocity_physical(cache)
      dt = cfl * Δx / max(max_speed(cache), 1e-6)
      push!(energies, kinetic_energy(u))
      step!(scheme, state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
    end
    @test all(isfinite, energies)
    @test 0.05 < energies[end] < 10.0
    rel_div = l2norm(divergence(û, domain.multipliers)) / (l2norm(û) + 1e-30)
    @test rel_div < 1e-8

    dt = cfl * Δx / max(max_speed(cache), 1e-6)
    step!(scheme, state, generator, domain, buffers, cache, dt)                       # warm up
    deposit!(cache, state, domain, buffers)
    bytes = @allocated step!(scheme, state, generator, domain, buffers, cache, dt)
    deposit_bytes = @allocated deposit!(cache, state, domain, buffers)
    field_bytes = length(field_data(û)) * sizeof(eltype(field_data(û)))
    @test bytes + deposit_bytes < field_bytes
  end

  @testset "recommended_cfl" begin
    @test recommended_cfl(IFLowStorageRK3(), domain) > recommended_cfl(IFHeun(), domain)
    @test 0 < recommended_cfl(IFHeun(), domain) < 1
    @test 0 < recommended_cfl(IFLowStorageRK3(), domain) < 1
  end
end

# The gap that let a first-order default ship undetected for as long as it did: every temporal
# convergence test above uses `NoForcing()`, so the one configuration a user actually gets was the
# only one never measured. A forcing whose rate depends on the state, folded into the integrating
# factor, evaluates ∫A dt by a left-endpoint rectangle rule and collapses the scheme to first order —
# and nothing here would have said so. Measured before the fix: ConstantPower 1.018, the front-door
# default 1.023, against 2.995 unforced.
#
# `VarianceRescaling` is deliberately included AT first order. It is the reference implementation of
# Sullivan-Mahalingam-Kerr (1994), a post-step projection, and Lie-Trotter splitting is first order by
# construction — so the assertion pins the caveat rather than a defect. If someone routes it through
# the rate or source hook, this test fails and asks them to update the documented caveat with it.
@testset "the scheme keeps its order under forcing, and the one exception is pinned" begin
  T = 0.2
  function measured_order(forcing)
    reference = nothing; errors = Float64[]
    for n in (1024, 32, 64)
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, field_integration_scheme = IFLowStorageRK3(),
                       velocity_forcing = forcing, rng = MersenneTwister(7))
      for _ in 1:n; advance!(sim; dt = T / n); end
      data = copy(field_data(sim.state.velocity_spectral))
      n == 1024 ? (reference = data) : push!(errors, maximum(abs, data .- reference))
    end
    return log2(errors[1] / errors[2])
  end

  @testset "third order — the rate and source routes" begin
    for (name, forcing) in (("unforced", NoForcing()),
                            ("Linear (steady rate → integrating factor)", Linear(rate = 0.5)),
                            ("ConstantPower (state-dependent → per-stage source)",
                             ConstantPower(injection_rate = 0.2)),
                            ("VarianceController (state-dependent → per-stage source)",
                             VarianceController(target = 1.5)))
      order = measured_order(forcing)
      @info "temporal order" forcing = name order
      @test order ≥ 2.5
    end
  end

  @testset "first order — the projection route, as documented" begin
    @test measured_order(VarianceRescaling(target = 1.5, over = :total)) < 1.5
  end
end

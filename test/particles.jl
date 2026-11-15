# Lagrangian tracer tests. Key checks: a uniform velocity advects tracers exactly; each particle
# integration scheme converges at its own order on a flow whose trajectory is known exactly and
# whose velocity varies in space (so the predictor matters) and in time; the ordinary start-up caps
# the order at three and the shortened one restores it; the Adams weights reduce to the classical
# constants; the stability limits are the textbook ones; positions wrap periodically; the
# interpolation scheme is pluggable; sampling reads a field along the trajectories; a trail keeps
# its samples and differentiates them; and the particle step and deposit refuse a field and
# positions from different times.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Cache: advance_fields_epoch!, advance_particles_epoch!,
                                    restore_velocity_at_particles!
using GBGHomogeneousTurbulence.ParticlePropagator: _adams_weights, _steps, _order_of_accuracy
using GBGHomogeneousTurbulence.SimulationRun: _startup_growth
using GBGPeriodicFields: point_positions, npoints
using GBGPeriodicFields: VectorFieldPhysical, ScalarFieldPhysical, field_data, to_physical, PointSet,
                         CatmullRom, LagrangeSpline, point_values
using Random
using Test

include(joinpath(@__DIR__, "prescribed_flow.jl"))


set_uniform_x!(uf, cx) = (d = field_data(uf); d .= 0; @views(d[:, :, :, 1] .= cx); uf)

# The straining flow of the order tests: u_x = c(t)·s·(x − x_c) with c(t) = cos(ωt), a sawtooth in
# x whose jump sits at the box edge, far from the tracer. `CatmullRom` reproduces a field linear in
# x exactly, so the tracer obeys x' = c(t)·s·(x − x_c), with the exact solution below. The velocity
# depends on the position, so a scheme's predictor enters the error; a uniform flow would hide it.
const STRAIN, FREQUENCY, CENTRE, START = 1.0, 3.0, π, π + 0.4
strain_exact(t) = CENTRE + (START - CENTRE) * exp(STRAIN * sin(FREQUENCY * t) / FREQUENCY)
strain_velocity(t) = cos(FREQUENCY * t) * STRAIN * (strain_exact(t) - CENTRE)
function write_strain!(u, t)
  d = field_data(u); d .= 0
  N = size(d, 1); Δx = 2π / N
  for i in 1:N
    @views d[i, :, :, 1] .= cos(FREQUENCY * t) * STRAIN * ((i - 1) * Δx - CENTRE)
  end
  return u
end

# The largest error along a pass through `steps`. (The error at one time changes sign with the step
# count, which makes an order estimated from it erratic; the largest over the pass does not.) With
# `exact_start` the trail is given the exact earlier samples the scheme integrates over (at times
# −h, −2h, … for the first step size h), so the measured order is the scheme's own; without it the
# run starts as a run does, on one sample.
function strain_error(scheme, steps; exact_start::Bool)
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  tracers = Tracers(domain; positions = PointSet([START 1.0 1.0]), interpolation_scheme = CatmullRom)
  cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
  deposit_prescribed_velocity!(u -> write_strain!(u, 0.0), cache; step = false)
  if exact_start
    h = steps[1]
    for j in (_steps(scheme) - 1):-1:1
      restore_velocity_at_particles!(cache, -j * h) do value
        values = point_values(value); values .= 0; values[1, 1] = strain_velocity(-j * h)
      end
    end
  end
  deposit!(cache, tracers, 0.0)
  t, largest = 0.0, 0.0
  for h in steps
    t = advect_in_prescribed_flow!(write_strain!, scheme, tracers, domain, cache, (h,); t0 = t,
                                   started = true)
    largest = max(largest, abs(point_positions(tracers.positions)[1, 1] - strain_exact(t)))
  end
  return largest
end

uniform_steps(n; T = 2.0) = fill(T / n, n)
uneven_steps(n; T = 2.0) = (h = [1 + 0.3 * sin(7i) for i in 1:n]; h .* (T / sum(h)))
# The steps a run with `shortened_first_steps` takes, by the run's own rule with the flow's time
# scale 1/ω in the place of the Kolmogorov time: the first step τ(Δt/τ)^(p/3), then growth by the
# package's factor for the order, up to the ordinary Δt.
function shortened_steps(scheme, n; T = 2.0, τ = 1 / FREQUENCY)
  p = _order_of_accuracy(scheme); Δt = T / n
  steps = Float64[]; t = 0.0
  while t < T - 1e-12
    h = isempty(steps) ? min(Δt, τ * (Δt / τ)^(p / 3)) : min(Δt, _startup_growth(p) * steps[end])
    h = min(h, T - t); push!(steps, h); t += h
  end
  return steps
end
measured_order(errors) = log2(errors[end-1] / errors[end])


@testset "particles" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T, dealiasing = TwoThirds(), array_family = Array)

  @testset "uniform field advects exactly" begin
    X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0; 2.0 3.0 4.0]
    c = 0.5
    nsteps, dt = 20, 0.005
    for scheme in (Heun(), AB(1), AB(3), ABM(3))
      tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
      cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
      advect_in_prescribed_flow!((u, t) -> set_uniform_x!(u, c), scheme, tracers, domain, cache,
                                 fill(dt, nsteps))
      X = point_positions(tracers.positions)
      @test X[:, 1] ≈ mod.(X0[:, 1] .+ c * nsteps * dt, L)     # moved at constant speed
      @test X[:, 2] ≈ X0[:, 2]                                  # transverse components unchanged
      @test X[:, 3] ≈ X0[:, 3]
    end
  end

  @testset "positions wrap into [0, L)" begin
    X0 = T[6.2 6.2 6.2]                                        # near the upper boundary (L = 2π ≈ 6.283)
    tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom,
                      unwrapped = true)
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = Heun())
    advect_in_prescribed_flow!((u, t) -> set_uniform_x!(u, 1.0), Heun(), tracers, domain, cache,
                               fill(0.02, 30))
    X = point_positions(tracers.positions)
    @test all(0 .<= X .< L)                                    # wrapped, still in the box
    # The unwrapped record took the same displacements without the reduction.
    @test point_positions(unwrapped_positions(tracers))[1, 1] ≈ 6.2 + 30 * 0.02
  end

  @testset "pluggable scheme" begin
    for scheme in (CatmullRom, LagrangeSpline(6))
      tracers = Tracers(domain; number_of_particles = 50, interpolation_scheme = scheme, rng = MersenneTwister(1))
      cache = ObservablesCache(domain; tracers, particle_integration_scheme = Heun())
      advect_in_prescribed_flow!((u, t) -> set_uniform_x!(u, 0.3), Heun(), tracers, domain, cache,
                                 fill(0.01, 10))
      X = point_positions(tracers.positions)
      @test all(isfinite, X) && all(0 .<= X .< L)
    end
  end

  @testset "interpolate_at_particles! reads a field along trajectories" begin
    tracers = Tracers(domain; number_of_particles = 40, interpolation_scheme = CatmullRom, rng = MersenneTwister(2))
    constant = ScalarFieldPhysical(Array, (x, y, z) -> 2.5, domain.grid)
    samples = new_scalar_point_values(tracers)
    interpolate_at_particles!(samples, constant, tracers)
    @test all(≈(2.5), point_values(samples))                  # a constant field samples exactly
  end

  @testset "advect in a real HIT velocity field" begin
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    conditions = FlowConditions(viscosity = 0.05,
                      velocity_forcing = VarianceRescaling(domain; target = 0.5, over = :band, lowest_shell = 1, highest_shell = 2), schmidt = 1.0, scalar_forcing = NoForcing())
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain, 0.5; peak_shell = 2.0, rng = MersenneTwister(4))
    truncate_to_band!(û, domain)
    state = ResolvedFields(û, new_scalar_field_spectral(domain))
    generator = ResolvedGenerator(domain, conditions; scalar = true)
    tracers = Tracers(domain; number_of_particles = 200, interpolation_scheme = CatmullRom, rng = MersenneTwister(5))
    cache = ObservablesCache(domain; scalar = true, tracers, particle_integration_scheme = Heun())
    deposit!(cache, state, domain, buffers)
    deposit!(cache, tracers, 0.0)

    Δx = L / N
    t = 0.0
    for _ in 1:50
      dt = 0.4 * Δx / max(max_speed(cache), 1e-6)
      step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, dt)
      deposit!(cache, state, domain, buffers)
      advect!(Heun(), tracers, domain, cache, dt)
      t += dt
      deposit!(cache, tracers, t)                              # u(tₙ₊₁) at the new positions
    end
    @test all(isfinite, point_positions(tracers.positions)) && all(0 .<= point_positions(tracers.positions) .< L)
    @test all(isfinite, point_values(velocity_at_particles_trail(cache)[0].value))

    # allocation-free advection step — the push and its closing deposit
    step!(IFLowStorageRK3(), state, generator, domain, buffers, cache, 0.001)
    deposit!(cache, state, domain, buffers)
    bytes = @allocated (advect!(Heun(), tracers, domain, cache, 0.001);
                        deposit!(cache, tracers, t + 0.001))
    @test bytes < 4096
  end
end


# The schemes. The weights are the machinery, so they are pinned against the classical constants
# they must reduce to at uniform step; the orders are measured against an exact trajectory; and the
# start-up is pinned end to end, since a multistep scheme that silently never left its first steps
# would still "work".
@testset "particle integration schemes" begin
  @testset "the scheme family" begin
    @test ABM(1) === Heun()                                    # one scheme, one name
    @test Heun() isa AbstractParticleIntegrator && AB(4) isa AbstractParticleIntegrator
    @test_throws ArgumentError AB(0)
    @test_throws ArgumentError AB(9)                           # past the quadrature's exactness
    @test_throws ArgumentError ABM(0)
    @test_throws ArgumentError ABM(8)
    @test AB(8) isa AB && ABM(7) isa ABM
  end

  @testset "the weights reduce to the classical coefficients at uniform step" begin
    nodes(k) = ntuple(i -> -(i - 1.0), k)
    # Adams–Bashforth
    @test collect(_adams_weights(nodes(1), 1.0)) ≈ [1.0]
    @test collect(_adams_weights(nodes(2), 1.0)) ≈ [3, -1] ./ 2
    @test collect(_adams_weights(nodes(3), 1.0)) ≈ [23, -16, 5] ./ 12
    @test collect(_adams_weights(nodes(4), 1.0)) ≈ [55, -59, 37, -9] ./ 24
    # Adams–Moulton: the step's end among the nodes
    @test collect(_adams_weights((1.0, nodes(1)...), 1.0)) ≈ [1, 1] ./ 2          # trapezoid
    @test collect(_adams_weights((1.0, nodes(2)...), 1.0)) ≈ [5, 8, -1] ./ 12
    @test collect(_adams_weights((1.0, nodes(3)...), 1.0)) ≈ [9, 19, -5, 1] ./ 24
    @test collect(_adams_weights((1.0, nodes(4)...), 1.0)) ≈ [251, 646, -264, 106, -19] ./ 720
    # A weight set integrates a constant exactly, whatever the nodes; and a polynomial up to its
    # degree: here t³ over [0, 0.7] from four uneven nodes.
    uneven = (0.0, -0.3, -1.2, -1.4)
    @test sum(_adams_weights(uneven, 0.7)) ≈ 0.7
    @test sum(_adams_weights(uneven, 0.7) .* uneven .^ 3) ≈ 0.7^4 / 4
    # The largest sets the constructors allow are still integrated exactly: degree 7, eight nodes.
    eight = ntuple(i -> -0.37 * (i - 1) - 0.05 * i^2, 8)
    @test sum(_adams_weights(eight, 0.9) .* eight .^ 7) ≈ 0.9^8 / 8 rtol = 1e-8
  end

  @testset "each scheme converges at its own order" begin
    # Exact earlier samples, so nothing but the scheme's own error is measured: `AB(k)` at order k,
    # `ABM(k)` at order k + 1, at uniform and at uneven steps alike. The high orders reach round-off
    # sooner, so they are measured one refinement coarser.
    for scheme in (AB.(1:8)..., ABM.(1:7)...), steps_of in (uniform_steps, uneven_steps)
      p = _order_of_accuracy(scheme)
      counts = p >= 6 ? (32, 64, 128) : (64, 128, 256)
      errors = [strain_error(scheme, steps_of(n); exact_start = true) for n in counts]
      @test abs(measured_order(errors) - p) < 0.5
    end
    # At equal order and equal number of samples, the corrected scheme makes the smaller error.
    for k in 1:7
      @test strain_error(ABM(k), uniform_steps(64); exact_start = true) <
            strain_error(AB(k + 1), uniform_steps(64); exact_start = true)
    end
  end

  @testset "the ordinary start-up leaves an error of third order" begin
    # The first step is taken on one sample, as ABM(1), with a local error of third order; whatever
    # the scheme's own order, that error stays. So a higher order buys nothing here, and costs
    # nothing either: the errors agree.
    counts = (64, 128, 256)
    reference = [strain_error(ABM(4), uniform_steps(n); exact_start = false) for n in counts]
    @test 2.7 < measured_order(reference) < 3.3
    for scheme in (AB(6), AB(8), ABM(7))
      errors = [strain_error(scheme, uniform_steps(n); exact_start = false) for n in counts]
      @test 2.7 < measured_order(errors) < 3.3
      @test isapprox(errors[end], reference[end]; rtol = 0.05)
    end
    errors = [strain_error(AB(4), uniform_steps(n); exact_start = false) for n in counts]
    @test 2.7 < measured_order(errors) < 3.5
    @test reference[end] / 2 < errors[end] < 2 * reference[end]
    # A two-step scheme is no better than its own order allows.
    errors = [strain_error(AB(2), uniform_steps(n); exact_start = false) for n in counts]
    @test 1.7 < measured_order(errors) < 2.3
  end

  @testset "shortened first steps restore the full order" begin
    for scheme in (AB.(3:8)..., ABM.(2:7)...)
      errors = [strain_error(scheme, shortened_steps(scheme, n); exact_start = false) for n in (32, 64, 128)]
      @test measured_order(errors) > _order_of_accuracy(scheme) - 0.6
      # …with an error close to the exactly started scheme's at the same step.
      @test errors[2] < 4 * strain_error(scheme, uniform_steps(64); exact_start = true)
    end
    # The growth factor depends on the order for a reason: at order 8, the doubling that serves
    # order 5 loses the accuracy again.
    doubling = let p = 8, τ = 1 / FREQUENCY, Δt = 2.0 / 64
      steps = Float64[]; t = 0.0
      while t < 2.0 - 1e-12
        h = isempty(steps) ? min(Δt, τ * (Δt / τ)^(p / 3)) : min(Δt, 2.0 * steps[end])
        h = min(h, 2.0 - t); push!(steps, h); t += h
      end
      strain_error(AB(8), steps; exact_start = false)
    end
    @test doubling > 20 * strain_error(AB(8), shortened_steps(AB(8), 64); exact_start = false)
  end

  @testset "the stability limits on the real axis are the textbook ones" begin
    # The largest h·|λ| at which the scheme, at uniform step, damps x' = λx with λ real and negative.
    # At z = hλ a step is the linear recurrence y_{n+1} = Σ_j c_j(z) y_{n+1-j}, and the scheme is
    # stable there exactly when its iterates stay bounded; the recurrence is iterated directly, from a
    # start that excites every mode, and the edge of the interval is then found by bisection.
    function real_axis_limit(k, corrected)
      nodes = ntuple(i -> -(i - 1.0), k)
      b = collect(_adams_weights(nodes, 1.0))
      β = corrected ? collect(_adams_weights((1.0, nodes...), 1.0)) : zeros(k + 1)
      function grows(z)
        c = corrected ? z .* β[2:end] .+ z^2 * β[1] .* b : z .* b
        c[1] += corrected ? 1 + z * β[1] : 1
        y = [isodd(i) ? 1.0 : -0.6 for i in 1:k]            # newest first
        for _ in 1:40_000
          newest = sum(c[j] * y[j] for j in 1:k)
          abs(newest) > 1e8 && return true
          for j in k:-1:2; y[j] = y[j-1]; end
          y[1] = newest
        end
        return false
      end
      stable, unstable = 0.0, 3.0
      for x in 0.05:0.05:3.0                                  # the first unstable point, coarsely
        grows(-x) ? (unstable = x; break) : (stable = x)
      end
      for _ in 1:12                                           # …then its edge
        middle = (stable + unstable) / 2
        grows(-middle) ? (unstable = middle) : (stable = middle)
      end
      return stable
    end
    # Adams–Bashforth: 2, 1, 6/11, 3/10, 90/551 — the classical intervals.
    @test real_axis_limit(1, false) ≈ 2 atol = 2e-3
    @test real_axis_limit(2, false) ≈ 1 atol = 2e-3
    @test real_axis_limit(3, false) ≈ 6 / 11 atol = 2e-3
    @test real_axis_limit(4, false) ≈ 3 / 10 atol = 2e-3
    @test real_axis_limit(5, false) ≈ 90 / 551 atol = 2e-3
    # Heun is the second-order Runge–Kutta polynomial 1 + z + z²/2, stable to −2.
    @test real_axis_limit(1, true) ≈ 2 atol = 2e-3
    # The numbers the `AB` docstring states, for the scheme and for the corrected one of its order.
    @test real_axis_limit(6, false) ≈ 0.088 atol = 2e-3
    @test real_axis_limit(8, false) ≈ 0.024 atol = 2e-3
    @test real_axis_limit(3, true) ≈ 1.93 atol = 0.02
    @test real_axis_limit(5, true) ≈ 1.04 atol = 0.02
    @test real_axis_limit(7, true) ≈ 0.58 atol = 0.02
    # The interval shrinks fast with the order, and the corrected scheme of the same order keeps a
    # far larger one.
    @test real_axis_limit(8, false) < 0.03
    @test real_axis_limit(7, true) > 0.5
    @test all(real_axis_limit(k, true) > 4 * real_axis_limit(k + 1, false) for k in 2:7)
  end

  @testset "the trail fills and the scheme takes over" begin
    for (scheme, capacity) in ((Heun(), 2), (AB(4), 4), (ABM(4), 5), (AB(1), 1))
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                       particles = ParticleTracking(number_of_particles = 32,
                                                    particle_integration_scheme = scheme),
                       rng = MersenneTwister(7))
      trail = velocity_at_particles_trail(sim.cache)
      @test length(trail) == 1                                 # the seeding sample, at time zero
      @test trail[0].time == 0.0
      for n in 1:(capacity + 2)
        advance!(sim)
        @test length(velocity_at_particles_trail(sim.cache)) == min(n + 1, capacity)
        # The trail's newest time is the clock's reading, bit for bit.
        @test velocity_at_particles_trail(sim.cache)[0].time === current_time(sim)
      end
      @test all(isfinite, point_positions(sim.tracers.positions))
    end
  end

  @testset "positions stay in the box and tracers actually move" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 32,
                                                  particle_integration_scheme = AB(2)),
                     rng = MersenneTwister(8))
    X0 = copy(point_positions(sim.tracers.positions))
    for _ in 1:5; advance!(sim); end
    X = point_positions(sim.tracers.positions)
    @test !isapprox(X0, X)
    @test all(0 .<= X .< sim.domain.grid.domain_size[1])
  end

  @testset "the run's first steps are shortened on request" begin
    step_sizes(scheme; shortened) = begin
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(5),
                       particles = ParticleTracking(number_of_particles = 16,
                                                    particle_integration_scheme = scheme,
                                                    shortened_first_steps = shortened))
      sizes = Float64[]
      for _ in 1:8
        before = current_time(sim); advance!(sim); push!(sizes, current_time(sim) - before)
      end
      sizes
    end
    ordinary = step_sizes(ABM(4); shortened = false)
    short = step_sizes(ABM(4); shortened = true)
    @test short[1] < ordinary[1] / 2                           # the first step is cut
    @test all(short[i+1] <= _startup_growth(5) * short[i] * (1 + 1e-12) for i in 1:7)
    @test short[2] ≈ 2 * short[1]                              # and grows back by the factor
    @test short[end] > short[1]
    # A one-sample scheme has nothing to start, so the setting leaves its steps alone.
    @test step_sizes(Heun(); shortened = true) == step_sizes(Heun(); shortened = false)
    # A fixed step and the shortened start are two rules for the same steps.
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 16,
                                                  particle_integration_scheme = AB(4),
                                                  shortened_first_steps = true))
    @test_throws ArgumentError advance!(sim; dt = 0.01)
    @test_throws ArgumentError run!(s -> current_step(s) < 2, sim; dt = 0.01)
  end

  # Decision 86: the traversal order reorders the gathers' visits and changes no value, so a run
  # with it must be BITWISE the run without it — the witness that the wiring passed the order to
  # the right gathers and nothing else. Under `:manual` the order goes stale as the tracers move,
  # which the field library documents as never wrong; the identical assertion holds unrebuilt.
  @testset "the traversal order is a value-preserving accelerator (decision 86)" begin
    function tracked(mode; scheme = Heun(), steps = 6, M = 300)
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(3),
                       particles = ParticleTracking(number_of_particles = M, unwrapped = true,
                                                    particle_integration_scheme = scheme,
                                                    traversal_mode = mode))
      for _ in 1:steps; advance!(sim); end
      sim
    end
    for scheme in (Heun(), AB(3), ABM(3))
      off = tracked(:none; scheme)
      for mode in (:automatic, :manual)
        on = tracked(mode; scheme)
        @test point_positions(on.tracers.positions) == point_positions(off.tracers.positions)
        @test point_positions(unwrapped_positions(on.tracers)) ==
              point_positions(unwrapped_positions(off.tracers))
        @test all(point_values(a.value) == point_values(b.value) && a.time == b.time
                  for (a, b) in zip(velocity_at_particles_trail(on.cache),
                                    velocity_at_particles_trail(off.cache)))
        @test on.particle_traversal isa ParticleTraversal
        @test on.particle_traversal.automatic == (mode !== :manual)
      end
      @test off.particle_traversal === nothing
    end

    # A caller's gather takes the same order, with the same values.
    on = tracked(:automatic); off = tracked(:none)
    a = new_vector_point_values(on.tracers); b = new_vector_point_values(off.tracers)
    interpolate_at_particles!(a, velocity_physical(on.cache), on.tracers;
                              traversal = on.particle_traversal)
    interpolate_at_particles!(b, velocity_physical(off.cache), off.tracers)
    @test point_values(a) == point_values(b)

    # A rebuilt order agrees with a freshly built one from the same positions.
    man = tracked(:manual)
    rebuild_traversal!(man)
    fresh = ParticleTraversal(man.domain, man.tracers)
    @test Array(man.particle_traversal.order.indices) == Array(fresh.order.indices)
    @test sort(Int.(Array(fresh.order.indices))) == 1:300
  end

  @testset "the traversal order adds no per-step allocation that scales with M" begin
    alloc(M) = (sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                 particles = ParticleTracking(number_of_particles = M),
                                 rng = MersenneTwister(1));
                advance!(sim); advance!(sim); @allocated advance!(sim))
    # Tenfold in M, both above the count where a threaded run's CPU kernels stop adding tasks (the
    # task setup grows with M up to a cap and then stays flat, measured 2026-10-09; one thread is flat
    # throughout), so any growth left is an M-sized buffer.
    small, large = alloc(40_000), alloc(400_000)
    @test large <= small + 512               # constant launch bookkeeping, not an M-sized buffer
  end

  @testset "the traversal setting is refused by name where it cannot apply" begin
    # Since 2026-10-14 the mode travels inside `ParticleTracking`, so it cannot be written for a
    # tracer-free run at all; a mode that is not one of the three is refused where it is named.
    @test_throws MethodError Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                        traversal_mode = :manual)
    @test_throws ArgumentError ParticleTracking(number_of_particles = 8, traversal_mode = :sometimes)
    @test_throws ArgumentError ParticleTracking(number_of_particles = 0)
    @test_throws ArgumentError rebuild_traversal!(Simulation(grid_points_per_axis = 16, viscosity = 0.05))
    @test_throws ArgumentError rebuild_traversal!(Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                                                             particles = ParticleTracking(number_of_particles = 8,
                                                                                          traversal_mode = :none)))
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                     particles = ParticleTracking(number_of_particles = 8, traversal_mode = :manual))
    @test rebuild_traversal!(sim) === sim
  end
end


# The trail as a collection: what it holds, how it is read and written, and what it refuses.
@testset "ParticleTrail" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  tracers = Tracers(domain; number_of_particles = 3, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  fill_with(x) = value -> (point_values(value) .= x)

  @testset "it keeps the newest samples and reads them by offset" begin    # `getindex` and the collection interface
    trail = ParticleTrail(new_scalar_point_values, tracers, 3)
    @test length(trail) == 0 && isempty(trail)
    @test_throws ArgumentError trail[0]                        # nothing to read yet
    for (n, t) in enumerate((0.1, 0.25, 0.3, 0.52, 0.6))
      @test push!(fill_with(10t), trail, t) === trail
      @test length(trail) == min(n, 3)
      @test trail[0].time == t && all(==(10t), point_values(trail[0].value))
    end
    # Full: the three newest, the oldest two dropped.
    @test [sample.time for sample in trail] == [0.3, 0.52, 0.6]         # oldest to newest
    @test trail[-1].time == 0.52 && all(==(5.2), point_values(trail[-1].value))
    @test trail[begin].time == 0.3 && trail[end].time == 0.6
    @test firstindex(trail) == -2 && lastindex(trail) == 0 && keys(trail) == -2:0
    @test eltype(trail) == typeof(trail[0])
    # A sample is the trail's own storage, not a copy.
    @test trail[0].value === trail[0].value
  end

  @testset "what it refuses" begin
    trail = ParticleTrail(new_vector_point_values, tracers, 4)
    push!(fill_with(1.0), trail, 1.0); push!(fill_with(2.0), trail, 2.0)
    @test_throws ArgumentError trail[1]                        # a positive offset
    @test_throws ArgumentError trail[-2]                       # further back than is held so far
    @test_throws ArgumentError trail[-4]                       # further back than the capacity
    @test occursin("holds only 2", sprint(showerror, try trail[-2] catch e; e end))
    @test occursin("capacity is 4", sprint(showerror, try trail[-4] catch e; e end))
    @test_throws ArgumentError push!(fill_with(3.0), trail, 2.0)       # a repeated time
    @test_throws ArgumentError push!(fill_with(3.0), trail, 1.5)       # an earlier one
    @test_throws ArgumentError push!(fill_with(3.0), trail, NaN)
    @test length(trail) == 2 && trail[0].time == 2.0           # a refused time changed nothing
    @test_throws ArgumentError push!(trail, 3.0)               # no value given
    @test_throws ArgumentError push!(trail, new_vector_point_values(tracers), 3.0)
    @test_throws MethodError (trail[0] = trail[-1])            # no assignment
    @test_throws ArgumentError ParticleTrail(new_vector_point_values, tracers, 0)
    @test_throws ArgumentError ParticleTrail(_ -> zeros(3, 3), tracers, 2)     # not point values
  end

  @testset "a sample that fails to be written is never readable" begin
    trail = ParticleTrail(new_scalar_point_values, tracers, 2)
    push!(fill_with(1.0), trail, 1.0); push!(fill_with(2.0), trail, 2.0)
    @test_throws ErrorException push!(trail, 3.0) do value
      point_values(value) .= NaN                               # half-written…
      error("the measurement failed")
    end
    # The oldest sample's slot was handed out and is gone; what remains is whole.
    @test length(trail) == 1
    @test trail[0].time == 2.0 && all(==(2.0), point_values(trail[0].value))
    push!(fill_with(3.0), trail, 3.0)
    @test [sample.time for sample in trail] == [2.0, 3.0]
  end

  @testset "the time derivative is exact on a polynomial, at uneven times" begin
    # f(t) = t³ + 2t at five uneven times: the polynomial through them is f itself, so every
    # derivative at the newest time is exact.
    f(t) = t^3 + 2t
    times = (0.1, 0.25, 0.3, 0.52, 0.6)
    trail = ParticleTrail(new_scalar_point_values, tracers, 5)
    for t in times
      push!(fill_with(f(t)), trail, t)
    end
    out = new_scalar_point_values(tracers)
    for (order, exact) in ((0, f(0.6)), (1, 3 * 0.6^2 + 2), (2, 6 * 0.6), (3, 6.0), (4, 0.0))
      @test time_derivative!(out, trail; order) === out
      @test all(isapprox(exact; atol = 1e-9), point_values(out))
      @test point_values(time_derivative(trail; order)) ≈ point_values(out)
    end
    # Order 0 is the newest value itself, exactly, and a new object in the allocating form.
    @test point_values(time_derivative(trail; order = 0)) == point_values(trail[0].value)
    @test time_derivative(trail; order = 0) !== trail[0].value
    # A vector quantity, and a trail longer than one pass combines: f(t) = sin t, eleven samples.
    long = ParticleTrail(new_vector_point_values, tracers, 11)
    for n in 0:10
      push!(fill_with(sin(0.05n)), long, 0.05n)
    end
    @test all(isapprox(cos(0.5); atol = 1e-9), point_values(time_derivative(long)))
  end

  @testset "the derivative's accuracy is the trail's length less the order" begin
    # f(t) = sin t at d evenly spaced samples: a first derivative of order d − 1 in the spacing.
    error_at(d, h) = begin
      trail = ParticleTrail(new_scalar_point_values, tracers, d)
      for n in 0:d-1
        push!(fill_with(sin(1 + n * h)), trail, 1 + n * h)
      end
      abs(point_values(time_derivative(trail))[1] - cos(1 + (d - 1) * h))
    end
    for d in (2, 3, 4)
      @test d - 1.3 < log2(error_at(d, 0.02) / error_at(d, 0.01)) < d - 0.7
    end
  end

  @testset "what the derivative refuses" begin
    trail = ParticleTrail(new_scalar_point_values, tracers, 3)
    out = new_scalar_point_values(tracers)
    @test_throws ArgumentError time_derivative!(out, trail; order = 0)   # no sample at all
    @test_throws ArgumentError time_derivative(trail)
    push!(fill_with(1.0), trail, 1.0)
    @test point_values(time_derivative!(out, trail; order = 0)) == point_values(trail[0].value)
    @test_throws ArgumentError time_derivative!(out, trail)              # one sample, order 1
    push!(fill_with(2.0), trail, 2.0)
    @test all(≈(1.0), point_values(time_derivative!(out, trail)))
    @test_throws ArgumentError time_derivative!(out, trail; order = 2)
    @test_throws ArgumentError time_derivative!(out, trail; order = -1)
    @test_throws ArgumentError time_derivative!(trail[0].value, trail)   # the trail's own storage
    # A value of another kind: a scalar per particle would otherwise broadcast over a vector's components.
    @test_throws ArgumentError time_derivative!(new_vector_point_values(tracers), trail; order = 0)
    @test_throws ArgumentError time_derivative!(new_vector_point_values(tracers), trail)
  end

  @testset "the run's own trail is read, not written" begin
    sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(2),
                     particles = ParticleTracking(number_of_particles = 8,
                                                  particle_integration_scheme = ABM(2)))
    for _ in 1:3; advance!(sim); end
    trail = velocity_at_particles_trail(sim.cache)
    @test trail isa ParticleTrail
    @test_throws ArgumentError push!(fill_with(0.0), trail, 99.0)
    # A caller's trail of the same quantity, pushed in the callback with the clock's time, carries
    # the cache's values and times.
    again = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(2),
                       particles = ParticleTracking(number_of_particles = 8,
                                                    particle_integration_scheme = ABM(2)))
    own = ParticleTrail(new_vector_point_values, again.tracers, 3)
    run!(again) do s
      push!(own, current_time(s)) do value
        interpolate_at_particles!(value, velocity_physical(s.cache), s.tracers;
                                  traversal = s.particle_traversal)
      end
      current_step(s) < 3
    end
    @test [sample.time for sample in own] == [sample.time for sample in trail]
    @test all(point_values(a.value) == point_values(b.value) for (a, b) in zip(own, trail))
    # The Lagrangian acceleration, from the cache's trail.
    acceleration = time_derivative(trail)
    @test size(point_values(acceleration)) == (8, 3) && all(isfinite, point_values(acceleration))
  end
end


# The step and the deposit check that a field and positions belong to one time. A run cannot fail
# these — `advance!` keeps the order — so each is triggered here by driving the pieces out of order.
@testset "the particle step and deposit refuse mismatched times" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  uniform!(u, t) = set_uniform_x!(u, 0.2)
  fresh(scheme = Heun()) = begin
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = scheme)
    advect_in_prescribed_flow!(uniform!, scheme, tracers, domain, cache, [0.01, 0.01])
    tracers, cache
  end

  @testset "the particle step needs the fields exactly one step ahead" begin
    tracers, cache = fresh()
    @test_throws ErrorException advect!(Heun(), tracers, domain, cache, 0.01)      # no field step
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)                       # two field steps
    @test_throws ErrorException advect!(Heun(), tracers, domain, cache, 0.01)
    # …and a current velocity field: a field step with no deposit after it.
    tracers, cache = fresh()
    advance_fields_epoch!(cache)
    @test_throws ErrorException advect!(Heun(), tracers, domain, cache, 0.01)
  end

  @testset "the particle step needs the sample of the current positions" begin
    tracers, cache = fresh()
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    advect!(Heun(), tracers, domain, cache, 0.01)
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    # The closing particle deposit was skipped, so the second step has no sample to start from.
    @test_throws ErrorException advect!(Heun(), tracers, domain, cache, 0.01)
  end

  @testset "the particle deposit needs the positions caught up with the fields" begin
    tracers, cache = fresh()
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    @test_throws ErrorException deposit!(cache, tracers, 0.03)      # fields stepped, tracers not
    advect!(Heun(), tracers, domain, cache, 0.01)
    @test deposit!(cache, tracers, 0.03) === cache
    @test_throws ErrorException deposit!(cache, tracers, 0.04)      # already sampled here
  end

  @testset "a sample's time must increase" begin
    tracers, cache = fresh()
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    advect!(Heun(), tracers, domain, cache, 0.01)
    @test_throws ArgumentError deposit!(cache, tracers, 0.02)       # the previous sample's time
    # …and a step that is not positive would put it at a repeated or earlier time.
    tracers, cache = fresh()
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    @test_throws ArgumentError advect!(Heun(), tracers, domain, cache, 0.0)
    @test_throws ArgumentError advect!(Heun(), tracers, domain, cache, -0.01)
  end

  @testset "the trail is read only while the positions have not moved" begin
    tracers, cache = fresh()
    @test velocity_at_particles_trail(cache)[0].time == 0.02
    # A field step does not date the samples: they belong to the particles' time.
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    @test velocity_at_particles_trail(cache)[0].time == 0.02
    advect!(Heun(), tracers, domain, cache, 0.01)
    @test_throws ErrorException velocity_at_particles_trail(cache)   # the positions moved
    deposit!(cache, tracers, 0.03)
    @test velocity_at_particles_trail(cache)[0].time == 0.03
    # A cache without tracers has no trail, and says so.
    @test_throws ArgumentError velocity_at_particles_trail(ObservablesCache(domain))
    @test_throws ArgumentError deposit!(ObservablesCache(domain), tracers, 0.0)
  end

  @testset "fields stepped alone before tracking starts" begin
    # The first sample pairs the counters, so the fields may have been advanced first.
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = Heun())
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache; step = false)
    for _ in 1:5
      deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    end
    @test deposit!(cache, tracers, 0.5) === cache
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    advect!(Heun(), tracers, domain, cache, 0.01)
    @test deposit!(cache, tracers, 0.51) === cache
  end

  @testset "a refused deposit changes nothing" begin
    # A time that is refused is refused before the counters are paired…
    tracers = Tracers(domain; number_of_particles = 4, interpolation_scheme = CatmullRom,
                      rng = MersenneTwister(1))
    cache = ObservablesCache(domain; tracers, particle_integration_scheme = AB(1))
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache; step = false)
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    before = (cache.fields_epoch, cache.particles_epoch)
    @test_throws ArgumentError deposit!(cache, tracers, NaN)
    @test (cache.fields_epoch, cache.particles_epoch) == before
    # …and the pairing is made once. A trail of one slot is empty again after a sample fails to be
    # written, which must not let fields stepped alone since then pass as the start of tracking.
    deposit!(cache, tracers, 0.0)
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    advect!(AB(1), tracers, domain, cache, 0.01)
    deposit_prescribed_velocity!(u -> (field_data(u) .= 0.2; u), cache)             # a second field step
    @test_throws ErrorException deposit!(cache, tracers, 0.01)
    @test isempty(cache.velocity_at_particles_trail) || length(cache.velocity_at_particles_trail) == 1
    @test_throws ErrorException deposit!(cache, tracers, 0.02)                      # still refused
  end

  @testset "an iteration is refused whole, before anything has moved" begin
    run() = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(4),
                       particles = ParticleTracking(number_of_particles = 4))
    snapshot(sim) = (copy(field_data(sim.state.velocity_spectral)), copy(point_positions(sim.tracers.positions)),
                     sim.cache.fields_epoch, sim.cache.particles_epoch, current_time(sim), current_step(sim))
    # Fields stepped alone since the last iteration: the trail still reads, the iteration must not start.
    sim = run(); advance!(sim; dt = 0.01)
    step!(sim.field_integration_scheme, sim.state, sim.generator, sim.domain, sim.buffers, sim.cache, 0.01)
    deposit!(sim.cache, sim.state, sim.domain, sim.buffers)
    before = snapshot(sim)
    @test_throws ErrorException advance!(sim; dt = 0.01)
    @test snapshot(sim) == before
    # A step too small to move the clock, and one that is not finite.
    sim = run(); advance!(sim; dt = 0.01)
    before = snapshot(sim)
    @test_throws ArgumentError advance!(sim; dt = 1e-20)
    @test_throws ArgumentError advance!(sim; dt = Inf)
    @test_throws ArgumentError advance!(sim; dt = NaN)
    @test snapshot(sim) == before
    advance!(sim; dt = 0.01)                                   # and the run goes on
    @test current_step(sim) == 2
    @test_throws ArgumentError advect!(Heun(), sim.tracers, sim.domain, sim.cache, Inf)
    # The setting that shortens the first steps has nothing to shorten for a one-sample scheme, so a
    # fixed step is not in conflict with it there.
    plain = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(4),
                       particles = ParticleTracking(number_of_particles = 4, shortened_first_steps = true))
    @test advance!(plain; dt = 0.01) === plain
  end

  @testset "the cache is built for the scheme that advances the tracers" begin
    tracers, cache = fresh(Heun())
    deposit_prescribed_velocity!(u -> uniform!(u, 0), cache)
    @test_throws ArgumentError advect!(AB(4), tracers, domain, cache, 0.01)
    @test_throws ArgumentError ObservablesCache(domain; tracers)                   # one without the other
    @test_throws ArgumentError ObservablesCache(domain; particle_integration_scheme = Heun())
  end
end

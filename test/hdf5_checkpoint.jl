# The HDF5 checkpoint slice (decision 75): each writer/reader pair round-trips its object through
# one self-describing group, and a restored run continues bitwise where the checkpointed one left
# off. The leaves are the field library's own persistence (write_field / write_points /
# write_scheme); nothing derivable is stored, so the reads below also exercise the re-deposit and
# the fill-aware history restore.
using Test, Random, HDF5
using GBGIsotropicTurbulence
using GBGPeriodicFields: CatmullRom, LalescuSpline, PointSet, point_positions, point_values,
                         field_data, npoints


make_domain(; T = Float64, dealiasing = TwoThirds()) =
  FixedDomain(; grid_points_per_axis = 8, side_length = 2π, element_type = T,
              array_type = Array, dealiasing)


@testset "write_domain / read_domain round-trip the defining parameters" begin
  path = tempname() * ".h5"
  for dealiasing in (TwoThirds(), HouLi(order = 20, strength = 0.5),
                    HouLi(order = 20, strength = 0.5, materialized = true), PhaseShift())
    domain = make_domain(; T = Float32, dealiasing)
    h5open(io -> (io["d"] = domain), path, "w")
    back = h5open(io -> read_domain(io, "d"), path, "r")
    @test back.grid.grid_size == domain.grid.grid_size
    @test back.grid.domain_size == domain.grid.domain_size
    @test back.dealiasing === dealiasing
    @test eltype(field_data(new_scalar_field_physical(back))) == Float32
  end
  # A dataset, a missing name, and a foreign group are each refused with a named error.
  h5open(path, "w") do io
    io["plain"] = [1.0, 2.0]
    create_group(io, "foreign")
  end
  h5open(path, "r") do io
    @test_throws ArgumentError read_domain(io, "absent")
    @test_throws ArgumentError read_domain(io, "plain")
    @test_throws ArgumentError read_domain(io, "foreign")
  end
end


@testset "write_state / read_state are bitwise, and refuse a mismatched domain" begin
  path = tempname() * ".h5"
  domain = make_domain()
  state = GBGIsotropicTurbulence.State.ResolvedFields(domain; scalar = true)
  rng = MersenneTwister(3)
  copyto!(field_data(state.velocity_spectral),
          randn(rng, ComplexF64, size(field_data(state.velocity_spectral))))
  copyto!(field_data(state.scalar_spectral),
          randn(rng, ComplexF64, size(field_data(state.scalar_spectral))))
  h5open(io -> write_state(io, "s", state), path, "w")
  back = h5open(io -> read_state(io, "s", domain), path, "r")
  @test field_data(back.velocity_spectral) == field_data(state.velocity_spectral)
  @test field_data(back.scalar_spectral) == field_data(state.scalar_spectral)
  bigger = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       array_type = Array, dealiasing = TwoThirds())
  h5open(path, "r") do io
    @test_throws ArgumentError read_state(io, "s", bigger)
  end
end


@testset "write_tracers / read_tracers keep positions, scheme, and the unwrapped record" begin
  path = tempname() * ".h5"
  domain = make_domain()
  tracers = Tracers(domain; number_of_particles = 5, interpolation_scheme = LalescuSpline(2, 1),
                    unwrapped = true, rng = MersenneTwister(4))
  h5open(io -> (io["t"] = tracers), path, "w")
  back = h5open(io -> read_tracers(io, "t", domain), path, "r")
  @test point_positions(back.positions) == point_positions(tracers.positions)
  @test back.interpolation_scheme === tracers.interpolation_scheme
  @test point_positions(unwrapped_positions(back)) ==
        point_positions(unwrapped_positions(tracers))
  # An untracked set stays untracked through the round trip.
  plain = Tracers(domain; number_of_particles = 3, interpolation_scheme = CatmullRom)
  h5open(io -> write_tracers(io, "p", plain), path, "w")
  back2 = h5open(io -> read_tracers(io, "p", domain), path, "r")
  @test_throws ArgumentError unwrapped_positions(back2)
end


@testset "write_forcing / read_forcing rebuild each strategy from its parameters" begin
  path = tempname() * ".h5"
  domain = make_domain()
  built = (NoForcing(),
           GBGIsotropicTurbulence.Forcing.Linear(domain; rate = 0.3, lowest_shell = 2,
                                                 highest_shell = 3),
           ConstantPower(domain; injection_rate = 0.1),
           VarianceRescaling(domain; target = 0.5, over = :band),
           VarianceController(domain; target = 1.2, gain = 2.0),
           GBGIsotropicTurbulence.Forcing.StochasticOU(domain; variance = 1.0, correlation_time = 0.3))
  h5open(path, "w") do io
    for (i, f) in enumerate(built)
      io["f$i"] = f
    end
    # A deferred (operator-free) form is a constructor, not a built strategy.
    @test_throws ArgumentError write_forcing(io, "deferred",
                                             ConstantPower(injection_rate = 0.1))
  end
  h5open(path, "r") do io
    for (i, f) in enumerate(built)
      back = read_forcing(io, "f$i", domain)
      @test nameof(typeof(back)) == nameof(typeof(f))
      for p in (:rate, :injection_rate, :target, :gain, :turnover_time, :turnover_time_derived,
                :over, :variance, :correlation_time, :lowest_shell, :highest_shell)
        hasproperty(f, p) && @test getproperty(back, p) == getproperty(f, p)
      end
    end
  end
end


@testset "a restored run continues the checkpointed one bitwise" begin
  path = tempname() * ".h5"
  # A multistep tracer scheme past its bootstrap, a scalar, and the unwrapped record: the
  # configuration where every stored piece — state, positions, unwrapped record, and the sample
  # history — is load-bearing for the continuation below.
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, scalar = true,
                   number_of_particles = 6, unwrapped = true,
                   particle_integration_scheme = AdamsBashforth(order = 2),
                   rng = MersenneTwister(7))
  for _ in 1:4
    advance!(sim; dt = 0.01)
  end
  h5open(io -> (io["run"] = sim), path, "w")
  sim2 = h5open(io -> read_simulation(io, "run"), path, "r")

  @test current_time(sim2) == current_time(sim)
  @test current_step(sim2) == current_step(sim)
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  @test field_data(sim2.state.scalar_spectral) == field_data(sim.state.scalar_spectral)
  @test point_positions(sim2.tracers.positions) == point_positions(sim.tracers.positions)
  @test point_positions(unwrapped_positions(sim2.tracers)) ==
        point_positions(unwrapped_positions(sim.tracers))
  @test sim2.cache.history_filled == sim.cache.history_filled
  @test sim2.cache.history_steps == sim.cache.history_steps
  for j in 1:sim.cache.history_filled
    @test point_values(sim2.cache.velocity_at_particles_history[j]) ==
          point_values(sim.cache.velocity_at_particles_history[j])
  end
  # The re-deposited observables equal the originals: nothing derivable was stored, so this pins
  # the restore's recomputation, not a copy.
  @test field_data(velocity_physical(sim2.cache)) == field_data(velocity_physical(sim.cache))
  @test velocity_at_particles(sim2.cache) == velocity_at_particles(sim.cache)

  # Continuation: 4 + 3 steps in one run equals 4 steps, a checkpoint, and 3 more — bitwise, the
  # default deterministic forcing making the comparison exact.
  for _ in 1:3
    advance!(sim; dt = 0.01)
    advance!(sim2; dt = 0.01)
  end
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  @test field_data(sim2.state.scalar_spectral) == field_data(sim.state.scalar_spectral)
  @test point_positions(sim2.tracers.positions) == point_positions(sim.tracers.positions)
  @test point_positions(unwrapped_positions(sim2.tracers)) ==
        point_positions(unwrapped_positions(sim.tracers))

  # The traversal order is derived, not state (decision 86): nothing of it is stored, the restored
  # run rebuilds it under the reader's setting, and the continuation is bitwise under any of them.
  h5open(path, "r") do io
    @test !haskey(io["run"], "particle_traversal")
    @test !haskey(attributes(io["run"]), "ordered_interpolation")
  end
  @test sim2.particle_traversal isa ParticleTraversal && sim2.particle_traversal.automatic
  manual = h5open(io -> read_simulation(io, "run"; ordered_interpolation = :manual), path, "r")
  off = h5open(io -> read_simulation(io, "run"; ordered_interpolation = false), path, "r")
  @test !manual.particle_traversal.automatic
  @test off.particle_traversal === nothing
  for _ in 1:3
    advance!(manual; dt = 0.01)
    advance!(off; dt = 0.01)
  end
  @test point_positions(manual.tracers.positions) == point_positions(sim.tracers.positions)
  @test point_positions(off.tracers.positions) == point_positions(sim.tracers.positions)
end


@testset "a tracer-free, scalar-free run checkpoints and continues too" begin
  path = tempname() * ".h5"
  sim = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(9),
                   velocity_forcing = ConstantPower(injection_rate = 0.1))
  advance!(sim; dt = 0.01)
  h5open(io -> write_simulation(io, "run", sim), path, "w")
  sim2 = h5open(io -> read_simulation(io, "run"), path, "r")
  @test sim2.tracers === nothing
  @test sim2.state.scalar_spectral === nothing
  advance!(sim; dt = 0.01)
  advance!(sim2; dt = 0.01)
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
end


# Decision 80: the third field scheme round-trips by tag like the other two, and the restored run
# continues bitwise — the checkpoint contract is scheme-blind, so a new scheme must not silently
# restore as the default.
@testset "an IFSSPRK3 run checkpoints, restores its scheme, and continues bitwise" begin
  path = tempname() * ".h5"
  sim = Simulation(grid_points_per_axis = 8, viscosity = 0.05, rng = MersenneTwister(11),
                   field_integration_scheme = IFSSPRK3(),
                   velocity_forcing = ConstantPower(injection_rate = 0.1))
  advance!(sim; dt = 0.01)
  h5open(io -> write_simulation(io, "run", sim), path, "w")
  sim2 = h5open(io -> read_simulation(io, "run"), path, "r")
  @test sim2.field_integration_scheme isa IFSSPRK3
  advance!(sim; dt = 0.01)
  advance!(sim2; dt = 0.01)
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  rm(path)
end


@testset "an adopted state and tracer set continue a run bitwise (decision 83)" begin
  path = tempname() * ".h5"
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, scalar = true,
                   number_of_particles = 5, rng = MersenneTwister(21))
  for _ in 1:3
    advance!(sim; dt = 0.01)
  end
  h5open(path, "w") do io
    io["s"] = sim.state
    io["t"] = sim.tracers
  end
  st = h5open(io -> read_state(io, "s", sim.domain), path, "r")
  tr = h5open(io -> read_tracers(io, "t", sim.domain), path, "r")
  # Same physics settings, the evolved state and positions ADOPTED: from here the two runs are the
  # same discrete system, so three more steps must agree bitwise (deterministic default forcing).
  sim2 = Simulation(sim.domain; viscosity = 0.05, scalar = true, state = st, tracers = tr)
  for _ in 1:3
    advance!(sim; dt = 0.01)
    advance!(sim2; dt = 0.01)
  end
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  @test field_data(sim2.state.scalar_spectral) == field_data(sim.state.scalar_spectral)
  @test point_positions(sim2.tracers.positions) == point_positions(sim.tracers.positions)
  rm(path)
end


@testset "the injection door refuses conflicting or mismatched settings by name" begin
  domain = make_domain()
  st = ResolvedFields(domain)
  st_scalar = ResolvedFields(domain; scalar = true)
  tr = Tracers(domain; number_of_particles = 3, interpolation_scheme = CatmullRom,
               rng = MersenneTwister(5))
  # Two ways to set the same thing, and property-of-the-adopted-object settings:
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = st,
                                        initial_spectrum = κ -> κ^-2)
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = st, scalar = true)
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = st_scalar)
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, tracers = tr,
                                        number_of_particles = 3)
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, tracers = tr,
                                        interpolation_scheme = CatmullRom)
  @test_throws ArgumentError Simulation(domain; viscosity = 0.05, tracers = tr, unwrapped = true)
  # A state from a different grid is refused before anything is built from it.
  bigger = FixedDomain(; grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       array_type = Array, dealiasing = TwoThirds())
  @test_throws ArgumentError Simulation(bigger; viscosity = 0.05, state = st)
  # Derived ν + an adopted state whose energy is not the calibration's: warned, not silent.
  seeded = Simulation(domain; viscosity = 0.05, rng = MersenneTwister(6))   # k = 1.5 by default
  @test_logs (:warn, r"adopted `state` holds k") match_mode = :any Simulation(
    domain; state = seeded.state, kinetic_energy = 15.0)
end


@testset "an IFLowStorageRK4 run checkpoints, restores its scheme, and continues bitwise" begin
  path = tempname() * ".h5"
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05,
                   field_integration_scheme = IFLowStorageRK4(),
                   rng = MersenneTwister(61))
  for _ in 1:3
    advance!(sim; dt = 0.01)
  end
  h5open(io -> (io["run"] = sim), path, "w")
  sim2 = h5open(io -> read_simulation(io, "run"), path, "r")
  @test sim2.field_integration_scheme isa IFLowStorageRK4
  for _ in 1:3
    advance!(sim; dt = 0.01)
    advance!(sim2; dt = 0.01)
  end
  @test field_data(sim2.state.velocity_spectral) == field_data(sim.state.velocity_spectral)
  rm(path)
end

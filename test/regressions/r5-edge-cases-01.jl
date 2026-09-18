# Witness: a non-positive `cfl` must never produce a silently non-positive adaptive timestep.
#
# `Simulation(...; cfl = ...)` stores the coefficient unchecked (`Float64(cfl)`), while the
# constructor validates every neighbouring front-door setting (`kinetic_energy > 0`,
# `scalar_variance >= 0`, `κ_max_η > 0`). `advance!` guards positivity only on an EXPLICIT `dt`;
# on the adaptive branch it takes whatever `cfl_timestep` returns — `sim.cfl * Δx / speed` — with
# no sign or positivity check. The correct behaviour asserted here: a run must never integrate
# backwards in time, and must never bump its step counter on a zero-length step. Either the
# non-positive `cfl` is refused at the front door (an `ArgumentError`, the neighbouring
# convention) or `advance!` refuses the step it computed — a normal return that moved the clock
# backwards, or not at all, is the defect.
using Test, Random, GBGHomogeneousTurbulence

# Advance twice, tolerating a refusal (a throw IS the fix). Returns `nothing` when the run
# refused, or the vector of (time, step) pairs it actually reported.
function probe(cfl)
  sim = try
    Simulation(grid_points_per_axis = 16, viscosity = 5e-3, cfl = cfl, rng = MersenneTwister(7))
  catch err
    err isa ArgumentError && return nothing
    rethrow()
  end
  @assert max_speed(sim.cache) > 0            # the `speed > 0` branch of `cfl_timestep` is the one taken
  trace = Tuple{Float64,Int}[(current_time(sim), current_step(sim))]
  for _ in 1:2
    try
      advance!(sim)
    catch err
      err isa Union{ArgumentError,ErrorException} || rethrow()
      return nothing                          # refused mid-run — also an acceptable fix
    end
    push!(trace, (current_time(sim), current_step(sim)))
  end
  return trace
end

@testset "a non-positive `cfl` must not silently drive the run backwards or freeze it" begin
  @testset "cfl < 0 must never let the clock run backwards" begin
    trace = probe(-0.3)
    if trace === nothing
      @test true                              # refused: the correct behaviour
    else
      @info "cfl = -0.3 advanced normally" trace
      # Simulated time is elapsed time: it must increase, step after step.
      @test all(trace[i+1][1] > trace[i][1] for i in 1:length(trace)-1)
    end
  end

  @testset "cfl = 0 must not count steps that advance no time" begin
    trace = probe(0.0)
    if trace === nothing
      @test true                              # refused: the correct behaviour
    else
      @info "cfl = 0.0 advanced normally" trace
      # A counted step must be a step: the counter may not climb while the clock stands still.
      @test all(trace[i+1][1] > trace[i][1] for i in 1:length(trace)-1)
      @test !(trace[end][2] > trace[1][2] && trace[end][1] == trace[1][1])
    end
  end
end

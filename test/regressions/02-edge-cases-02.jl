# Witness: a zero-length step must not poison the Adams–Bashforth tracer history.
#
# `advect!(::AdamsBashforth, …)` stores the step just taken verbatim into `buffers.steps[1]`
# (src/Particles.jl:391) with no floor, and `advance!` (src/SimulationRun.jl:414) accepts whatever
# `dt` it is given. A `dt = 0.0` therefore inserts a REPEATED node into the variable-step history:
# `_adams_bashforth_weights` builds τ[j] = τ[j-1] - steps[j-1] (Particles.jl:345), so τ[j] == τ[j-1],
# and the Lagrange-basis product divides by (τ[j] - τ[m]) == 0 (Particles.jl:355).
#
# Correct behaviour, either way round: `advance!` rejects the degenerate step cleanly at the call
# that supplies it, OR the trajectory survives it with finite positions. What must NOT happen is the
# current outcome — the zero step returning quietly, NaN entering the positions one step later, and
# the run dying inside the dependency's interpolation grid-locate (`InexactError: Int64(NaN)`).

using Test, Random
using GBGPeriodicFields: point_positions
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Particles: AdamsBashforth

const N = 16
const M = 4

build() = Simulation(grid_points_per_axis = N, number_of_particles = M,
                     particle_integration_scheme = AdamsBashforth(order = 4),
                     rng = MersenneTwister(1234))

# Take the sequence of steps, returning (:ok, positions), (:rejected,) if a zero step was refused
# cleanly, or (:crash, err) if anything else escaped.
function walk(sim, steps)
  for dt in steps
    try
      advance!(sim; dt = dt)
    catch err
      (err isa ArgumentError || err isa DomainError) && dt == 0.0 && return (:rejected, err)
      return (:crash, err)
    end
  end
  return (:ok, copy(Array(point_positions(sim.tracers.positions))))
end


@testset "a zero-length step does not poison the Adams-Bashforth tracer trajectory" begin

  # Control: the same run with four ordinary steps is finite throughout, so any failure below is
  # the zero step and not the flow blowing up.
  control = walk(build(), (0.01, 0.01, 0.01, 0.01, 0.01))
  @test control[1] === :ok
  @test all(isfinite, control[2])

  # The claim: a dt = 0.0 in the middle of the sequence must either be refused on the spot or be
  # survived. It must not crash a LATER step.
  outcome = walk(build(), (0.01, 0.0, 0.01, 0.01, 0.01))
  @test outcome[1] !== :crash
  outcome[1] === :ok && @test all(isfinite, outcome[2])
end

# Witness: a zero-length step must not poison the samples an Adams–Bashforth tracer integrates over.
#
# The defect: the particle step recorded the step just taken with no floor, and `advance!` accepted
# whatever `dt` it was given. A `dt = 0.0` therefore put two samples at one time, and the weights,
# which integrate the Lagrange basis on the samples' times, divided by the difference of two equal
# times.
#
# Correct behaviour, either way round: `advance!` rejects the degenerate step cleanly at the call
# that supplies it, OR the trajectory survives it with finite positions. What must NOT happen is the
# current outcome — the zero step returning quietly, NaN entering the positions one step later, and
# the run dying inside the dependency's interpolation grid-locate (`InexactError: Int64(NaN)`).

using Test, Random
using GBGPeriodicFields: point_positions
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.ParticlePropagator: AB

const N = 16
const M = 4

build() = Simulation(grid_points_per_axis = N,
                     particles = ParticleTracking(number_of_particles = M,
                                                  particle_integration_scheme = AB(4)),
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

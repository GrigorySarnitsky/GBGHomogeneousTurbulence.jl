using Test, Random
using GBGIsotropicTurbulence
using Test: collect_test_logs

# Hunter's claim: the scalar under-resolution warning asserts "The grid resolves the velocity
# (κ_max·η = X)" unconditionally, even when the quoted X is below the very 1.5 floor the same
# sentence applies — at Sc = 1 (η_B = η exactly) the warning then attributes plain grid
# under-resolution, shared equally by the velocity, to the scalar's Batchelor scale.
@testset "the scalar under-resolution warning never claims the velocity resolved at a κ_max·η below its own 1.5 floor" begin
  logs, _ = collect_test_logs(min_level = Base.CoreLogging.Warn) do
    Simulation(; grid_points_per_axis = 16, viscosity = 5e-2, scalar = true,
                 rng = MersenneTwister(1))
  end
  warnings = [l.message for l in logs if occursin("under-resolved", l.message)]
  @test !isempty(warnings)   # the scalar warning does fire at this ν and grid
  msg = first(warnings)
  m = match(r"The grid resolves the velocity \(κ_max·η = ([0-9.]+)\)", msg)
  if m === nothing
    # Correct behaviour: the message does not claim the velocity resolved when it is not.
    @test true
  else
    quoted = parse(Float64, m.captures[1])
    # If the message asserts "The grid resolves the velocity", the value it quotes must satisfy
    # the well-resolved floor the same sentence states. Anything less is a self-contradiction.
    @test quoted >= 1.5
  end
end

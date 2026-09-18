# Witness r4-free-hot-path-04 — a derived-viscosity `Simulation` must validate `κ_max_η`.
#
# `κ_max_η` is the resolution criterion the viscosity derivation exists to honour: it sets
# ν = ε^(1/3) (κ_max·η / κ_max)^(4/3), so it must be a positive finite number.
# Its neighbours `kinetic_energy` and `scalar_variance` are guarded with named
# `ArgumentError`s precisely so a bad value cannot surface far downstream; the
# same guard is owed here.
using Test, Random, GBGHomogeneousTurbulence

# A derived-viscosity run whose ν came out non-positive or non-finite is not a DNS.
build(v) = Simulation(grid_points_per_axis = 8, κ_max_η = v, rng = MersenneTwister(1))

@testset "a derived-viscosity Simulation rejects a non-positive or non-finite κ_max_η with a named ArgumentError" begin
  for bad in (0, -1, NaN, Inf)
    err = try
      sim = build(bad)
      # No throw: record what the constructor produced instead.
      (:built, sim.generator.conditions.viscosity)
    catch e
      (:threw, e)
    end
    @test err[1] === :threw
    if err[1] === :threw
      e = err[2]
      @test e isa ArgumentError
      @test e isa ArgumentError && occursin("κ_max_η", e.msg)
    end
  end

  # The guard must not disturb the legitimate range: the default and an explicit
  # positive criterion still build, with a positive finite ν.
  @test isfinite(build(1.5).generator.conditions.viscosity) &&
        build(1.5).generator.conditions.viscosity > 0
  let sim = Simulation(grid_points_per_axis = 8, rng = MersenneTwister(1))
    @test sim.generator.conditions.viscosity > 0
  end
end

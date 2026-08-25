# Witness r6-numerics-and-types-01: Simulation's DEFAULT VarianceController forcing must carry the
# run's element type. `kinetic_energy::Real = 1.5` is a Float64 literal; if it reaches
# `VarianceController(domain; target = kinetic_energy)` uncast on a Float32 run, the constructor's
# `promote(float(target), …)` fixes the strategy's type parameter at Float64 — the leak the
# test/forcing.jl "preserves a Float32 run's element type" testset states but never exercises
# through the default Simulation path.
using Test, GBGIsotropicTurbulence

@testset "Simulation's default velocity forcing carries the run's element type" begin
  for T in (Float32, Float64)
    sim = Simulation(grid_points_per_axis = 8, element_type = T, array_type = Array,
                     viscosity = 0.05)
    vf = sim.generator.conditions.velocity_forcing
    @test vf isa VarianceController
    @test typeof(vf.target) === T
    @test typeof(vf.gain) === T
    @test typeof(vf.turnover_time) === T
  end
end

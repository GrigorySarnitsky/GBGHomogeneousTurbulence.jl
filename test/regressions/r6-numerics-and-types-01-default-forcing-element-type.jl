# Witness r6-numerics-and-types-01: Simulation's DEFAULT forcing (then a VarianceController) must carry the
# run's element type. `kinetic_energy::Real = 1.5` is a Float64 literal; if it reaches
# `VarianceController(domain; target = kinetic_energy)` uncast on a Float32 run, the constructor's
# `promote(float(target), …)` fixes the strategy's type parameter at Float64 — the leak the
# test/forcing.jl "preserves a Float32 run's element type" testset states but never exercises
# through the default Simulation path.
using Test, GBGHomogeneousTurbulence

@testset "Simulation's default velocity forcing carries the run's element type" begin
  # Since 2026-09-24 (decision 95) the default is `ConstantPower`, taking its rate from the run's state
  # — a Float64 computation, so the same leak applies to it. A controller that takes its target from
  # the state is the path the old default took, and is pinned alongside.
  for T in (Float32, Float64)
    sim = Simulation(grid_points_per_axis = 8, element_type = T, array_type = Array,
                     viscosity = 0.05)
    vf = sim.generator.conditions.velocity_forcing
    @test vf isa ConstantPower
    @test typeof(vf.injection_rate) === T
    controlled = Simulation(grid_points_per_axis = 8, element_type = T, array_type = Array,
                            viscosity = 0.05, velocity_forcing = VarianceController())
    vc = controlled.generator.conditions.velocity_forcing
    @test typeof(vc.target) === T
    @test typeof(vc.gain) === T
    @test typeof(vc.turnover_time) === T
  end
end

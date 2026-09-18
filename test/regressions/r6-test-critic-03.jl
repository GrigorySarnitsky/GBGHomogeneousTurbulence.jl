# Witness for: "IFHeun's order-preservation-under-forcing is never measured; only IFLowStorageRK3 is."
# The existing testset (test/integrators.jl:118) hardcodes IFLowStorageRK3 in `measured_order`; this
# witness runs the identical self-convergence measurement with IFHeun over the same forcing set and
# asserts the second-order scheme keeps order ≥ 1.5 under every rate/source-routed forcing. It FAILS
# only if IFHeun's stage-source wiring actually degrades the order — i.e. if the code (not merely the
# coverage) is defective.

using Test
using Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data

@testset "IFHeun keeps second order under every rate/source-routed forcing" begin
  T = 0.2
  function measured_order(forcing)
    reference = nothing; errors = Float64[]
    for n in (1024, 32, 64)
      sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, field_integration_scheme = IFHeun(),
                       velocity_forcing = forcing, rng = MersenneTwister(7))
      for _ in 1:n; advance!(sim; dt = T / n); end
      data = copy(field_data(sim.state.velocity_spectral))
      n == 1024 ? (reference = data) : push!(errors, maximum(abs, data .- reference))
    end
    return log2(errors[1] / errors[2])
  end

  for (name, forcing) in (("unforced", NoForcing()),
                          ("Linear (steady rate → integrating factor)", Linear(rate = 0.5)),
                          ("ConstantPower (state-dependent → per-stage source)",
                           ConstantPower(injection_rate = 0.2)),
                          ("VarianceController (state-dependent → per-stage source)",
                           VarianceController(target = 1.5)))
    order = measured_order(forcing)
    @info "IFHeun temporal order" forcing = name order
    @test order ≥ 1.5
  end
end

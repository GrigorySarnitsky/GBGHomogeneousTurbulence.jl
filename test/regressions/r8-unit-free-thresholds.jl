# Two absolute constants sat in otherwise scale-free code, each a threshold in the user's units. The
# stationarity test called any series whose mean was below 1e-30 flat, whatever its drift. The
# dissipation rate solved from a given ν and k was searched in [1e-30, 1e30], and a root outside
# it came back as the bracket's edge with no signal. Both are now free of units: the flatness
# test is multiplied out, and the search is centred on the dimensional estimate k^{3/2}/L.
using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.SimulationRun: _is_flat


@testset "the flatness test has no floor in the series' units" begin
  turn = collect(0.0:0.1:2.0)
  drifting = 1 .+ turn                                        # doubles across the window
  @test !_is_flat(turn, drifting, 2.0, 2.0, 0.05)
  @test !_is_flat(turn, 1e-35 .* drifting, 2.0, 2.0, 0.05)   # the same drift, in other units
  @test _is_flat(turn, zeros(length(turn)), 2.0, 2.0, 0.05)  # identically zero is flat
end


@testset "the dissipation rate solved from ν and k is not clamped" begin
  domain = FixedDomain(; grid_points_per_axis = 16, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = Float64, array_family = Array)
  k = 1e22                                                    # ε ≈ (k/k̃)^{3/2}/L, beyond 1e30
  prediction = predicted_stationary_state(domain; velocity_forcing = ConstantPower(), kinetic_energy = k,
                                          viscosity = 1.0)
  k̃ = kinetic_energy_in_box_units(ConstantPower(); reynolds_box = prediction.reynolds_box)
  @test prediction.dissipation ≈ (k / k̃)^(3 / 2) / 2π rtol = 1e-10
  @test prediction.kinetic_energy_in_box_units * (prediction.dissipation * 2π)^(2 / 3) ≈ k rtol = 1e-10
end

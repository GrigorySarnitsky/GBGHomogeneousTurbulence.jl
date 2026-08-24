# Witness: the blow-up (non-finite velocity) guard must be an iteration-level health check, not a
# side effect of the adaptive-CFL branch. `advance!(sim; dt = …)` bypasses `cfl_timestep`, which is
# the only site carrying `isfinite(speed) || error(…)`, so a run driven with a hand-fixed `dt`
# deposits NaN/Inf observables and returns normally.
using Test, Random, GBGIsotropicTurbulence

@testset "advance! with a hand-fixed dt must not silently accept a blown-up (non-finite) state" begin
  make = () -> Simulation(grid_points_per_axis = 8, viscosity = 1e-6,
                          velocity_forcing = Linear(rate = 50.0), field_integration_scheme = IFHeun(), rng = MersenneTwister(42))

  # (1) A fixed-dt run must never return normally having deposited a non-finite maximum speed.
  sim = make()
  # The claim is that no iteration RETURNS NORMALLY having deposited a non-finite state. A throw
  # satisfies it — that is the fix — so the loop must tolerate the throw and only fail on a normal
  # return that left the cache non-finite. (As first written the bare call let the throw escape the
  # testset, so the corrected behaviour registered as a BROKEN witness rather than a passing one.)
  blown_step = 0
  refused = false
  for i in 1:8
    try
      advance!(sim; dt = 0.5)
    catch err
      err isa ErrorException || rethrow()
      refused = true                       # the run refused to advance a blown-up state
      break
    end
    if !isfinite(max_speed(sim.cache))
      blown_step = i                       # returned normally with a non-finite deposit — the defect
      break
    end
  end
  @test blown_step == 0

  # (2) The identical state the adaptive path rejects must also be rejected by the fixed-dt path.
  #     `sim` above is now blown up (if the tree is healthy this state was never reached and the
  #     check is vacuous — guard it so the assertion means what it says).
  if blown_step != 0
    @test_throws ErrorException advance!(sim; dt = 0.5)
  end
  @info "fixed-dt blow-up" refused blown_step
end

# D2 (audit-changes round 2 residue): the controller's convergence FROM ABOVE — k₀ = 2.6 → 1.5 —
# was asserted in a commit message and never witnessed; the only dynamic controller tests were the
# marginal law (gain = 0, conserves) and the amplitude identity at one state. The two directions
# are not symmetric physics: from below the forcing must OUTRUN nothing (dissipation helps it
# drain toward nothing, the restoring term does the lifting); from above BOTH the restoring term
# and the cascade drain k, and the risk asserted-but-unwitnessed was overshoot/undershoot of the
# discrete update. This pins both directions of the restoring dynamics.
using Test, GBGHomogeneousTurbulence
using Random


@testset "VarianceController restores k toward target from BOTH sides" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  target = 1.5
  gap_closed(k0; steps = 300, seed) = begin
    # Seeded at k0 through an adopted state: `kinetic_energy` beside the controller's target would
    # state the run's stationary state twice (decision 95).
    seeded = ResolvedFields(domain)
    random_solenoidal_velocity_spectral!(seeded.velocity_spectral, domain; kinetic_energy = k0,
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(seed))
    sim = Simulation(domain; viscosity = 0.05,
                     velocity_forcing = VarianceController(domain; target), state = seeded)
    for _ in 1:steps; advance!(sim); end
    k = kinetic_energy(sim.state.velocity_spectral)
    (k = k, closed = abs(k - target) / abs(k0 - target))
  end

  above = gap_closed(2.6; seed = 11)     # the commit-message claim, now measured
  below = gap_closed(0.4; seed = 12)     # the mirror
  @test above.closed < 0.25              # ≥ 75% of the 2.6 → 1.5 gap closed
  @test below.closed < 0.25
  @test isapprox(above.k, target; rtol = 0.2)
  @test isapprox(below.k, target; rtol = 0.2)
end

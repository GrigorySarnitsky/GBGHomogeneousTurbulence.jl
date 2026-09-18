# PF item 3 (`reality_residual`, PF decision 71) wired at the escape hatch: `fields_modified!(sim)`
# now measures the conjugate-symmetry residual of the announced state and refuses an inconsistency
# beyond roundoff. Before the check, a corrupted k_x = 0 plane was undetectable — the docstring said
# "it is not checked" and every spectral diagnostic silently disagreed with the physical images.
# This is the witness the PF request promised: hand-corrupt the plane, and the violation is NAMED.
using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, to_physical, to_spectral, reality_projection!
using Random


@testset "fields_modified!(sim) names a conjugate-symmetry violation" begin
  sim = Simulation(grid_points_per_axis = 16, viscosity = 0.05, rng = MersenneTwister(1))

  # A healthy state passes: the seeders satisfy the constraint by construction, and a symmetric
  # in-place rescale preserves it exactly.
  @test fields_modified!(sim) === sim
  field_data(sim.state.velocity_spectral) .*= 2
  @test fields_modified!(sim) === sim

  # Corrupt ONE member of a stored conjugate pair on the folded axis's zero plane: (1, j, k) pairs
  # with (1, N-j+2, N-k+2), a distinct entry, so a one-sided write breaks f̂(-κ) = conj(f̂(κ)) at O(1).
  field_data(sim.state.velocity_spectral)[1, 2, 3, 1] += 1
  @test_throws ArgumentError fields_modified!(sim)

  # The documented repair (decision 88): the field library's projector onto real-field spectra —
  # exact, O(N²); the physical round trip it replaced projects only to the transform's own floor.
  û = sim.state.velocity_spectral
  reality_projection!(û)
  @test fields_modified!(sim) === sim
  # …and the old repair still agrees with it to round-off, which is what decision 71 promised of it.
  field_data(û)[1, 2, 3, 1] += 1
  field_data(û) .= field_data(to_spectral(to_physical(û, sim.domain.transform_plans),
                                          sim.domain.transform_plans))
  @test fields_modified!(sim) === sim
end

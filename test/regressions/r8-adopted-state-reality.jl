# An adopted state must hold the spectrum of a real field. On the real-to-complex layout the folded
# axis's zero plane stores both members of each conjugate pair, so a spectrum imported from another
# solver or written by hand can break f̂(-κ) = conj(f̂(κ)) there. Nothing downstream would name it:
# the spectral diagnostics count the anti-Hermitian part the physical fields never see, and the first
# step's projection (decision 88) removes it. The constructor refuses it, names the repair, and lets
# roundoff through.
using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, to_physical, to_spectral, reality_projection!
using Random

const DOMAIN = FixedDomain(grid_points_per_axis = 16, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_family = Array)

function seeded_state(; scalar = false)
  state = ResolvedFields(DOMAIN; scalar)
  random_solenoidal_velocity_spectral!(state.velocity_spectral, DOMAIN, 1.5; rng = MersenneTwister(1))
  scalar && random_scalar_spectral!(state.scalar_spectral, DOMAIN, 1.0; rng = MersenneTwister(2))
  return state
end

adopt(state) = Simulation(DOMAIN; viscosity = 0.05, state,
                          scalar = state.scalar_spectral === nothing ? nothing : PassiveScalar())

@testset "an adopted state must be the spectrum of a real field" begin
  # A seeded state passes: the seeders transform real noise, so the constraint holds by construction.
  @test adopt(seeded_state()) isa Simulation

  # ONE member of a stored conjugate pair on the zero plane: (1, j, k) pairs with (1, N-j+2, N-k+2),
  # a distinct entry, so a one-sided write breaks the constraint at O(1). The error names the repair.
  state = seeded_state()
  field_data(state.velocity_spectral)[1, 2, 3, 1] += 1
  err = try adopt(state); nothing catch e; e end
  @test err isa ArgumentError
  @test occursin("velocity", err.msg) && occursin("reality_projection!", err.msg)

  # The repair it names makes the same coefficients adoptable.
  reality_projection!(state.velocity_spectral)
  @test adopt(state) isa Simulation

  # The scalar is checked too.
  state = seeded_state(scalar = true)
  field_data(state.scalar_spectral)[1, 2, 3] += 1
  err = try adopt(state); nothing catch e; e end
  @test err isa ArgumentError && occursin("scalar", err.msg)

  # Roundoff is not a violation: a physical round trip leaves the pairs equal only to the transform's
  # own precision, as another solver's spectrum would be.
  state = seeded_state()
  û = state.velocity_spectral
  field_data(û) .= field_data(to_spectral(to_physical(û, DOMAIN.transform_plans), DOMAIN.transform_plans))
  @test adopt(state) isa Simulation
end

# Probe for the hunter's claimed "one rule": that `to_physical!` MUST run before
# `vorticity_physical!` when they share a spectral scratch. If the rule exists, swapping the two
# calls must change the result. It does not.
using Test, Random, GBGHomogeneousTurbulence
using GBGPeriodicFields: to_physical!, field_data
using GBGHomogeneousTurbulence.Observables: vorticity_physical!

@testset "the two recovery calls are order-independent on a shared scratch" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       dealiasing = TwoThirds(), array_family = Array)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain, 0.5;
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(7))

  scratch = new_vector_field_spectral(domain)
  u1, w1 = new_vector_field_physical(domain), new_vector_field_physical(domain)
  u2, w2 = new_vector_field_physical(domain), new_vector_field_physical(domain)

  # order A — the order every call site uses
  to_physical!(u1, û, domain.transform_plans, scratch)
  vorticity_physical!(w1, û, domain, scratch)

  # order B — swapped
  vorticity_physical!(w2, û, domain, scratch)
  to_physical!(u2, û, domain.transform_plans, scratch)

  @test field_data(u1) == field_data(u2)
  @test field_data(w1) == field_data(w2)
end

# Witness: a forcing amplitude that is documented non-negative must be rejected AT CONSTRUCTION,
# naming the keyword — not surfaced as a bare `sqrt` DomainError two frames downstream.
#
# `SimulationRun.jl` already records this exact class, in the comment above its own guard:
#   "a negative value surfaced far downstream as a DomainError out of `sqrt` with nothing naming the
#    argument that caused it"
# and guards `kinetic_energy > 0` / `scalar_variance >= 0` accordingly. `StochasticOU`'s `forcing_variance`
# — documented as the stationary ⟨|f|²⟩ = σ², which cannot be negative — carried no such guard, and
# every draw scales by sqrt(variance), so a negative value reached `sqrt` downstream.
# `VarianceRescaling`'s `target` (an exported, front-door forcing) is the same shape via `project_forcing!`.
using Test, Random, GBGHomogeneousTurbulence

@testset "forcing amplitudes documented non-negative are guarded at construction" begin

@testset "a negative forcing variance is rejected at construction, not as a downstream sqrt DomainError" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)

  # (1) The construction guard the codebase's own pattern calls for.
  @test_throws ArgumentError StochasticOU(domain; forcing_variance = -1.0, correlation_time = 0.3)

  # (2) Whatever the tree does at construction, no caller must ever meet a raw `DomainError` out of
  #     `sqrt`: either the keyword was refused by name, or the step runs. Written so that a fixed
  #     tree (ArgumentError at (1)) passes this too.
  ou = try
    StochasticOU(domain; forcing_variance = -1.0, correlation_time = 0.3)
  catch err
    err
  end
  raised = if ou isa ArgumentError
    ou                                     # already refused by name — nothing downstream to reach
  else
    û = new_vector_field_spectral(domain)
    try
      prepare_forcing!(ou, initial_forcing_state(ou, û, domain), û, domain, 0.01)
      nothing
    catch err
      err
    end
  end
  @test !(raised isa DomainError)
  @info "negative-variance StochasticOU" construction_or_step_error = raised

  # (3) Control: a legitimate non-negative variance keeps working (the guard must not over-reach).
  ok = StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.3, seed = 3)
  û = new_vector_field_spectral(domain)
  @test prepare_forcing!(ok, initial_forcing_state(ok, û, domain), û, domain, 0.01) === nothing
end


# The same class on an EXPORTED, front-door forcing: `VarianceRescaling`'s `target` is a kinetic energy
# (velocity) or a scalar variance (scalar), so it too cannot be negative — and `project_forcing!`
# computes scale = sqrt(target_band / band_value). `over = :total` is shielded by its `max(0, …)`;
# `over = :band` passes the raw target straight into `sqrt`. Fix the class, not the line.
@testset "a negative VarianceRescaling target is rejected at construction, not as a downstream sqrt DomainError" begin
  domain = FixedDomain(grid_points_per_axis = 16, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)

  @test_throws ArgumentError VarianceRescaling(domain; target = -1.0, over = :band)

  state = ResolvedFields(domain)
  random_solenoidal_velocity_spectral!(state.velocity_spectral, domain;
                                       kinetic_energy = 1.0, envelope_wavenumber = 2.0,
                                       rng = MersenneTwister(1))
  raised = try
    forcing = VarianceRescaling(domain; target = -1.0, over = :band)
    project_forcing!(forcing, state.velocity_spectral, domain)
    nothing
  catch err
    err
  end
  @test !(raised isa DomainError)
  @info "negative-target VarianceRescaling" construction_or_apply_error = raised
end

end  # outer testset

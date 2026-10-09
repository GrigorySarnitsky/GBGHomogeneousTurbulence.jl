# Witness for candidate test-critic-05: "IFHeun's step! allocation-free guarantee is never measured
# with @allocated". The claim is a coverage claim; the behaviour it worries about is that IFHeun's
# stage-2 predictor path allocates. This asserts the CORRECT behaviour: one warmed IFHeun step! plus
# its closing deposit! allocate less than a single field's worth of bytes, on both the velocity-only
# and the velocity+scalar path (the scalar branch carries the extra predictor/stage registers).

using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data
using Random
using Test


function step_deposit_bytes(; scalar::Bool, N = 16, T = Float64)
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  scheme = IFHeun()
  buffers = allocate_buffers(scheme, domain; scalar = scalar)
  conditions = FlowConditions(viscosity = 5.0e-2, schmidt = 1.0,
                              velocity_forcing = VarianceRescaling(domain; target = 0.6, over = :band,
                                                               lowest_shell = 1, highest_shell = 2),
                              scalar_forcing = NoForcing())
  generator = ResolvedGenerator(domain, conditions; scalar = scalar)

  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain, 0.6;
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(42))
  truncate_to_band!(û, domain)
  φ̂ = nothing
  if scalar
    φ̂ = new_scalar_field_spectral(domain)
    random_scalar_spectral!(φ̂, domain, 1.0;
                            envelope_wavenumber = 2.0, rng = MersenneTwister(43))
    truncate_to_band!(φ̂, domain)
  end
  state = ResolvedFields(û, φ̂)
  cache = ObservablesCache(domain; scalar = scalar)
  deposit!(cache, state, domain, buffers)

  dt = 1.0e-3
  for _ in 1:2                                     # warm (compile) before measuring
    step!(scheme, state, generator, domain, buffers, cache, dt)
    deposit!(cache, state, domain, buffers)
  end
  step_bytes = @allocated step!(scheme, state, generator, domain, buffers, cache, dt)
  deposit_bytes = @allocated deposit!(cache, state, domain, buffers)
  field_bytes = length(field_data(û)) * sizeof(eltype(field_data(û)))
  return step_bytes + deposit_bytes, field_bytes
end


@testset "IFHeun's step! (and its closing deposit!) is allocation-free over the preallocated buffers" begin
  @testset "velocity only" begin
    bytes, field_bytes = step_deposit_bytes(scalar = false)
    @info "IFHeun velocity-only" bytes field_bytes
    @test bytes < field_bytes
  end
  @testset "velocity + passive scalar" begin
    bytes, field_bytes = step_deposit_bytes(scalar = true)
    @info "IFHeun velocity+scalar" bytes field_bytes
    @test bytes < field_bytes
  end
end

# Witness: gpu-and-hot-loop-02 — StochasticOU.prepare_forcing! must not allocate at field scale per step.
#
# `prepare_forcing!` is reached once per timestep from `step!` via `Generator.prepare!`, i.e. it sits
# on the hot loop the package declares in-place and allocation-free at field scale. The archived
# `StochasticOU` drew a full physical-vector host array per step (`randn(ou.rng, T, dims...)`) — on a
# device backend an implicit host→device copy of it too. The band-sparse form draws a few hundred
# numbers into host scratch and uploads a band-sized array; what remains is the reseed's small
# fixed-size allocation, far below one field-scale array, and the bound below is held against that
# field scale.

using Test
using Random
using GBGHomogeneousTurbulence

@testset "StochasticOU.prepare_forcing! allocates nothing at field scale" begin
  T = Float64
  N = 16
  unit = sizeof(T) * N^3                       # one field-scale real array
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  ou = StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0,
                                       rng = MersenneTwister(1))
  state = initial_forcing_state(ou, û, domain)

  prepare_forcing!(ou, state, û, domain, 0.01)       # compile
  prepare_forcing!(ou, state, û, domain, 0.01)

  bytes = @allocated prepare_forcing!(ou, state, û, domain, 0.01)
  @info "prepare_forcing! steady-state allocation" bytes units = bytes / unit
  # Half a field-scale array is a wide margin over the reseed's fixed allocation and far below the
  # 3 units a physical vector costs.
  @test bytes < 0.5 * unit

  # …and the same must hold through the run layer, the way memory_audit.jl guards every other cell.
  sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; rng = MersenneTwister(2),
                   velocity_forcing = StochasticOU(forcing_variance = 1.0, correlation_time_in_box_units = 0.5))
  advance!(sim; dt = 1e-3); advance!(sim; dt = 1e-3)          # warm before measuring
  step_bytes = @allocated advance!(sim; dt = 1e-3)
  @info "advance! with StochasticOU forcing" step_bytes units = step_bytes / unit
  @test step_bytes < 0.5 * unit
end

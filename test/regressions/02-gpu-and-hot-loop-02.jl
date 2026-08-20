# Witness: gpu-and-hot-loop-02 — StochasticOU.prepare_forcing! must not allocate per step.
#
# `prepare_forcing!` is reached once per timestep from `step!` via `Generator.prepare!`
# (src/Generator.jl:267, called at src/Propagator.jl:268 and :374), i.e. it sits on the hot loop the
# package declares in-place and allocation-free over preallocated buffers. Every other forcing hook
# (Linear/ConstantPower `set_forcing_rate!`, BandRescaling `apply_forcing!`) meets that contract.
# `StochasticOU` owns preallocated noise scratch (`noise_physical`, `noise_spectral`) yet fills it
# from a freshly allocated host `randn(ou.rng, T, dims...)` on EVERY call (src/Forcing.jl:505) —
# a full physical-vector host array per step, and on a device backend an implicit host→device copy.

using Test
using Random
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Forcing: StochasticOU, prepare_forcing!

@testset "StochasticOU.prepare_forcing! is allocation-free after its first-use scratch is built" begin
  T = Float64
  N = 16
  unit = sizeof(T) * N^3                       # one field-scale real array
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)

  ou = StochasticOU(domain; variance = 1.0, correlation_time = 0.5)
  û = new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 0.5, envelope_wavenumber = 2.0,
                                       rng = MersenneTwister(1))

  # First two calls: compile, and build the lazily-allocated scratch (ou.state / ou.noise_*).
  prepare_forcing!(ou, û, domain, 0.01)
  prepare_forcing!(ou, û, domain, 0.01)

  bytes = @allocated prepare_forcing!(ou, û, domain, 0.01)
  @info "prepare_forcing! steady-state allocation" bytes units = bytes / unit
  # The scratch is already resident; a steady-state call must reuse it. Half a field-scale array is
  # a wide margin over run-layer bookkeeping and far below the 3 units a physical vector costs.
  @test bytes < 0.5 * unit

  # …and the same must hold through the run layer, the way memory_audit.jl guards every other cell.
  sim = Simulation(grid_points_per_axis = N, viscosity = 0.05; rng = MersenneTwister(2),
                   velocity_forcing = StochasticOU(variance = 1.0, correlation_time = 0.5))
  advance!(sim; dt = 1e-3); advance!(sim; dt = 1e-3)          # warm before measuring
  step_bytes = @allocated advance!(sim; dt = 1e-3)
  @info "advance! with StochasticOU forcing" step_bytes units = step_bytes / unit
  @test step_bytes < 0.5 * unit
end

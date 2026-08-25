# r6-free-hot-path-01 (owner-ruled 2026-08-25, option a) — a VarianceController whose
# turnover_time was DEFAULTED must be refused when bound as `scalar_forcing`: the default
# tℓ = 2·target/(3·ε_∞), ε_∞ = (target/0.9)^{3/2}/L is Bassenne's KINETIC-energy law; fed the
# scalar's ⟨φ²⟩ it makes tℓ ∝ 1/sqrt(target), so the restoring rate G·(⟨φ²⟩ − target)/tℓ breaks
# the scalar equation's exact φ → s·φ covariance (the invariance the relative empty-band floor was
# designed around). The velocity binding keeps the derived default — there the target IS a kinetic
# energy. With an explicit turnover_time the covariance must hold to the last bit.

using Test
using Random: MersenneTwister
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data

function scaled_scalar_pair(turnover_time)
  # Same seed ⇒ identical velocity draws and identical raw scalar draw; the seeder rescales the
  # scalar by sqrt(scalar_variance/current), a power-of-two ratio here, so φ_B(0) = 2·φ_A(0)
  # bit-exactly. The scalar is passive, so velocities and the CFL dt stay bit-identical.
  make(scalar_variance, target) =
    Simulation(; grid_points_per_axis = 16, viscosity = 5e-2, scalar = true, scalar_variance,
               scalar_forcing = VarianceController(; target, turnover_time),
               rng = MersenneTwister(42))
  simA = make(1.0, 1.0)
  simB = make(4.0, 4.0)
  return simA, simB
end

function covariance_violation(turnover_time; steps = 5)
  simA, simB = scaled_scalar_pair(turnover_time)
  # Preconditions of the symmetry — the harness itself, checked bit-exactly.
  @test field_data(simB.state.velocity_spectral) == field_data(simA.state.velocity_spectral)
  @test field_data(simB.state.scalar_spectral) == 2 .* field_data(simA.state.scalar_spectral)
  for _ in 1:steps
    advance!(simA)
    advance!(simB)
  end
  φA = field_data(simA.state.scalar_spectral)
  φB = field_data(simB.state.scalar_spectral)
  return maximum(abs.(φB .- 2 .* φA)) / maximum(abs.(φB))
end

@testset "a defaulted turnover_time is refused at the scalar binding; explicit covariance is exact" begin
  # Control: with the SAME explicit turnover_time on both controllers, every term of the forced
  # scalar problem is homogeneous of degree one in φ and the covariance holds to the last bit.
  # This pins the rest of the scalar path (advection, diffusion, amplitude formula) as exactly
  # linear.
  @test covariance_violation(3.0) == 0.0

  # The ruling: a defaulted-turnover_time controller bound as `scalar_forcing` is refused with a
  # named ArgumentError at the one seam every construction path crosses (`FlowConditions`).
  err = try
    Simulation(; grid_points_per_axis = 16, viscosity = 5e-2, scalar = true,
               scalar_forcing = VarianceController(; target = 1.0), rng = MersenneTwister(42))
    nothing
  catch e
    e
  end
  @test err isa ArgumentError
  @test err isa ArgumentError && occursin("turnover_time", err.msg)

  # The velocity binding keeps its derived default — the target there IS a kinetic energy — so
  # the run layer's default controller stays legal, as does an explicit velocity-side build.
  @test Simulation(; grid_points_per_axis = 16, viscosity = 5e-2,
                   rng = MersenneTwister(42)) isa Simulation
  @test Simulation(; grid_points_per_axis = 16, viscosity = 5e-2,
                   velocity_forcing = VarianceController(; target = 1.5),
                   rng = MersenneTwister(42)) isa Simulation
end

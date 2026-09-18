# Witness: the zero-speed branch of `cfl_timestep` (SimulationRun.jl:407,
# `speed > 0 ? sim.cfl * Δx / speed : sim.cfl * Δx`) is claimed to hand back a
# velocity-independent step with "no diffusive stability bound behind it", so that on a fine grid
# or at small ν the automatically-chosen step could violate stability.
#
# The correct behaviour asserted here: whatever `cfl_timestep` returns at a resting flow, the
# resulting `advance!` must be STABLE and EXACT — the integrating factor solves the linear part
# exactly, and a resting unforced flow is a fixed point, so the answer must not depend on the step.
# Each test states a property a correct time-stepper must have; a real defect makes one of them fail.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.SimulationRun: cfl_timestep
using GBGPeriodicFields: field_data
using Random
using Test


# A run at rest: velocity identically zero, announced and re-deposited so `max_speed` reads 0.
function resting_run(; N, ν, scalar::Bool, seed = 20250820)
  sim = Simulation(grid_points_per_axis = N, side_length = 2π, viscosity = ν,
                   velocity_forcing = NoForcing(), scalar_forcing = NoForcing(),
                   scalar = scalar, field_integration_scheme = IFLowStorageRK3(),
                   rng = MersenneTwister(seed))
  fill!(field_data(sim.state.velocity_spectral), 0)
  fields_modified!(sim.cache)
  deposit!(sim)
  return sim
end


@testset "the zero-speed CFL fallback still yields a stable, step-independent advance" begin
  N, ν = 16, 1e-3
  Δx = 2π / N

  @testset "the fallback branch is the one under test" begin
    sim = resting_run(; N, ν, scalar = false)
    @test max_speed(sim.cache) == 0
    @test cfl_timestep(sim) ≈ sim.cfl * Δx        # the branch the hunter names, confirmed reached
  end

  @testset "a resting unforced flow stays exactly at rest under the fallback step" begin
    sim = resting_run(; N, ν, scalar = false)
    for _ in 1:20
      advance!(sim)
    end
    @test all(iszero, field_data(sim.state.velocity_spectral))
    @test isfinite(current_time(sim)) && current_time(sim) > 0
    @test kinetic_energy(sim.state.velocity_spectral) == 0
  end

  @testset "the fallback step is no larger than the advective limit it replaces" begin
    # At speed 0 the advective-CFL limit C·Δx/max|u| is +Inf, so ANY finite step is inside it.
    # The fallback must therefore be finite and not exceed that limit — the stability claim.
    sim = resting_run(; N, ν, scalar = false)
    Δt = cfl_timestep(sim)
    @test isfinite(Δt) && Δt > 0
    @test Δt ≤ sim.cfl * Δx / max_speed(sim.cache)   # RHS is Inf; the fallback must sit under it
  end

  @testset "the scalar's decay under the fallback step is exact, not step-size dependent" begin
    # ∂φ/∂t = (ν/Sc)∇²φ at rest, solved exactly by the integrating factor: one step of Δt must
    # agree with n substeps of Δt/n to round-off. A step chosen "with no stability bound behind it"
    # would show up here as a divergence between the two.
    coarse = resting_run(; N, ν, scalar = true)
    fine   = resting_run(; N, ν, scalar = true)
    Δt = cfl_timestep(coarse)
    advance!(coarse; dt = Δt)
    for _ in 1:32
      advance!(fine; dt = Δt / 32)
    end
    a = field_data(coarse.state.scalar_spectral)
    b = field_data(fine.state.scalar_spectral)
    @test maximum(abs, a .- b) ≤ 1e-12 * max(1.0, maximum(abs, b))
  end

  @testset "the hunter's stated trigger — fine grid, tiny viscosity — is still stable" begin
    sim = resting_run(; N = 32, ν = 1e-8, scalar = true)
    @test max_speed(sim.cache) == 0
    e0 = scalar_variance(sim.state.scalar_spectral)
    for _ in 1:20
      advance!(sim)
    end
    @test all(isfinite, field_data(sim.state.scalar_spectral))
    @test all(iszero, field_data(sim.state.velocity_spectral))
    # Pure diffusion at ν/Sc = 1e-8 can only decay the variance; growth would be the instability.
    @test scalar_variance(sim.state.scalar_spectral) ≤ e0 * (1 + 1e-10)
  end
end

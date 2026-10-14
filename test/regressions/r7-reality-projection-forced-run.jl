# Decision 88 — the advanced state is projected onto real-field spectra every step, beside the
# divergence re-projection of decision 61. The rfft layout stores both members of a conjugate pair
# on the folded axis's zero plane; their anti-Hermitian part is invisible to the inverse real
# transform (so the nonlinear term neither sees nor feeds it), damped only by νκ² at κ ≈ 1, and
# amplified by every forcing proportional to the field with the same coefficient as the physical
# modes. Measured before the fix: from the transform's round-off floor it grew at ≈ 0.26 per time
# unit and by t ≈ 70 held all of k — spectral k pinned at the controller's target while the physical
# field's k, ε and maximum speed collapsed (six Float32 seeds at 96³, RK3 and RK4, TwoThirds and
# PhaseShift alike; Float64 at t = 142). The discriminating half plants the violation by hand,
# because FFTW's real transform is EXACTLY Hermitian at some sizes (32³, 64³, 128³) and only
# round-off-Hermitian at others (96³, 256³; cuFFT and rocFFT everywhere), so a witness that waits
# for the library's own seed can pass vacuously on the very machine that runs the suite. Planted at
# 2e-6 relative, the controller grew it ×360 in 27 time units before the fix; NoForcing damped it ×0.4.
using Test, GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, reality_residual
using Random

# An anti-Hermitian perturbation of the pair (0, 1, 0) / (0, −1, 0) — both members shifted by +iδ,
# where a Hermitian pair would take +iδ and −iδ — on every component of `f̂`. Relative size `ε`.
function plant!(f̂, ε)
  data = field_data(f̂)
  N = size(data, 2)
  δ = ε * maximum(abs, @view data[1, :, :, :])
  for c in axes(data)[end]
    data[1, 2, 1, c] += im * δ
    data[1, N, 1, c] += im * δ
  end
  return f̂
end
physical_energy(u) = sum(abs2, field_data(u)) / (2 * prod(size(field_data(u))[1:3]))

@testset "the advanced state is projected onto real-field spectra: the parasitic mode cannot grow" begin
  @testset "a planted violation is removed by the next step, exactly, velocity and scalar" begin
    sim = Simulation(grid_points_per_axis = 32, κ_max_η = 1.5, scalar = PassiveScalar(), rng = MersenneTwister(1))
    û, φ̂ = sim.state.velocity_spectral, sim.state.scalar_spectral
    plant!(û, 2e-6)
    let data = field_data(φ̂), N = size(data, 2), δ = 2e-6 * maximum(abs, @view data[1, :, :])
      data[1, 2, 1] += im * δ; data[1, N, 1] += im * δ
    end
    @test reality_residual(û) > 0 && reality_residual(φ̂) > 0        # the plant is a real violation
    fields_modified!(sim.cache); deposit!(sim)                       # the run-level verb refuses a plant, by design
    advance!(sim)
    @test reality_residual(sim.state.velocity_spectral) == 0         # exactly: a projection, not a decay
    @test reality_residual(sim.state.scalar_spectral) == 0
  end

  @testset "under the controller the residual stays at zero and spectral energy is the physical energy" begin
    # Before the fix the planted 2e-6 grew ×360 over 27 time units and spectral k parted from ½⟨|u|²⟩.
    sim = Simulation(grid_points_per_axis = 32, κ_max_η = 1.5, rng = MersenneTwister(2))
    plant!(sim.state.velocity_spectral, 2e-6)
    fields_modified!(sim.cache); deposit!(sim)
    worst = 0.0
    run!(sim) do s
      if current_step(s) > 0                                         # the step-0 callback sees the plant
        @test reality_residual(s.state.velocity_spectral) == 0
        k_spectral = kinetic_energy(s.state.velocity_spectral)
        k_physical = physical_energy(velocity_physical(s.cache))
        worst = max(worst, abs(k_spectral - k_physical) / k_spectral)
      end
      current_step(s) < 200
    end
    @test worst < 1e-10                                              # Parseval, to round-off, every step
  end

  @testset "Float32 at a size where the transform itself seeds the violation" begin
    # 48³: FFTW's real transform is Hermitian only to round-off here (measured 1.5e-7 at 96³, 0 at
    # 32³/64³/128³), so without the projection the residual would sit at ~1e-7·scale and grow.
    sim = Simulation(grid_points_per_axis = 48, κ_max_η = 1.5, element_type = Float32, rng = MersenneTwister(3))
    for _ in 1:50; advance!(sim); @test reality_residual(sim.state.velocity_spectral) == 0; end
  end
end

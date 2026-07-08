# De-aliasing-strategy tests: the sharp `TwoThirds` (default) vs the smooth `HouLi` kernels, and the
# CFL ceiling auto-scaling to the active strategy (a strategy that keeps more modes takes a smaller step).

using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data
using Random
using Test

@testset "dealiasing" begin
  L = 2π
  N = 16

  @testset "TwoThirds sharp kernel is the default" begin
    domain = SimulationDomain(N, L; scalar_type = Float64)
    @test domain.dealiasing isa TwoThirds
    mask = real.(field_data(domain.dealias))
    @test all(m -> m == 0 || m == 1, mask)             # sharp 0/1 truncation
    @test any(==(1), mask) && any(==(0), mask)         # both kept and cut modes present
  end

  @testset "HouLi smooth filter" begin
    domain = SimulationDomain(N, L; dealiasing = HouLi(), scalar_type = Float64)
    @test domain.dealiasing isa HouLi
    g = real.(field_data(domain.dealias))
    @test all(x -> -1e-12 ≤ x ≤ 1 + 1e-12, g)          # a transfer function in [0,1]
    @test maximum(g) ≈ 1 rtol = 1e-6                    # ≈ 1 at the mean (k = 0)
    @test any(x -> 0.01 < x < 0.99, g)                 # genuinely smooth intermediate values, not 0/1
    zeros_houli = count(==(0), g)
    zeros_23 = count(==(0), real.(field_data(SimulationDomain(N, L).dealias)))
    @test zeros_houli < zeros_23                        # keeps more modes than the 2/3 rule
  end

  @testset "auto-CFL scales with the dealiasing" begin
    ops23 = SimulationDomain(N, L)
    opsHL = SimulationDomain(N, L; dealiasing = HouLi())
    rk3 = IFLowStorageRK3()
    @test recommended_cfl(rk3, ops23) ≈ recommended_cfl(rk3)          # 2/3 ⇒ base value unchanged
    @test recommended_cfl(rk3, opsHL) ≈ recommended_cfl(rk3) * 2 / 3  # HouLi keeps to Nyquist ⇒ ×2/3
    @test recommended_cfl(rk3, opsHL) < recommended_cfl(rk3, ops23)   # a tighter step
  end

  @testset "a HouLi simulation runs and stays finite" begin
    domain = SimulationDomain(N, L; dealiasing = HouLi())
    sim = Simulation(domain; viscosity = 0.03,
                     velocity_forcing = ConstantPower(power = 0.1), scalar = false,
                     rng = MersenneTwister(7))
    @test sim.cfl ≈ recommended_cfl(IFLowStorageRK3()) * 2 / 3        # the domain-aware CFL flowed in
    run!(sim; steps = 10)
    @test isfinite(kinetic_energy(sim)) && kinetic_energy(sim) > 0
    # the resolution front door threads `dealiasing` through to the domain
    sim2 = Simulation(grid_points_per_axis = N, viscosity = 0.05; dealiasing = HouLi(), scalar = false,
                      rng = MersenneTwister(8))
    @test sim2.domain.dealiasing isa HouLi
  end
end

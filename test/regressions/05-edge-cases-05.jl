# Witness — edge-cases-05
#
# Claim: `random_solenoidal_velocity_spectral!` documents that the seeded field is "rescaled so the
# kinetic energy ... equals the requested `kinetic_energy`".  When the dealiasing cutoff
# `max_retained_wavenumber(domain)` falls at or below the grid's lowest nonzero wavenumber 2π/L, the dealias
# kernel zeroes every surviving mode (the envelope already zeroes κ = 0), `current_energy` is exactly
# 0, the `current_energy > 0` guard at src/State.jl:138 skips the rescale, and the function returns an
# all-zero û — silently, while the `Simulation` derivation branch has already logged ν, ε and Re_λ
# computed as if `kinetic_energy` had been realized.
#
# Correct behaviour: either the requested kinetic energy is realized, or the caller is told (an error
# or at minimum a warning) that it was not.  Both are asserted below.

using Test, Random
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence: FixedDomain, TwoThirds, max_retained_wavenumber,
                              random_solenoidal_velocity_spectral!, new_vector_field_spectral,
                              kinetic_energy, Simulation

@testset "the requested kinetic_energy is realized, or the caller is told it was not" begin
  @testset "a coarse grid whose dealias band excludes every nonzero mode must not silently seed a zero-energy field" begin
    N, L = 2, 2π
    domain = FixedDomain(; grid_points_per_axis = N, side_length = L,
                         dealiasing = TwoThirds(), element_type = Float64, array_family = Array)

    # Precondition of the claim: the band really is empty of nonzero modes.
    lowest_nonzero_wavenumber = 2π / L
    @info "band" κ_max = max_retained_wavenumber(domain) lowest_nonzero_wavenumber
    @test max_retained_wavenumber(domain) < lowest_nonzero_wavenumber   # setup check, not the defect

    requested = 1.5

    # (1) The documented contract of the seeding function itself.
    û = new_vector_field_spectral(domain)
    seeded = nothing
    warned = false
    try
      seeded = random_solenoidal_velocity_spectral!(û, domain;
                          kinetic_energy = requested, envelope_wavenumber = 2.0,
                          rng = MersenneTwister(1))
    catch err
      warned = true                                # an explicit error is acceptable behaviour
      @info "seeding threw (acceptable)" err
    end
    if !warned
      @test kinetic_energy(seeded) ≈ requested
    end

    # (2) The front door: `Simulation` logs ν, ε, Re_λ as if `kinetic_energy` were realized, so the
    #     state it hands back must carry that energy (or construction must fail loudly).
    sim = nothing
    threw = false
    try
      sim = Simulation(grid_points_per_axis = N, kinetic_energy = requested,
                       rng = MersenneTwister(1))
    catch err
      threw = true
      @info "Simulation construction threw (acceptable)" err
    end
    if !threw
      @test kinetic_energy(sim.state.velocity_spectral) ≈ requested
    end
  end


  # The same silent-zero path on an ordinary grid: an `initial_spectrum` whose values underflow across
  # the whole resolved band leaves every mode at 0, so the `current_energy > 0` guard is skipped again.
  # No dealiasing degeneracy is needed — this is the general shape of the defect.
  @testset "an initial_spectrum that vanishes over the resolved band must not silently seed a zero-energy field" begin
    domain = FixedDomain(; grid_points_per_axis = 16, side_length = 2π,
                         dealiasing = TwoThirds(), element_type = Float64, array_family = Array)
    û = new_vector_field_spectral(domain)
    requested = 1.5
    threw = false
    local seeded
    try
      seeded = random_solenoidal_velocity_spectral!(û, domain;
                          kinetic_energy = requested, envelope_wavenumber = 2.0,
                          initial_spectrum = κ -> exp(-1000 * κ),   # underflows to 0 for every κ ≥ 1
                          rng = MersenneTwister(1))
    catch err
      threw = true
      @info "seeding threw (acceptable)" err
    end
    threw || @test kinetic_energy(seeded) ≈ requested
  end
end

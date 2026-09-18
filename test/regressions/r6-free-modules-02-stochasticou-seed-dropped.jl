# Witness r6-free-modules-02: write_forcing(StochasticOU) drops the seed, so read_forcing rebuilds
# every restored stochastic forcing on the constructor default MersenneTwister(0) — the documented
# contract ("a strategy IS its parameters"; "a reloaded run resumes on a fresh stream") holds under
# NEITHER reading: the user's configured seed is silently discarded, and two runs checkpointed with
# different seeds (independent ensemble members) restore to bitwise-identical forcing noise.
using Test, Random
using GBGHomogeneousTurbulence
# Under the gate's `julia --project` the main env has no HDF5 (it is a weak dep); the pile keeps a
# dedicated env with the package dev'd + HDF5, located through `pkgdir` so the file works from any
# depth. Promoted into test/regressions/ this branch is dead: Pkg.test's merged env already
# resolves HDF5, so the activation never fires there.
if Base.locate_package(Base.PkgId(Base.UUID("f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f"), "HDF5")) === nothing
  import Pkg
  Pkg.activate(joinpath(pkgdir(GBGHomogeneousTurbulence), ".claude", "bug-hunt", "env"); io = devnull)
end
using HDF5


@testset "read_forcing(StochasticOU) restores neither the written seed nor an independent stream" begin
  domain = FixedDomain(; grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       array_type = Array, dealiasing = TwoThirds())
  a = StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5, seed = 7)
  b = StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5, seed = 8)

  path = tempname() * ".h5"
  h5open(path, "w") do io
    write_forcing(io, "a", a)
    write_forcing(io, "b", b)
  end
  read_a, read_b = h5open(path, "r") do io
    read_forcing(io, "a", domain), read_forcing(io, "b", domain)
  end
  rm(path)

  # The stream is a function of the seed and the state's draw count, so the first draw a restored
  # forcing makes is the observable test of what was restored. (Rewritten 2026-09-17 for the shipped
  # StochasticOU, whose generator is scratch reseeded before every draw.)
  û = new_vector_field_spectral(domain)
  draw(f) = copy(GBGHomogeneousTurbulence.SimulationRun.field_data(initial_forcing_state(f, û, domain).process))

  # Two restored forcings from differently-seeded runs must not produce bitwise-identical noise…
  @test draw(read_a) != draw(read_b)

  # …and the configured seed is what was restored, not the constructor default.
  @test draw(read_a) == draw(a)
  @test draw(read_a) != draw(StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5))
end

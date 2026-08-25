# Witness r6-free-modules-02: write_forcing(StochasticOU) drops the seed, so read_forcing rebuilds
# every restored stochastic forcing on the constructor default MersenneTwister(0) — the documented
# contract ("a strategy IS its parameters"; "a reloaded run resumes on a fresh stream") holds under
# NEITHER reading: the user's configured seed is silently discarded, and two runs checkpointed with
# different seeds (independent ensemble members) restore to bitwise-identical forcing noise.
using Test, Random
# Under the gate's `julia --project` the main env has no HDF5 (it is a weak dep); the pile keeps a
# dedicated env with the package dev'd + HDF5. Promoted into test/regressions/ this branch is dead:
# Pkg.test's merged env already resolves HDF5, so the activation never fires there.
if Base.locate_package(Base.PkgId(Base.UUID("f67ccb44-e63f-5c2f-98bd-6dc0ccc4ba2f"), "HDF5")) === nothing
  import Pkg
  Pkg.activate(joinpath(@__DIR__, "..", "env"); io = devnull)
end
using GBGIsotropicTurbulence
using HDF5
using GBGIsotropicTurbulence.Forcing: StochasticOU   # archived (un-exported); persistable via write_forcing


@testset "read_forcing(StochasticOU) restores neither the written seed nor an independent stream" begin
  domain = FixedDomain(; grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       array_type = Array, dealiasing = TwoThirds())
  a = StochasticOU(domain; variance = 1.0, correlation_time = 0.5, seed = 7)
  b = StochasticOU(domain; variance = 1.0, correlation_time = 0.5, seed = 8)

  path = tempname() * ".h5"
  h5open(path, "w") do io
    write_forcing(io, "a", a)
    write_forcing(io, "b", b)
  end
  read_a, read_b = h5open(path, "r") do io
    read_forcing(io, "a", domain), read_forcing(io, "b", domain)
  end
  rm(path)

  # Draw from copies so the assertions do not consume each other's stream state.
  draw(f) = rand(copy(f.rng), UInt64, 4)

  # Under EITHER reasonable contract — the seed persisted (streams 7 and 8), or the streams
  # genuinely fresh (independently seeded) — two restored forcings from differently-seeded runs
  # must not produce bitwise-identical noise.
  @test draw(read_a) != draw(read_b)

  # And the restored stream must not be the one fixed constructor-default stream: seed 7 was
  # configured, so neither "the user's seed" nor "a fresh stream" is MersenneTwister(0).
  @test draw(read_a) != rand(MersenneTwister(0), UInt64, 4)
end

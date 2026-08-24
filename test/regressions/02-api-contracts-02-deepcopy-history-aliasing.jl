# Witness: the claim that `past = [deepcopy(velocity_at_particles) for _ in 1:…]` (src/Cache.jl:166)
# may alias rather than independently duplicate its storage — on a device backend in particular —
# so that the multistep history shift `copyto!(point_values(past[j]), point_values(past[j-1]))`
# (src/Particles.jl:483) would corrupt a slot some other slot secretly shares.
#
# This file asserts the CORRECT behaviour: every slot of the Lagrangian sample history — and the
# current slot the cache serves — owns storage independent of every other, so a history shift is
# observable only in the slot it writes.
#
# Base's contract (docs.julialang.org/en/v1/base/base/#Base.deepcopy): "Create a deep copy of `x`:
# everything is copied recursively, resulting in a fully independent object." The device backends
# honour it through their own specializations (CUDACore `deepcopy_internal(x::CuArray, ::IdDict) =
# copy(x)`; GPUArrays `deepcopy_internal(x::AbstractGPUArray, ::IdDict) = copy(x)`, which serves
# AMDGPU's `ROCArray`); the GPU half of this witness lives beside it and needs a CUDA environment.

using Test, Random
using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorPointValues, point_values, CatmullRom

@testset "the Lagrangian sample history owns independent storage per slot" begin
  T = Float64
  N = 8
  M = 5
  K = 4                                        # AdamsBashforth{4} ⇒ K-1 = 3 past slots

  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  tracers = Tracers(domain; number_of_particles = M, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  cache = ObservablesCache(domain; number_of_particles = number_of_particles(tracers),
                           history_depth = K)
  past = cache.velocity_at_particles_history
  @test length(past) == K - 1

  # every slot is a distinct object over a distinct array, including against the current slot
  slots = Any[cache.velocity_at_particles, past...]
  arrays = map(point_values, slots)
  for i in eachindex(arrays), j in eachindex(arrays)
    i == j && continue
    @test arrays[i] !== arrays[j]
  end

  # the mutation test: writing one slot leaves every other bit-unchanged
  for i in eachindex(arrays)
    for (j, a) in enumerate(arrays)
      a .= T(j)
    end
    arrays[i] .= T(-99)
    for j in eachindex(arrays)
      j == i && continue
      @test all(arrays[j] .== T(j))
    end
  end

  # the shift of Particles.jl:483, in place: past[j] ← past[j-1] must not leak into past[j-1]
  for (j, a) in enumerate(arrays)
    a .= T(j)
  end
  for j in (K - 1):-1:2
    copyto!(point_values(past[j]), point_values(past[j-1]))
  end
  copyto!(point_values(past[1]), point_values(cache.velocity_at_particles))
  # slots 1 (current) and past[1] now hold 1.0; past[j] holds the old past[j-1] = j
  @test all(point_values(past[1]) .== T(1))
  for j in 2:(K - 1)
    @test all(point_values(past[j]) .== T(j))   # the pre-shift value of past[j-1] = arrays[j]
  end
end

@testset "deepcopy of a point-values wrapper duplicates its array (Base contract)" begin
  a = ones(Float32, 5, 3)
  pv = VectorPointValues(a)
  q = deepcopy(pv)
  @test point_values(q) !== a
  point_values(q) .= 0
  @test all(a .== 1)
end

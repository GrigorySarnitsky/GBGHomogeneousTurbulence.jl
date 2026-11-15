# Witness: the claim that the slots holding the earlier samples of the velocity at the particles may
# alias rather than independently own their storage — on a device backend in particular — so that
# writing one sample would corrupt another that secretly shares its array. The claim was raised
# against a history built with `deepcopy`; the trail that replaced it allocates each slot by its own
# call of the allocator.
#
# This file asserts the CORRECT behaviour: every slot of the trail owns storage independent of every
# other, so a new sample is observable only in the slot it is written to.
#
# Base's contract (docs.julialang.org/en/v1/base/base/#Base.deepcopy): "Create a deep copy of `x`:
# everything is copied recursively, resulting in a fully independent object." The device backends
# honour it through their own specializations (CUDACore `deepcopy_internal(x::CuArray, ::IdDict) =
# copy(x)`; GPUArrays `deepcopy_internal(x::AbstractGPUArray, ::IdDict) = copy(x)`, which serves
# AMDGPU's `ROCArray`); the GPU half of this witness lives beside it and needs a CUDA environment.

using Test, Random
using GBGHomogeneousTurbulence
using GBGPeriodicFields: VectorPointValues, point_values, CatmullRom

@testset "the trail of the velocity at the particles owns independent storage per slot" begin
  T = Float64
  N = 8
  M = 5

  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)
  tracers = Tracers(domain; number_of_particles = M, interpolation_scheme = CatmullRom,
                    rng = MersenneTwister(1))
  for trail in (ObservablesCache(domain; tracers, particle_integration_scheme = AB(4)).velocity_at_particles_trail,
                ParticleTrail(new_vector_point_values, tracers, 4))
    slots = trail.values
    @test length(slots) == 4

    # every slot is a distinct object over a distinct array
    arrays = map(point_values, slots)
    for i in eachindex(arrays), j in eachindex(arrays)
      i == j && continue
      @test slots[i] !== slots[j]
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
  end

  # Through the public write: six samples into a trail of four. Each sample read back holds its own
  # values, and a new sample changes none of the three it leaves in place.
  trail = ParticleTrail(new_vector_point_values, tracers, 4)
  for n in 1:6
    kept = [(sample.time, copy(point_values(sample.value))) for sample in trail][max(end - 2, 1):end]
    push!(value -> (point_values(value) .= T(n)), trail, T(n))
    @test all(point_values(trail[0].value) .== T(n))
    for (offset, (time, values)) in zip((-length(kept)):-1, kept)
      @test trail[offset].time == time
      @test point_values(trail[offset].value) == values
    end
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

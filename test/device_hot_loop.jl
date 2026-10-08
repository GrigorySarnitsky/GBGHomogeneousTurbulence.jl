# The time loop allocates nothing on the device that grows with the run: no field-scale array and no
# array of the tracers' size. The CPU allocation audit (`test/allocations.jl`) cannot see a device-only
# allocation, and it runs with 8 tracers; this check runs the same iteration on a GPU with enough
# tracers that one (M, 3) array per step is unmistakable.
#
# Found 2026-10-02 by the memory plan's GPU-leg review: with 10⁵ tracers at 64³ / Float32 a step
# allocated 1.2 MB of device memory — 12 bytes per tracer, one (M, 3) Float32 array — and none on the
# CPU. The source was PF's in-place `displace!` (the Heun corrector, `displace!(positions, grid, …)`):
# each axis column was assigned from a broadcast reading a separately made view of the same array, and
# on a device the broadcast's aliasing guard copied it first. Fixed by PF the same day (its decision
# 95), which now checks every in-place operation for a device allocation; this is HT's own check.
#
# CUDA only: the measurement is `CUDA.@allocated`. With no functional CUDA the check records a visible
# skip, never a pass.
using Test
using GBGHomogeneousTurbulence
using Random
using Logging

const CUDA_MODULE = let found = nothing
  id = Base.identify_package("CUDA")
  if id !== nothing
    m = try Base.require(id) catch; nothing end
    m !== nothing && (try Base.invokelatest(getproperty(m, :functional)) catch; false end) && (found = m)
  end
  found
end

const TRACERS = 100_000
# The field-scale floor is one Float32 spectral scalar at 64³; the tracer floor one (M, 3) Float32
# array. A step may allocate a few kilobytes of launch bookkeeping, far below both.
const BOUND = 64 * 1024

function device_bytes_per_step(cuda, M)
  sim = with_logger(NullLogger()) do
    Simulation(grid_points_per_axis = 64, viscosity = 0.05, number_of_particles = M,
               element_type = Float32, array_family = getproperty(cuda, :CuArray), rng = Xoshiro(1))
  end
  step!() = (advance!(sim; dt = 1e-3); Base.invokelatest(getproperty(cuda, :synchronize)))
  for _ in 1:3
    step!()
  end
  # `CUDA.@allocated` counts the bytes allocated during the call, whatever is freed after.
  return Base.invokelatest(() -> Core.eval(Main, :($(cuda).@allocated $(step!)())))
end


@testset "the time loop allocates nothing on the device that grows with the run" begin
  if CUDA_MODULE === nothing
    @warn "device hot loop: no functional CUDA in this environment, so the device-side allocation of " *
          "a step was not measured. It is SKIPPED, not passed."
    @test_skip false
  else
    untracked = device_bytes_per_step(CUDA_MODULE, 0)
    tracked = device_bytes_per_step(CUDA_MODULE, TRACERS)
    @info "device hot loop: bytes allocated per step" untracked tracked
    @test untracked < BOUND                       # the fields: nothing at field scale
    @test tracked < BOUND                         # the tracers: nothing of size M (PF decision 95)
  end
end

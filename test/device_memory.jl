# The device memory a run holds, predicted from the ledgers and measured on the GPU's memory pool
# (the memory plan's GPU leg, item 1).
#
# The prediction is the bytes of every device array a live run reaches, each counted once by its
# storage: the walk the memory audit's ledgers are built on, which `test/memory_audit.jl` holds equal
# to the frozen tables cell by cell. The measurement is the CUDA memory pool's used memory, which knows
# nothing of the walk, so the two have independent origins. They must agree: a pool holding more than
# the walk reaches is memory no ledger accounts for; one holding less is a stale walk.
#
# Read after synchronizing, collecting garbage and reclaiming the pool, so a reading is the live
# memory, not uncollected garbage. The stepping stage is measured by the pool's used high-water mark,
# reset just before the steps: the peak of a step above what the run holds is the step's temporary.
#
# CUDA only, and with no functional CUDA a visible skip, never a pass.
using Test
using GBGHomogeneousTurbulence
using Random
using Logging

include("audit_ops.jl")

const CUDA_MODULE = let found = nothing
  id = Base.identify_package("CUDA")
  if id !== nothing
    m = try Base.require(id) catch; nothing end
    m !== nothing && (try Base.invokelatest(getproperty(m, :functional)) catch; false end) && (found = m)
  end
  found
end

# Every device array reachable from `x`, counted once by storage, in bytes.
function walked_bytes(x)
  arrays = collect_field_arrays!(AbstractArray[], x, Set{UInt}(), 0; keep = a -> !(a isa Array))
  return sum(sizeof, arrays; init = 0)
end

# The pool readings, through the public handle taken after a first allocation (a handle taken before
# it is the driver's stock pool, whose statistics never move).
struct Pool
  cuda::Module
  handle::Any
end
function Pool(cuda)
  Base.invokelatest(getproperty(cuda, :zeros), Float32, 1)
  Pool(cuda, Base.invokelatest(getproperty(cuda, :memory_pool), Base.invokelatest(getproperty(cuda, :device))))
end
_attribute(p::Pool, name) =
  Int(Base.invokelatest(getproperty(p.cuda, :attribute), UInt64, p.handle, getproperty(p.cuda, name)))
used(p::Pool) = _attribute(p, :MEMPOOL_ATTR_USED_MEM_CURRENT)
peak(p::Pool) = _attribute(p, :MEMPOOL_ATTR_USED_MEM_HIGH)
reset_peak!(p::Pool) =
  Base.invokelatest(getproperty(p.cuda, :attribute!), p.handle, getproperty(p.cuda, :MEMPOOL_ATTR_USED_MEM_HIGH), UInt64(0))
function settle!(p::Pool)
  Base.invokelatest(getproperty(p.cuda, :synchronize))
  GC.gc(true)
  Base.invokelatest(getproperty(p.cuda, :reclaim))
  Base.invokelatest(getproperty(p.cuda, :synchronize))
end

# One configuration: the run's bytes as the walk predicts them, as the pool holds them once built,
# and the pool's peak over a few steps beyond what the run holds.
function readings(p::Pool, N, T; kwargs...)
  settle!(p)
  baseline = used(p)
  sim = with_logger(NullLogger()) do
    Simulation(grid_points_per_axis = N, viscosity = 0.05, element_type = T,
               array_type = getproperty(p.cuda, :CuArray), rng = Xoshiro(1); kwargs...)
  end
  advance!(sim; dt = 1e-3)                  # compile and fill every slot before measuring
  settle!(p)
  held = used(p) - baseline
  predicted = walked_bytes(sim)
  reset_peak!(p)
  for _ in 1:3
    advance!(sim; dt = 1e-3)
  end
  Base.invokelatest(getproperty(p.cuda, :synchronize))
  step_excess = peak(p) - baseline - held
  sim = nothing
  settle!(p)
  return (; predicted, held, step_excess)
end

const CONFIGURATIONS = [
  ("default", ()),
  ("scalar", (scalar = true,)),
  ("PhaseShift", (dealiasing = PhaseShift(),)),
  ("HouLi", (dealiasing = HouLi(),)),
  ("IFHeun", (field_integration_scheme = IFHeun(),)),
  ("IFLowStorageRK4", (field_integration_scheme = IFLowStorageRK4(),)),
  ("IFSSPRK3", (field_integration_scheme = IFSSPRK3(),)),
  ("Linear", (velocity_forcing = Linear(rate = 0.1),)),
  ("StochasticOU", (velocity_forcing = StochasticOU(forcing_variance = 0.1, correlation_time_in_box_units = 0.5),)),
  ("tracers", (number_of_particles = 4096,)),
]
# A held figure within this of the prediction agrees: the pool rounds an allocation to its own
# granularity, and a run holds a few small host-side-launched arrays below the walk's notice.
const HELD_TOLERANCE = 0.01                 # relative
const STEP_TOLERANCE = 64 * 1024            # bytes a step may hold above the run, launch bookkeeping


@testset "a run's device memory, predicted from the ledgers and measured on the pool" begin
  if CUDA_MODULE === nothing
    @warn "device memory: no functional CUDA in this environment, so the pool was not measured. " *
          "It is SKIPPED, not passed."
    @test_skip false
  else
    p = Pool(CUDA_MODULE)
    for N in (64, 128), T in (Float32, Float64), (name, kwargs) in CONFIGURATIONS
      r = readings(p, N, T; kwargs...)
      @info "device memory, $name, $(N)³ $T" predicted_MiB = r.predicted / 2^20 held_MiB = r.held / 2^20 step_excess_KiB = r.step_excess / 2^10
      @test abs(r.held - r.predicted) <= HELD_TOLERANCE * r.predicted
      if name == "tracers"
        @test_broken r.step_excess <= STEP_TOLERANCE     # PF's in-place displace! copy, see device_hot_loop.jl
      else
        @test r.step_excess <= STEP_TOLERANCE
      end
    end
  end
end

# A run fits in the device memory the ledgers predict, and not in much less — tested in fresh
# processes under CUDA.jl's hard memory limit (the memory plan's GPU leg, item 3).
#
# The prediction for the default run is the largest, over its stages, of the resident set when the
# stage runs plus the stage's device temporary: the bytes of every device array the run then reaches
# (held equal to the pool in `device_memory.jl`), and the seeding noise field, 3 N³ elements, while
# the run is being seeded (the device column of the temporary ledger). The limit is read once per process and baked into the pool at its first use, so
# each limit needs a fresh `julia` process. It governs the pool only; the memory outside it — cuFFT's
# workspace and the loaded kernels — is not counted against it.
#
# The pool reserves memory in 32 MiB chunks (measured 2026-10-01), so the limit is effectively rounded
# up to a chunk, and both the fitting margin and the tightness margin must exceed one: the run must
# complete under the prediction plus 64 MiB, and must run out of memory under the prediction less
# 96 MiB. At 256³ / Float32 the prediction is about 1.5 GiB, so the margins are a few percent of it
# and the tightness run is meaningful; at smaller grids a chunk is a large share of the whole.
#
# CUDA only, and with no functional CUDA a visible skip, never a pass. The fresh processes take the
# active project, which must provide CUDA as this one does.
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

const N = 256
const T = Float32
const MiB = 2^20

# The run a fresh process builds and steps; it prints DONE when it gets through.
const DRIVER = """
using CUDA, GBGHomogeneousTurbulence, Random, Logging
CUDA.zeros(Float32, 1); CUDA.synchronize()
free_before = first(CUDA.memory_info())             # the context is in place, nothing else
pool = CUDA.memory_pool(CUDA.device())
reserved() = Int(CUDA.attribute(UInt64, pool, CUDA.MEMPOOL_ATTR_RESERVED_MEM_CURRENT))
reserved_before = reserved()
sim = with_logger(() -> Simulation(grid_points_per_axis = $N, viscosity = 0.05, element_type = $T,
                                   array_type = CuArray, rng = Xoshiro(1)), NullLogger())
for _ in 1:3
  advance!(sim; dt = 1e-3)
end
CUDA.synchronize()
outside = (free_before - first(CUDA.memory_info())) - (reserved() - reserved_before)
println("OUTSIDE=", outside)
println("DONE")
"""

const LAST_OUTSIDE = Ref(0)

# The memory outside the pool — cuFFT's workspace and the loaded kernel modules, measured in the
# fitting run as the driver's free memory consumed beyond what the pool reserved. The limit does not
# govern it, so a card must hold it beside P. Frozen 2026-10-02 on the RTX 5070 Ti at 256³ / Float32.
const OUTSIDE_FROZEN_MiB = 34         # 34 at 128³ too: kernels and library state, not field-sized
const OUTSIDE_TOLERANCE_MiB = 16

# Run the driver in a fresh process under a hard limit of `limit` bytes: :done, :out_of_memory, or
# the failure's last line.
function run_limited(limit)
  command = addenv(`$(Base.julia_cmd()) --project=$(Base.active_project()) --startup-file=no -e $DRIVER`,
                   "JULIA_CUDA_HARD_MEMORY_LIMIT" => string(limit))
  output = IOBuffer()
  ok = success(pipeline(ignorestatus(command); stdout = output, stderr = output))
  text = String(take!(output))
  m = match(r"OUTSIDE=(-?\d+)", text)
  m === nothing || (LAST_OUTSIDE[] = parse(Int, m.captures[1]))
  occursin("DONE", text) && return :done
  occursin("Out of GPU memory", text) && return :out_of_memory      # how CUDA.jl prints the error
  return Symbol(last(split(strip(text), '\n')))
end

# The prediction, from the walk of a live run in this process, stage by stage (the plan's theorem:
# the peak is the largest of each stage's resident set plus its temporary). The seeding noise field
# lives while only the domain and the state exist — the cache, the generator and the buffers come
# after — so it is added to those, not to the whole run; the whole run's resident set is the other
# candidate, a step adding nothing at field scale.
device_bytes(x) = sum(sizeof, collect_field_arrays!(AbstractArray[], x, Set{UInt}(), 0;
                                                    keep = a -> !(a isa Array)); init = 0)
function predicted_bytes(cuda)
  sim = with_logger(NullLogger()) do
    Simulation(grid_points_per_axis = N, viscosity = 0.05, element_type = T,
               array_type = getproperty(cuda, :CuArray), rng = Xoshiro(1))
  end
  seeding_stage = device_bytes((sim.domain, sim.state)) + 3 * sizeof(T) * N^3
  whole_run = device_bytes(sim)
  return (; P = max(seeding_stage, whole_run), seeding_stage, whole_run)
end


@testset "a run fits in the predicted device memory, and not in much less" begin
  if CUDA_MODULE === nothing
    @warn "device limits: no functional CUDA in this environment, so the fresh-process limit runs did " *
          "not run. They are SKIPPED, not passed."
    @test_skip false
  else
    prediction = predicted_bytes(CUDA_MODULE)
    P = prediction.P
    GC.gc(true); Base.invokelatest(getproperty(CUDA_MODULE, :reclaim))
    tight = run_limited(P - 96 * MiB)
    fits = run_limited(P + 64 * MiB)              # last, so the outside figure is a completed run's
    @info "device limits, $(N)³ $T" predicted_MiB = P / MiB seeding_stage_MiB = prediction.seeding_stage / MiB whole_run_MiB = prediction.whole_run / MiB fits_under_P_plus_64_MiB = fits tight_under_P_minus_96_MiB = tight
    @info "device limits: memory outside the pool" outside_MiB = LAST_OUTSIDE[] / MiB
    @test fits === :done
    @test tight === :out_of_memory
    @test abs(LAST_OUTSIDE[] / MiB - OUTSIDE_FROZEN_MiB) <= OUTSIDE_TOLERANCE_MiB
  end
end


# ---------------------------------------------------------------- host memory, one-sided

# The host side of the same run, in a fresh process under a cgroup cap (`systemd-run --user --scope`,
# swap off, which kills a process above the cap). The prediction is the peak resident set of the
# same driver at 16³, where the fields are negligible and the peak is Julia, CUDA and the package
# loaded and compiled, plus the 256³ host draw of the seeding, 3 N³ elements. Measured 2026-10-02:
# 1874.6 + 192 = 2066.6 MiB predicted against 2062.3 measured.
#
# ONE-SIDED, and the reason is measured: the peak resident set is an upper estimate of what the run
# needs, not the need. Under a cap the kernel evicts the libraries' file-backed pages and the run
# still completes at P − 512 MiB; it stops completing only between P − 1024 and P − 512. So a fitting
# run is meaningful and a tightness run is not; the check fails when host memory grows past the
# prediction plus the margin.
host_driver(n) = """
using CUDA, GBGHomogeneousTurbulence, Random, Logging
sim = with_logger(() -> Simulation(grid_points_per_axis = $n, viscosity = 0.05, element_type = $T,
                                   array_type = CuArray, rng = Xoshiro(1)), NullLogger())
for _ in 1:3
  advance!(sim; dt = 1e-3)
end
CUDA.synchronize()
hwm = parse(Int, split(only(filter(l -> startswith(l, "VmHWM"), readlines("/proc/self/status"))))[2]) * 1024
println("HWM=", hwm)
println("DONE")
"""

function run_host(n; cap = nothing)
  julia = `$(Base.julia_cmd()) --project=$(Base.active_project()) --startup-file=no -e $(host_driver(n))`
  command = cap === nothing ? julia :
            `systemd-run --user --scope -q -p MemoryMax=$cap -p MemorySwapMax=0 $julia`
  output = IOBuffer()
  run(pipeline(ignorestatus(command); stdout = output, stderr = output))
  text = String(take!(output))
  m = match(r"HWM=(\d+)", text)
  return (done = occursin("DONE", text), peak = m === nothing ? nothing : parse(Int, m.captures[1]))
end

@testset "the run's host memory fits the prediction" begin
  if CUDA_MODULE === nothing || Sys.which("systemd-run") === nothing
    @warn "host limits: no functional CUDA or no systemd-run in this environment, so the capped host " *
          "run did not run. It is SKIPPED, not passed."
    @test_skip false
  else
    baseline = run_host(16).peak
    predicted = baseline + 3 * sizeof(T) * N^3
    fits = run_host(N; cap = predicted + 128 * MiB)
    @info "host limits, $(N)³ $T" baseline_MiB = baseline / MiB predicted_MiB = predicted / MiB completed_under_P_plus_128_MiB = fits.done
    @test fits.done
  end
end

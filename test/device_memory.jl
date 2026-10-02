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
using HDF5

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
  # the scaling axes beyond N: the tracer count M, the multistep order K, the stochastic band
  ("tracers M = 32768", (number_of_particles = 32768,)),
  ("tracers M = 262144", (number_of_particles = 262144,)),
  ("AdamsBashforth K = 2", (number_of_particles = 4096, particle_integration_scheme = AdamsBashforth(order = 2))),
  ("AdamsBashforth K = 4", (number_of_particles = 4096, particle_integration_scheme = AdamsBashforth(order = 4))),
  ("StochasticOU band 1–4", (velocity_forcing = StochasticOU(forcing_variance = 0.1, correlation_time_in_box_units = 0.5,
                                                             highest_shell = 4),)),
  ("StochasticOU band 1–8", (velocity_forcing = StochasticOU(forcing_variance = 0.1, correlation_time_in_box_units = 0.5,
                                                             highest_shell = 8),)),
]
# The full product of the strategy axes — every field scheme, dealiasing strategy, scalar setting and
# velocity forcing — runs only when asked for, `DEVICE_FULL_SWEEP=1`, since it builds hundreds of runs.
if get(ENV, "DEVICE_FULL_SWEEP", "") == "1"
  for scheme in (IFLowStorageRK3(), IFLowStorageRK4(), IFSSPRK3(), IFHeun()),
      dealiasing in (TwoThirds(), HouLi(), PhaseShift()), scalar in (false, true),
      forcing in (NoForcing(), ConstantPower(injection_rate = 0.1), VarianceController(target = 1.5),
                  VarianceRescaling(target = 1.5, over = :total), Linear(rate = 0.1),
                  StochasticOU(forcing_variance = 0.1, correlation_time_in_box_units = 0.5))
    push!(CONFIGURATIONS, ("$(nameof(typeof(scheme))) $(nameof(typeof(dealiasing))) scalar=$scalar $(nameof(typeof(forcing)))",
                           (field_integration_scheme = scheme, dealiasing, scalar, velocity_forcing = forcing)))
  end
end
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
      @test r.step_excess <= STEP_TOLERANCE
    end
  end
end


# ---------------------------------------------------------------- the device temporaries

# What a call allocates on the device beyond what it keeps, in N³ elements of the run's precision —
# the device column of the temporary ledger (`test/temporary_audit.jl` is the CPU's). The CPU
# figures do not transfer: the domain's planning is 2.0 here against the CPU's 3.1, and seeding's
# noise field is device memory, with the host draw beside it in host memory. The result is kept live
# while "kept" is read; a dead result is collected, and its whole size then reads as transient (the
# probe's first version did exactly that).
function device_transient(p::Pool, f, N, T)
  quiet() = with_logger(f, NullLogger())
  quiet(); settle!(p)
  base = used(p)
  reset_peak!(p)
  r = quiet()
  Base.invokelatest(getproperty(p.cuda, :synchronize))
  high = peak(p) - base
  GC.gc(true)
  Base.invokelatest(getproperty(p.cuda, :reclaim))
  kept = used(p) - base
  Base.donotdelete(r)
  return (high - kept) / (sizeof(T) * N^3)
end

# Frozen 2026-10-02 on the RTX 5070 Ti at 64³ and 128³, both precisions; each holder is the CPU
# row's (test/audit_ops.jl). Every other row measured reads zero, and must.
const DEVICE_TEMPORARIES = Dict(
  "FixedDomain" => 2.03,                 # TRANSFORM PLANNING: the planner's prototypes
  "Simulation" => 3.0,                   # SEEDING NOISE FIELD: the device noise vector
  "Simulation/scalar" => 4.0,            # …and the scalar's
  "derivative_skewness" => 18.3,         # FULL STRAIN TENSORS
  "read_simulation" => 2.6,              # the domain it builds, and the restore's small arrays
)
const DEVICE_TOLERANCE = 0.4             # N³ elements: read_simulation's small arrays vary with N

@testset "the device temporaries, measured on the pool" begin
  if CUDA_MODULE === nothing
    @warn "device temporaries: no functional CUDA in this environment, so they were not measured. " *
          "It is SKIPPED, not passed."
    @test_skip false
  else
    p = Pool(CUDA_MODULE)
    cu = getproperty(CUDA_MODULE, :CuArray)
    for T in (Float32, Float64), N in (64, 128)
      d = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(), element_type = T,
                      array_type = cu)
      sim = with_logger(() -> Simulation(d; viscosity = 0.05, scalar = true, number_of_particles = 64,
                                         rng = Xoshiro(1)), NullLogger())
      advance!(sim; dt = 1e-3)
      û, φ̂ = sim.state.velocity_spectral, sim.state.scalar_spectral
      path = tempname() * ".h5"
      h5open(f -> write_simulation(f, "run", sim), path, "w")
      rows = [
        "FixedDomain" => () -> FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                                           element_type = T, array_type = cu),
        "Simulation" => () -> Simulation(d; viscosity = 0.05, rng = Xoshiro(1)),
        "Simulation/scalar" => () -> Simulation(d; viscosity = 0.05, scalar = true, rng = Xoshiro(1)),
        "derivative_skewness" => () -> derivative_skewness(û, d),
        "read_simulation" => () -> h5open(f -> read_simulation(f, "run"; array_type = cu), path, "r"),
        "energy_spectrum" => () -> energy_spectrum(û, d),
        "integral_scale" => () -> integral_scale(û, d),
        "flow_parameters" => () -> flow_parameters(sim),
        "dissipation" => () -> dissipation(û, d, 0.05),
        "scalar_dissipation" => () -> scalar_dissipation(φ̂, d, 0.05),
        "write_simulation" => () -> h5open(f -> write_simulation(f, "s", sim), tempname(), "w"),
        "read_state" => () -> h5open(f -> read_state(f, "run/state", d), path, "r"),
      ]
      for (name, f) in rows
        measured = device_transient(p, f, N, T)
        expected = get(DEVICE_TEMPORARIES, name, 0.0)
        @info "device temporary, $name, $(N)³ $T" measured expected
        @test abs(measured - expected) <= DEVICE_TOLERANCE
      end
    end
  end
end

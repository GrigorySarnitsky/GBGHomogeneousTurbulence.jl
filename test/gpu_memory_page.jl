# The GPU memory page holds the code to a number: its sizing table says how many bytes a run keeps per
# grid point, and a reader plans a grid on a card from it. A table typed into a page drifts the first
# time a buffer is added, and nothing would say so — so this file reads the table OUT OF THE PAGE and
# re-derives every cell from a live `Simulation` (decision 89).
#
# The method is exact, not a fit. For even N a run's resident storage is a polynomial in N of degree
# three: every array it holds has a shape that is a product of N, N ÷ 2 + 1 and constants, and N ÷ 2 + 1
# is affine in N only within one parity — hence even fit sizes, and a page that says "N even". Four sizes therefore
# determine the polynomial, and a fifth size that it must reproduce BYTE FOR BYTE checks that claim
# rather than assuming it. The leading coefficient is the table's bytes per grid point; the polynomial
# evaluated at 512³, 768³ and 1024³ is its GiB columns, rounded as the page rounds them.
#
# What this cannot see: the CUDA transform library's workspace and the device allocator's rounding,
# which the page states separately as measured once, and never as pinned.
#
# `GPU_MEMORY_PRINT=1` prints the table as the page should carry it, for a deliberate update.

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Propagator: AbstractIntegrator
using GBGHomogeneousTurbulence.Forcing: AbstractForcing
using Random: MersenneTwister
using Logging: NullLogger, with_logger


const PAGE = joinpath(pkgdir(GBGHomogeneousTurbulence), "docs", "src", "gpu.md")
const FIT_SIZES = (32, 40, 48, 56)
const CHECK_SIZE = 64


# Every array a run can reach is counted once, the way `summarysize` walks an object graph.
resident_bytes(N; kwargs...) = with_logger(NullLogger()) do
  Base.summarysize(Simulation(; grid_points_per_axis = N, κ_max_η = 1.5, rng = MersenneTwister(1),
                              kwargs...))
end


# The exact cubic through the four fit sizes, returned as an evaluator plus its leading coefficient.
function resident_polynomial(; kwargs...)
  V = Rational{BigInt}[big(N)^p for N in FIT_SIZES, p in 0:3]
  y = Rational{BigInt}[resident_bytes(N; kwargs...) for N in FIT_SIZES]
  c = V \ y
  evaluate(N) = sum(c[p + 1] * big(N)^p for p in 0:3)
  return (evaluate = evaluate, leading = c[4])
end


gib(bytes) = round(Float64(bytes / 2^30); digits = 1)

const ROW = r"^\| `(TwoThirds|PhaseShift)\(\)` \| `(Float32|Float64)` \| (no|yes) \| (\d+) \| ([\d.]+) GiB \| ([\d.]+) GiB \| ([\d.]+) GiB \|$"
const DEALIASING = Dict("TwoThirds" => TwoThirds(), "PhaseShift" => PhaseShift())
const PRECISION = Dict("Float32" => Float32, "Float64" => Float64)


@testset "GPU memory page: the sizing table" begin
  rows = [m for m in (match(ROW, line) for line in eachline(PAGE)) if m !== nothing]
  # The denominator: two dealiasing strategies × two precisions × with and without the scalar.
  @test length(rows) == 8
  @test Set((m[1], m[2], m[3]) for m in rows) ==
        Set((d, T, s) for d in ("TwoThirds", "PhaseShift"), T in ("Float32", "Float64"), s in ("no", "yes"))

  printing = get(ENV, "GPU_MEMORY_PRINT", "") == "1"
  for m in rows
    settings = (dealiasing = DEALIASING[m[1]], element_type = PRECISION[m[2]], scalar = m[3] == "yes")
    poly = resident_polynomial(; settings...)
    @testset "$(m[1]) $(m[2]) scalar=$(m[3])" begin
      @test poly.evaluate(CHECK_SIZE) == resident_bytes(CHECK_SIZE; settings...)   # the cubic is exact
      @test poly.leading == parse(Int, m[4])
      @test [gib(poly.evaluate(N)) for N in (512, 768, 1024)] == parse.(Float64, [m[5], m[6], m[7]])
    end
    printing && println("| `$(m[1])()` | `$(m[2])` | $(m[3]) | $(Int(poly.leading)) | ",
                        join(("$(gib(poly.evaluate(N))) GiB" for N in (512, 768, 1024)), " | "), " |")
  end
end


# The page says which settings leave the table unchanged and which add storage. Each exported
# integrator, forcing and dealiasing strategy is classified here, and an unclassified one fails; every
# setting classified as adding storage must also be named on the page.
@testset "GPU memory page: which settings the table covers" begin
  reference = resident_polynomial().leading   # `TwoThirds()`, `Float64`, no scalar: the defaults
  # The exported non-abstract types under each abstract type (parametric ones included) — what a user can pass.
  exported(A) = Set(n for n in names(GBGHomogeneousTurbulence)
                    if (T = getfield(GBGHomogeneousTurbulence, n)) isa Type && T <: A && !isabstracttype(Base.unwrap_unionall(T)))

  # Keyed by type name: a forcing's keyword form returns a wrapper awaiting the domain, so the value
  # does not carry the name the page uses.
  integrators = [:IFLowStorageRK3 => (IFLowStorageRK3(), :same), :IFLowStorageRK4 => (IFLowStorageRK4(), :same),
                 :IFSSPRK3 => (IFSSPRK3(), :same), :IFHeun => (IFHeun(), :more)]
  @test Set(first.(integrators)) == exported(AbstractIntegrator)

  forcings = [:NoForcing => (NoForcing(), :same),
              :ConstantPower => (ConstantPower(injection_rate = 0.1), :same),
              :VarianceController => (VarianceController(target = 0.5), :same),
              :VarianceRescaling => (VarianceRescaling(target = 0.5, over = :band), :same),
              :Linear => (Linear(rate = 0.1), :more),
              :StochasticOU => (StochasticOU(forcing_variance = 0.1, correlation_time = 0.5), :same)]
  @test Set(first.(forcings)) == exported(AbstractForcing)

  strategies = [:HouLi => (HouLi(), :same), Symbol("HouLi(materialized = true)") => (HouLi(materialized = true), :more)]
  @test Set([:TwoThirds, :PhaseShift, :HouLi]) ==   # the table's two strategies, and `HouLi` above
        exported(GBGHomogeneousTurbulence.DealiasingStrategy)

  page = read(PAGE, String)
  for (name, (_, verdict)) in [integrators; forcings; strategies]
    verdict === :more && @test occursin(string('`', name, '`'), page)
  end

  for (kwarg, table) in ((:field_integration_scheme, integrators), (:velocity_forcing, forcings),
                         (:dealiasing, strategies))
    for (name, (setting, verdict)) in table
      leading = resident_polynomial(; kwarg => setting).leading
      @testset "$name" begin
        verdict === :same ? (@test leading == reference) : (@test leading > reference)
      end
    end
  end
end


const TRACER_SENTENCE = r"a `Float32` run holds (\d+) bytes per tracer and a `Float64` run (\d+)"

@testset "GPU memory page: bytes per tracer" begin
  m = match(TRACER_SENTENCE, read(PAGE, String))
  @test m !== nothing
  for (T, stated) in ((Float32, m[1]), (Float64, m[2]))
    per_tracer = (resident_bytes(32; element_type = T, number_of_particles = 40_000) -
                  resident_bytes(32; element_type = T, number_of_particles = 10_000)) / 30_000
    @test per_tracer == parse(Int, stated)
  end
end

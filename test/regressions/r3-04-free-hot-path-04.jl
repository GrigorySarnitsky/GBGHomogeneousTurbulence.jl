# Architecture probe (evidence, not a pass/fail regression test).
#
# A `DealiasingStrategy` is consumed by FOUR internal hooks. THREE refuse to answer for a
# strategy that has not declared itself (`_retained_nyquist_fraction`, `_build_dealias` — both
# with concrete-type methods only). The FOURTH, the nonlinear assembly, dispatches on the
# ABSTRACT supertype (`_velocity_nonlinear!(::DealiasingStrategy, …)` Generator.jl:370,
# `_scalar_nonlinear!(::DealiasingStrategy, …)` Generator.jl:518) with `PhaseShift` the only
# override — so an unrecognized strategy is SILENTLY given the single-evaluation MASK treatment.
#
# The sibling axis states the opposite discipline explicitly, in Propagator.jl:578:
#   "NO `::AbstractIntegrator` FALLBACK, matching `allocate_buffers` on the same supertype: a
#    scheme that has not declared its stability limit gets a hard error, not a number."
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, DealiasingStrategy, TwoThirds,
                                               _retained_nyquist_fraction, _build_dealias,
                                               spectral_cutoff
using GBGIsotropicTurbulence.Generator: _velocity_nonlinear!, _scalar_nonlinear!
using GBGIsotropicTurbulence.SimulationRun: Simulation, advance!

# (1) A brand-new strategy that has declared NOTHING — which hooks answer for it anyway?
struct ProbeBare <: DealiasingStrategy end

println("=== hooks answering for a strategy that declared NOTHING ===")
for (name, answers) in (
      ("_retained_nyquist_fraction", hasmethod(_retained_nyquist_fraction, Tuple{ProbeBare})),
      ("_build_dealias",             hasmethod(_build_dealias, Tuple{ProbeBare, Any, Any, Any, Any, Type{Float64}})),
      ("_velocity_nonlinear!",       hasmethod(_velocity_nonlinear!, Tuple{ProbeBare, Any, Any, Any, Any, Any, FixedDomain})),
      ("_scalar_nonlinear!",         hasmethod(_scalar_nonlinear!, Tuple{ProbeBare, Any, Any, Any, Any, Any, Any, FixedDomain, Bool})))
  println(rpad(name, 28), " hasmethod = ", answers, answers ? "   <-- ANSWERS (abstract catch-all)" : "   (refuses)")
end

# (2) The maintenance consequence: an author adding a padding (3/2-rule) strategy supplies the
#     two hooks that HARD-ERROR at them, and never learns the assembly needed one too.
struct ProbePad <: DealiasingStrategy end
GBGIsotropicTurbulence.SimulationDomain._retained_nyquist_fraction(::ProbePad) = 2 // 3
GBGIsotropicTurbulence.SimulationDomain._build_dealias(::ProbePad, reference, multipliers, N, L, ::Type{T}) where {T} =
  spectral_cutoff(multipliers, T(2 // 3) * (N / 2) * (2π / L))

println()
println("=== a run on the undeclared strategy, with only the two refusing hooks supplied ===")
domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                     dealiasing = ProbePad(), element_type = Float64, array_type = Array)
sim = Simulation(domain; viscosity = 0.05)
advance!(sim); advance!(sim)
println("Simulation(domain; viscosity = 0.05) + advance! x2 -> COMPLETED, no error")
println("  clock            = ", sim.clock)
println("  assembly reached = ", hasmethod(_velocity_nonlinear!,
          Tuple{ProbePad, Any, Any, Any, Any, Any, FixedDomain}),
        "  (the MASK assembly answered for a strategy that never declared one)")

# (3) The sibling axis, for contrast: the SAME shape of undeclared subtype hard-errors.
println()
println("=== the sibling axis (Propagator), for contrast ===")
using GBGIsotropicTurbulence.Propagator: AbstractIntegrator, recommended_cfl, allocate_buffers
struct ProbeScheme <: AbstractIntegrator end
for (name, f) in (("recommended_cfl",  () -> recommended_cfl(ProbeScheme(), domain)),
                  ("allocate_buffers", () -> allocate_buffers(ProbeScheme(), domain)))
  print(rpad(name, 28), " ProbeScheme -> ")
  try
    f(); println("RETURNED (no error)")
  catch e
    println(typeof(e), "   (refuses to guess)")
  end
end

# Closure audit — 04-dns-practitioner

## Finding 1 — HouLi f=1 "resolves a finer η" claim leans on inexact spectral content
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:111-113` — "a wider-band strategy (larger `f`) resolves a finer
dissipation scale `η` on the same grid at the same `k_max_η` — which credits the whole retained band
as clean signal, exact for `TwoThirds` and `PhaseShift`, approximate for `HouLi`, whose top of band
is damped rather than exactly dealiased." The exact caveat the finding's resolution hint asked for is
now present at the site of the formula. Cross-checked `HouLi`'s own docstring
(`src/SimulationDomain.jl:81`, "only damps aliasing rather than removing it exactly — a
stabilization") — unchanged, still consistent with the new caveat, no regression introduced.

---

## Finding 2 — `max_speed` reduction/readback unconditional under fixed `dt`, undocumented
**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:473-475`, `deposit!` docstring — "its pass counts are unchanged but for
one: the maximum-speed reduction runs every iteration, including under a hand-fixed `Δt` that never
reads it." This is one of the two pages the finding named (`deposit!`), stating exactly the cost and
condition the finding asked to surface. `advance!` (`src/SimulationRun.jl:355-361`) itself still
doesn't repeat the note, but the resolution hint asked for it on "`advance!` **or** `deposit!`" and
`deposit!` now carries it.

---

## Finding 3 — `IFRK2`'s CFL ceiling (0.25) presented without derivation or ν-dependence caveat
**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:526-528`, `recommended_cfl` docstring — "`IFRK2` is imaginary-axis
unstable (`y_s = 0`, relying on viscous damping), which makes the formula degenerate — its `0.25` is
an empirical margin, not a computed limit, and the damping it leans on weakens as `ν` falls." Matches
the finding's resolution hint (state it's an empirical margin, not a stability-limit computation)
essentially verbatim, including the explicit ν-dependence caveat.

---

## Finding 4 — "24 bytes moved" traffic estimate silently Float64-only
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:43` — "...against twenty-four bytes moved in double
precision (twelve in single)." Matches the finding's exact resolution hint wording. (Note: the
adjacent flop count changed from "ten" to "one" arithmetic operations per point — an unrelated edit,
not part of this finding's scope, not evaluated here.)

---

## Finding 5 — "five operations" lead-in doesn't match the four clauses that follow
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:279-284` — the "five operations" lead-in phrase is gone
entirely; the passage now reads "one **evaluation** of the velocity term proceeds as follows: recover
`u` (3 inverse transforms); form `ω̂` and recover `ω` (3 inverse); multiply pointwise ... and
transform it back (3 forward); apply `P` and the mask..." with no operation count claimed up front —
matches the finding's resolution hint ("drop the 'five operations' lead-in").

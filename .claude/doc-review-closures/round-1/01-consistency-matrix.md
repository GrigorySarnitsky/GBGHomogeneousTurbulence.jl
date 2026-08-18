# Closure audit — hat: 01-consistency-matrix

## Finding 1 — Two decision-log entries disagree about what "decision 46's pattern" is

**VERDICT: ABSENT**

**Evidence:** `docs/ARCHITECTURE.md:1628` (decision 47) now reads "...an f/`f!` **pair**, not
decision 46's single dispatched generic, and the difference is structural rather than a drift:
`max_speed` is a pure reduction... Decision 46's one-generic rule therefore governs reductions; a
field-valued observable takes the pair." The phrase "decision 46's pattern implies" no longer
exists anywhere (`grep -n "pattern implies\|decision 46's pattern" docs/ARCHITECTURE.md` → no
hits). Decision 47 now argues its own naming shape from first principles instead of misattributing
it to decision 46, resolving the contradiction against §4.3.

---

## Finding 2 — `tracer_scheme`'s stated default drops the parens every sibling default keeps

**VERDICT: NOT-A-DEFECT**

**Evidence:** `GBGPeriodicFields/src/Interpolation.jl:345`: `const CatmullRom = LalescuSpline(1, 1)`
— `CatmullRom` is genuinely a bound singleton value, not a type, so the bare (no-parens) form is
the *correct* literal default, unlike `TwoThirds()`/`IFLowStorageRK3()`/`EndpointHeun()` which are
constructor calls on types. `src/Particles.jl:59-61` now states this explicitly: "a ready-made
value rather than a type, so it is passed bare." `src/SimulationRun.jl:226` confirms the code
default is literally `interpolation_scheme = CatmullRom` (bare). The original finding's premise —
that every strategy default "needs an instance... not the bare type" — was false for this one
binding; the docs now say so directly.

---

## Finding 3 — Three descriptions of what makes `particle_velocities` readable name three different actors

**VERDICT: ABSENT**

**Evidence:** All three docstrings now converge on one producer. `src/Particles.jl:227-230`
(`record_trajectory_velocity!`): "**This call is that slot's only producer**: it sets both of the
epochs the slot is checked against... Every other mention of the slot going fresh names some
caller of this function." `src/Cache.jl:311-314` (`particles_modified!`): "...then
`record_trajectory_velocity!`... — the slot's only producer, and what sets both of its epochs —
before advancing." `src/Propagator.jl:478-480` (`deposit!`): "The particle-velocities slot is
**not** among them... it is filled by `record_trajectory_velocity!`... which `advance!` and the
`deposit!(sim)` form above both do for you." One home (`record_trajectory_velocity!`), two
consistent pointers.

---

## Finding 4 — "the developed-turbulence markers" (plural) names only one built marker

**VERDICT: ABSENT**

**Evidence:** `docs/src/index.md:95` and `docs/src/api.md:12` both now read "the
developed-turbulence marker" (singular). `grep -rn "developed-turbulence" src/*.jl
docs/ARCHITECTURE.md docs/src/*.md` returns only these two singular occurrences; no plural form
survives anywhere in the corpus. Matches the single built observable, `derivative_skewness`
(`src/Observables.jl:15`).

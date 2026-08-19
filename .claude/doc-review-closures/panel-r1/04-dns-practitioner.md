# Closure — DNS-practitioner hat (04-dns-practitioner)

## Finding 1 — The cache's one non-free cost described as both per-iteration and per-run

**Verdict: PARTIAL**

Evidence: `docs/src/observables_cache.md` §1.4 (lines 191-200) now carries an explicit
disambiguating sentence added since the finding: "Those are two different costs and it is worth
keeping them apart: the maximum-speed reduction above recurs **every iteration**, while the only
work the cache adds over a cacheless solver is §1.3's final closing deposit ... paid **once per
run**." This resolves the finding's most severe citation — the apparent self-contradiction
*within* §1.4 itself (lines 193 vs 196-198), which now reads as two named, distinguished costs
rather than a flat contradiction. `src/Propagator.jl`'s `deposit!` docstring ("It costs one extra
pass: the maximum-speed reduction runs every iteration...") and `docs/ARCHITECTURE.md:1502-1504`
("once-per-iteration maximum-speed readback ... a hand-fixed-Δt iteration still pays it") both
still agree with "every iteration," unchanged.

**Surviving class:** `docs/src/observables_cache.md` §1.3 (lines 146-149) still lists "one
reduction" inside the bundle described as paid "per run rather than per iteration": *"the run pays
one extra closing deposit: the state-only share of one first-stage evaluation, **one reduction**,
and one interpolation, **per run rather than per iteration**."* This is the exact conflation the
finding named ("§1.3's summary sentence ... need[s] to stop lumping the max-speed reduction in
with the ... once-per-run ... argument") and it has not been rewritten — only §1.4's later
clarification defuses it for a reader who reads onward. A reader stopping at §1.3 still receives
the pre-fix framing.

---

## Finding 2 — `recommended_cfl` cannot express the one variable IFRK2's own stability depends on

**Verdict: PARTIAL**

Evidence: `src/Propagator.jl:544-549` now carries a new, explicit admonition not present at the
time of the finding: `!!! warning "The IFRK2 margin does not know the viscosity"` — stating
plainly that the function "takes no ν, by design ... but IFRK2's margin is the one value that
depends on a quantity it cannot see," that "the same `0.25` is returned at every Reynolds number
while the viscous damping it rests on weakens as ν falls," and instructing the reader to "verify
the step against a run that holds its energy, or set `cfl` yourself." This directly answers the
finding's documentation-visibility complaint.

**Surviving class:** the finding explicitly frames this as "a genuine numerical-safety gap in the
API surface ... not merely a documentation slip." The signature is unchanged —
`recommended_cfl(scheme::AbstractIntegrator, domain::FixedDomain)` at
`src/Propagator.jl:566-567` still takes no `viscosity`/`FlowConditions` argument, so the flat
`0.25` (`_base_cfl(::IFRK2) = 0.25`, line 561) is still returned identically at every Reynolds
number — the structural gap the finding centers on persists, now disclosed but not closed.

---

## Finding 3 — `max_speed`'s stated justification for being cached overstates its necessity

**Verdict: ABSENT**

Evidence: `src/Observables.jl:149-157` (admonition "Why this observable alone has a cached form")
now reads: *"The maximum speed qualifies because the run itself needs it: **on the adaptive-CFL
path** the next timestep is chosen from it, so the reduction happens whether or not anyone reads
the value. **Under a hand-fixed Δt nothing consumes it** and the pass is spent anyway — the
schedule is fixed when the cache is built and does not vary with how the run is driven."* This is
exactly the qualification the finding requested ("The justification is true only for the
adaptive-CFL path; stated flatly it reads as a stronger necessity claim..."). Confirmed present in
the rendered build at `docs/build/api/Observables/index.html` (search: "on the adaptive-CFL path").
No trace of the old flat "the run itself needs it" without qualification remains in
`src/Observables.jl` or the built page.

---

## Finding 4 — `IFRK2` called "cheaper" without the memory axis

**Verdict: PARTIAL**

Evidence: `docs/ARCHITECTURE.md:385-387` (§4.5, the location the finding quoted) is now fully
qualified: *"`IFRK2` (Heun) is a two-stage option, cheaper in transforms (two nonlinear evaluations
against three) but **dearer** in memory — three spectral registers per field against the
low-storage scheme's two — and imaginary-axis unstable..."* This resolves the finding's
architecture-page citation.

**Surviving class:** two more unqualified "cheaper" instances remain, one of them the finding's own
second cited location, verbatim unchanged:
- `src/Propagator.jl:29-30` (module docstring map): *"IFLowStorageRK3, IFRK2 — the schemes (RK3
  low-storage; IFRK2/Heun **a cheaper two-stage alternative**, imaginary-axis unstable)."* — no
  memory-axis caveat, identical wording to the finding's quote.
- `docs/src/api/Propagator.md:10-11`: *"The integrating-factor scheme supertype and its concretes
  — the third-order low-storage RK3, then **the cheaper**, imaginary-axis-unstable second-order
  Heun."* — likewise unqualified; confirmed present in
  `docs/build/api/Propagator/index.html`.

Both render on the API pages a DNS practitioner would read for scheme selection, so the
memory-axis omission the finding flagged is still live on two of its three (or three, counting the
decision-log entry) surfaces.

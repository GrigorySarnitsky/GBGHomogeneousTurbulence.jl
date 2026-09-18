# Fix audit — batch 43–49

Baseline: `0b3d58c`. Fix commit under audit: `4a03de9` (Panel fix pass, tier 2), preceded by
`752149e`/`5a6157f`/`2d981f8` (T7–T9, not implicated in this batch).

---

## 43 — Vocabulary defines the observation as "once per iteration"; the loop observes n+1 times

**Owner's ask (verbatim, via the panel finding):** the glossary's `observation` row said "it reads
the run once per iteration," undercounting relative to `run!`'s own claim of `n + 1` instants
(the seeded `t_0` read).

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `docs/src/notation.md:136` now reads: *"the callback a run is driven by: it reads
the run once at the start and once after every iteration — `n+1` readings over a run of `n`
iterations — and its return decides whether to continue."* Diff (`git diff 0b3d58c..HEAD --
docs/src/notation.md`) shows the flagged clause "once per iteration" replaced in place, not
appended beside — a correction, not an insertion. The new count matches `src/SimulationRun.jl:742`
verbatim ("A run of `n` iterations therefore observes `n + 1` instants"), so the two surfaces now
agree. `grep` for "once per iteration" elsewhere finds only an unrelated use in
`src/Observables.jl:185` about `kinetic_energy` measurement cadence, not the observation-callback
count — no surviving instance of the flagged claim.

---

## 44 — The step!/deposit! "alignment" claim holds only as a subsequence

**Owner's ask (verbatim, via the panel finding):** `step!`'s docstring claimed `state`, `domain`,
`buffers` appear "in the same order" in both `step!` and `deposit!`, when the true relation is a
subsequence (two arguments — `generator`, `cache` — are interposed in `step!`).

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `src/Propagator.jl:212-213` now reads: *"after that first argument, the shared trio
`state`, `domain`, `buffers` appears in the same relative order in both."* The diff shows the
literal "in the same order" replaced with the hedged "same relative order," which is the accurate
claim: `step!(scheme, state, generator, domain, buffers, cache, dt)` (src/Propagator.jl:269-270)
and `deposit!(cache, state, domain, buffers)` (src/Propagator.jl:563-564) do preserve
`state → domain → buffers` as a subsequence but not as adjacent/same-order arguments. The fix
narrows the claim to what is actually true rather than papering over it with a caveat.

---

## 45 — The turnover clock is homed in two fields of one struct

**Owner's ask (verbatim, via the panel finding):** `StationarityCriterion`'s `monitor` field entry
and its `elapsed_turn`/`last_time`/`started` entry each claimed to be "the turnover clock,"
assigning one object to two homes.

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `src/SimulationRun.jl:921-927`. The `monitor` entry was reworded from "the sampled
signals (the turnover clock, ε, the scalar variance, the skewness …)" to "the sampled signal
series (ε, the scalar variance, the skewness …), each recorded **against the turnover clock's
readings**" — `monitor` no longer claims to *be* the clock, only to be timestamped by it. The trio
entry keeps sole ownership: "the turnover clock itself: the accumulated turnovers, the instant
last read, and whether the clock has started." This matches the code: `StationarityMonitor`'s
`turn::Vector{Float64}` (src/SimulationRun.jl:799) stores readings pushed from
`criterion.elapsed_turn` (`_push_and_test!`, line 844), confirming `monitor.turn` records against
the clock rather than owning it. One home now, correctly assigned by the code's actual data flow.

---

## 46 — Notation page: the τ disambiguation points "below" but the integrating-factor row is above

**Owner's ask (verbatim, via the panel finding):** the τ row in "Derived scales" says "in the
integrating factor's row below," but the ℰ(κ) row lives in "Spectral representation and
operators," which precedes "Derived scales" on the page — the pointer is backwards.

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `docs/src/notation.md:93` now reads: *"in the integrating-factor row of *Spectral
representation and operators* above."* The word "below" is gone (not left beside a correction),
replaced with "above" and the table is named directly, which satisfies the finding's own resolution
hint ("row above," or name the table — both done). Table order confirmed unchanged: "Spectral
representation and operators" is `## ` at line 54, "Derived scales" at line 81, so "above" is
geometrically correct.

---

## 47 — t_ℓ formula unparenthesized in the VarianceController docstring, parenthesized in the glossary

**Owner's ask (verbatim, via the panel finding):** `VarianceController`'s `turnover_time` entry
gave `t_ℓ = 2k∞/3ε∞` (ambiguous slash grouping) where the glossary's own row already used the
unambiguous `2k/(3ε)`.

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `src/Forcing.jl:617` changed from `` t_\ell = 2k_\infty/3\varepsilon_\infty `` to
`` t_\ell = 2k_\infty/(3\varepsilon_\infty) `` — parentheses added around the denominator, matching
`docs/src/notation.md:94`'s `` t_\ell `` row (`2k/(3\varepsilon)`) exactly in grouping. A residual
unparenthesized form survives in a `#` comment at `src/Forcing.jl:658` ("t_ℓ = 2k_∞/3ε_∞"), but
per house rule comments are not rendered ("Plain `#` comments stay Unicode (they are not
rendered)"), so it is not a second instance of the flagged *docstring-surface* defect — the fix
covers the surface the finding named.

---

## 48 — κ_min appears in the adaptive-step formula but is bound nowhere

**Owner's ask (verbatim, via the panel finding):** the `max_dt` docstring's diffusive-decay bound
`1/(D κ_min²)` used κ_min without ever defining it (presumably 2π/L), unlike every other wavenumber
symbol in the corpus.

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `src/SimulationRun.jl:224-225` now reads: *"time `1/(D κ_min²)` — with `κ_min =
2π/L` the box's fundamental wavenumber and `D` the **larger** of the run's diffusivities …"* — the
symbol is bound in place, correctly, matching the actual computation at
`src/SimulationRun.jl:598` (`κ_min = 2π / Float64(sim.domain.grid.domain_size[1])`). The only other
docstring referencing this bound, `advance!` (`src/SimulationRun.jl:611-612`), does so by prose
cross-reference ("the same diffusive-decay bound the `Simulation` docstring states") without
re-using the bare symbol, so it needs no independent binding — no surviving unbound instance.
`grep` across `src/*.jl` and `docs/src/*.md` finds κ_min only at this one docstring site plus
internal code/comments, confirming this was the sole gap and it is now closed.

---

## 49 — Skewness aliasing: module summary says PhaseShift is "priced", the docstring says treat it as "not alias-controlled"

**Owner's ask (verbatim, via the panel finding):** the `Observables` module docstring groups
`PhaseShift` with `TwoThirds` as "priced" (sharp truncations), while `derivative_skewness`'s
closing "on either" grouped `PhaseShift` with `HouLi` as unquantified — the two classifications of
PhaseShift's standing read differently.

**VERDICT: HONORED**

**Which question:** n/a — passed all four.

**Evidence:** `src/Observables.jl:322-323` changed the closing clause from "no bound here prices —
**on either**, treat the skewness…" to "no bound here prices — **on every strategy**, treat the
skewness…" The module docstring's "priced for the sharp truncations, unpriced for `HouLi`'s taper"
(`src/Observables.jl:44`) is untouched and remains correct: the surrounding paragraph already
states PhaseShift "carries the same kind of residual" as the sharp-truncation case (grouping it
with `TwoThirds` as "priced" in kind), while HouLi's taper residual is unbound by any formula here.
The old "on either" implicitly re-grouped PhaseShift with HouLi as a pair excluded from pricing,
contradicting the module doc; "on every strategy" removes that implicit grouping and states the
indicator-only caveat as orthogonal to (applies regardless of) the priced/unpriced classification —
resolving the contradiction with a minimal, targeted edit rather than a reword that dodges it.
`grep` for "on either" elsewhere in `src/`/`docs/src/` finds only an unrelated PF-testing sentence
in `decisions.md`, so this was the sole instance.

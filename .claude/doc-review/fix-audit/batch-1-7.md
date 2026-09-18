# Fix audit — batch 1–7

Auditing `git diff 0b3d58c..HEAD` against the merged pile's findings 1–7 (owner-words ground truth
in `/tmp/claude-1000/merged-pile.md`).

---

## Finding 1 — [01-free-reader-a, local 1] rounded number off by a hundredth

**Owner's ask (resolution hint, treated as spec):** "change `0.96Δx` to `0.95Δx`."

**VERDICT: HONORED**

**Evidence:** `src/SimulationRun.jl:128` now reads
`` ``\eta \approx 0.64\Delta x`` at `κ_max_η = 2` against ``0.95\Delta x`` for ``2/3`` ``, replacing
the flagged `0.96Δx`. Arithmetic check: `2/(f·π)` at `f = 2/3` is `3/π = 0.95493…`, which rounds to
`0.95` — the fix is numerically correct, and only this one decimal changed (`git diff` shows a
single-token substitution, no collateral rewording). The neighboring 31% Re_λ claim, which the
finding said was unaffected, is untouched.

---

## Finding 2 — [01-free-reader-a, local 2] Quick Start's first example assumes deep cache vocabulary

**Owner's ask (resolution hint):** "trim the parenthetical to a plain-English gloss ('gates every
read, so a stale read throws rather than serving an old value') and let the terms of art get
introduced on their own page."

**VERDICT: LINE-ONLY**

**Which question failed:** STRATEGY (b), line vs. class.

**Evidence:** The flagged sentence itself was fixed almost verbatim to the suggested gloss —
`docs/src/index.md:51-52` now reads "The state is always current; the cache serves what the last
iteration recorded at its end — a stale read throws rather than serving an old value," removing both
flagged terms ("closing deposit", "epoch — the cache's freshness counter") from that line. But the
pre-fix snippet (`git show 0b3d58c:docs/src/index.md`) shows "closing deposit" appeared **twice** in
this same Quick Start block — once in the flagged parenthetical (now fixed) and once two lines below,
in the comment on `velocity_physical(sim.cache)`. That second instance is untouched:
`docs/src/index.md:54` still reads `velocity_physical(sim.cache) # the last closing deposit's
field`. The finding's complaint was explicitly about "the very first code a new reader meets"
front-loading unexplained cache vocabulary before it is introduced elsewhere — that complaint is
satisfied for the fixed line and unaddressed for its sibling line in the identical code block the
finding quoted from.

---

## Finding 3 — [01-free-reader-a, local 3] the decision log dwarfs, and out-registers, the rationale it is attached to

**Owner's ask:** No resolution hint was offered ("none strong ... flagging only"); the pile's own
OWNER RULINGS preamble states the owner ruled "Yes, go ahead" over a plan whose dispositions
explicitly included "the decision-log register/density complaints (deliberate append-only ledger)"
as an owner-sanctioned dismissal, not an assistant-authored one.

**VERDICT: HONORED**

**Evidence:** `.claude/doc-review/00-SUMMARY.md:19-20` records "3 DISMISSED (the decision log is a
deliberate append-only ledger; its audience is recorded in CLAUDE.md)". Per the pile's own ground-
truth preamble, this specific dismissal (decision-log register/density complaints) was one of the
named dispositions the owner explicitly ruled "go ahead" on — this is the one closure class in this
batch where a LAUNDERED-looking dismissal is pre-authorized by the owner's own words, not asserted
unilaterally by the assistant. Nothing in CLAUDE.md or ARCHITECTURE.md was rewritten for this
finding, consistent with "flagging only, no strong resolution hint."

---

## Finding 4 — [01-free-reader-a, local 4] an identical "References" paragraph is repeated verbatim three times

**Owner's ask (resolution hint):** "could shorten to one sentence per page with the shared rationale
stated once, e.g. on the `Phenomenology` overview page."

**VERDICT: ADJACENT**

**Which question failed:** FIDELITY.

**Evidence:** The commit (`4a03de9`, `docs/src/api/phenomenology/{Scalings,Spectra,
StructureFunctions}.md`) cut one clause — "A few works are cited in `ARCHITECTURE.md` as well,
where the DNS side needs them — the leaf's independence means it does not *rely* on that list, not
that the two never overlap." — identically from all three pages. Reading the three files now
(`Scalings.md:29-31`, `Spectra.md:63-65`, `StructureFunctions.md:23-25`), the remaining "##
References" opening paragraph is **still word-for-word identical across all three pages** — same
sentence "The published provenance of each law on this page, read from its `provenance(law)` ...",
same closing sentence about scoping. The finding's title and core complaint is the tripled
repetition itself, not the content of the removed clause; nothing was deduplicated, no shared
rationale was moved to the `Phenomenology` overview page as the resolution hint suggested — the
paragraph is simply a shorter version of the same paragraph, repeated three times exactly as before.
A reader going page to page still meets the identical boilerplate three times in a row.

---

## Finding 5 — [01-free-reader-a, local 5] `kinetic_energy_and_dissipation` missing from both summary tours of `Observables`

**Owner's ask (resolution hint):** "add a short clause to both Home/api `Observables` bullets, e.g.
'...and the fused $(k,\varepsilon)$ pair `kinetic_energy_and_dissipation`.'"

**VERDICT: HONORED**

**Evidence:** Both flagged locations were edited identically. `docs/src/index.md:103-104`: "the
energy and dissipation diagnostics of the flow and the scalar (including the fused pair
`kinetic_energy_and_dissipation`), the developed-turbulence marker..." `docs/src/api.md:15`: same
clause inserted verbatim in the `api` overview's `Observables` bullet. Both sites now name the
function; `kinetic_energy_and_dissipation` is confirmed exported and defined at
`src/Observables.jl:52,168`, so the added reference is accurate.

---

## Finding 6 — [02-free-reader-b, local 1] the one runnable-code claim in ARCHITECTURE.md is false as written

**Owner's ask:** The runnability claim ("the example above runs as written") must actually be true —
the block calling undefined `accumulate_statistics!(my_stats, s)` needs to become genuinely
self-contained, matching the finding's contrast with the Home page's runnable quick-start.

**VERDICT: HONORED**

**Evidence:** `docs/ARCHITECTURE.md:63-68` replaces the undefined call with a self-contained snippet:
`energies = Float64[]` is declared before the loop, and the callback body is
`push!(energies, kinetic_energy(s.state.velocity_spectral))` — both `push!` and `kinetic_energy` are
real, resolvable calls (`kinetic_energy` is exported and defined at `src/Observables.jl:79`,
`kinetic_energy(u) = inner(u, u) / 2`, callable on `s.state.velocity_spectral`). The "runs as
written" sentence immediately following the block (`ARCHITECTURE.md:90`) is untouched and is now
true of the new block. This is a repair by correction, not by insertion — the flagged undefined call
is gone, not appended beside a working alternative.

---

## Finding 7 — [02-free-reader-b, local 2] the architecture's "comparison machine" has no public entry point

**Owner's ask (T7 ruling, verbatim in the pile's OWNER RULINGS section):** "remove the advertisement,
we won't have it" — the comparison machine reworded as a discipline (commits 752149e + 5a6157f).

**VERDICT: HONORED**

**Evidence:** All locations the finding named were reworded to state plainly that no shipped
comparer exists. `docs/ARCHITECTURE.md:166-168` (§3): "The machine is a discipline the caller runs,
not a component the package ships: the package provides the two sides — the measured observables and
the reference laws — and no public comparer (its own test suite practices the comparison
internally)." `docs/ARCHITECTURE.md:524-529` (§4.8's "provider, not comparer" bullet): "The
comparison lives consumer-side — the caller's own analysis, or a test suite — reading both; the
package ships no comparer." `docs/src/phenomenology.md:5-7`: "...and setting the two side by side is
the caller's own comparison — the package ships no comparer (its test suite practices the comparison
internally)." `src/Phenomenology.jl:14-16` (module docstring): "a provider a caller's own validation
reads to compare a run against — the package ships no comparer — never a comparer itself." A
corpus-wide grep for "validation layer" (the phrase the finding flagged as implying a shipped
component) finds it surviving only in `docs/src/decisions.md:89` and `docs/ARCHITECTURE.md:1006`,
both inside the append-only §11 decision log, which the corpus's own convention (confirmed elsewhere
in this same pile round) treats as historical record exempt from live-prose sweeps — not a live
current-state claim the reader would trust as describing today's API. No stray "validation layer" or
"comparison machine" phrasing survives on a current-state surface.

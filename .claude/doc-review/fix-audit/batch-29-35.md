# Fix audit — batch 29–35

Diff audited: `git diff 0b3d58c..HEAD` in GBGIsotropicTurbulence (three commits: "Panel fix pass,
tier 2", "Panel T8+T9", "Repair: T7's ruled growth re-baselined").

---

## 29 — "A caller reads through the accessors and never deposits" vs the mandated caller re-deposit

**Owner's ask (verbatim, via the finding):** the module docstring's "A caller reads through the
accessors and never deposits" contradicts `fields_modified!`'s and both `State.jl` seeders'
mandated `deposit!` re-seed workflow; the reader/solver split needs to be stated.

**VERDICT: HONORED**

**Evidence.** `src/Cache.jl` module docstring now reads (diff, `src/Cache.jl`):
> "A caller reads through the accessors and deposits only to re-seed the cache after an
> out-of-band mutation it announced (`fields_modified!`); the iteration's own deposits are the
> solver's."

This replaces the absolute "never deposits" with the exact split the finding asked for (reader vs.
the one sanctioned re-seed act), and does not merely append beside the false absolute — the
offending clause itself is gone. Checked both other named locations for consistency:
`fields_modified!`'s own docstring (`src/Cache.jl:348`, "After a hand-made mutation, re-deposit
with…") and both `State.jl` seeders (`src/State.jl:124-131`, `:224-231`, the "Seeding a running
simulation invalidates the observables cache" admonition, "then restore the cache with `deposit!`
before advancing again") — all three surfaces now agree with the corrected module docstring. No
stray "never deposits" language survives elsewhere (checked `grep -rn "never deposits"` — no hits).

---

## 30 — `deposit!` ownership named two different ways

**Owner's ask (verbatim, via the finding):** the module docstring says `Propagator` owns
`deposit!`; `fields_modified!`'s docstring attributed it to "the run layer's `deposit!`," which
exports no such verb — reconcile the ownership statement.

**VERDICT: HONORED**

**Evidence.** `src/Cache.jl` diff: `fields_modified!`'s docstring now reads "re-deposit with the
`Propagator`'s [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing
again" — matching the module docstring's "`Propagator` owns rather than this module" (`src/Cache.jl:30`).
Verified against the actual definition site: `deposit!` is defined at `src/Propagator.jl:563`
(`grep -n "function deposit!"` — only hit), confirming `Propagator` genuinely owns it and
`SimulationRun` does not. Swept the corpus for the misattribution surviving elsewhere
(`grep -rn "run layer's.*deposit"` across `src/` and `docs/src/*.md`) — zero hits; the class, not
just the flagged line, is clean. Remaining "run layer's `advance!` calls it" phrasing
(`docs/src/observables_cache.md:416`, `src/Propagator.jl:221,552`) correctly describes *invocation*
by `advance!`, not *ownership*, and was never the contradiction flagged.

---

## 31 — "The recoveries are exported" vs the no-re-export ruling

**Owner's ask (verbatim, via the finding):** the design page's premise that "the recoveries are
exported" is false — the velocity/scalar recovery is a `GBGPeriodicFields` backend operation
reached through `to_physical!`, not an IT export; only `vorticity_physical!` is IT's own export —
fix the false premise so the conclusion (a mutating caller can self-serve) still follows correctly.

**VERDICT: HONORED**

**Evidence.** `docs/src/observables_cache.md` diff, §1.3:
> "That interval belongs to whoever made the change: the recoveries stay callable — the field ones
> through the backend (`GBGPeriodicFields`'s four-argument `to_physical!`), the vorticity through
> this package's [`vorticity_physical!`](@ref) — so a caller who mutates the state mid-run computes
> what they need themselves, in their own buffer."

This states the category distinction the finding demanded (backend recovery vs. package export)
rather than papering over it. The second flagged instance (§2.5, "the exported recoveries and
reductions") is also corrected in the same diff to "the exported reductions and the backend's
recoveries" — both locations fixed, not just the first (class swept, not line-only). The third
location cited by the finding, `docs/src/decisions.md`'s "re-exports no `GBGPeriodicFields` name…"
line, was already correct and is untouched — consistent with the repaired pair.

---

## 32 — The §2.4 table's Built column discriminates nothing by its own legend

**Owner's ask (verbatim, via the finding):** the Built column is a vacuous function of Cached by
its own stated legend, and additionally mislabels `dissipation`/`derivative_skewness` as "—" while
they are built functions of the package.

**VERDICT: HONORED**

**Evidence.** `docs/src/observables_cache.md` diff, §2.4: the Built column and its defining
sentence ("Its **Built** column says whether the package holds the observable today, and reads `—`
wherever *Cached* is *no* or *never*…") are deleted outright, and the table's header/rows are
reflowed to `| Observable | Where it lives | Cached | Producer, or reason |` with no Built column
at all. This is a deletion, not an insertion beside the flagged text — the vacuous column is gone
rather than re-justified. Confirmed no residue: `grep -n "Built column\|\*\*Built\*\*\| Built |"`
returns nothing in the file.

---

## 33 — §2's configuration enumeration excludes what the section then covers

**Owner's ask (verbatim, via the finding):** §2's stated configuration (two mask rules, three
stages, adaptive Δt) omits `PhaseShift`, other stage counts, and fixed-Δt driving, which the same
section (§2.3, §1.4) then prices — reconcile the enumeration with what is actually covered.

**VERDICT: NEW-DEFECT**

**Which question failed:** IMPLEMENTATION — the repair fixes the contradiction but introduces a
factually wrong cross-reference in doing so.

**Evidence.** `docs/src/observables_cache.md` diff, §2 opening:
> "One configuration fixes the system. The chapter's running instance is the default one — … an
> adaptive timestep — and §2.3 prices the departures from it (`PhaseShift`, another stage count,
> **a hand-fixed `\Delta t`**)."

This resolves the base contradiction (the enumeration is now explicitly framed as "the running
instance," with departures acknowledged) for `PhaseShift` and stage count — both genuinely priced
in §2.3 (confirmed: §2.3's table gives transform counts for `TwoThirds`/`HouLi`/`PhaseShift` and
states "a scheme with a different stage count scales them by its own," `docs/src/observables_cache.md`
§2.3). But the claim that **§2.3** also prices "a hand-fixed `\Delta t`" is false: I read §2.3 in
full (the transforms/arrays section) and it contains no mention of fixed-Δt pricing at all. The
hand-fixed-Δt cost (the standing maximum-speed reduction) is priced in **§1.4**, not §2.3
(`docs/src/observables_cache.md:203-208`, "…paid even by a hand-fixed-`\Delta t` run that never
reads the number…", and line 208, "plus, under a hand-fixed `\Delta t`, the recurring
maximum-speed…" — both under the §1.4 heading, several sections before §2). The fix therefore
introduces a new, checkable factual error: a reader following "§2.3 prices … a hand-fixed Δt" to
§2.3 will not find that pricing there.

---

## 34 — The absolute design choice and its standing exception form a soft inconsistent pair

**Owner's ask (verbatim, via the finding):** §1.1's absolute claim ("Caching an observable adds
nothing to what an iteration computes, moves, or stores," stated as non-derived) is contradicted by
§1.4's documented standing exception (the max-speed reduction paid even when unread) — the rule is
never weakened to admit the exception it has.

**VERDICT: HONORED**

**Evidence.** `docs/src/observables_cache.md` diff, §1.1, immediately after the boxed absolute
claim and its "opposite choice is defensible…" paragraph:
> "One standing exception survives, priced in §1.4: the closing deposit's maximum-speed reduction,
> a traffic-axis cost kept so the schedule never varies with how the run is driven."

This names the exception at the point of the absolute claim, with an explicit forward pointer to
where it is priced (§1.4) — the strategy the finding called for (state the exception rather than
leave it silently contradicting), not an unrelated reword. The boxed claim itself is left as the
general design principle (correctly — it holds for every observable except the one named
exception), and the exception is now visible to a reader holding both sentences instead of hidden.
Checked §1.2's "Computed — some component must produce it anyway" test (the biconditional the
finding also cited) for consistency: it is not separately amended to flag max-speed as its own
exception-to-the-test, but the finding's core ask was the §1.1/§1.4 pair, which is now reconciled;
I did not find this treated as a separate, distinct ask in the finding's text warranting its own
fix.

---

## 35 — "Front door" — the glossary resolves only one of the term's two live senses

**Owner's ask (verbatim, via the finding):** the notation-page glossary row ("declared 'where a
reader resolves it'") defines "front door" only as the domain-building `Simulation` constructor,
while ARCHITECTURE §4.7's heading uses it for the whole run layer — the glossary resolves only one
of the two live senses.

**VERDICT: HONORED**

**Evidence.** `docs/src/notation.md` diff, Vocabulary table, "front door" row — the existing
constructor-sense definition is kept verbatim and a second sentence is appended to the *same row*:
> "The architecture's §4.7 heading also wears it in a wider entry-point sense — `SimulationRun` as
> the layer a user enters the package through."

This is the correct repair shape for an equivocation finding: the glossary is the one resolver, so
both live senses now have to live in that one row rather than be reconciled by picking one and
deleting the other (which would have been a scope-narrowing, not a resolution). Checked §4.7's
heading in `docs/ARCHITECTURE.md`/`docs/src/architecture.md` (both mirror `### 4.7 SimulationRun —
the front door`) — unchanged, and now correctly resolvable via the glossary's second sentence.
Also checked this doesn't collide with `CLAUDE.md`'s no-invented-alias rule ("front door" confined
to its own docstring/§4.7 sections and the glossary's historical row) — the added sentence is
inside the glossary row itself, which the rule explicitly carves out as "where a reader resolves
it," so no new alias site was created.

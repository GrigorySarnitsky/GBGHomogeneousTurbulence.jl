# Fix audit — batch 33–40

Diff audited: `git diff 52ada56..HEAD` (commits `7abb434`, `c587b30`).

---

## 33 — `_warn_grid_mode_forcing_mismatch` retired-name rename

**Owner's ask (verbatim claim under audit):** "Internal helper `_warn_grid_mode_forcing_mismatch`
kept the retired mode name. CLAIM: renamed `_warn_derived_viscosity_forcing_mismatch` (5 sites)."

**VERDICT: HONORED**

**Evidence:** `git diff -- src/SimulationRun.jl` shows five `-`/`+` pairs, all four method
definitions (`VarianceController`, `VarianceRescaling`, `NoForcing`, `AbstractForcing` methods) plus
the one call site at line 423 renamed from `_warn_grid_mode_forcing_mismatch` to
`_warn_derived_viscosity_forcing_mismatch`. A repo-wide grep for `warn_grid_mode_forcing_mismatch`
returns zero hits; `warn_derived_viscosity_forcing_mismatch` returns exactly the claimed five. Clean
rename, no residue, no drift between call sites.

---

## 34 — ARCHITECTURE §7 checkpoint bullet stale ("scheduled next capability")

**Owner's ask:** "ARCHITECTURE §7's checkpoint bullet still said 'the scheduled next capability…
owner-directed to-do' after decision 75 delivered it. CLAIM: rewritten as DELIVERED with the honest
OU gap noted; and §4.7 gained a write_simulation/read_simulation bullet, closing §4's silence on
persistence."

**VERDICT: HONORED**

**Evidence:** `docs/ARCHITECTURE.md` diff: the §7 bullet header changed from "Checkpoint / exact
restart to HDF5 — **the scheduled next capability**." to "Checkpoint / exact restart to HDF5 —
**DELIVERED (decision 75)**.", body rewritten to describe the five writer/reader pairs and name the
one recorded gap: "a stochastic forcing's evolving force and stream are ruled non-persistent, so a
reloaded `StochasticOU` resumes on a fresh stream rather than continuing the same realization" — the
honest OU gap, present and correctly hedged (not silently dropped). Separately, §4.7 (confirmed at
line 466, `### 4.7 SimulationRun — the front door`) gained a new bullet at line 497: "**`write_simulation`
/ `read_simulation`** — the HDF5 checkpoint (decision 75): one self-describing group fully restores
the run…" — landing in the correct section, closing the silence the claim names.

---

## 35 — ARCHITECTURE §9 invariant 8 "grid mode" terminology leak

**Owner's ask:** "ARCHITECTURE §9 invariant 8 said 'the grid mode resolves' — a decision-73
terminology leak in a current-state section. CLAIM: now 'the derived viscosity resolves'."

**VERDICT: HONORED**

**Evidence:** Diff at §9 invariant 8: "the grid mode resolves the velocity's cutoff" → "the derived
viscosity resolves the velocity's cutoff". Confirmed `derived_viscosity` is the current code term
(five occurrences in `src/SimulationRun.jl`, all from finding 33's rename). Checked for class
survival: `grep -rn "grid mode" src/ docs/ARCHITECTURE.md docs/src/` still returns two other
occurrences (`docs/ARCHITECTURE.md`/`docs/src/decisions.md` lines ~1859/1871, inside **decision 54**,
dated 2026-08, i.e. pre-decision-73 history). These sit inside "## 11. Decision log", which is
explicitly "Append-only; each entry stands on its own" per the doc-edit conventions — a historical
decision entry legitimately uses the vocabulary current *at the time of that decision*, unlike §9's
invariant list which is a current-state section. The finding itself scoped the defect to "a
current-state section", so the decision-log occurrences are not the same class; no LINE-ONLY residue
in current-state prose was found by a broader scan.

---

## 36 — Four lowercase-code-identifier sentence leads in decisions 63/65/67(×2)

**Owner's ask:** "Four sentences in this session's own decision entries (63, 65, 67 ×2) opened with a
lowercase code identifier. CLAIM: each reworded with a capitalized lead; older history untouched."

**VERDICT: HONORED**

**Evidence:** All four sites confirmed fixed by a capitalized lead, three by inserting a capitalized
word before the identifier and one by a colon-introduced clause:
- Decision 63: `` `weighted_inner(f, (w_1, \ldots, w_n))` answers `` → `` The fused
  `weighted_inner(f, (w_1, \ldots, w_n))` answers ``.
- Decision 65: `` `particles_modified!` on a run restarts `` → `` An announced `particles_modified!`
  on a run restarts ``.
- Decision 67 (first): `` `record_velocity_at_particles!(cache, tracers, u)` writes into the cache ``
  → "The write moved with it: `record_velocity_at_particles!(cache, tracers, u)` writes into the
  cache…" — the colon-clause is a full independent clause ("The write moved with it"), not a bare
  `label:` tag, so it does not trip the house rule's separate ban on `label:`-colon-tag fragments.
- Decision 67 (second): `` `particle_velocities` / `record_particle_velocities!` became… `` → "The
  old names `particle_velocities` / `record_particle_velocities!` became…".

Checked the class more broadly: a script search for `[.!?]\s*\n?\s*` immediately followed by a
lowercase-leading backtick span across the whole of `docs/ARCHITECTURE.md` turns up only two
candidates outside these four, both false positives from line-wrap (the true sentence-initial word is
capitalized in both: "After the push, the particle form of `deposit!` interpolates…" and "Read
through `unwrapped_positions`; an untracked set throws."). No other genuine instance found; "older
history untouched" is consistent with the finding's own scoping to this session's entries.

---

## 37 — ARCHITECTURE §4.7 verbless clause

**Owner's ask:** 'ARCHITECTURE §4.7 verbless clause ("…and the observables applied to sim.state (…)
the current-state diagnostics"). CLAIM: "are" restored.'

**VERDICT: HONORED**

**Evidence:** Diff: "…and the observables applied to `sim.state` (e.g. `kinetic_energy(…)`,
`dissipation` on the recovered vorticity) **the** current-state diagnostics, for a callback to read."
→ "…and the observables applied to `sim.state` (e.g. `kinetic_energy(…)`, `dissipation` on the
recovered vorticity) **are the** current-state diagnostics, for a callback to read." The clause now
has a verb ("are"); sentence is grammatical, no other wording disturbed beyond the single word insert.

---

## 38 — Code identifier inside math span, decision 71 witness sentence

**Owner's ask:** 'Code identifier inside a math span in decision 71\'s witness sentence: ``target =
1.5`` renders as an italic product. CLAIM: demoted to a code span `target = 1.5`.'

**VERDICT: HONORED**

**Evidence:** Diff: "seeded at ``k = 0.5`` against ``target = 1.5``, the marginal law must stay at" →
"seeded at ``k = 0.5`` against `target = 1.5`, the marginal law must stay at". Only `target = 1.5` was
demoted to a backtick code span; `k = 0.5` was correctly left as a math span since `k` is the house
symbol for kinetic energy, not a code identifier. Confirmed `target` is a genuine code keyword
(`VarianceController(; target, gain = 1, …)` in `src/Forcing.jl:146`), so demoting it is the correct
application of silent-rendering micro-rule (a) ("a code identifier never sits inside a `…` span").
Scoped correctly — the companion `k = 0.5` math span, which is legitimate math notation, was left
alone rather than being over-corrected.

---

## 39 — Heterogeneous `@docs` blocks (type + functions mixed), 3 sites

**Owner's ask:** "Heterogeneous @docs blocks (type + functions mixed), 3: SimulationRun's Advancing
block (StationarityCriterion among advance!/run!/warmup!), Cache's (ObservablesCache +
fields_modified!/particles_modified!), Propagator's (IntegratorBuffers + allocate_buffers). CLAIM:
each split into a type block and a function block under the same header."

**VERDICT: HONORED**

**Evidence:** All three confirmed split into two consecutive ` ```@docs ` fences under one unchanged
`##` header:
- `docs/src/api/Cache.md`, under "## The observables cache": `ObservablesCache` now alone in its own
  fence, followed by a second fence with `fields_modified!` / `particles_modified!`.
- `docs/src/api/Propagator.md`, under "## Step scratch": `IntegratorBuffers` alone, then a second
  fence with `allocate_buffers`.
- `docs/src/api/SimulationRun.md`, under "## Advancing the run": `StationarityCriterion` moved into
  its own fence placed *before* the `advance!` / `run!` / `warmup!` fence (previously interleaved
  between `advance!`/`run!` and `warmup!`).

Each is now internally homogeneous (all-type or all-function), matching the house rule "a `@docs`
block stays homogeneous (all-types or all-functions…)"; the header structure was not otherwise
touched (no section split, no renumbering), matching "under the same header" in the claim.

---

## 40 — index.md momentum equation over-wide display line

**Owner's ask:** "index.md's momentum display equation was one over-wide line (no display
auto-wrap). CLAIM: wrapped in aligned, matching observables_cache.md's own treatment of the same
equation."

**VERDICT: HONORED**

**Evidence:** Diff: the single-line
`` \partial_t \boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}, \qquad \nabla\cdot\boldsymbol{u} = 0, ``
was rewritten as an `aligned` block:
```
\begin{aligned}
\partial_t \boldsymbol{u} &= \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega})
  + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}, &
\nabla\cdot\boldsymbol{u} &= 0,
\end{aligned}
```
Confirmed every source line inside the new display block is short (no horizontal-scroll risk).
`docs/src/observables_cache.md` (lines 249–255) uses the same `\begin{aligned}…\end{aligned}` idiom
for the same momentum + continuity pair (as part of a larger three-equation system block), so the
treatment is consistent in kind, satisfying "matching observables_cache.md's own treatment" — the two
are not byte-identical (observables_cache.md's block also carries the scalar and particle equations
with `\\[4pt]` row breaks), but the claim only asserts a matching *treatment* (the `aligned`
mechanism), which holds.

---

## Summary

| # | Verdict |
|---|---|
| 33 | HONORED |
| 34 | HONORED |
| 35 | HONORED |
| 36 | HONORED |
| 37 | HONORED |
| 38 | HONORED |
| 39 | HONORED |
| 40 | HONORED |

All eight findings in this batch check out: each claim landed as described, by the right means
(correction/deletion, never insertion-beside-defect), correctly (formulas, notation, and cross-refs
verified against the current source), and without unflagged scope creep. No LINE-ONLY residue, no
LAUNDERED closures, no NEW-DEFECT introductions found in this batch.

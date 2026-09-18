# Fix audit — batch 57–63

Diff audited: `git diff 0b3d58c..HEAD` (commits `752149e`..`4a03de9`) in GBGIsotropicTurbulence.

---

## Finding 57 — "scratch" and "register" used as if interchangeable, with no stated relationship

**Owner's ask (verbatim, via the pile):** "'Register' gets a precise definition (Notation
Vocabulary...). 'Scratch' never gets an equivalent entry, yet is used constantly for the same kind
of object... A reader is left to infer whether 'scratch' names a collection of registers, a synonym
for register, or something broader."

**VERDICT: HONORED**

**Which question:** none — passes all four.

**Evidence:** `docs/src/notation.md` Vocabulary table gained a new row directly under `register`:

> `**scratch** | working storage a component owns for its intermediate results — a register, or a
> named bundle of them (the generator's assembly scratch, a scheme's `IntegratorBuffers`).`

This states exactly the relationship the finding says was missing: scratch is either a register
itself or a named bundle of registers, not an unrelated third kind of object. Checked against usage
in `src/Generator.jl` (`ResolvedGenerator`'s "assembly scratch" bundles `product_spectral`,
`phase_shift`, the rate arrays — a named bundle) and `src/Propagator.jl` (`IntegratorBuffers`'s
"preallocated per-step scratch," itself a bundle of stage registers) — the new definition matches
both cited usages. The fix follows the same convention the corpus already used for `register`
(defined once in the glossary, used unglossed throughout), so it is the right kind of repair for a
clarity finding of this shape, not a rename campaign the owner never asked for.

---

## Finding 58 — `restart!` reads as a checkpoint verb next to `read_simulation`'s "restore"

**Owner's ask (verbatim, via the pile):** "the package's checkpoint family is consistently named
`write_*` / `read_*` ('restore,' in prose), so `restart!`... is the one verb on the site that sounds
like it belongs to that family. A reader skimming the index for 'how do I resume a run' could
plausibly reach for `restart!` first."

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `src/Particles.jl`, `restart!`'s docstring gained one sentence, inserted after the
existing multistep/one-step explanation and before the `Simulation`-form cross-reference:

> "This is an in-memory reset of one scheme's history, not a checkpoint verb — restoring a saved run
> is `read_simulation`'s job."

This directly disambiguates the two verbs at the point a confused reader would land, without
renaming `restart!` (the finding is `clarity`/`minor`/`low confidence`, not a rename mandate — the
fix matches its severity). No other call site needed the same disambiguation: `restart!` is
documented once (bare binding, house style), and `read_simulation`'s own docstring already used
"Restore" unambiguously before this round.

---

## Finding 59 — `PointSet` / `VectorPointValues` / `ScalarPointValues` never get an on-site structural description

**Owner's ask (verbatim, via the pile):** "These three types gate every particle-facing call on the
page... but are never shown with a field list, a shape, or a constructor on this site — only
inferable from one worked example... for a reader who does not already know that sibling package,
the objects driving the whole Particles page remain structurally opaque."

**VERDICT: UNDONE**

**Which question:** FIDELITY.

**Evidence:** `git diff 0b3d58c..HEAD -- src/Particles.jl | grep -n "PointSet\|PointValues"` returns
exactly one touched line, and it is unrelated to this finding — a wording change from "off the
fields directly" to "straight off the struct's own fields" (the fix for a different, `!`-flagged
"fields means struct fields" ambiguity, finding 73 in the pile). No new field list, shape note, or
constructor sketch was added anywhere `PointSet`, `VectorPointValues`, or `ScalarPointValues` are
used in `src/Particles.jl` or `src/Cache.jl`; the whole-diff grep for `PointSet|PointValues` across
every changed file returns the same single, unrelated line. Nothing was done for this finding.

---

## Finding 60 — "the default" forcing (Home page) is only the velocity's default; the scalar defaults differently

**Owner's ask (verbatim, via the pile):** "Read on its own, the Home page's '(the default)' tag on
`VarianceController` reads as *the* package default, not *the velocity's* default; a reader only
learns the scalar defaults to `NoForcing()` two pages later."

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `docs/src/index.md`:

```
-    `VarianceController` (the default), and `VarianceRescaling`, and Lagrangian particle
+    `VarianceController` (the velocity default), and `VarianceRescaling`, and Lagrangian particle
```

Minimal, exact fix at the flagged line: the parenthetical now names the axis it qualifies, matching
what `Simulation`'s Arguments entry two pages later actually says (`velocity_forcing` defaults to
`VarianceController`, `scalar_forcing` to `NoForcing()`). No other instance of the unqualified "(the
default)" phrasing for this forcing exists elsewhere in the diffed surfaces.

---

## Finding 61 — `$G$` names two unrelated constants, disclosed but not locally noted where each formula uses it

**Owner's ask (verbatim, via the pile):** "nothing in either formula's own docstring reminds the
reader which `G` is meant at the point of use — a reader who lands on `VarianceController`'s formula
without having read Notation first... has no local signal that this `G` is not the grid's `Li2008`
constant a few pages away."

**VERDICT: UNDONE**

**Which question:** FIDELITY.

**Evidence:** `src/Forcing.jl`'s `VarianceController` docstring was touched in this diff (citation
formatting, the `injection_rate` keyword list, a settling-time note), but the bare-`G` formula block
itself —

```
A(\boldsymbol{\kappa}, t) = \frac{\varepsilon(t) - G[k(t) - k_\infty]/t_\ell}{2k_f(t)}
```

— and the adjacent `gain = 1` bullet are byte-identical before and after (confirmed by diff: no `-`
or `+` line touches lines 573–630 of the pre-image around the formula or the `gain` bullet). The
`docs/ARCHITECTURE.md` §9 invariant-1 bare `G = k/(L\varepsilon)^{2/3}` and the decision-20 entry's
`G = \tfrac{3}{2} C_\varepsilon^{-2/3}` (`Li2008`'s `G`) are likewise untouched — confirmed by
`git diff -- docs/ARCHITECTURE.md | grep "G "` returning nothing in that region. `docs/src/notation.md`'s
`G` glossary row is also unchanged. No local disambiguation was added anywhere a bare `G` sits in a
formula; the finding's specific ask — a reminder *at the point of use* — did not land.

---

## Finding 62 — §1.3 calls the recurring max-speed reduction free; §1.4 calls it the one standing cost

**Owner's ask (verbatim, via the pile):** "§1.3 asserts the recurring reduction is work the next
first stage would do anyway and cites §1.4 for it; §1.4 states the opposite... Also, the first stage
never reduces a maximum; the consumer is the timestep choice, and only on the adaptive path.
REWRITE §1.3's sentence."

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `docs/src/observables_cache.md`, the flagged §1.3 sentence —

> "The reduction inside every other closing deposit recurs per iteration, and is work the following
> first stage would have done anyway (§1.4)."

— is deleted outright (not appended-beside) and replaced with:

> "Inside every other closing deposit the recovery is work the following first stage would have done
> anyway; the maximum-speed reduction is owed by no stage — it is the standing per-iteration traffic
> cost §1.4 prices."

This resolves the contradiction the correct way: it separates "the recovery" (genuinely owed by the
next stage) from "the maximum-speed reduction" (owed by no stage, a standing cost), matching §1.4's
unedited claim — "the closing deposit's maximum-speed reduction is one physical-vector pass every
iteration, paid even by a hand-fixed-``\Delta t`` run" (line 203, confirmed unchanged and now
consistent with §1.3). This also implicitly corrects the finding's second point (the first stage
never reduces a maximum) by no longer claiming the reduction is stage-owed at all, rather than
patching in a stage/timestep-choice distinction that would have kept the false claim alive in
weakened form.

---

## Finding 63 — The PhaseShift reuse-contract prose cannot be paraphrased

**Owner's ask (verbatim, via the pile):** "'Rather than either signature' compresses 'rather than
being expressed in either verb's signature' past recovery; 'needs this record to match and the
caller's promise' is a broken coordination ('needs X to match and Y')... REWRITE both."

**VERDICT: NEW-DEFECT**

**Which question:** IMPLEMENTATION.

**Evidence:** Both flagged clauses in `src/Generator.jl` were genuinely rewritten (old text deleted,
not appended-beside):

- The `ResolvedGenerator` admonition now reads: "Neither verb's signature carries the handoff: the
  generator records which `û` the displaced velocity was taken of, and `scalar_rhs!` reuses the
  scratch only when that record matches its own `û`." — no longer an unparseable compression; passes
  the paraphrase test.
- The `displaced_velocity_source` field entry now reads: "Reuse takes two conditions together: this
  record must match the caller's `û`, **and** the caller must promise through
  `displaced_velocity_current` that the scratch is still fresh." — the broken coordination is fixed
  and the two-condition structure is stated plainly.

But the two rewrites now disagree with each other, and the admonition disagrees with the code. The
actual reuse guard, `scalar_rhs!`'s `_scalar_nonlinear!` dispatch on `PhaseShift`
(`src/Generator.jl:730`): `if !(displaced_velocity_current && generator.displaced_velocity_source === û)`
— rebuilds unless **both** the keyword `displaced_velocity_current` is `true` **and** the recorded
source matches `û`. The field-entry rewrite states this correctly ("two conditions together"), but
the admonition's rewrite states reuse as gated on the record match alone — "`scalar_rhs!` reuses the
scratch only when that record matches its own `û`" — with no mention of the `displaced_velocity_current`
keyword anywhere in that paragraph. A reader who stops at the admonition (the more prominent,
earlier-encountered surface, and the one most likely to be read in isolation as "the" explanation of
the mechanism) comes away believing a matching record is sufficient for reuse, when the field
entry two paragraphs later — and the code — says it is only one of two required conditions. The
pre-fix text avoided this specific claim (it only described what gets *recorded*, plus "the record
half is opportunistic, never load-bearing," which hinted at *something else* being load-bearing);
the rewrite, in fixing the paraphrase problem, introduced a new sentence that states an incomplete
— and in isolation misleading — version of the reuse contract.

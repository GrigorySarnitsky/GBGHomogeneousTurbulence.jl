# Closure audit — Hat 12: plain-sense

Adjudicated against the current corpus only (src/, docs/src/, docs/ARCHITECTURE.md). 16 findings enumerated.

---

## Finding 1 — quick-start "deposit" circular gloss

**VERDICT: ABSENT**

`docs/src/index.md` (Quick start code comment, ~line 47) now reads: "One ITERATION is one
advance: a step, then the DEPOSIT that closes it. A deposit writes the observables the iteration
has just computed into the cache, each recorded against the epoch of the state it came from." The
circular appositive ("the write in which the closing deposit writes … into the cache") is gone;
searched `docs/src/index.md` in full for "deposit" — no remaining self-referential definition.

---

## Finding 2 — "Two kinds of field share the word"

**VERDICT: ABSENT**

`src/Cache.jl` (`ObservablesCache` `# Fields`, ~line 108) now reads: "The word *epoch* names two
things here, and the fields below are of both kinds. The two **counters** tick as the state
changes; every other `*_epoch` field records the counter's value at the moment its slot was
filled." The word is now named explicitly ("epoch"), resolving the unreconstructable-subject
defect. Grepped repo for "share the word" — zero hits outside `.claude/`.

---

## Finding 3 — max_speed admonition triple-restates its rule

**VERDICT: ABSENT**

`src/Observables.jl` (`max_speed`, admonition "Why this observable alone has a cached form", line
149) now reads as one clause: "The cache holds exactly what the iteration already computes and
leaves alive at its end; its contents follow from the run's fixed computation schedule rather than
from anything a caller declares." No nested nested-dash nested restatement remains; "never
declared" is folded into the one clause rather than hanging as a fragment.

---

## Finding 4 — 40+-word sentences with buried verb spine (3 samples)

**VERDICT: PRESENT**

Two of the three flagged sites are unchanged in the defect's substance:
- `src/SimulationRun.jl` lines 103–120 (Grid mode bullet): still one sentence from "It reads the
  dissipation…" through "…then sets `ν`…", carrying the same ~180-word, multi-clause parenthetical
  about `G`/`C_ε`/`L₁₁/L` between the two verbs.
- `docs/ARCHITECTURE.md` lines 179–192 (§4.1 `FixedDomain` sentence): still one ~100-word sentence
  with three nested parentheticals ("(one for the velocity, …)", "(in spectral space …)", "(the
  sharp 2/3 rule …)").
`src/Propagator.jl` `step!` (lines 189–195) was reworded but remains one long em-dash-laden
sentence. The class survives at the two clearest sites; verdict PRESENT.

---

## Finding 5 — StationarityCriterion trailing forward-reference sentence

**VERDICT: ABSENT**

`src/SimulationRun.jl` `StationarityCriterion` identity paragraph (lines 568–573) ends at "…give a
decaying run a fixed-length loop instead, which is a three-line callback (see `run!`)." The
sentence "The same argument the scalar gate makes for an unforced scalar applies to the velocity."
is gone. Grepped `src/SimulationRun.jl` for "scalar gate makes" — no hits.

---

## Finding 6 — step!/deposit! order mnemonic asserted then withdrawn

**VERDICT: ABSENT**

Both docstrings were rewritten to a checkable, mutually consistent claim. `src/Propagator.jl`
`step!` (lines 197–200): "The leading argument differs from `deposit!`'s in kind … `scheme` here is
a stateless dispatch tag … `deposit!` leads with `cache`, the object it mutates. After the leader
both take `state`, `domain`, `buffers` in that order." `deposit!` (lines 498–500): "The argument
order is shared with `step!` — the mutated dispatch object (here the cache) leads, and `state`,
`domain`, `buffers` follow in the same fixed order as there." No contradiction between the two;
the strong-claim-then-qualify shape is gone.

---

## Finding 7 — "so the arrows stay primary" unglossed jargon

**VERDICT: PARTIAL**

The flagged §4.1 instance is fixed: `docs/ARCHITECTURE.md` line 198–199 now reads "kept a bare
carrier so the operations acting on it, not the record itself, carry the design (§11 decision 26)"
— the jargon "arrows" is gone from the cited sentence. But the class survives in the same document:
decision-log entry 26 itself (`docs/ARCHITECTURE.md` line 1052) still reads "adopts the category
lens's guardrail (**arrows primary**, no methods on the carrier)" — the identical undefined
category-theory shorthand, unglossed, inside the same self-contained document.

**surviving_class**: `docs/ARCHITECTURE.md` line 1052, decision-log entry 26 — "arrows primary, no
methods on the carrier," unglossed.

---

## Finding 8 — "output cursors" names a nonexistent component

**VERDICT: ABSENT**

`docs/ARCHITECTURE.md` §8 (line 751) now reads: "…the clock and what a run records are the
experimenter's logbook rather than physics." "output cursors" is gone. Grepped
`docs/ARCHITECTURE.md` for "cursors" — zero hits.

---

## Finding 9 — §1.4 states its two costs twice

**VERDICT: PRESENT**

`docs/src/observables_cache.md` §1.4 is essentially unchanged. Line 195: "It costs nothing on the
memory axis, nothing on the transform axis, and — with one exception — nothing on the traffic
axis: the closing deposit's maximum-speed reduction is one physical-vector pass every iteration…".
Line 198: "Those are two different costs and it is worth keeping them apart: the maximum-speed
reduction above recurs every iteration, while the only work the cache *adds*… is §1.3's final
closing deposit…". Both sentences persist near-verbatim; the antecedent problem for "Those" (nearest
plural is the three axes, not "two costs") is unchanged.

---

## Finding 10 — `*_rhs!` docstrings state the consumed-operand fact 3×

**VERDICT: PRESENT**

`src/Generator.jl` `velocity_rhs!` still carries three statements of the same fact: body (line
307, "`ω_consumed` is consumed in place"), admonition first paragraph (lines 339–344, "`ω_consumed`
must hold the vorticity on entry and no longer does on return"), and admonition second paragraph
(lines 346–350, "Which operand is consumed follows the **physics**, not the argument position").
`scalar_rhs!`'s admonition (lines 480–487) still repeats the "physics not position" point, now via
"As in `velocity_rhs!`, the consumed argument is fixed by the physics rather than by its position in
the signature" — shortened but the same duplicated defence of an unproposed convention survives.

---

## Finding 11 — "deliberately deferred" ×3 in `DissipationFactor`

**VERDICT: ABSENT**

`src/phenomenology/Spectra.jl` `DissipationFactor` (lines 61–77): the title ("Bottleneck models are
deliberately deferred") and the closing clause ("…they are deliberately deferred") remain, but the
middle sentence that verbatim-repeated the title ("These factors are inertial-normalized cutoffs;
bottleneck models are deliberately deferred.") is gone, replaced by "These factors are
inertial-normalized cutoffs." — a plain statement carrying no repetition. Only the bookend
title/closing pattern remains, which is not the flagged triple-restatement defect.

---

## Finding 12 — argument entries explain implementation, not meaning (2 samples)

**VERDICT: PRESENT**

Both instances persist, reworded but substantively unchanged:
- `src/Phenomenology.jl` `FlowParameters` → `scalar_dissipation` (lines 93–97): "It is a
  **sentinel, not a value that propagates** … Arithmetic a caller does on the field itself is not
  covered — there `NaN` propagates as it always does." Still restates Julia's default `NaN`
  arithmetic behavior to a Julia user.
- `src/SimulationRun.jl` `Simulation` → `κ_max_η` (lines 137–140): "the sentinel is what lets the
  constructor tell an omitted keyword from an explicit one, so that giving both it and `viscosity`
  is an error rather than a silent drop" — unchanged, still explains the internal sentinel
  mechanism ahead of/instead of purely the user-facing meaning.

---

## Finding 13 — observation before/after iteration, framed two ways

**VERDICT: ABSENT**

`docs/src/observables_cache.md` §1.3 (line 139) now reads: "**The loop observes, then advances.**
… Read from the callback's side it runs *after* each iteration, which is how [`run!`](@ref)
describes it — the same loop, named from the two ends." The two framings are now explicitly
reconciled as the same event seen from two sides, rather than left to collide. §3.2 (line 422) and
`run!`'s docstring both consistently use "after every iteration … and once before/at the seeded
`t_0`."

---

## Finding 14 — "the thing that reads the run each iteration"

**VERDICT: ABSENT**

`src/SimulationRun.jl` module map (lines 22–24) now reads: "the callback *is* the observation — the
**function** the loop calls to read the run each iteration — and its return decides continuation."
The placeholder noun "the thing" is gone, replaced by "the function," naming the object as every
other gloss on the page does.

---

## Finding 15 — "It is never the cache" unprovoked denial

**VERDICT: ABSENT**

`docs/src/notation.md` Vocabulary table, *observation* entry (line 125): "the callback a run is
driven by: it reads the run once per iteration and its return decides whether to continue. By
extension the *occasion* — 'computed at an observation' means computed in that callback, between
iterations, from what the run already holds." The denial sentence ("It is never the cache, which is
the storage the callback reads.") is gone.

---

## Finding 16 — "and that is the module owning the iteration it closes"

**VERDICT: ABSENT**

`src/Cache.jl` module docstring (lines 21–24) now reads: "The field slots are filled by
[`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), which `Propagator` owns because it
needs the scheme's scratch to recover the fields." The grafted second clause with the ambiguous
"that" pronoun is gone; one clean reason remains.

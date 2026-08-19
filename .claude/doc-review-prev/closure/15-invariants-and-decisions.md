# Closure verdicts — Hat: invariants-and-decisions

## Finding 1 — "Stamp" terminology, retired by decision 53, still live on rendered surfaces

**VERDICT: ABSENT**

**Evidence:** `rg -i '\bstamp' src/` → no hits. `rg -i '\bstamp' docs/src/` → no hits (includes
`index.md`, `notation.md`, `api/Cache.md`). `rg -i '\bstamp' docs/ARCHITECTURE.md` → hits only
inside decision 53's own historical prose (lines 1738–1754), which is exempt (it describes the
rename, using the retired word to name what was retired). `docs/build` shows "stamp" only in the
rendered architecture page (mirrors the exempt decision-log text) and `search_index.js`. The
vocabulary is now `epoch`/`slot` throughout: `docs/src/index.md:48` reads "recorded against the
epoch"; `docs/src/notation.md:121-122` define `slot`/`epoch` with no "stamp"; `docs/src/api/Cache.md:22`
reads "deposited at the current epoch". Genuinely swept.

---

## Finding 2 — Order of closing deposit vs. tracer push contradicts itself across pages

**VERDICT: PARTIAL**

**Evidence:** `docs/src/notation.md:119` (the "iteration" glossary row) is now fixed and matches
`advance!`/decision 42: "...`step!` the fields, `deposit!` to close them, then advance any tracers
and record their sample — the tracers come last because their second velocity sample is
interpolated from the field the deposit just made current." This is the correct order.

But `docs/src/observables_cache.md:29-30` (§1.1), one of the finding's two originally-quoted
locations, is unchanged and still lists the wrong order: "the timestep choice, the step, **the
particle push, and the deposits at its end**" — push named before the end-of-iteration deposits.
This still contradicts `advance!`'s docstring (`src/SimulationRun.jl:387-390`, deposit called at
line 408 before `advect!` at line 410) and decision 42, and even contradicts the same page's own
§2.4 two paragraphs later (`observables_cache.md:320-322`: the push's velocity sample "is the
cache's deposit from the previous closing deposit" — i.e., push consumes an already-deposited
value, meaning deposit precedes push).

**Surviving class:** `docs/src/observables_cache.md:29-30` (§1.1) still states the particle-push-
before-deposit ordering; unfixed, and now the sole remaining site of the contradiction with
`advance!` / decision 42 (notation.md side is resolved).

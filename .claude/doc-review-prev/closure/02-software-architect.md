# Closure — Software-architect review (02-software-architect)

## 1. `Cache` module page misattributes `deposit!` to its own module

**VERDICT: ABSENT**

`src/Cache.jl`'s module docstring (lines 17–24) lists `deposit_sample!` as "the one writer this
module owns" and explicitly links `deposit!` to
`` [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) ``, stating it "`Propagator` owns
because it needs the scheme's scratch to recover the fields." No trace of the contradicting phrase
"That verb lives in `Propagator` rather than here" remains (`rg` for it across the corpus, excluding
`.claude/`, returns nothing). The bullet list and the later prose now agree.

---

## 2. `displaced_velocity_fresh` reintroduces the cross-verb ordering coupling

**VERDICT: PRESENT**

`src/Generator.jl:209-213` still carries the identical "One optimization crosses two verbs" note:
`velocity_rhs!` leaves `phase_shift.u_shifted` fresh via the `displaced_velocity_fresh::Bool` field
(line 242) for the same stage's `scalar_rhs!` to consume, described as "opportunistic, never
load-bearing." `docs/ARCHITECTURE.md:299-312` still states the reified generator means "it can never
assemble the right-hand side from a mismatched intermediate." Decision 45 (`docs/ARCHITECTURE.md:1600-1615`)
documents and justifies the same-stage freshness contract but does not reconcile the "unrepresentable"
claim with this hidden-boolean ordering dependency — the tension the finding describes is unchanged.

---

## 3. `step!`/`deposit!` "same argument order" conflates dispatch tag with mutated object

**VERDICT: ABSENT**

`src/Propagator.jl:197-200` now states explicitly: "The leading argument differs from `deposit!`'s in
kind, and it is worth knowing which: `scheme` here is a stateless dispatch tag, and what this call
mutates is `state`, the second argument; `deposit!` leads with `cache`, the object it mutates." This
directly names the two different roles the finding says were conflated.

---

## 4. Grid-mode viscosity precondition undocumented on `Simulation`'s own docstring

**VERDICT: PRESENT**

`docs/ARCHITECTURE.md:1756-1783` (decision 54) documents the load-bearing precondition — grid-mode
``\nu`` is self-consistent only under `:total`-holding forcing — but `src/SimulationRun.jl`'s
`Simulation` docstring (Grid-mode prose at lines 101-126, `velocity_forcing` argument entry at
150-155) still contains no cross-reference or warning that swapping `velocity_forcing` away from a
``k``-pinning strategy invalidates grid mode's ``\nu``. Searched for "assum", "precondition",
"unsound", "miscalibrat", ":total" in `SimulationRun.jl` — no such statement found there.

---

## 5. `recommended_cfl` admits unsoundness for `IFRK2` with no way to detect it

**VERDICT: PRESENT**

`src/Propagator.jl:547-554`, the `!!! warning "The IFRK2 margin does not know the viscosity"` block,
still reads: "There is no code-level guard for this, and adding one would mean giving a
grid-and-scheme property a physics argument; the practical course at high Reynolds number is to
prefer `IFLowStorageRK3` ... or to pass an explicit `cfl` and verify it against a run that holds its
energy." The documented failure mode and the absence of any code-level guard are unchanged from the
finding's description.

---

## 6. `deposit_sample!` documents its return value twice, in two different words

**VERDICT: ABSENT**

`src/Cache.jl:265-286`: the synopsis is now the bare `deposit_sample!(cache)` with no `-> particle
velocities` arrow; the only return description left is the closing sentence "Returns the
particle-velocities slot." One description, one wording — the arrow/sentence duplication and the
vocabulary drift the finding flagged are both gone.

---

## 7. `velocity_rhs!`/`scalar_rhs!` mutate a second, non-leading argument the `!` convention doesn't flag

**VERDICT: PRESENT**

`src/Generator.jl:301-352` (`velocity_rhs!`) and `:450-489` (`scalar_rhs!`) still name the destructively
consumed second physical argument `ω_consumed` / `u_consumed`, with the docstring stating "the
`_consumed` suffix marks it, since Julia's `!` convention flags only the first." This remains a
naming-level mitigation only — no signature-level change distinguishes the consumed argument from an
ordinary read-only one, exactly as the finding describes.

---

## 8. `particle_velocities` aliasing between `Tracers` and `ObservablesCache` has no documented failure behavior

**VERDICT: PRESENT**

`src/Cache.jl:86-88` instructs "Pass `tracers.particle_velocities`: the slot **is** that array, so
the tracer advance writes the values and the cache only records which epochs they belong to," but
neither this docstring nor `docs/src/observables_cache.md` states what happens if a caller passes a
different array (a copy) instead — searched both files for "diverge", "silently", "copy rather",
"aliasing"/"alias": no hit describing the failure mode. The aliasing contract is asserted, not
guarded or its violation documented.

---

## 9. "Chart" absent from the `notation.md` Vocabulary glossary

**VERDICT: ABSENT**

`docs/src/notation.md:126` now carries the entry: "**chart** | a physical-representation view of the
spectral state — the velocity, vorticity or scalar recovered from it. The cache's field slots are the
run's charts; the *chart map* is the recovery itself." — in the same Vocabulary table as `iteration`,
`deposit`, `slot`, `epoch`, `register`, `front door`, `observation`, `resolved`, right where the
finding says it was missing.

# Hat: invariants-and-decisions

Audits whether the rendered docs (and, where directly checkable, `src/`) still honour
`CLAUDE.md`'s Core Invariants and `docs/ARCHITECTURE.md` §11's decision log — both directions:
a decision the current state contradicts, and a current-state claim no decision supports.
Substrate read in full: `CLAUDE.md`, `docs/ARCHITECTURE.md` §11 (decisions 1–56), the rendered
manuscript (all 19 pages), and `src/*.jl` for direct verification of the two findings below.

---

## Finding 1 — "Stamp" terminology, explicitly retired by decision 53, is still live on the primary rendered surfaces

**Type:** other (decision-log violation) **Severity:** major **Confidence:** high

**Locations:**
- PAGE: Home (quick-start code comment): *"the closing deposit writes the observables the iteration has just computed into the cache, each **stamped** with the epoch of the state they were computed from."*
- PAGE: notation, Vocabulary table, "epoch" row: *"the value of that counter **stamped** on it when it was filled. A slot is readable exactly when the **stamp** it carries still equals the counter it depends on."*
- PAGE: api / Cache, `ObservablesCache` Fields section: *"each slot carries a **stamp**, the counter's value at the moment that slot was filled... its **stamp** still equals the counter"*; *"`velocity_epoch`, … — each slot's **stamp**, or a sentinel"*; *"`sample_fields_epoch`, `sample_particles_epoch` — the particle velocities' two **stamps**"*.
- PAGE: api / Cache, `deposit_sample!`: *"this call **stamps** both from the cache's current counters."*
- Verified live in the authored source, not just an extraction artifact: `src/Cache.jl:111-116,280` carry the identical wording.

**Contradicts:** ARCHITECTURE.md decision 53 (2026-08, user-directed), which states in terms that
name exactly this text: *"'Stamp' is retired... The cache described itself as 'stamped storage'
and gave each slot a `*_stamp` field... The `*_stamp` fields become `*_epoch`, **and the verb goes
with the noun — a deposit fills a slot and sets its epoch rather than 'stamping' it.**"*

**Description:** Decision 53 is a user-directed rename explicitly retiring "stamp"/"stamped" as
the vocabulary for what is now called a slot's epoch, and the decision log itself notes the sweep
"covered the decision log too, so the log reads in the current vocabulary." That sweep did not
reach the rendered docs or the docstrings it describes: the word survives as both a noun ("a
stamp", "two stamps") and a verb ("stamped", "stamps") on the front page, the notation glossary,
and the `Cache` API page's `ObservablesCache` Fields section — the exact surface decision 53
describes rewriting. This is not a stray leftover; it is the same class of defect the decision
itself was written to eliminate, present on the module whose design the decision is about.

---

## Finding 2 — The order of closing deposit vs. tracer push contradicts itself across pages

**Type:** contradiction **Severity:** major **Confidence:** high

**Locations:**
- PAGE: notation, Vocabulary table, "iteration" row: *"one advance of the run: choose the
  timestep, `step!` the fields, **advance any tracers, then the deposit! that closes it**."*
- PAGE: observables_cache, §1.1: *"An iteration is everything a run does to advance from
  $t_n$ to $t_{n+1}$: the timestep choice, the step, **the particle push, and the deposits at
  its end**."* (particle push listed before the deposits)

**Contradicts (both quoted sides):**
- PAGE: api / SimulationRun, `advance!`: *"...**Closes the iteration with `deposit!`**, so the
  cache is readable when it returns. **Advects the tracers**, if any, by Heun-in-time on the
  start- and end-of-step velocities..."* — deposit stated first, tracer advance second.
- ARCHITECTURE.md decision 42 (2026-08, user-directed): *"The push's schedule moves fully onto
  the iteration ends: `advance!` checks the sample at the start... **pushes after the closing
  field deposits** ($\boldsymbol{v}_2$ from **the deposited** $\boldsymbol{u}(t_{n+1})$)..."*

**Description:** Decision 42 explicitly re-ordered the tracer push to run **after** the closing
field deposit — the push's own second velocity sample is interpolated from the just-deposited
`u(t_{n+1})`, so the deposit must precede the push; `advance!`'s own docstring lists the calls in
exactly that order (deposit, then advect). But the notation page's glossary definition of
"iteration" — a definitional entry using explicit sequencing ("...then...") — states the opposite
order (tracers advanced, *then* the deposit that closes it), and the observables-cache design
page's own summary sentence lists the particle push ahead of "the deposits." A reader who trusts
the glossary over the `advance!` docstring would believe the tracer push runs on the pre-deposit
(stale, mid-iteration) velocity field, which is exactly the hazard decision 42 was written to
close.

---

## Notes on scope

An extensive cross-check of the remaining decision-log entries (1–56) against the rendered API
pages found no further contradictions: the include order (`SimulationDomain → State →
Observables → Cache → Forcing → Generator → Propagator → Particles → SimulationRun`) matches
`src/GBGIsotropicTurbulence.jl` exactly; the retired names `ForcingSpec`, `velocity_to_physical!`,
`scalar_to_physical!`, `physical_velocity`/`physical_vorticity` (cache accessors),
`resolved_fields_modified!`, "tail deposit", and "boundary" appear only inside the historical
decision-log prose (exempt per the adjudicated-non-defect rule), never as live current-state
claims; `BandRescaling`'s required `over` and the front door's `:total` override (decision 54),
the consumed-operand naming (`ω_consumed`/`u_consumed`, decision 56), the `scheme`/
`interpolation_scheme`/`trajectory_scheme` split (decision 55), the memory-audit figures (768 MiB
/ 384 MiB / 322.5 MiB, decisions 36–41) and the transform-count table (decision 45) all check out
arithmetically and terminologically against their decisions. `StochasticOU` is confirmed genuinely
absent from every rendered API page, consistent with its archived status (§7).

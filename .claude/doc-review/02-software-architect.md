# Software-architect review — GBGIsotropicTurbulence rendered docs

Hat: software architect / senior Julia programmer. Scope: the documented design (API pages,
ARCHITECTURE.md, notation.md, observables_cache.md, Phenomenology pages) as rendered. Findings
below are ranked most-severe first. Items already settled in
`.claude/doc-review-adjudicated.md` are not repeated.

---

## Finding 1 — The particle-velocities slot needs a hand-run two-call, cross-module protocol that the other four cache slots don't

**Type:** api-gap · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Cache — `ObservablesCache`: "The cache allocates and owns every slot but one: the
  particle velocities are the tracer set's own storage, which the cache borrows and records
  epochs for rather than filling itself."
- PAGE: api / Particles — `record_particle_velocities!`: "This call is that slot's only producer
  of values, but it writes values only: the slot stays stale, and reads of it throw, until
  `deposit_sample!` records them as current."
- PAGE: api / Cache — `particles_modified!`: "A hand-run loop ... must call this, then
  `record_particle_velocities!` to write the new values, and finally `deposit_sample!` to record
  them at the current epochs — the write alone leaves the slot stale."
- Contrast, PAGE: api / Propagator — `deposit!`: "Close an iteration: deposit the field
  observables the cache's fixed schedule carries — the velocity, vorticity and scalar recoveries
  and the maximum speed, the same set every iteration ... into `cache`" — one call, one module.

**Description:** Four of the five cache slots are filled atomically by a single `deposit!` call
in `Propagator`. The fifth — particle velocities — requires two calls in a fixed order, split
across two different modules (`Particles.record_particle_velocities!` writes the values;
`Cache.deposit_sample!` marks them current), because the array is jointly owned by `Tracers` and
`ObservablesCache` rather than owned outright by either. `advance!` chains the two correctly, but
any hand-run loop (which the docs explicitly anticipate and instruct) must remember the order
itself, with no compiler or runtime enforcement beyond "a read throws" after the fact. This is a
genuine asymmetry in an architecture whose central design commitment is that a slot's validity is
never a matter of caller discipline. It is well-rationalized in the docs, but the coupling cost
(shared mutable storage across a module boundary, order-dependent) is real and worth naming as a
design cost, not only a decision.

---

## Finding 2 — The cache's checked-read guarantee is convention-only: the struct's public fields share the accessor functions' names

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: observables_cache — §1.3: "There is no path — internal or on request — by which reading
  causes a computation," and reads either "find the value the schedule left, or throws."
- PAGE: api / Cache — `ObservablesCache` Fields: "`velocity_physical`, `vorticity_physical` — the
  cached velocity and vorticity in physical representation ... `max_speed` — the cached fastest
  flow speed ... `particle_velocities` — the particle-velocities slot."
- Same page, `velocity_physical` function: "Returns the deposited field when its epoch is
  current, and throws otherwise ... nothing is ever recomputed on a read."

**Description:** The type docstring documents `velocity_physical`, `vorticity_physical`,
`scalar_physical`, `max_speed`, and `particle_velocities` as ordinary public struct fields —
exactly the same names as the checked accessor functions. Nothing stops a caller (or a future
internal call site) from writing `cache.velocity_physical` instead of `velocity_physical(cache)`,
which returns the raw slot whether it is current, mid-iteration scratch, or never deposited —
none of the epoch check or the documented throw applies. The design page's absolute claim ("no
path ... by which reading causes [a stale value to be served]") holds only if every caller,
including future maintainers, remembers to go through the function and never the dot. The
"treat every returned array as read-only" caveat warns against mutation, not against this
staleness bypass.

---

## Finding 3 — `FlowParameters.scalar_dissipation` uses a `NaN` sentinel where every sibling "field absent" case in the package uses `nothing`

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: api / phenomenology / Phenomenology — `FlowParameters`: "`NaN` rather than `nothing`
  keeps the bundle a plain, type-stable set of `Float64`s ... Arithmetic a caller does on the
  field itself is not covered — there `NaN` propagates as it always does."
- Contrast, PAGE: api / State — `ResolvedFields`: "`scalar_spectral` ... or `nothing` when the
  run carries no passive scalar."
- Contrast, PAGE: api / Propagator — `IntegratorBuffers`: "`scalar` — a `ScalarBuffers` ... else
  `nothing`."
- Contrast, PAGE: api / Cache — `ObservablesCache` Fields: "`scalar_physical` — the cached scalar
  in physical representation, or `nothing` for a scalar-free run."

**Description:** Every other "this run carries no scalar" case in the corpus is represented by
`nothing`, checked explicitly at the boundary (an `ArgumentError`, a `nothing`-guard). One type —
`FlowParameters` — instead uses `NaN`, whose entire failure mode is silent propagation through
arithmetic, which the docstring itself concedes ("propagates as it always does"). The stated
justification, keeping the bundle "a plain, type-stable set of `Float64`s," doesn't hold up in
Julia: a field typed `Union{Float64,Nothing}` is a concrete, compiler-specialized type (small
unions are union-split), and `FlowParameters` is not a hot-loop struct — it's an occasional
validation/diagnostic bundle, exactly the class of object the rest of the package is happy to let
carry a `Union` (as `ResolvedFields`, `IntegratorBuffers`, and `ObservablesCache` all do for the
identical "no scalar" case). This reintroduces, in one type, the silent-failure mode the rest of
the design goes out of its way to convert into a loud throw.

---

## Finding 4 — `deposit!` mutates `ObservablesCache` but is defined and owned by `Propagator`, not `Cache`

**Type:** organization · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Cache — module docstring: "The field slots are filled by `deposit!`, which
  `Propagator` owns rather than this module because it needs the scheme's scratch to recover the
  fields."

**Description:** `deposit!`'s leading, mutated argument is `cache::ObservablesCache`, yet the
verb is homed in `Propagator`, a different module from the one that defines and owns
`ObservablesCache`. This is legal and explained, but it means a reader looking for "what fills
the cache" must already know to look outside `Cache`'s own page — a discoverability cost the
module-map convention (a module docstring as "a linked one-liner per operation") only partly
offsets, since the pointer runs the "wrong" way (the owning module's page explains why it does
*not* have the mutator, rather than the mutator's page explaining why it lives elsewhere in
symmetric terms). Worth flagging as the one place the "each concern is its own module" principle
and Julia's usual first-argument-owns-the-verb convention pull in different directions.

---

## Finding 5 — The `AbstractForcing` protocol states "every mutating hook returns its mutated argument," then documents an exception in the same sentence

**Type:** api-gap · **Severity:** minor · **Confidence:** high

**Locations:**
- PAGE: api / Forcing — `AbstractForcing`: "Each mutating hook returns its mutated argument
  (`set_forcing_rate!` the rate, `add_forcing_source!` the right-hand side, `apply_forcing!` the
  field); `prepare_forcing!` returns `nothing`."
- Same page, `prepare_forcing!`: "Update the strategy `forcing`'s internal state once per step
  ... from the start-of-step `field` ... A stateful forcing owns whatever scratch this needs."

**Description:** `prepare_forcing!` is documented as mutating the forcing's own internal state —
exactly the kind of mutation the "returns its mutated argument" rule is stated to cover — yet it
returns `nothing` rather than `forcing`. The stated rule and its one exception sit in the same
sentence with no rationale given for the asymmetry (unlike, elsewhere in the corpus, the
carefully argued `-> Type` vs `Returns x.` split). A caller chaining forcing hooks functionally
cannot rely on the stated pattern without checking each hook individually.

---

## Finding 6 — `FlowConditions` and `FlowParameters` are near-homonyms sharing two field names, flagged in-doc as confusable rather than differentiated

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Generator — `FlowConditions`: "Not to be confused with `Phenomenology`'s
  `FlowParameters`, which shares two field names: this type holds what a run is configured with,
  that one holds what a run has been measured to have."

**Description:** The package's own naming rule (CLAUDE.md) requires a public name to be
"unambiguous (one reading)." `FlowConditions` (configured inputs: viscosity, Schmidt, forcings)
and `FlowParameters` (measured outputs: viscosity, dissipation, rms velocity, integral scale) sit
one edit-distance apart in both name and in two of their fields (viscosity, Schmidt/schmidt), and
the docstring's own disclaimer is evidence the authors recognized the risk — yet resolved it with
a warning rather than a more differentiated pair of names (e.g. a name that foregrounds
"measured" the way `FlowConditions` foregrounds nothing in particular). A cold reader who has
seen one type and encounters the other via autocomplete is exactly who this disclaimer is for.

---

## Finding 7 — The glossary's one-sentence definition of "deposit" doesn't cover `deposit_sample!`'s actual behavior

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: notation — Vocabulary: "deposit | to write an observable into the cache and mark the
  moment it belongs to."
- PAGE: api / Cache — `deposit_sample!`: "Record the particle velocities already written into
  `cache` ... as current ... The two are separate because the slot is the tracer set's own
  storage: the cache never fills it."

**Description:** The Vocabulary page states "deposit" as one atomic act: write the value *and*
mark its epoch. `deposit_sample!` is named with that verb but performs only the marking half —
the writing half is a separate, differently-named call (`record_particle_velocities!`) in a
different module. A reader who takes the glossary at its word (which the glossary itself invites:
"a docstring introduces a symbol on first use and need not repeat the convention") would expect
`deposit_sample!` to also write the values it deposits.

---

## Finding 8 — `StationarityCriterion`'s documented keywords don't map onto its documented `# Fields`, unlike every sibling type in the corpus

**Type:** organization · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun — `StationarityCriterion`: "The fields are not the keywords:
  `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol` and `skew_floor` all live inside
  `monitor`, which holds the sampled series together with the thresholds that judge them."

**Description:** Every other keyword-constructed type shown in this corpus documents `# Fields`
that mirror its keyword constructor directly (`FlowConditions(viscosity, schmidt, ...)`,
`Reference(citation, valid_Reλ)`, `ModelSpectrum(C_K, large_scale, dissipation, ref)`,
`Sreenivasan1998(asymptote, correction)`). `StationarityCriterion` breaks that pattern with an
internal `monitor` sub-bundle absorbing five of its seven keywords, and the docstring has to say
so explicitly because the convention elsewhere trains the reader to expect otherwise. Not wrong,
but a template deviation with no stated reason (contrast the careful, reasoned exceptions
recorded elsewhere in the corpus, e.g. the `vorticity_physical!`/`Cache.vorticity_physical`
f/`f!` exception to the one-generic rule).

---

## Finding 9 — `step!` and `deposit!`, always called back to back, lead with differently-typed first arguments

**Type:** api-gap · **Severity:** minor · **Confidence:** low

**Locations:**
- PAGE: api / Propagator — `step!`: "The leading argument differs from `deposit!`'s in kind, and
  it is worth knowing which: `scheme` here is a stateless dispatch tag, and what this call
  mutates is `state`, the second argument; `deposit!` leads with `cache`, the object it mutates."

**Description:** The docs pre-empt this by explaining the reason (`step!` needs a dispatch tag,
`deposit!` doesn't) and note the tail arguments still line up. Still, the two verbs that make up
the documented hand-run loop's core pair (`step!` then `deposit!`) lead with an argument of a
different *kind* in each call — a scheme value versus the mutated object itself — which is a real
(if minor, and self-acknowledged) usability wrinkle for exactly the pairing the docs present as
the canonical idiom.

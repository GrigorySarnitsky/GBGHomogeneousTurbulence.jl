# docstring-review-round3.md — user read-through, round 3 (SETTLED — worked off in a3a523c…08c2c4d; header corrected 2026-08-20)

A fresh human read of the **rendered** docs after the 8-hat panel fix pass (commits `90c9829`,
`3e6c5e7`). The user finds problems by reading and reports them; collected here verbatim, then distilled
to a **defect-class** and a **cold-read probe**. **Do NOT act on any of these until the user says "fix."**
See [[docstrings-are-the-steering-surface]].

---

## §1 — Home page carries architecture-decision rationale the reader doesn't want

**Surface:** Home / `docs/src/index.md`, the second paragraph ("It is built on `GBGPeriodicFields`…").

**Reported (user):** comparing the three intro surfaces — the **Home page**, the **umbrella module
docstring** (API › GBGIsotropicTurbulence, from `src/GBGIsotropicTurbulence.jl`), and the **GitHub
README** — the Home page is the one that keeps the old architecture-decision talk:

> "GBGPeriodicFields is deliberately time- and particle-free; this package is the consumer that owns
> time integration, forcing, the scalar transport, particle tracking, and the statistics."

That sentence is an **architecture decision the reader has no interest in.** (The *preceding* clause on
the same line — "built on `GBGPeriodicFields`, which supplies every field operation — transforms,
spectral differential operators, convolution, interpolation, and reductions" — is fine; it says what PF
*gives*. It is specifically the "deliberately time-/particle-free … the consumer that owns …" sentence
that editorializes.)

The two sibling surfaces describe the same package↔backend relationship *without* the framing:
- umbrella module docstring: "Built on `GBGPeriodicFields`." (clean)
- GitHub README: "builds on `GBGPeriodicFields.jl`, which supplies the underlying field representations,
  FFT transforms, fiberwise algebra, spectral differential operators, reductions, and grid↔point
  transfer." (says what PF supplies, no decision framing)

**Defect class:** *architectural rationale leaking onto a user-facing surface* — the thin-physics /
rich-numerics division-of-labor ("deliberately …", "the consumer that owns …") is `ARCHITECTURE.md`
material, not Home-page prose. Compounded by a **cross-surface inconsistency**: Home vs module-docstring
vs README tell the PF story three different ways.

**Cold-read probe:** on each user-facing intro (Home, README, umbrella module docstring), flag any
sentence that *justifies a design decision* — "deliberately", "the consumer that owns", the
thin-physics/rich-numerics split, "owns no physics/numerics of its own" — rather than tell the reader
*what the package does* or *what the backend supplies them*. Rationale belongs one hop away in
`ARCHITECTURE.md`.

**Advisory resolution direction (NOT applied):** drop the "deliberately time-/particle-free … consumer
that owns …" sentence from the Home page (keep the "supplies every field operation" clause), and align
the three intro surfaces to one neutral framing of what PF supplies + what this package does.

---

## §2 — Inconsistent `@extref` linking of GBGPeriodicFields types (FixedDomain `# Fields`, and repo-wide)

**Surface:** API › SimulationDomain, `FixedDomain` type docstring `# Fields` section (`src/SimulationDomain.jl`).
User: "Really inconsistent overall" — i.e. a broad pattern, not just this one list.

**Reported (user):** within the *same* Fields list, some GBGPeriodicFields (PF) entities are hyperlinked
(`@extref` to PF docs) while sibling PF entities are bare backticks:
- **Linked:** `Grid3D` (`grid`), `FieldSpectralMultipliers` (`multipliers`) — PF `@extref`; `DealiasingStrategy`
  (`dealiasing`) — intra-package `@ref`.
- **Not linked, though PF-backed:** the memory `layout`; the transform `plans` (`velocity_plans` /
  `scalar_plans` / `tensor_plans`); the `squared_wavenumber_kernel` (the "scalar-field kernel"); the
  `dealias` kernel.

**Defect class:** *inconsistent cross-package (`@extref`) linking of dependency types on a user-facing
surface.* The doc policy makes the PF types "the deliberate `@extref` exception" worth a jump — but the
rule is applied to some PF entities and not their siblings in the same list, so the linking reads as
arbitrary.

**Consideration for the fix (not resolved here):** some unlinked entities may have *no* PF doc
destination (PF may not export/document a transform-plan or layout type, or IT may hold them opaquely) —
which would *explain* the asymmetry, but the docs never say so, and a reader only sees inconsistency. The
fix needs a **stated, uniform principle:** link every PF type that has a published `objects.inv`
destination (first mention), and accept bare backticks only where no destination exists — applied the
same way everywhere.

**Cold-read probe:** in any docstring naming PF types, check `@extref`-linking is uniform — flag a
list/paragraph where some PF types render as links while sibling PF types are bare backticks. Cross-check
each bare PF type against PF's published `objects.inv`: a destination ⇒ it should be linked; none ⇒ that
is the *only* acceptable reason it is bare.

**Advisory resolution direction (NOT applied):** either `@extref`-link the PF-backed
`layout` / `plans` / `squared_wavenumber_kernel` / `dealias`-kernel types (where PF documents them) to
match `Grid3D` / `FieldSpectralMultipliers`, or — if they have no PF destination — leave them bare *and
apply the same rule across every docstring* so the pattern reads as intentional. Sweep repo-wide.

---

## §3 — Dealiasing-strategies section intro mixes descriptive phrases with a bare type name (`PhaseShift`)

**Surface:** API › SimulationDomain, "## Dealiasing strategies" section intro
(`docs/src/api/SimulationDomain.md`).

**Reported (user):** "the PhaseShift is cited as its type, while others are plain words." The intro reads:
> "The aliasing-control strategy passed to `FixedDomain` — the supertype, then the sharp `2/3`-rule
> default, the smooth Hou–Li filter, and `PhaseShift`."

The siblings are described by **role/behavior** ("the supertype" = `DealiasingStrategy`, "the sharp
2/3-rule default" = `TwoThirds`, "the smooth Hou–Li filter" = `HouLi`), but the last item is given as its
**bare type name** `PhaseShift`. Mixed register in one list.

**Defect class:** *sibling items in one list referenced in two registers* — descriptive prose vs bare
type name. (The section-intro convention here is descriptive prose; the type names live in the `@docs`
block immediately below, so a bare type name in the intro is off-register.) Same family as §2 (a
reference *style* not applied uniformly to siblings).

**Provenance note:** self-inflicted — introduced by the PhaseShift-enumeration fix (commit `90c9829`, the
panel §M3 fix), which appended `PhaseShift` as a type name where the surrounding items were descriptive.

**Cold-read probe:** in a section-intro / map sentence that lists sibling concretes by descriptive
phrase, flag any item given instead as a bare type name (or vice versa) — one register per list.

**Advisory resolution direction (NOT applied):** describe PhaseShift by its behavior to match — e.g.
"…, the smooth Hou–Li filter, and the phase-shift shift-average" — dropping the bare `PhaseShift` type
name (it appears in the `@docs` block below).

---

## §4 — Citation handling is inconsistent and unlinked (POLICY-LEVEL, not a one-line fix)

**Surface:** `PhaseShift` docstring (`src/SimulationDomain.jl`): "Phase-shift dealiasing follows Patterson
& Orszag (1971); the combination with spherical truncation is Rogallo (1981)."

**Instances (accumulating — bare author-year, no venue, no link):**
- `PhaseShift` — "Patterson & Orszag (1971)", "Rogallo (1981)".
- `Linear` (`src/Forcing.jl`) — "(Lundgren 2003)" *(user-confirmed: "no full clickable citation for
  Lundgren")*; `ConstantPower` sits next to it (Architecture attributes Lundgren to `Linear` only — see
  the panel's §4.4 fix).
- `derivative_skewness` — "(Betchov 1956)".
- `IFLowStorageRK3` (`src/Propagator.jl`) — "(Williamson 1980)" *(user-confirmed)*. Its sibling `IFRK2`
  cites "Heun" — a **classical** method that correctly needs **no** reference (the policy's classical
  exception), so it is the one place the bare style is right; the fix must **not** "correct" it.
- … and others across SimulationDomain / Generator.

Contrast `Phenomenology`, which renders full structured `Reference`s for the same class of thing. (`HouLi`
is the *worse* sub-case — no citation at all; see §5.)

**Reported (user):** "Why no proper citations and links? I thought we had a policy on how references in
docstrings must be handled."

**Policy reality (for the record):** the current policy *is* inline **author-year**, *verbatim-consistent
with* the `ARCHITECTURE.md` §References entry, **self-contained for the REPL** (no cross-links — a
docstring must read complete at `?PhaseShift`, where links are dead); the full bibliographic entry lives
once in §References. By that policy the PhaseShift line is **format-compliant** — bare
"Patterson & Orszag (1971)" / "Rogallo (1981)", both now with full §References entries (added `90c9829`).
So this is not a policy *violation*; it is a policy *gap*.

**The real gaps (worth a decision):**
1. **Inconsistent citation MECHANISM.** `Phenomenology` laws carry structured `Reference` objects — full
   author-year-venue-volume-page, rendered in the docstring (e.g. `_YAGLOM = Reference("Yaglom (1949),
   Dokl. Akad. Nauk SSSR 69, 743")`) — while the DNS-side docstrings (`PhaseShift`, and siblings in
   SimulationDomain / Generator / Propagator) carry only a bare inline author-year, no venue. Two citation
   systems in one package.
2. **No linked bibliography in the RENDERED docs.** The policy optimizes for REPL-completeness, so the
   rendered HTML has no clickable citation and no References page, even though a rendered site supports
   one. The user reads "and links" and finds none.

**Defect class:** *citation handling not uniform* (structured `Reference` vs bare author-year) + a
*REPL-first-vs-rendered tension* (no clickable bibliography). **Policy-level / cross-cutting**, not a
per-docstring wording fix.

**Decision flag (for the user) — two directions:**
- (a) *Keep REPL-first:* accept bare author-year + no links in rendered docs, but **unify** the DNS-side
  docstrings onto one style, and consider giving them the `Reference`-style venue the Phenomenology laws
  already render.
- (b) *Adopt a real bibliography:* `DocumenterCitations.jl` — `@cite Rogallo1981` in docstrings, a shared
  `.bib`, a rendered **References** page with clickable citations. Delivers "proper citations and links",
  but changes the docstring register and needs a REPL-fallback story (`@cite` renders as a dead token at
  the REPL, in tension with the self-contained-at-the-REPL rule).

**Cold-read probe:** flag any docstring citation that is a bare author-year with no venue while a sibling
module (`Phenomenology`) renders a full structured reference for the same class of thing — one citation
mechanism per package. And: if the rendered docs have no References/bibliography page, every inline
author-year is a dead end for a reader chasing the source.

---

## §5 — `HouLi` names a published method but carries NO citation (policy item-6 miss)

**Surface:** `HouLi` docstring (`src/SimulationDomain.jl`).

**Reported (user):** "No reference to Hou-Li too." The docstring fully describes the smooth Hou–Li
spectral filter ``\exp(-\text{strength}\,(\kappa/\kappa_{\mathrm{Ny}})^{\text{order}})`` (order = 36,
strength = ``-\log`` machine-ϵ) but carries **no citation** — even though "Hou–Li" is literally the
method's authors.

**Defect class:** *a named / published method with no inline citation* — a direct miss on doc-policy item
(6). One step worse than §4: `PhaseShift` *has* its author-year (just bare/unlinked); `HouLi` has **none
at all**, for an eponymous method.

**Reference (verify at fix time):** Hou, T. Y. & Li, R. (2007), "Computing nearly singular solutions using
pseudo-spectral methods," *J. Comput. Phys.* **226**, 379–397 — the ``\exp(-\alpha(k/k_{\max})^m)`` smooth
filter with ``\alpha = m = 36`` (reaches machine epsilon at Nyquist), matching the docstring's defaults
exactly; also the filter TurTLE uses. Confirm exact venue/pages before citing.

**Cold-read probe:** for every method whose NAME encodes an author or paper (`HouLi`, `TwoThirds`/Orszag,
`Betchov`, `Rogallo`, `Pao`, `Lundgren`, `Passot–Pouquet`, the Williamson RK3, …), check the docstring
carries an inline author-year citation. Flag an eponymous method whose docstring omits it. (Cross-cut with
§4: the dealiasing strategies alone show the unevenness — `PhaseShift` cited, `HouLi` not; **check
`TwoThirds`** — the 2/3 rule is Orszag 1971, now in §References.)

**Advisory resolution direction (NOT applied):** add "(Hou & Li 2007)" to the `HouLi` docstring + the
matching §References entry; while there, audit the sibling strategies (`TwoThirds` → Orszag 1971) so the
dealiasing family cites uniformly. Ties into §4's mechanism decision.

---

## §6 — `FlowConditions` unlinked in the Forcing module docstring (broadens §2 to intra-package `@ref`)

**Surface:** `Forcing` module docstring (`src/Forcing.jl`), rendered on API › Forcing.

**Reported (user):** "FlowConditions must be linked." In the module docstring the sibling documented types
are `@ref`-linked — `NoForcing`, `BandRescaling`, `Linear`, `ConstantPower`, `DeferredForcing`,
`Simulation` (all blue) — but `FlowConditions` ("`FlowConditions` takes a separate `velocity_forcing` and
`scalar_forcing`") is bare backticks. `FlowConditions` is a documented IT type (in `Generator`), so it
should link like its siblings.

**Defect class:** *missing intra-package `@ref` for a documented type* — the same "linking not uniform
across siblings" family as §2, but for an INTRA-package `@ref` (IT's own type), not a PF `@extref`.
**Broadens §2:** the linking inconsistency is not only PF — it hits IT's own documented types too.

**Fix consideration (verify at fix time):** `FlowConditions` lives in `Generator`, included *after*
`Forcing`, so it is not in `Forcing`'s namespace — a **bare** `[`FlowConditions`](@ref)` may fail to
resolve (the cross-module resolution that broke the build on `State.jl` → `[`Simulation`](@ref)`, fixed in
`3e6c5e7` by dropping to plain backticks). Tension: `Simulation` / `DeferredForcing` *are* linked in this
very docstring despite the same include-order situation — so either bare cross-module `@ref` resolves here
(and `FlowConditions` was simply forgotten) or a fully-qualified
`[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions)` is needed. **Determine the
correct form and verify against `docs/make.jl` before committing.**

**Cold-read probe:** (§2 extended) in any docstring, for each documented type mentioned — IT's own
(`@ref`) or PF's (`@extref`) — check it is linked on first mention; flag a documented type left bare while
its siblings in the same docstring are linked.

**Advisory resolution direction (NOT applied):** link `FlowConditions` (bare `@ref` or fully-qualified per
the build), matching its linked siblings.

---

## §7 — `FlowConditions` type docstring omits the mandated `# Fields` section

**Surface:** `FlowConditions` type docstring (`src/Generator.jl`), rendered on API › Generator.

**Reported (user):** "We have a type, but here nothing tells about its fields and how to access them." The
docstring is constructor-first (shows `FlowConditions(; viscosity, schmidt, velocity_forcing,
scalar_forcing)` + prose) but has **no `# Fields` section** — nothing names the accessible fields or how to
read them (`conditions.viscosity`, `.schmidt`, `.velocity_forcing`, `.scalar_forcing`).

**Defect class:** *type docstring missing the mandated `# Fields` section.* The type-docstring-structure
policy (constructor-first, then a demoted `# Fields` with the field explanations — codified in R2, task
#13) requires it, and sibling types render one (`FixedDomain`, `IntegratorBuffers`, `Simulation` all have
a `# Fields` list). **`FlowConditions` and `Tracers`** both omit it (`Tracers` user-flagged: "another
type without explanation of its fields?!!!") — so it is a **recurring pattern, not a one-off**, and the
`# Fields` policy was not applied uniformly. `Tracers`' docstring names the accessors
(`tracer_positions` / `tracer_velocities` / `ntracers`) and says "the remaining fields are preallocated
predictor and point-value scratch", but carries no `# Fields` section. **Fix = a repo-wide sweep of every
documented struct type**, not just these two.

**Note (relevance):** the fields are genuinely user-facing — e.g. the observables read `viscosity` from
`sim.conditions` (panel api-user finding), so "how to access them" is not academic. (Even though the field
names equal the constructor keywords, the policy + sibling consistency still call for the section.)

**Cold-read probe:** for every documented struct type, check the docstring carries a `# Fields` section
naming the accessible fields (and, where a field is read off an object the user holds, how to reach it —
e.g. `sim.conditions.viscosity`). Flag a type documented by constructor only, no `# Fields`, especially
where sibling types have one.

**Advisory resolution direction (NOT applied):** add a `# Fields` section to `FlowConditions`
(`viscosity`, `schmidt`, `velocity_forcing`, `scalar_forcing`), matching `FixedDomain` /
`IntegratorBuffers` / `Simulation`.

---

## §8 — `velocity_nonlinear!` / `scalar_nonlinear!` don't document the `phase_shift` argument

**Surface:** `velocity_nonlinear!` function docstring (`src/Generator.jl`), rendered on API › Generator.
Same on `scalar_nonlinear!` (user-confirmed) — there `û`, `φ̂`, *and* `phase_shift` are the mask-unused
args, so the "what to pass" contract question applies ×3.

**Reported (user):** "I don't think it documents what is that phase_shift kernel and where would a user get
one." The signature ends `…, phase_shift`, and the prose *uses* it ("the `phase_shift` translation kernels
and scratch", "the `phase_shift` buffers"), but there is **no argument entry** stating WHAT `phase_shift`
is — a `PhaseShiftBuffers` bundle (the two translation kernels + displaced-evaluation scratch), or
`nothing` for a non-PhaseShift domain — or WHERE to get one (held in the `IntegratorBuffers` as
`buffers.phase_shift`, built when `domain.dealiasing isa PhaseShift`; assembled by `step!`).

**Also reported (user, same two arguments):** for the *mask* strategies the prose says "`û` and
`phase_shift` are unused" — but "unused" ≠ what to *pass*. They are **positional**, so a caller must supply
*something*: "Supply arguments `û` and `phase_shift` with `nothing`?" The docstring never states the
calling contract for the arguments a strategy ignores. **Verified against the code:** the mask dispatch
`_velocity_nonlinear!(::DealiasingStrategy, …)` never touches `û` or `phase_shift`, so **`nothing` is
accepted** — but the docstring doesn't say it. This is the flip side of the first point: the
`û`/`phase_shift` **argument contract is under-specified across strategies** — for PhaseShift, what they
*are* and where to get them; for the mask strategies, what to *pass* when unused.

**Defect class:** *a signature argument mentioned only by use (bound-by-use), not documented* — a
self-containedness / argument-coverage miss (function-docstring item 3 + doc-edit checklist #2; the "an
arg mentioned only in prose reads as bound-by-use and is UNDOCUMENTED" pattern, cf. how `ops`/`ws` once
slipped). Every other arg (`nonlinear`, `û`, `u`, `ω`, `domain`, `product_physical`, `product_spectral`)
is described; `phase_shift` is the un-enumerated one. Provenance: added with the PhaseShift feature.

**Secondary consideration (for the fix):** `phase_shift` is an *internal* buffer bundle — a user
hand-calling `velocity_nonlinear!` couldn't construct a `PhaseShiftBuffers`. So the fix is either (a)
document it ("from `buffers.phase_shift`; `nothing` unless PhaseShift; assembled by `step!`"), or (b)
clarify the function's role (an internal assembly, not typically called directly). Worth asking whether a
raw internal arg belongs on the *public* surface at all.

**Cold-read probe:** for every function docstring, enumerate the signature args (positional + keyword) and
confirm each has its own "what it is / where it comes from" entry — flag any argument appearing only in
passing prose. Weight non-obvious internal args (`phase_shift`, scratch bundles) highest: the reader must
be told where to obtain them.

**Advisory resolution direction (NOT applied):** document the full `û`/`phase_shift` contract on
`velocity_nonlinear!` and `scalar_nonlinear!` — for `PhaseShift`, a `PhaseShiftBuffers` from
`buffers.phase_shift`; for the mask strategies, state explicitly that both are ignored and **`nothing` may
be passed** (verified accepted). One argument entry that covers both dispatch paths.

---

## §9 — `scalar_nonlinear!` second paragraph is a cramped wall of text (and unlike its `velocity_nonlinear!` sibling)

**Surface:** `scalar_nonlinear!` function docstring (`src/Generator.jl`), rendered on API › Generator — the
second paragraph.

**Reported (user):** "that second paragraph reads quite cramped." The single paragraph packs, without
breaks: the conservative-form identity ``-\nabla\cdot(\boldsymbol u\varphi) = -\boldsymbol u\cdot\nabla\varphi``;
the mean-conservation rationale (the ``\boldsymbol\kappa = \boldsymbol 0`` argument); the pseudospectral
formula ``-\mathrm{dealias}(\mathrm i\boldsymbol\kappa\cdot\widehat{\boldsymbol u\varphi})``; the
mask-vs-PhaseShift assembly (which args each uses/ignores); and the scratch-reuse note
(`product_physical` / `product_spectral`). Five distinct ideas in one block.

**Defect class:** *a docstring paragraph packs too many distinct ideas into one dense block* — a
readability / paragraphing defect. Compounded by a **cross-sibling inconsistency**: `velocity_nonlinear!`
breaks the *same* material into several short paragraphs (identity → Leray projection → assembly → scratch),
while `scalar_nonlinear!` did not get the same treatment.

**Cold-read probe:** flag a docstring paragraph that runs many sentences and chains ≥ 3 distinct concerns
(formula + rationale + computation + arg-dispatch + scratch) without a break; and diff an `f` / sibling
pair for uneven paragraphing of equivalent content.

**Advisory resolution direction (NOT applied):** break the paragraph into shorter units matching
`velocity_nonlinear!`'s structure (conservative-form identity; the mean-conservation note; the
pseudospectral computation + mask-vs-PhaseShift assembly; the scratch reuse). Pulling the per-argument
bits into their own entries also feeds §8's contract fix.

---

## §10 — Observables docstring's blanket "reductions are exact" hides which observables actually need a dealiased field

**Surface:** `Observables` module docstring (`src/Observables.jl`): "Each reduces a field to a scalar …
none dealiases first — a reduction is Parseval-exact and the run keeps the field dealiased, so a reduction
in physical representation is exact too."

**Reported (user):** "To be clear, all observables are to be called on dealiased (truncated) fields? Or
not?" — the blanket exactness claim doesn't let a reader answer this.

**The reality (verified against the ops):**
- **Quadratic inner-product reductions** — `kinetic_energy` (½⟨u,u⟩), `dissipation` (ν⟨ω,ω⟩),
  `scalar_variance` (⟨φ,φ⟩), `scalar_dissipation` (2ϰ⟨φ̂,|κ|²φ̂⟩), `energy_spectrum` (|û|² per shell),
  `integral_scale` (from it): **Parseval-exact** — the *computation* is exact on any field. But that is
  NOT the same as dealiasing-*independent*: the ``|\boldsymbol\kappa|^2``-weighted `dissipation` /
  `scalar_dissipation` faithfully include, and heavily weight, any spurious modes past ``\kappa_{\max}``
  (see the refinement below).
- **`max_speed`** — a physical max, no aliasing concern.
- **`derivative_skewness`** — the exception: it reduces a **cubic** quantity ⟨det S⟩ *in physical space*
  (it forms `S` then `det!` pointwise), so its accuracy **depends on a band-limited input**. This is what
  "the run keeps the field dealiased, so a reduction in physical representation is exact too" is really
  guarding — but it is stated as a *general* property, not a precondition specific to skewness.

**Defect class:** *a blanket exactness claim that conflates dealiasing-independent (quadratic, Parseval)
reductions with the one that has a real band-limited precondition (the cubic skewness).* The "a reduction
is Parseval-exact" quantifier is false for the cubic `derivative_skewness`; a reader cannot answer "must I
call these on dealiased fields?".

**Correctness subtlety to VERIFY (for the fix, not resolved here):** the ``2/3`` rule dealiases *quadratic*
products; a *cubic* reduction (⟨det S⟩) on a ``2/3``-truncated field is not obviously alias-free — with
retained ``|\boldsymbol\kappa| \le N/3``, triple sums reach ``N`` (a wrap into the mean ``\boldsymbol\kappa
= \boldsymbol 0`` needs ``|k_1+k_2+k_3| = N``, i.e. all three at the edge — plausibly negligible, but not
"exact"). So even the "run keeps it dealiased ⇒ physical reduction exact" claim needs checking
*specifically* for `derivative_skewness`. Confirm before re-asserting exactness.

**Refinement (user follow-up — "could `scalar_dissipation` be called on a `φ̂` with non-zero modes past
``\kappa_{\max}``?"):** the "quadratic ⇒ dealiasing-independent" bucket is too clean — the
``|\boldsymbol\kappa|^2``-weighted dissipations have a band-limited precondition too, for a *different*
reason than the cubic skewness (not aliasing, but faithfully over-weighting spurious high-``\kappa``).
- **Package internals — no** *(verify)*: the run's `φ̂` is band-limited — the IC is seeded de-aliased (the
  State page seeds a "de-aliased" field) and the step preserves it (the nonlinear term is dealiased; the
  integrating factor only *scales* existing modes, adding none past ``\kappa_{\max}``; forcings act on
  low-``\kappa`` bands). Verify: `random_scalar!` really applies `domain.dealias`, and no RK stage or
  forcing injects past ``\kappa_{\max}``.
- **A user — yes**: `scalar_dissipation(φ̂, …)` accepts *any* `φ̂`; a hand-built / externally-sourced
  non-truncated field passes straight through, and the ``|\boldsymbol\kappa|^2``-weighted sum then includes
  its high-``\kappa`` content. So `dissipation` / `scalar_dissipation` are the observables **most**
  sensitive to a non-band-limited input, and there is **no documented precondition**. "Parseval-exact" is
  right about the *computation*, wrong about the *physical meaning*: it is the true dissipation only on a
  clean (band-limited) field.

**Cold-read probe:** flag a blanket "the reduction is exact / Parseval-exact" claim over a set of ops where
at least one reduces a *higher-than-quadratic* (physical-space nonlinear) quantity — Parseval covers
quadratic inner products only; a cubic/quartic physical-space reduction has a genuine band-limited
precondition that must be stated per-op.

**Advisory resolution direction (NOT applied):** rewrite the sentence to distinguish — the quadratic
inner-product reductions are Parseval-exact on any field (no dealias needed); `derivative_skewness` reduces
a cubic physical-space quantity and assumes a band-limited (dealiased) input; state that precondition on
`derivative_skewness` itself. Resolve the cubic-on-``2/3`` exactness question first.

---

## §11 — Bare-backticked PF *function* `weighted_inner` reads as ours (implementation-leak; the general criterion)

**Surface:** `scalar_dissipation` docstring (`src/Observables.jl`): "…the Dirichlet (``H^1``) energy
``\langle\varphi, |\boldsymbol\kappa|^2\varphi\rangle``, formed by a fused `weighted_inner` against the
squared-wavenumber multiplier `domain.squared_wavenumber_kernel` …".

**Reported (user):** `weighted_inner` is a bare-backticked identifier — a reader thinks it's an IT
function, but it lives in **PF (GBGPeriodicFields)**. Fix: **`@extref`-link it**, or **drop it for the
plain math** (the formula ``\langle\varphi, |\boldsymbol\kappa|^2\varphi\rangle`` is already there, so the
"fused `weighted_inner`" detail adds nothing a user needs). *Contrast (user):* naming
`domain.squared_wavenumber_kernel` **is** appropriate — it explains *why* `scalar_dissipation` requires the
`domain` argument, unlike the velocity `dissipation`.

**Defect class:** *a bare-backticked dependency (PF) function reads as a package function* — sharper than
§2/§6's "linking not uniform": an **unlinked** PF identifier actively **misleads** (the reader searches IT
for `weighted_inner`), and it's an **implementation-detail leak** — policy already routes implementation
internals to `#` comments, not user docstrings. So this is a *policy violation*, not just a gap.

**THE CRITERION (this is the reusable principle — codify it):** a code identifier in a docstring earns its
place only if it either
1. is `@ref` / `@extref`-linked to where it lives, **or**
2. names something on the **user-facing API surface the reader must know** — e.g.
   `domain.squared_wavenumber_kernel` (justifies the `domain` arg), `sim.conditions.viscosity` (how to read
   viscosity).

A bare-backticked *dependency-internal* function that is neither — that only says *how* a result is
computed — must be **linked or replaced by the math/prose**. (i.e. §2/§6 "link uniformly" + this: never
leave a dependency function bare where it reads as ours and carries no API meaning.)

**Cold-read probe:** flag a bare-backticked identifier that (i) is a PF/dependency function, and (ii) only
describes *how* a result is computed rather than the user-facing API — it reads as an IT function and
misleads; `@extref` it or cut it for the already-present math. Keep identifiers that explain the API
surface (a `domain.*` / `sim.*` field that justifies a required argument or a return).

**Sweep (repo-wide, the same class):** the DNS-side docstrings name many PF ops as bare backticks —
`weighted_inner`, `symmetric_gradient`, `inner`, `det`, `cross!`, `helmholtz_projection!`, `to_spectral!`,
`to_physical!`, `radial_spectrum`, `translation_kernel`, `convolve!`, `combine!`, … Audit each: link
(`@extref`), or cut for math/prose if it's pure "how", keeping only those that carry API meaning.

**Advisory resolution direction (NOT applied):** in `scalar_dissipation`, `@extref`-link `weighted_inner`
or replace "formed by a fused `weighted_inner` against …" with plain prose/math (e.g. "computed straight
from the spectral coefficients against `domain.squared_wavenumber_kernel`, no physical
``\nabla\varphi`` materialized"). Keep `domain.squared_wavenumber_kernel`. Then run the sweep above.

---

## §12 — `integral_scale`: add `L_{22}` and the unprojected (trace-correlation) integral scale [requested addition]

**Surface:** `integral_scale` docstring (`src/Observables.jl`) — gives only
``L_{11} = \tfrac{3\pi}{4}\,\int_0^\infty (E/\kappa)\,d\kappa / \int_0^\infty E\,d\kappa``.

**Reported (user):** "Just for user reference, add how one calculates ``L_{22}`` from it, as well as the one
defined from the correlation function ``\langle u_i(\boldsymbol x)u_i\rangle`` with no projection." A doc
*enhancement* (reference formulas), not a defect — the docstring is correct, just narrower than wanted.

**Verified physics (ready to apply):** with ``I = \int_0^\infty (E/\kappa)\,d\kappa / \int_0^\infty E\,d\kappa``
and the docstring's ``L_{11} = \tfrac{3\pi}{4} I``:
- **Lateral / transverse:** ``L_{22} = \tfrac12 L_{11} = \tfrac{3\pi}{8} I`` (isotropic relation; already
  stated in `notation.md`).
- **Unprojected (trace) scale** from ``R_{ii}(r) = \langle u_i(\boldsymbol x)u_i(\boldsymbol x+\boldsymbol r)\rangle``
  (no longitudinal/transverse projection):
  ``L_E = \dfrac{\int_0^\infty R_{ii}\,dr}{R_{ii}(0)} = \dfrac{\pi}{2} I = \tfrac{2}{3} L_{11}``, equivalently
  the component-weighted mean ``L_E = \tfrac13\,(L_{11} + 2L_{22})`` (1 longitudinal + 2 transverse).
  *Derivation:* ``R_{ii}(r) = 2\int_0^\infty E(\kappa)\,\tfrac{\sin\kappa r}{\kappa r}\,d\kappa`` ⇒
  ``\int_0^\infty R_{ii}\,dr = \pi\int_0^\infty (E/\kappa)\,d\kappa`` (using
  ``\int_0^\infty \sin(\kappa r)/r\,dr = \pi/2``) and ``R_{ii}(0) = 2\int_0^\infty E\,d\kappa``.

**Defect class:** *doc completeness / user-reference enhancement* (not an error). Cheap and high-value —
all three scales share the one ratio ``I``.

**Advisory resolution direction (recorded; NOT applied per collect-only):** add a short reference note
after the ``L_{11}`` formula — the lateral ``L_{22} = L_{11}/2`` and the unprojected
``L_E = \tfrac{2}{3}L_{11} = \tfrac13(L_{11}+2L_{22})`` (from the trace correlation
``\langle u_i u_i\rangle``). Keep `integral_scale` **returning** ``L_{11}`` (its documented job); the note
is reference-only. Re-check the ``L_{11}`` coefficient and the ``L_E`` derivation against Pope / Batchelor
at apply time.

---

## §13 — `Tracers(positions)`: allocation backend/type undocumented, and it falsifies SimulationDomain's "backend & precision enter only here"

**Surfaces:** `Tracers` type docstring (`src/Particles.jl`), 2nd form `Tracers(positions; scheme = CatmullRom)`;
and the `SimulationDomain` module docstring: "Precision and backend enter here and flow everywhere from here."

**Reported (user):** "where will it allocate, CPU/CUDA/ROCm? And what type? … [SimulationDomain] claims
that's the only place where you set the backend and precision. How would `Tracers(positions)` know these
and allocate in agreement with the domain?"

**Answer (no domain is passed):** `Tracers(positions)` can only take the tracers' backend + element type
from the **`positions` array itself** — the docstring never says so (doc gap). And that makes `positions`
a **second** place backend/precision enters, **contradicting** the SimulationDomain "enter only here"
claim (doc overclaim). The design facet (unchecked second source ⇒ mismatch) is D-r3-3.

**Defect class:** (a) *undocumented allocation contract* — a constructor that allocates internal scratch
must state the backend/eltype source (here: inherited from `positions`); (b) *a cross-surface
contradiction* — an "X is the only place Y happens" invariant on one page falsified by another surface.

**Cold-read probe:** for any constructor that allocates internal buffers, check the docstring states the
backend/eltype source; and audit every "X is the *only* place Y happens" claim against the rest of the API
for a second entry point that falsifies the "only".

**Advisory resolution direction (NOT applied — tied to D-r3-3):** document that `Tracers(positions)` takes
its backend/eltype from `positions` and that these must match the run's domain; soften the SimulationDomain
"enter only here" claim if the positions-form stays; OR (design, D-r3-3) route backend/precision through
the domain so the invariant stays literally true.

---

## §14 — `Tracers(positions)`: the array-shape symbol `M` is used unbound (it's the tracer count)

**Surface:** `Tracers` type docstring (`src/Particles.jl`): "the second wraps a given `(M, 3)` position
array." (Same constructor as §13.)

**Reported (user):** "We should state explicitly that `M` is the number of tracers." The row count `M` of
the `(M, 3)` positions array is used without being defined — it is the **number of tracers** (the 3
columns are the ``x, y, z`` components).

**Defect class:** *an array-shape dimension symbol used unbound* — the "every symbol bound at first use"
self-containedness rule (doc-edit checklist #2). A reader meets `(M, 3)` with no statement of what `M` is.

**Cold-read probe:** flag an array-shape dimension symbol (`M`, `N`, `K`, …) in a signature or prose that
is never bound to its meaning (rows = tracers, the 3 columns = the spatial components, …).

**Advisory resolution direction (NOT applied):** state it — e.g. "wraps a given `(M, 3)` array of `M`
tracer positions (the 3 columns are the ``x, y, z`` components)."

---

# DESIGN TRACK (round 3) — structural questions, not docstrings (to discuss, then decide)

## D-r3-1 — `step!` takes loose `û`, `φ̂` (no `State`), and there is no `Generator` type

**Surface:** `step!(integrator, û, φ̂, domain, buffers, conditions, dt)` (`src/Propagator.jl`).

**Reported (user, design question):** "What's the role of our `State` (`ResolvedFields`) if even `step!`
accepts individual fields rather than state? … why is there no type for the generator. I would accept
propagator to accept something of type `State` and type `Generator`."

**Two sub-questions:**
1. **`State` vs loose fields.** D1/D2 reified `ResolvedFields` as *the single source of truth*, yet the hot
   loop takes `û`/`φ̂` loose — a real tension. `Propagator` is included *after* `State`, so
   `step!(integrator, state::ResolvedFields, …)` is available (mutable arrays ⇒ in-place still works;
   optional scalar already encoded). The "Propagator is pure numerics on raw fields" defense is stylistic,
   not structural. **Lean: take the `State` — coherent with the reification, low-risk.**
2. **No `Generator` type.** The MZ "Generator" is currently the `Generator` **module** (free RHS functions
   dispatched on `domain.dealiasing`) + `FlowConditions` (ν, Sc, forcings) — so `step!` receives the
   generator unbundled as `(domain, conditions)`. User's target `step!(integrator, state::State,
   generator::Generator, …)` is MZ-symmetric and collapses loose args. **Open question — what would a
   `Generator` type hold?** Risk (a): a thin re-wrap of `FlowConditions` + the dealiasing choice; risk (b):
   a god-object (domain + conditions + buffers ≈ the whole `Simulation` minus the state). **Lean: worth it
   only if `Generator` reifies the RHS *operator* (dealiasing strategy + integrating factor + forcing
   wiring), not merely renames `FlowConditions`.**

**Touches recorded decisions:** D1/D2 (state reified as `ResolvedFields`); the thin-physics "Generator =
module, `FlowConditions` = config" choice (likely a decision-log entry). **Do NOT re-litigate without
grounding in `ARCHITECTURE.md`'s decision log first** — pull those entries before committing a direction.

**Status:** DESIGN item, collect-only. Discuss → decide → (if adopted) refactor the `Propagator` API +
`SimulationRun` wiring. Combined proposal on the table: `step!(integrator, state::State,
generator::Generator, buffers, dt)`.

## D-r3-2 — Ad-hoc defaults & convenience overloads; e.g. the one-arg `recommended_cfl(integrator)`

**Surface:** `recommended_cfl(integrator)` vs `recommended_cfl(integrator, domain)` (`src/Propagator.jl`).

**Reported (user, broader design question):** "What are the reasons for providing some default
behavior/arguments for some functions and arguments, but not the others. E.g. here, why do we need that
single-argument `recommended_cfl`?"

**Specific (the example):** the one-arg form returns the CFL calibrated for the ``2/3`` rule (the base);
the two-arg form scales it by the domain's dealiasing (``C \propto 1/\kappa_{\max}``) — "the value
`Simulation` uses" (the correct, domain-aware one). Internally the two-arg **is** the one-arg × ``(2/3)/f``,
so the one-arg is the base the two-arg scales — but as a **public** method it is a mild footgun: on a
`HouLi` / `PhaseShift` run it returns the ``2/3`` value, which is **too large** (they keep more modes ⇒ need
a *smaller* step). It reads like an internal `_base_cfl(integrator)` exposed needlessly. **Lean:** make the
one-arg form internal (or drop it); the public surface is the domain-aware form.

**General principle (the real question):** ties to **D3** ("name what you consume and can default, forward
the rest" — *postponed*). The coherent rule to state: **provide a default / convenience only when the
default is the unambiguous, SAFE common-case choice** (like `Simulation`'s kwargs — a valid default run,
overriding explicit); **never a default that silently returns a wrong answer for a valid non-default
configuration** (the ``2/3`` CFL for a non-``2/3`` domain). "Some have defaults, some don't" reads ad-hoc
precisely because the principle isn't stated. **Lean:** write the default-principle into `ARCHITECTURE.md`
(extend D3) so the pattern is principled, not case-by-case.

**Touches recorded decisions:** D3 (postponed), D11 (removed `default_integrator`; `recommended_cfl` takes
the integrator explicitly). Ground in the decision log before deciding.

**Status:** DESIGN item, collect-only. Related to D-r3-1 (both Propagator API-surface questions).

**DECISION DIRECTION (user, 2026-07-14):** "defaults only in `SimulationRun` (except `rng` — a default RNG
for the IC is fine)." Refined (the carve-out is required, else it breaks `Phenomenology`):
- **Convenience defaults → `SimulationRun` (front door) ONLY**; the computational modules
  (SimulationDomain / State / Generator / Observables / Forcing / Propagator / Particles) take explicit args.
- **Model/preset *types* keep their canonical parameters as defaults** — `Pope2000(; C_K=1.5, …)`,
  `HouLi(; order=36, strength=…)`, `Kolmogorov1941(; C₂=2.0)`: those defaults are the model's *identity*,
  not API convenience.
- **`rng` may default anywhere** (harmless seeding convenience) — the sanctioned exception.
- **Implications:** one-arg `recommended_cfl` → gone/internal; `Simulation` supplies the default `cfl`.
- **RESOLVED (user, 2026-07-14 — Option A):** `FixedDomain` keeps **no** defaults — all four
  (`side_length`, `dealiasing`, `scalar_type`, `array_type`) become explicit; `Simulation` is the **sole**
  default-owner. Removes the current two-source duplication and makes backend/precision a deliberate choice
  (GPU-primary / precision-is-a-fitness-axis ethos — no silent CPU/Float64).

**⇒ D-r3-2 DECIDED. The principle in full:**
1. Convenience defaults live **only** in `SimulationRun`.
2. Model/preset **types** keep their canonical defaults (`Pope2000`, `HouLi`, `Kolmogorov1941`, …).
3. `rng` may default anywhere (sanctioned exception).
4. `FixedDomain`: no defaults (all explicit); the one-arg `recommended_cfl` → internal/dropped.

**Execution plan (when collect-only lifts):** (1) strip `FixedDomain`'s four defaults; (2)
drop/internalize the one-arg `recommended_cfl`; (3) audit every other default across the computational
modules → classify each {move to `SimulationRun` / keep (model or `rng`) / drop}; (4) codify the principle
in `ARCHITECTURE.md` (extend D3); (5) verify — the front-door `Simulation` still defaults everything, so
user ergonomics are unchanged; docs build + tests green. **Step (3) audit is now done — below.**

### D-r3-2 DEFAULTS AUDIT (2026-07-14) — the full class, not just `FixedDomain`

`FixedDomain` and one-arg `recommended_cfl` were **samples of a class**. The class = *a convenience value
default on an object that `Simulation` itself constructs and passes its own value into* — so the low-level
default is dead duplication of (sometimes a contradiction with) the front door.

**The sharp test (cold-read probe for this class):** for each defaulted argument, *does `Simulation` pass
its own value when it builds that object?*
- **YES → STRIP** — dead duplication; `Simulation` is that object's front door.
- **NO (`Simulation` relies on the type's default) → KEEP** — the type is the genuine front door for it.
- **rng-family (`rng`, `seed`) → KEEP** (sanctioned exception).
- **`= nothing` sentinel (optional/off/auto) → KEEP** — not a convenience *value* default.

**STRIP — `Simulation` passes the value (line refs in `SimulationRun.jl`):**
| Site | Args to strip | Simulation supplies | Note |
|---|---|---|---|
| `FixedDomain` | `side_length`, `dealiasing`, `scalar_type`, `array_type` | 200–203 | **DECIDED** (Option A) |
| `FlowConditions` | `schmidt`, `velocity_forcing`, `scalar_forcing` | 176–178 | exact `FixedDomain` parallel |
| `random_solenoidal_velocity!` | `kinetic_energy`, `peak_wavenumber`, `spectrum` | 189 | **exemplar** — State.jl docstring admits `0.5` "differs by design" from the front door's `1.5` |
| `random_scalar!` | `scalar_variance`, `peak_wavenumber`, `spectrum` | 190 | |
| `Tracers` | `scheme` | 192 (`tracer_scheme`) | ties to D-r3-3 |
| `BandRescaling` | `over` (`:band`) | 155 (`over = :total`) | the panel's `:band`-vs-`:total` footgun — stripping removes it |
| `recommended_cfl` | one-arg public form | uses two-arg (158) | **DECIDED** → internalize |

In every strip row `rng` / `seed` stays.

**KEEP — `Simulation` relies on the type default, or carve-out:**
- Forcing **band** `lowest_shell = 1`, `highest_shell = 2` — line 155 does *not* override them, so the
  forcing type is their genuine front door.
- `StochasticOU` `seed = 0` — rng-family.
- `HouLi(order = 36, strength = nothing)` — user-built (`Simulation`'s default `dealiasing` is
  `TwoThirds()`), so its defaults are its own front door; `strength = nothing` is an auto-sentinel.
- **All `Phenomenology` presets** (`Pope2000`, `Kolmogorov1941`, …) + `FlowParameters` — user-built.
  **Scope boundary:** `Simulation` *does* build a `FlowParameters` (line 183, passing `schmidt`), but
  `Phenomenology` is the **extraction-bound leaf** with its own front door (→ standalone
  `GBGTurbulencePhenomenology`); D-r3-2 governs the dynamics stack, not the leaf. So its defaults stay.
- `= nothing` sentinels — `integrating_factor!(rate)`, `advance!(dt)`, `run!`/`warmup!`/`_run_loop!`
  stop-criteria, `initial_spectrum`, `viscosity` (grid mode) — optional/off/auto, not value defaults.
- **`SimulationRun` front door** — every `Simulation` / `warmup!` / `run!` kwarg (it IS the front door).

**TWO residual rulings (user):**
1. **The `scalar` feature-flag** on `ResolvedFields` / `IntegratorBuffers` / `allocate_buffers`
   (`scalar = false`): `Simulation` *does* pass `scalar` (lines 175, 180) → by the sharp test, strip. **But**
   commit `3aa3467` *deliberately* aligned it to `false` "matching Simulation", and it is a feature-**off**
   toggle (closer to a `nothing`-sentinel than a value default). **Keep-as-toggle or strip?**
   *(Lean: keep — an off-by-default toggle is not the convenience-value class, and the alignment was intentional.)*
2. **Confirm the `= nothing`-sentinel exemption.** *(Lean: exempt — absent/off/auto, not a duplicated value.)*

Everything in STRIP beyond the two DECIDED rows follows **mechanically** from the `FixedDomain` decision +
the sharp test — same class, same ruling, one refactor.

## D-r3-3 — `Tracers(positions)` is a second, unchecked source of backend/precision (breaks the domain single-source invariant)

**Surface:** `Tracers(positions; scheme = CatmullRom)` (`src/Particles.jl`) vs the SimulationDomain
invariant "backend & precision enter only at the domain, and flow everywhere from here". (Doc facets: §13.)

**Reported (user, design facet):** `Tracers(positions)` has no domain, so it cannot allocate "in agreement
with the domain" — the `positions` array is an independent source of backend/precision with **no check**
that it matches the domain the tracers are advected in. CPU/`Float64` `positions` + a CUDA/`Float32` run ⇒
**mismatch**, surfacing in `advect!` / `sample!` (which evaluate the domain-backed velocity at tracer
positions) as an error at best, silent wrongness at worst.

**Design options:**
1. **Route through the domain** — `Tracers(domain, positions; scheme)`: source backend/eltype from
   `domain`, converting `positions` to it. Keeps the single-source invariant literally true; no mismatch
   possible. **(Lean — the only option that keeps the invariant rather than annotating around it.)**
2. **Keep `Tracers(positions)` but constrain** — document that `positions`' backend/eltype defines the
   tracers' and MUST match the domain; assert agreement when the domain first meets the tracers.

**Ties in:** the SimulationDomain single-source invariant; **D-r3-2** — `scheme = CatmullRom` here is a
*convenience* default on a computational-module constructor (would move to `SimulationRun` under the
principle), while `rng = default_rng()` (first form) is the sanctioned `rng` exception.

**Status:** DESIGN item, collect-only. Related to D-r3-1, D-r3-2.

---

# PANEL RE-AUDIT — open items merged into this fix list (2026-07-14)

Full disposition + `file:line` + one-line fixes live in **`panel-reaudit.md`**; indexed here so this pile
is the single fix list. Verdicts from 6 independent verifiers, each blind to the prior dispositions
(~35 of the panel's ~55 were genuinely fixed — incl. both code bugs B1/M1 with tests — and need no action).

**🔴 Laundered (2) — closed by prose, issue stands:**
- **L1** — `kinetic_energy` 0.5/1.5 (`State.jl:56–58`). **Already the `random_solenoidal_velocity!` row of
  the D-r3-2 DEFAULTS-AUDIT strip table** — fixed there (strip `= 0.5`; delete the "by design" sentence).
  No separate action; listed for traceability.
- **L2** — `IntegratorBuffers` carries **two** unused registers into the low-storage RK3 run (`stage2`,
  `velocity_star_spectral`); the self-tension was reworded not fixed, and the new disclosure names only
  **1 of 2** (`Propagator.jl:174–176,103`). Touches the minimal-footprint / GPU invariant (4). Fix =
  per-scheme `allocate_buffers` omitting both (real footprint fix), or complete+correct the disclosure.

**🟠 Partial (4) — wrapper edited, defect-home still stale (the "looks-fixed" class):**
- **P1** — `structure_function` generic **evaluator** still "pure-velocity ``\langle(\delta u)^{order}\rangle``"
  though `Yaglom1949` (same generic) is the mixed ``\langle\delta u_L(\delta\varphi)^2\rangle``
  (`Phenomenology.jl:197–206`); only the supertype/map were broadened. Fix = broaden the evaluator docstring
  (mirror the `spectrum` generic, which names both).
- **P2** — Saffman σ=2 "Saffman-type" large-scale form year-less (`Spectra.jl:230`). Cite or annotate as a class label.
- **P3** — spelling still mixed on the rendered surface (`organise`×7, `analysing`×1, `honour`×1). → American.
- **P4** — Leray naming 3→2; bare "Leray projection" survives (`notation.md:29`, `architecture.md:458`) → "Leray–Helmholtz".

**🟡 Still-open (10) — never touched:**
- Real API gaps: **M8** — no `derivative_skewness`/`scalar_dissipation`/`max_speed`(sim) method + the 5
  existing `f(sim)` undocumented at their homes; **`flow_parameters`** never states it leaves
  `scalar_dissipation = NaN`; **`Simulation`↔`Tracers`** kwarg drift (`ntracers`/`tracer_scheme` vs `count`/`scheme`).
- Citation: **`S ≈ −0.5 "(Kolmogorov)"`** mis-attribution (`Observables.jl:127`) → drop "(Kolmogorov)".
- Cold-read nits: `scalar_type` collision with reserved "scalar"; K41/K62/"solenoidal"/"aliasing" undefined
  on first use; `kinetic_energy`/`scalar_variance` are both keyword and observable function.
- Infra nits: `@extref` PF inventory `/dev/`→`/stable/` (`docs/make.jl:109`); return-type annotations inconsistent
  (Phenomenology `-> Float64`, Observables none).
- Physics-prose: §2 warm-up comment names the wrong mechanism — `ConstantPower` **rings**, not clamps
  (`ARCHITECTURE.md:56–57`) → say "fixed-injection makes k(t) ring", or switch the example to `BandRescaling(over=:total)`.

**Residuals inside FIXED items (~6, low priority):** ARCH:775 `G` "dissipation anomaly in box variables"
(loose — distinct group); decision-14 lead still shows `ConstantPower(power=)`/`ForcingSpec` (copy-paste
footgun); ARCH:401 abstract `f_L(κL)` bare `L`; ObukhovCorrsin convention text (`ARCH:390`); `index.md:12–13`
"owns … the statistics" (present tense, unbuilt); generic `order`-default note. (Detail in `panel-reaudit.md`.)

**Watch when executing:** **L2** and **P1** are the dangerous ones — they *look* addressed. Re-verify every
fix against source before calling it done (the lesson that started this re-audit).

---

# DECISIONS RESOLVED (2026-07-14) — all open round-3 decisions closed

This block is the authority; it supersedes the "open / collect-only" status noted in the D-r3-* sections above.

- **D-r3-1 (a) — `step!(state::State, …)`:** DECIDED — `step!` takes `State`, not loose `û`/`φ̂`. (Code
  refactor: `step!` signature in `Propagator` + its callers in `SimulationRun`.)
- **D-r3-1 (b) — `Generator` type:** ROADMAP — deferred to `ARCHITECTURE.md` §7. Build only if/when it
  reifies a real RHS operator; today the RHS is functions + the integrating factor. Not built now.
- **§4 — citations:** DECIDED — unify every inline author–year cite **and** add the missing `§References`
  entries; **no** `DocumenterCitations`. **Fix once, for good, and codify the policy so it can't regress:**
  every inline cite ↔ a verbatim-consistent `§References` entry (author–year + venue + vol/pp). Add a
  positive check + a deterministic grep guard to `/check-docs`, and the rule to `CLAUDE.md`'s doc policy.
- **D-r3-3 — `Tracers(domain, positions)`:** DECIDED (route backend/eltype through the domain).
  **Argument order = DOMAIN FIRST:** `Tracers(domain, count)` (unchanged) + `Tracers(domain, positions)`.
  Rationale (first-principle, not legacy): (1) **a domain-derived object leads with the domain** — the
  package's constructor convention (`ResolvedFields(domain)`, `IntegratorBuffers(domain)`), the reason the
  user endorsed; (2) backend/precision flows *from* the domain (the D-r3-3 point), so the governing argument
  leads; (3) a bare leading integer (`Tracers(1000, …)`) reads cryptically. (The two forms staying parallel
  is a *consequence*, not a justification — "it's already domain-first" is the circular-justification
  weakness now in `CLAUDE.md`.) (Also strip `scheme` per the D-r3-2 audit; `Simulation` supplies `tracer_scheme`.)
- **L2 / item 4 — exact-allocation invariant:** DECIDED + **NEW INVARIANT.** `allocate_buffers` allocates
  **exactly** the given scheme's working set — never a superset; **over-allocation is a hard error**, not a
  tolerated compromise. ⇒ per-scheme `allocate_buffers` (`IFLowStorageRK3` allocates its own registers,
  dropping IF-RK2's `stage2` + `velocity_star_spectral`). Elevates L2 from prose to a Propagator refactor;
  write the invariant into `ARCHITECTURE.md` (it makes the minimal-footprint / GPU invariant 4 enforceable).
- **§5 — `scalar_type` → `element_type`:** DECIDED — rename the kwarg everywhere (`FixedDomain`,
  `Simulation` front door, all docstrings, `notation.md`). "scalar_type" read as "type of the passive
  scalar" — a naming-policy violation.
- **D-r3-2 residuals (6):** CONFIRMED — the `scalar = false` flag stays a toggle (not stripped);
  `= nothing` sentinels stay exempt from the defaults strip.

**EXECUTING (go given 2026-07-14).** Strip-all confirmed (user): `FlowConditions` (schmidt/forcings) and
`Tracers` (scheme) strip too, for uniformity with `FixedDomain`; the user noted this friction argues for
the roadmapped `Generator` type (D-r3-1b — a clean low-level front door bundling conditions + RHS).
`FixedDomain`'s stripped args are **required keyword args**. Stage order: 1a defaults-strip + `element_type`
rename → 1b `step!`/`State` + per-scheme `allocate_buffers` → 2 doc sweep → 3 ARCHITECTURE.

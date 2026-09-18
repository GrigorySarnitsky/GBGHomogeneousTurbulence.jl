# Hat 27 — Cross-package parity reviewer (IT vs GBGPeriodicFields)

Substrate: IT's rendered manuscript + `CLAUDE.md`, and PF's `CLAUDE.md` + `docs/ARCHITECTURE.md` +
a sample of PF's `src/*.jl` docstrings (`Convolution.jl`, `Interpolation.jl`). Findings already
dispositioned in `.claude/doc-review-adjudicated.md` (the conditional admonition-title rule, the
economy/full cost-mode split, IT's richer constructor-first type-docstring template) are **not**
re-flagged below.

---

## Finding 1 — Citation architecture: PF docstrings carry a full verbatim `Reference:` line; IT's never do

**Type:** citation · **Severity:** major · **Confidence:** high

**Locations:**
- IT, `api / Propagator`, `IFLowStorageRK3`: "Integrating-factor third-order low-storage
  Runge–Kutta of the Williamson (1980, Low-storage Runge–Kutta schemes) 2N-storage family."
- IT, `api / Forcing`, `VarianceController`: "the constant-$k$ controller of Bassenne et al.
  (2016, Constant-energetics physical-space forcing methods for improved convergence to
  homogeneous-isotropic turbulence with application to particle-laden flows)."
- IT, `api / Forcing`, `VarianceRescaling`: "The deterministic rescaling forcing of Sullivan,
  Mahalingam & Kerr (1994, Deterministic forcing of homogeneous, isotropic turbulence)."
- PF, `src/Interpolation.jl:147`: `Reference: C. C. Lalescu, B. Teaca, D. Carati, [*Implementation
  of high order spline interpolations for tracking test particles in discretized fields*]
  (https://doi.org/10.1016/j.jcp.2009.10.046), J. Comput. Phys. **229**(17) (2010) 5862–5869.`
- PF `CLAUDE.md` (~line 478): "**docstrings carry the full reference inline** (a `# References`
  block, or a one-line `Reference:`) ... each inline copy must match the `§References` entry
  **verbatim**."

**Description:** PF's rule and its actual corpus both give every cited docstring a dedicated,
full bibliographic `Reference:` line — author list, italic linked title, journal, volume, year,
pages — checked verbatim against `ARCHITECTURE.md` §References. IT's rulebook instead only
promises DOI-title link identity ("one link form on both surfaces"), and every sampled IT
docstring citation (7+ instances across Propagator/Forcing/Observables) folds a compact
author-year-title mention into running prose, with no dedicated `Reference:` line and no journal,
volume, or page ever given inline. This is either an intentional, undocumented scaling-down of
PF's rule for physics prose, or an unexamined drift when IT "adopted" the DOI-link convention
(2026-08-24) without adopting the fuller inline-reference requirement it sits inside in PF.
Worth an explicit owner ruling either way, since IT's own rule text implies parity ("adopting
PF's convention ... so the two surfaces cannot drift") but the practiced shape is narrower.

**Resolution hint:** either state explicitly in IT's `CLAUDE.md` that the inline citation is
deliberately compact (title only, no full reference line), or bring the docstring citations up
to PF's full verbatim-`Reference:` standard.

---

## Finding 2 — Module-map shape: IT's rule bans an "essay before the list"; PF's rule requires one, and PF's corpus delivers a multi-paragraph one

**Type:** organization · **Severity:** minor · **Confidence:** high

**Locations:**
- IT `CLAUDE.md`, Template conventions: "A **module map is identity → contents list → optional
  trailing remark**, in that order, with no essay before the list."
- PF `CLAUDE.md` (~line 176): "**Module docstring = map.** What the module is, its scope and
  place in the architecture, and its invariants (physical vs spectral, the base measure) — then
  a linked one-liner per operation family."
- PF, `src/Convolution.jl:1–37`: five substantial paragraphs on the module's place in the
  "integration structure" (shared with `Interpolation`), the kernel/field type distinction, and
  the consumer-side-physics boundary — all *before* the "Convolution operations:" bulleted list.
- IT, `api / Generator` module docstring: one short identity sentence, then straight into
  "Its contents (each formula lives in the operation's own docstring): ..." — compliant with
  IT's own no-essay rule.

**Description:** The two rulebooks state the module-docstring template in visibly different
shapes — PF explicitly asks for scope-and-invariants prose ahead of the list (and its own corpus
delivers several paragraphs of it), while IT explicitly forbids any essay before the list. IT's
own module docstrings (`Generator`, `Forcing`, `Observables`) all honor IT's stricter shape, so
this is an internally consistent but genuine template divergence from the leading-edge sibling —
plausibly a deliberate simplification for a smaller, four-role module map, but not stated as
such anywhere.

---

## Finding 3 — Rulebook text: IT carries a "Known weaknesses — self-guards" section with no PF counterpart

**Type:** other · **Severity:** minor · **Confidence:** high

**Locations:**
- IT `CLAUDE.md`, final section: four documented recurring failure patterns ("Circular /
  self-referential justification", "Asserting a shape instead of expanding it", "Treating what is
  *in place* as evidence it should be so", "Fixing the instance, not the class"), each with dated
  historical instances.
- PF `CLAUDE.md`: no section header matches (`Modules and wiring`, `Core invariants`, `Code
  generation rules`, `Documentation policy`, `Style`, `Verification workflow`, `Current state and
  roadmap`, `Planned directions`, `Working agreements` — nine headers, none of them a self-guard
  register); the only nearby text is the one-line "not by convenience: 'it's convenient', 'for
  symmetry'..." inside the invariants section.

**Description:** IT has an entire rulebook section devoted to naming and guarding against its own
observed authoring failure modes (self-referential justification, unexamined recorded costs,
instance-not-class fixes); PF's `CLAUDE.md` has nothing structurally similar — only a single
inline "not by convenience" clause. Since at least two of IT's four guarded patterns (circular
justification, instance-vs-class fixes) look like generic authoring failure modes rather than
physics-specific ones, this reads as a candidate reverse-transfer to PF rather than a defect in
IT — named per the hat's brief, not raised as a problem.

---

## Finding 4 — Docstring template: PF mandates a verbatim in-place-steer sentence for every f/f! pair; IT has no equivalent boilerplate

**Type:** method · **Severity:** minor · **Confidence:** medium

**Locations:**
- PF `CLAUDE.md`, shape rule (4): "Every `!` form that *has* an allocating sibling carries this
  sentence verbatim, after the identity paragraph and before the arguments: *'Use this in-place
  form when `destination` is already allocated; the allocating [`f`](@ref) returns a fresh result
  instead.'*"
- IT `CLAUDE.md`, Docstrings section: "Across an `f` / `f!` pair the in-place `!` form is the
  **home** (owns the formula and the kernel, listed first); the allocating form is a thin
  `@ref`-linking wrapper with no second copy of the formula and no notation that drifts across
  the pair" — no verbatim sentence prescribed.

**Description:** PF fixes the *exact wording* an in-place docstring must use to steer a reader to
its allocating sibling, mechanically checkable for drift; IT states the same underlying
home/wrapper relationship but leaves the steering sentence to prose discretion, so nothing in
IT's rulebook or corpus enforces a single recognizable phrasing across its own f/f! pairs (e.g.
`vorticity_physical!`/`vorticity_physical` on the `Cache`/`Observables` split). Worth naming as a
candidate reverse-transfer from PF, or an explicit statement that IT does not need it because its
allocating/mutating pairs are fewer and less uniform in shape than PF's.

---

## Finding 5 — Aliasing documentation: IT encodes the consumed operand in the argument *name*; PF documents it in the `destination` bullet's prose

**Type:** method · **Severity:** nit · **Confidence:** medium

**Locations:**
- IT, `api / Generator`, `velocity_rhs!`: `ω_consumed` in the signature, with "the `_consumed`
  suffix marks it, since Julia's `!` convention flags only the first" argument.
- PF `CLAUDE.md`, shape rule (5): "An operation-specific statement of whether `destination` may
  alias an input lives in the **`destination` argument bullet**, not as standalone prose."

**Description:** The two packages solve the same problem — a mutated argument that is not the
signature's first, conventionally-`!`-flagged one — by different mechanisms: PF keeps the
argument name plain and states the aliasing contract in prose at the argument's bullet; IT
bakes the fact into the argument name itself (`ω_consumed`, `u_consumed`), justified in IT's own
decision log ("the only available improvement was to move the warning from the prose into the
signature"). This looks like a considered, physics-motivated adaptation (which operand is
consumed follows the physics, not argument position, so a positional convention could not carry
it) rather than an unexamined divergence — named for completeness, not as a defect.

---

## Not flagged (already adjudicated or out of scope)

- The conditional admonition-title rule, the economy/full-on-request cost-mode split, and
  IT's richer constructor-first type-docstring template — all recorded 2026-08-23 as deliberate,
  two as candidate reverse-transfers already banked.
- IT's frequent temporal/step-cadence framing in docstrings ("per-step", "every step") against
  PF's explicit "cost register, not time" ban on such framing — not flagged: PF's rule is
  grounded in PF being a backend with "no concept of time" (its own invariant 12), while IT's
  whole subject is time integration, so the divergence is a necessary consequence of domain, not
  an authoring lapse.
- The DOI-link mechanics (labelled inline link vs. bare `§References` autolink, `no DOI` vs.
  `(no DOI: ...)` capitalization) — already settled in prior rounds as extraction artifacts /
  deliberate per-surface conventions.

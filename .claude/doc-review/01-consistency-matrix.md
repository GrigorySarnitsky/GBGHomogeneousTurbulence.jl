# Consistency Matrix — fresh-eyed audit

Hat: **consistency-matrix** (systematic entity-diff across every rendered page)

Methodology: built a matrix of every recurring entity (physical quantities, notation, numerical
constants, vocabulary terms, docstring structure) and diffed each entity's stated form across every
page of the manuscript. Extensive cross-page formula/dimension expansion was performed (Reynolds
number, dissipation-group identities, transform/pass ledger counts, frame-memory byte counts,
skewness constant, CFL ceilings, PhaseShift band-volume ratio) — all of it checked out internally
consistent; those are not reported below. What follows are the divergences that survived expansion.

---

## Finding 1 — "stamp" is a retired term, but the rendered docs still use it as the primary noun

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high

**Locations:**
- PAGE: architecture, §11 decision log (2026-08, user-directed): *""Stamp" is retired; a slot carries
  an epoch... The `*_stamp` fields become `*_epoch`... One noun now serves both roles: the counters
  are epochs..."*
- PAGE: notation, Vocabulary table, "epoch" row: *"the value of that counter **stamped** on it when
  it was filled. A slot is readable exactly when the **stamp** it carries still equals the counter it
  depends on."*
- PAGE: api / Cache, `ObservablesCache` Fields section: *"each slot carries a **stamp**, the
  counter's value at the moment that slot was filled. A slot is readable exactly when its **stamp**
  still equals the counter it depends on."* — then: *"`velocity_epoch`, ... — each slot's **stamp**,
  or a sentinel"* and *"`sample_fields_epoch`, `sample_particles_epoch` — the particle velocities'
  two **stamps**"*.
- PAGE: api / Cache, `deposit_sample!`: *"this call **stamps** both from the cache's current
  counters."*

**Contradicts:** the architecture page's own decision log explicitly retires "stamp" corpus-wide in
favor of "epoch," and the design page (`observables_cache`) itself is fully compliant — §1.3 and §3.1
there consistently say "epoch," never "stamp." The `notation.md` Vocabulary table is supposed to be
*the* single reference the rest of the corpus points to ("this page is the single reference — a
docstring introduces a symbol on first use and need not repeat the convention"), yet it is one of the
two surfaces still carrying the retired word, and the `api/Cache` page — the most-read API surface for
this exact concept — repeats it four more times.

**Description:** A user reading `notation.md`'s Vocabulary entry or the `Cache` API page for "epoch"
learns the retired vocabulary as if it were current, directly contradicting the decision log's own
claim that the rename is complete ("One noun now serves both roles"). This is exactly the kind of
"fix the instance, not the class" failure the project's own CLAUDE.md self-guards call out — the
rename evidently swept the field names (`*_stamp` → `*_epoch`) but not the prose nouns describing them.

---

## Finding 2 — the shared `particle_velocities` array carries its read-only/staleness caveat on one documentation surface but not the other

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium

**Locations:**
- PAGE: api / Cache, `ObservablesCache` Fields section: *"A cached array is the next iteration's
  scratch — ... Treat every returned array as read-only — it is the storage the next iteration will
  work in."* (repeated verbatim for `velocity_physical`, `vorticity_physical`, `scalar_physical`).
- PAGE: api / Particles, `Tracers` Fields section: *"`particle_velocities` — the interpolated
  velocity at the positions the tracers occupy, at the instant they occupy them: the genuine
  Lagrangian sample, and the observables cache's particle-velocities slot."* — no read-only /
  mid-iteration-staleness caveat given here.

**Description:** The architecture page and `observables_cache` design page both establish that
`tracers.particle_velocities` *is* the cache's particle-velocities slot — the identical array, not a
copy ("the slot IS the register, as everywhere else"). Reading it through `Cache.particle_velocities`
carries the epoch-checked-throw protection and an explicit read-only admonition; reading the same
bytes directly off `tracers.particle_velocities` (a public field, per the Particles page's own "Fields"
listing) bypasses both. The two documentation surfaces describing one shared array give it
asymmetric safety coverage — a reader who only reads the Particles page has no warning that the field
they can dot into is mid-iteration scratch part of the time.

---

## Finding 3 — twin Parseval-polymorphic reductions are documented with an inconsistent signature style

- **Type:** format
- **Severity:** nit
- **Confidence:** medium

**Locations:**
- PAGE: api / Observables, `kinetic_energy`: signature block shows **two** explicit forms —
  `` kinetic_energy(u) `` and `` kinetic_energy(û) `` — "so by Parseval's theorem it accepts the
  velocity in either representation."
- PAGE: api / Observables, `scalar_variance`: signature block shows **one** form only —
  `` scalar_variance(φ) `` — yet the prose makes the identical claim: "so by Parseval's theorem it
  accepts `φ` in either representation."

**Description:** Both functions are the same structural case (a Parseval quadratic reduction generic
over physical/spectral representation of its one argument), and the module docstring explicitly pairs
them ("Like every quadratic reduction here (`dissipation`, `scalar_variance`, `scalar_dissipation`),
it needs no dealiasing of its own"). Yet the two docstrings render the dual-signature capability
differently — one spells out both call forms in the code block, the other doesn't — which reads as if
`scalar_variance` supports only one representation until the prose sentence corrects that impression.

---

## Notes on what was checked and found consistent (no findings filed)

For the record, since this hat's job is exhaustive cross-page diffing, the following entities were
independently re-derived from their stated formulas across every page they appear on and found
internally consistent (not reported as findings): the Reynolds-number/viscosity convention
($\mathrm{Re}=1/\nu$ at $u'=L=1$; $2\pi/\nu$ on the shipped defaults); the $u'=\sqrt{2k/3}$ /
$k=\tfrac32u'^2$ round-trip between `notation.md` and `FlowParameters`; the $C_S=\tfrac47\sqrt{15/2}$
skewness constant and the $\operatorname{tr}\boldsymbol S^3=3\det\boldsymbol S$ traceless identity;
the $G=\tfrac32C_\varepsilon^{-2/3}$ cross-check between `Li2008`'s box-normalized group and
`Sreenivasan1998`'s integral-scale constant, including the numeric $G\approx0.81$ vs quoted $0.9$
reconciliation; the $E(\kappa)$ / $E_n$ dimensional pair ($L^3T^{-2}$ vs $L^2T^{-2}$); the
`PhaseShift` retained-band volume ratio ($\approx2.8\times$) and its $2\times$-transform-cost claim
against the observables-cache page's own transform-count table (18/9, 21/18, 36/18, 42/36 all
expand correctly); the frame-memory ledger's 322.5 MiB figure (verified by reconstructing it as one
rfft-shaped real array plus two rfft-shaped complex-container arrays); the `recommended_cfl` numeric
derivation ($C_{\mathrm{CFL}}\lesssim0.83$ from $y_s=\sqrt3$ and $\kappa_{\max}\Delta x=2\pi/3$); and
the `ConstantPower` injection-rate formula's self-consistency across the vector ($\tfrac12$-carrying)
and scalar (full-variance) conventions.

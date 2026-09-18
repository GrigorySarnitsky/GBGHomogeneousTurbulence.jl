# Consistency-matrix auditor — findings

Hat: systematic cross-page consistency auditor. Method: built an entity matrix (every recurring
physical quantity, formula, numeric constant, code name, and structural convention) and diffed
each entry across every page of the manuscript — Home, api overview, architecture, decisions,
notation, observables_cache, phenomenology overview + its three submodule pages, and all nine
per-module API pages (Cache, Forcing, Generator, Observables, Particles, Propagator,
SimulationDomain, SimulationRun, State).

## Summary

This document turned out to be exceptionally self-consistent. A large majority of candidate
mismatches I flagged while reading did **not** survive a careful expand-and-verify pass — formulas
that looked mismatched at first glance (e.g. the PhaseShift/mask transform-count table, the
322.5 MiB frame-memory figure, the `G = 3/2 C_ε^{-2/3}` identity, the field-order-vs-constructor-
order pairing across every plain-positional type, the `κ_max` formula written two different ways on
two different pages) all checked out exactly once expanded algebraically or arithmetically. The
decision log's own record of multiple prior panel/audit rounds (recorded fixes for the Yaglom 4/3
factor, the `E(κ)` per-shell-vs-density conversion, etc.) is consistent with what I observe: the
low-hanging fruit for a pure cross-page consistency sweep appears to already be gone. I report the
one item that survived scrutiny below, at appropriately modest severity/confidence, rather than
padding the list.

---

## Finding 1: Notation-page operator glyphs list PF operation names without their mutating `!`, while every other surface uses the bang form

- **Type:** format / notation
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE: notation, "Spectral representation and operators" table: `∇×, ∇· | curl, divergence | curl, divergence`; `𝔽, 𝔽⁻¹ | forward / inverse real transform | to_spectral, to_physical`; `⋆ | periodic convolution ... | convolve`; `ℙ | the Leray–Helmholtz projection ... | helmholtz_projection`.
  - PAGE: architecture, §5 (consumer boundary): "the transforms, `curl!` / `cross!` / `divergence!`, the Leray–Helmholtz projection `helmholtz_projection!` (ℙ), `convolve!` and the dealias/band kernels ..."
  - PAGE: decisions (2026-08 entry): "`helmholtz_projection!(û, û, …)`"
- **Contradicts:** the Notation page states of itself "This page is the single reference" and, for the adjacent Physical-variables table, explicitly disambiguates the pair — `vorticity_physical (the cached field; vorticity_physical! recovers it)` — showing the page's own convention is capable of naming the mutating form when it matters. For the Spectral-representation-and-operators table it instead lists every PF-imported operation (`curl`, `divergence`, `to_spectral`, `to_physical`, `convolve`, `helmholtz_projection`) without the `!` that every other surface (architecture §5, the decision log, and the generator docstrings) uses for the same functions.
- **Description:** Likely deliberate — the row may be naming the operation family rather than one exact PF signature, matching CLAUDE.md's "a family of related built-ins is one catalogue destination" convention — but nothing on the page states that reading, so a reader taking the Notation page as the literal `Code` binding (as its own header promises: "The Code column gives the name each symbol carries in the package") would come away with the wrong identifier for a mutating call. Low confidence because this may be an intentional, unstated convention rather than a drift.

---

## Candidates weighed and resolved as non-defects (not reported as findings)

For transparency, given the exhaustiveness of the sweep, the following looked like plausible
mismatches on first read and were each individually expanded/derived before being ruled clean:

- The `TwoThirds`/`HouLi` vs `PhaseShift` transform-count table (observables_cache §2.3): the
  "9 forward → 18 forward" jump when adding the scalar looked disproportionate until accounting
  for the conservative-form flux `uφ` being a **vector** product requiring 3 forward transforms,
  not 1 — the count is exact.
- `G = 3/2 C_ε^{-2/3}` (Scalings.Li2008) and the "≈0.81 against the quoted 0.9" cross-check
  (applying the `L/L11≈5` length correction): both verified algebraically to the stated figures.
- The 322.5 MiB frame-memory figure (decision log, decision 36): only resolves once the
  half-complex spectral (RFFT) layout and the "held in complex containers" detail (decision-log's
  own later correction) are both applied; the naive `3 × N³ × 8 bytes` guess is wrong, the
  documented figure is right.
- `κ_max` for `PhaseShift` written as `f·(N/2)·(2π/L)` with `f = 2√2/3` (SimulationDomain page) vs
  `(√2/3)N·(2π/L)` (notation page): algebraically identical.
- Every plain-positional-constructor "Fields ... takes the N fields directly, in the order shown"
  clause (`FlowConditions`, `FlowParameters`, `Reference`, `HouLi`, `Sreenivasan1998`, `Li2008`,
  `Kolmogorov1941`, `ModelSpectrum`, `PopeLargeScale`, `PopeDissipation`) was checked against its
  own keyword-constructor argument order: all match.
- `velocity_predictor_spectral` (IntegratorBuffers, field side) vs the Particles-page claim that
  `ParticleIntegratorBuffers.velocity_predictor` is "the particle-side counterpart of the field
  schemes' `velocity_predictor_spectral`": the name is confirmed correct on the Propagator page.
- `domain.squared_wavenumber_kernel` as the notation-table Code entry for `|κ|²`: confirmed against
  the SimulationDomain Fields section.
- The IFHeun/IFLowStorageRK3 register counts ("three" vs "two", architecture §4.5) against the
  IntegratorBuffers Fields list: `stage1 + stage2 + velocity_predictor_spectral` = three;
  `stage1 + nonlinear` = two. Matches.
- `tr(S³) = 3 det(S)` for a traceless symmetric tensor (derivative_skewness): verified by
  Cayley–Hamilton.
- The Yaglom 4/3 → 2/3 conversion (full-variance vs half-variance `ε_φ`) and the
  `VarianceController` marginal-law/proportional-restoring derivation (`dk/dt = -G(k-k_∞)/t_ℓ`):
  both verified by direct substitution.

None of the above is reported as a finding since each is, on inspection, correct and consistent.

**candidates_considered:** ~45 (the matrix entries above, plus routine field-order/table/glossary
cross-checks not individually itemized: the five forcing strategies list, the module include-order
statement repeated on three pages, the `front door` usage-scoping rule, the `min_turnovers`/
`skew_floor` defaults, the HDF5 "Persistence" section wording pattern across seven modules, and the
`κ_max·η` numeric worked examples for `TwoThirds` vs `HouLi`).

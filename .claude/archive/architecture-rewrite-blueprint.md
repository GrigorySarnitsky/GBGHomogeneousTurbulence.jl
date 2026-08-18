# Blueprint — the holistic rewrite of `docs/ARCHITECTURE.md`

The design of the new document, to be signed off before any prose is written. The decision log (§11) is
append-only and preserved verbatim; everything else is rewritten to read as one coherent whole.

## A. The spine (the one framing sentence that governs the whole doc)

> The architecture is carved into the four **Mori–Zwanzig roles** — **State**, **Generator**,
> **Observables**, **Propagation** — the level-agnostic parts every rung of the Model ladder shares; the
> modules *are* these roles, plus the job-named realization and infrastructure that support them. **MZ
> supplies the vocabulary and the carving; the code depends on no theory** — the roles are *demonstrated*
> by the DNS realization, never *assumed* (decision 8 preserved, decision 16 completed).

This resolves the pivotal question: MZ rises from "one lens in §8" to the **organizing carving** of §3–§4,
while the "lens, not foundation" discipline is kept explicit. It does not become load-bearing.

## B. Naming slate (the carving made concrete = the verified `.als`'s nine modules)

| Role / concern | Module | Change |
|---|---|---|
| The frame — the discretized box | `SimulationDomain` | **split out** of `SimulationState` |
| **State** — field buffers, initial conditions | `FlowState` | renamed from `SimulationState` (domain split off) |
| **Generator** — the Navier–Stokes RHS | `Generator` | ← `Dynamics` |
| **Observables** — measured functions of state | `Observables` | — |
| Forcing — the energy source | `Forcing` | — |
| **Propagation** — the integrating-factor stepper | `Propagation` | ← `TimeIntegration` |
| Particles — Lagrangian instruments | `Particles` | — |
| The run layer | `SimulationRun` | — |
| Reference laws | `Phenomenology` | — |

**Three naming decisions, honestly flagged:**
1. `Dynamics → Generator` — clean; completes decision 16 (which named it "the generator" but left the label).
2. `TimeIntegration → Propagation` — **a real judgment call.** It *completes the MZ quartet* and names what
   the module *means* (advance the state) over *how* (numerical integration) — your user-facing rule. But
   it **revises decision 16's** "realization concerns keep job-names," since the integrator is Method. I
   recommend it; it is the one rename that bends a recorded principle, so it is squarely yours.
3. `SimulationState → SimulationDomain + FlowState` — **the one code-structure change, not a rename.**
   `SimulationState` today conflates the *frame* (the box) and the *state* (buffers); the split separates
   them, matching the roles. `FlowState` names the State realization (buffers + ICs).

## C. Section map (keep the sound skeleton; rewrite content to thread the spine)

1. **§1 Identity** — kept; the thin-physics/rich-numerics inversion stays the opening fact. Light touch.
2. **§2 Running a simulation** — kept: the worked example + warm-up-as-a-verb. Identifiers checked.
3. **§3 The organizing frame** — **the largest restructure.** Fuse today's *specification × realization*
   (decision 7) with the **MZ role-spine** (the framing sentence A): State/Generator/Observables/
   Propagation as the level-agnostic carving; System (scenario) + Model (*a rung on the projection ladder*)
   as specification; Method as realization; the *comparison machine* as the fitness arbiter. The
   conceptual heart.
4. **§4 Modules** — **reorganized by role**, not a flat list: 4.1 State + frame (`FlowState`,
   `SimulationDomain`), 4.2 the `Generator` — with the **metriplectic seam made explicit** (reversible
   advection / irreversible diffusion / the forcing source), 4.3 `Observables`, 4.4 `Forcing`, 4.5
   `Propagation`, 4.6 `Particles`, 4.7 `SimulationRun`, 4.8 `Phenomenology`, 4.9 layout. Threads
   *abstraction-ready-not-populated*: the roles are level-agnostic, only the DNS concrete is built.
5. **§5 Consumer boundary** — kept (raise-don't-reimplement; the PF / SS division). Consistency rewrite.
6. **§6 Precision & footprint** — kept; ties to the sharpened invariant 4 (the compile-time state).
7. **§7 Deliberately deferred** — kept; the coarser Model rungs (LES/FDF/inertial/PDF/EDQNM) *are* the
   ready-but-not-populated roles; aligned to the projection-poset language (resolved / modeled / extra).
8. **§8 Lenses** — MZ shifts from *introducing* lens to the **deeper reading** (memory + noise, the
   commuting square, GENERIC's why-it-is-structure-preserving, RG-as-hypothesis), since the *carving* moved
   up to §3–§4. The "lens, not foundation" discipline lives here and in §3.
9. **§9 Invariants** — all kept (invariant 4 already sharpened); completeness re-checked against the new
   carving; *abstraction-ready* stated once (here or §7).
10. **§10 Conventions** — kept (operator-first docstrings, two-tier docs, oracle-not-ledger); add the note
    that the *structure* is Alloy-checked while *dynamics* stay on the oracle (decisions 21–22).
11. **§11 Decision log** — **preserved verbatim.** Uncommitted decision 21 revised (drop "no renames"); a
    new **decision 22** records the physics-first renames + split + this holistic rewrite, extending
    decision 16.
12. **References** — kept.

## D. Preserved / changed / added / cut

- **Preserved (substance):** the worked example, warm-up, the comparison machine, the consumer boundary,
  phenomenology, precision/footprint, the deferred set, the lenses' content, the nine invariants, the
  conventions, **the entire decision log**, references, and **every formula** (the coordinate-free
  skewness constant, the integrating factor, dissipation, scalar transport).
- **Changed:** module names (slate B); §3 fused with the MZ spine; §4 reorganized by role; the metriplectic
  seam made explicit in the Generator; §8's MZ role shifts from introducing to deeper-reading.
- **Added:** abstraction-ready-not-populated; the projection-poset Model-ladder language; the GPU
  realization invariant (already in invariant 4); the structural-verification note.
- **Cut:** nothing correct — only redundancy where sections repeat.

## E. Verification (the draft, not just the spec)

Single-author draft → **nine-lens adversarial review of the draft**: (i) genuinely physics-first, not
programmer-bias; (ii) every claim correct against the code, line-quoted; (iii) decision 8's "lens not
foundation" held despite the MZ-central framing; (iv) the `/check-docs` battery (correct / self-contained /
notation / formatting / current-&-complete / cold-read); (v) **was anything correct in the old doc lost?**
→ revise → the two build lints + docs build → **decision-log-byte-identical** check → present.

## F. Sequencing (flagged for your call)

**Recommended: the doc rewrite and the code renames land together**, in one consistent change — because the
doc's own *current-&-complete* rule forbids describing a carving the code lacks. `Generator`/`Propagation`
are mechanical renames; the `FlowState`/`SimulationDomain` split is the one substantive code edit; both keep
load + tests + docs green before anything is committed. *(Alternative: doc-only now with realized-vs-target
marking — not recommended; it invites drift.)*

## Decisions I need from you

1. **The framing sentence (A)** — MZ as organizing carving, still "lens not foundation." Confirm?
2. **The three names (B)** — `Generator`, `Propagation` (revises decision 16), the `FlowState` /
   `SimulationDomain` split. Confirm, adjust, or veto any.
3. **Sequencing (F)** — doc + code together (recommended), or doc-first.

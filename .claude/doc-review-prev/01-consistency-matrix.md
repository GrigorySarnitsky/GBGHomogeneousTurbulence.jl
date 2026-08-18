# Consistency-matrix audit — hat: consistency-matrix

Fresh-eyed cross-page consistency pass over the rendered manuscript (Home, api overview, ARCHITECTURE.md,
notation.md, observables_cache.md, phenomenology overview, and every per-module `api/*` reference page).
Built as an entity matrix (module include order, physical-quantity formulas/normalizations, numeric
constants, dealiasing cutoffs, transform counts) diffed page-to-page. Most of the manuscript
cross-checks cleanly — formulas for `kinetic_energy`, `dissipation`, `energy_spectrum`,
`integral_scale`, the `PhaseShift` cutoff, the transform-count tables, the memory-footprint MiB
figures, and the `Phenomenology` scaling constants all verified consistent and dimensionally sound
across every page that restates them. Two genuine divergences survived the cross-check; they are
reported below, ranked by severity.

---

## Finding 1 — The rendered module Index contradicts the stated include/dependency order, three times over

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- PAGE `api` (overview): *"Its re-exported submodules, in dependency order, are `SimulationDomain` → `State` → `Observables` → `Cache` → `Forcing` → `Generator` → `Propagator` → `Particles` → `SimulationRun`."*
- PAGE `architecture`, §4.9 Layout summary: *"`SimulationDomain → State → Observables → Cache → Forcing → Generator → Propagator → Particles → SimulationRun`."*
- PAGE `architecture`, §4.1 (inline): *"The values land in the `ObservablesCache` (its own module, `Cache`, after `Observables`)."*
- PAGE `architecture`, decision log (2026-08, user-directed): *"The include order becomes `State → Observables → Cache`."*
- PAGE `Home`, Components bullet list order: SimulationDomain, State, Observables, Cache, Forcing, Generator, Propagator, Particles, SimulationRun (same order as above).
- **Contradicts:** PAGE `api / GBGIsotropicTurbulence`, the rendered `## Index` — the actual generated symbol listing groups modules in the order **SimulationDomain, State, Cache, Generator, Observables, Forcing, Propagator, Particles, SimulationRun** (`Cache` immediately follows `State`, then `Generator`, then `Observables`, then `Forcing` — verified alphabetical *within* each module's symbol group, so the module grouping itself is not alphabetical noise but a real ordering).

**Description:** Five independent prose statements (Home, the api overview, and three places in ARCHITECTURE.md, including a 2026-08 decision explicitly announcing this exact reordering as newly landed) agree that `Observables` precedes `Cache`, which precedes `Forcing`, which precedes `Generator`. The one auto-generated artifact that should reflect the real code — the umbrella module's rendered `Index` — instead shows `Cache` immediately after `State` (before `Observables`), and `Generator` before both `Observables` and `Forcing`. Since the Index's *within-module* symbol ordering is demonstrably alphabetical (`DealiasingStrategy, FixedDomain, HouLi, PhaseShift, TwoThirds, dealias!, max_wavenumber, new_scalar_field_physical, …`), the *module* grouping order is not alphabetical and must reflect something structural (documented page order or actual `include()` sequence) — making the mismatch a real signal, not a rendering artifact.

---

## Finding 2 — The host-device-synchronization floor is stated as zero under a fixed step, then stated as nonzero for exactly that case

**Type:** contradiction
**Severity:** minor
**Confidence:** medium

**Locations:**
- PAGE `architecture`, decision log (2026-07, "A recorded cost is not a minimal one"): *"the floor is one such readback per step under an adaptive CFL … and **none under a fixed step**."*
- **Contradicts:** PAGE `architecture`, decision log (2026-08, "The observables cache is deposit-driven"): *"which surfaces the once-per-iteration maximum-speed readback in the pass and synchronization ledgers (+1 physical-vector pass in every cell; **a hand-fixed-$\Delta t$ iteration still pays it** — held by the new `UNIFORM DEPOSIT SCHEDULE` design holder, the price of a schedule that never varies with how the run is driven)."*

**Description:** The earlier entry sets the synchronization floor at zero readbacks for a fixed-step run (only an adaptive CFL needs the host to see `max_speed`). The later entry explicitly says a fixed-$\Delta t$ iteration now pays exactly that readback anyway, under a named holder acknowledging it as a genuine, currently-unclaimed-as-`FIX` cost. Both are decision-log entries (append-only history, ordinarily exempt per this panel's adjudication precedent for renamed verbs), but this is not a naming supersession — it is a live, quantitative floor claim that the later entry reverses without cross-referencing back to correct the earlier one, so a reader assembling "what is the current floor" from the log is misled. Worth a maintainer's glance even if ultimately dispositioned as decision-log history.

---

## Notes on what checked out clean (for the record, not separate findings)

- `kinetic_energy`, `dissipation` (both routes, and their equivalence via periodicity + solenoidality), `scalar_dissipation`, `derivative_skewness` and its $C_S = \tfrac47\sqrt{15/2}$ constant, `energy_spectrum`/`integral_scale` (including the $L_E = \tfrac23 L_{11} = \tfrac13(L_{11}+2L_{22})$ identity), `taylor_reynolds`'s two equivalent forms, and the `Li2008` $G \leftrightarrow C_\varepsilon$ conversion all algebraically verified against each other across pages.
- The dealiasing cutoffs ($\tfrac23\kappa_{\mathrm{Ny}}$ for `TwoThirds`, $\tfrac{\sqrt2}{3}N\cdot\tfrac{2\pi}{L} = \tfrac{2\sqrt2}{3}\kappa_{\mathrm{Ny}} \approx 0.94\kappa_{\mathrm{Ny}}$ for `PhaseShift`) and the `recommended_cfl` base-ceiling arithmetic ($\kappa_{\max}\Delta x = 2\pi/3 \approx 2.09$) check out exactly across `notation`, `architecture`, and the `SimulationDomain`/`Propagator` API pages.
- The per-step transform-count table in `observables_cache` (18/9, 21/18, 36/18, 42/36 inverse/forward) reconciles exactly with the decision log's "RK3 51→42 c2r" / "RK2 34→28 c2r" `PhaseShift`-reuse arithmetic once the per-evaluation breakdown is expanded stage-by-stage.
- The 384 MiB / 768 MiB memory-footprint figures in the 2026-08 decisions reconcile exactly with $3 \times 256^3 \times 8$ bytes per vector field.
- All four `Spectra` velocity-model presets (`Pope2000`, `VonKarman1948`, `Pao1965`, and `Sreenivasan1995`) share the same $C_K = 1.5$ default consistently.

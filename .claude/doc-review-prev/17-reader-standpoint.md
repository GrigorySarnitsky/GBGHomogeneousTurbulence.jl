# Reader-standpoint audit — silent wrong-number hazards

Hat: reader-standpoint. Predicate: what could a reasonable reader set or read here that
yields a wrong number with no error, no warning, and no caveat **at the site they are
actually reading**? Hazards the docs already guard with a thrown error, a warning, or an
explicit at-site caveat are excluded per the brief; only findings surviving that filter are
reported below, ranked most-severe first.

---

## Finding 1 — `Li2008` carries no stated Reynolds-number validity range, yet is the silent default for every grid-mode `Simulation()`

- **Type:** api-gap
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Scalings, `Li2008`: "nearly Reynolds-number-independent"
    — no `valid_Reλ` or floor is stated anywhere in the docstring.
  - Contrast PAGE: api / phenomenology / StructureFunctions, `Lundgren2002`: "the law's
    provenance records a validity floor of $\mathrm{Re}_\lambda = 50$."
- **Contradicts:** the sibling law in the same submodule/leaf (`Lundgren2002`) treats an
  unstated validity range as a defect worth a named floor; `Li2008` — fitted to one dataset
  at $\mathrm{Re}_\lambda \approx 433$ — ships with none, on the axis (dissipation-group
  scaling at low $\mathrm{Re}_\lambda$) most exposed by a small test grid.
- **Description:** `Li2008` is the law `Simulation`'s grid mode uses, silently, on every
  default construction (`Simulation(grid_points_per_axis = N)`) to set $\nu$. A small or
  low-Reynolds-number grid (a common smoke-test size, e.g. $16^3$–$32^3$) is exactly the
  regime furthest from the calibration dataset, yet nothing — no `valid_Reλ`, no
  construction-time check, no warning — flags that the resulting $\nu$/$\mathrm{Re}_\lambda$
  rest on an untested extrapolation. `Reference`'s own docs say a range "discriminates only
  where a law states one"; here none is stated.

---

## Finding 2 — Grid-mode viscosity calibration is silently invalidated by a hand-built forcing's target or band, with no code-level check

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / SimulationRun, `Simulation`, "Setting the Reynolds number": "the choice is
    self-consistent only if the run holds $k$ near `kinetic_energy`"; "and a forcing moved
    higher invalidates it"; "Give the velocity a forcing that lets $k$ float, or one holding
    some other quantity ... and the $\nu$ chosen here no longer matches the run."
- **Description:** A reader who passes `velocity_forcing = VarianceController(target = 0.5)`
  (a different set-point than the front door's `kinetic_energy = 1.5` default) or one with
  `lowest_shell`/`highest_shell` moved off the assumed 1–2 band gets a `Simulation` that
  builds without error or warning, yet whose $\nu$/$\kappa_{\max}\eta$/$\mathrm{Re}_\lambda$
  no longer mean what the docstring claims. The precondition is named in prose but nothing
  at construction compares the forcing's actual `target`/band against the values the Li2008
  estimate assumed — the two named failure modes ("target mismatch", "band moved") are each
  individually reachable through a natural-looking keyword and neither is checked.

---

## Finding 3 — `initial_spectrum` silently uses a stationary-forced dissipation estimate even in explicit-viscosity (e.g. decaying) mode

- **Type:** api-gap
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / SimulationRun, `Simulation`, `initial_spectrum` argument: "$\varepsilon$ from
    the `Li2008` stationary-dissipation law at the requested `kinetic_energy` and box side,
    $u'$ from that same energy, $\nu$ as resolved above."
  - Same page, "Explicit mode": "Grid mode is calibrated on a stationary forced balance ...
    so a decaying run should set $\nu$ explicitly."
- **Description:** The docs themselves recommend explicit-viscosity mode for a decaying
  (`NoForcing`) run. But if that same decaying run also passes `initial_spectrum` (say
  `Pope2000()`, which has a viscosity-informed dissipation-range cutoff), the seeded
  spectrum's $\eta$/roll-off is still built from the Li2008 *stationary-forced* $\varepsilon$
  estimate at the given `kinetic_energy`/`side_length` — an assumption the decaying run was
  explicitly set up to violate. Nothing at the `initial_spectrum` site (or elsewhere) flags
  that this specific combination feeds the IC shape a dissipation rate unrelated to the
  actual (decaying) physics about to run.

---

## Finding 4 — `envelope_wavenumber` has no documented relationship to the grid's resolvable band, unlike a forcing band, which is checked

- **Type:** api-gap
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Forcing (module docstring): "A band reaching above the dealias cutoff is
    inert there ... so construction warns about it."
  - PAGE: api / SimulationRun, `Simulation`, `envelope_wavenumber` argument: no mention of
    `max_wavenumber`, $\kappa_{\mathrm{Ny}}$, or any safe range.
  - PAGE: api / State, `random_solenoidal_velocity_spectral!`: same silence.
- **Description:** A forcing band placed above the dealiasing cutoff is a checked, warned
  condition. The initial-condition envelope wavenumber `κ_p` (`envelope_wavenumber`) receives
  no analogous guard: setting it comparable to or above `max_wavenumber(domain)` (plausible
  on a coarse grid, or when a user reuses a value tuned for a finer grid) concentrates most of
  the pre-rescale random field in the dealiased-away band. The docstring's `kinetic_energy`
  rescaling still runs afterward, so the reader silently gets an initial field far from the
  intended large-scale-peaked spectrum — with no warning at the one site (`Simulation`'s own
  `envelope_wavenumber` keyword) a reader would be looking at.

---

## Finding 5 — The near-empty-band forcing floor has no stated threshold and produces no runtime signal when it clamps mid-run

- **Type:** api-gap
- **Severity:** moderate
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Forcing, `ConstantPower`: "Below a small floor on $E_{\mathrm{band}}$ the
    amplitude is set to zero, so an empty band stays empty rather than taking an unbounded
    kick."
  - PAGE: api / Forcing, `VarianceController`: "An empty band is left alone rather than
    divided by $\sim 0$ ... seed content in the band if the run depends on the controller
    taking hold."
- **Description:** Both strategies document a floor that silently switches the forcing off
  when the band's own energy/variance nears zero, but neither states the numeric threshold
  nor emits any warning or observable flag when it fires. A run whose forced band's energy
  dips near that floor mid-run (plausible transiently, or for a scalar seeded with little
  content in the forced shells) would see the forcing silently go inert — a discontinuous
  change in the physics — with $k$/$\varepsilon$ drifting for a reason invisible from any
  cached observable or log message.

---

## Finding 6 — Overriding `Pope2000`'s `c_L`/`c_η` silently breaks the energy/dissipation normalization those coefficients are stated to encode

- **Type:** api-gap
- **Severity:** moderate
- **Confidence:** medium
- **Locations:**
  - PAGE: api / phenomenology / Spectra, `Pope2000`: "the defaults `c_L = 6.78`, `c_η = 0.40`
    are the high-Reynolds-number values Pope obtains from the energy and dissipation
    normalizations ... Override any coefficient to re-fit."
  - PAGE: api / phenomenology / Spectra, `PopeLargeScale`: "`c_L` — the large-scale
    coefficient, set by the energy normalization."
- **Description:** The docstring names `c_L`/`c_η` as the values that make
  $\int_0^\infty E(\kappa)\,\mathrm{d}\kappa = k$ and the spectrum yield the stated
  $\varepsilon$ hold, then immediately invites "override any coefficient to re-fit" with no
  distinction between the two shape exponents (`p₀`, `β`, free to vary) and the two
  normalization constants (`c_L`, `c_η`, whose values are *derived from* `fp` and no longer
  match it once hand-set). A reader who re-fits `c_L` to match a different large-scale
  roll-off, then numerically integrates `spectrum` to cross-check against a run's measured
  $k$, gets a silently non-matching total with no flag that the identity was broken by the
  very override the docstring invited.

---

## Finding 7 — `AdamsBashforth(order = N)` for `N > 8` — enforcement of the stated cap is unspecified

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE: api / Particles, `AdamsBashforth`: "Capped at `8`, which is where the four-point
    Gauss–Legendre rule that integrates the interpolation weights stops being exact."
- **Description:** The docstring states a cap without saying what happens when it is
  exceeded — thrown `ArgumentError`, silent clamp to 8, or silent use of an inexact
  quadrature beyond it are all consistent readings of "capped at 8." A reader passing
  `AdamsBashforth(order = 12)` has no way to tell from this docstring alone whether they get
  an error, a quietly different order than requested, or a scheme whose weight-integration is
  silently no longer exact.

---

## Finding 8 — A hand-assembled `ObservablesCache` with insufficient `history_depth` for its trajectory scheme has no documented failure mode

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - PAGE: api / Cache, `ObservablesCache`: "`history_depth = 1` — ... A one-step scheme
    needs 1 and stores no history; an `order`-step scheme needs `order`."
  - PAGE: api / Particles, `AdamsBashforth`: "`order = 4` — how many past samples are used."
- **Description:** The front door presumably keeps these two numbers consistent, but a
  hand-assembled run (the documented alternative path throughout this API) that builds
  `ObservablesCache(domain; history_depth = 1)` and then wires an `AdamsBashforth(order = 4)`
  scheme has no stated consequence documented at either site — whether the scheme throws,
  silently reads fewer samples than its order assumes, or silently integrates over
  uninitialized ring-buffer slots. Given the corpus's general care about throw-vs-silent
  behavior elsewhere, the absence here is likely an oversight rather than a documented
  contract, but the docstrings as written do not say which.

---

## Finding 9 — `VarianceController`'s default `turnover_time` ties the controller's relaxation rate to the grid-mode viscosity estimate even in explicit-viscosity mode

- **Type:** api-gap
- **Severity:** moderate
- **Confidence:** low
- **Locations:**
  - PAGE: api / Forcing, `VarianceController`, `turnover_time` argument: "with
    $\varepsilon_\infty$ the stationary estimate for this box — the same estimate the
    grid-mode viscosity solve uses."
- **Description:** In explicit-viscosity mode (the front door's own suggested path for a
  decaying or otherwise non-default run) there is no grid-mode Li2008 solve tying $\nu$ to
  `kinetic_energy`. If the default `VarianceController` (the front door's default velocity
  forcing) still resolves its `turnover_time` from the same Li2008 estimate regardless of
  mode, the controller's relaxation timescale $t_\ell/G$ is calibrated against an
  $\varepsilon_\infty$ that may be far from the run's actual dissipation whenever the
  caller's chosen $\nu$ departs from the grid-mode assumption — silently changing how fast
  (not whether) the run reaches `kinetic_energy`, which could interact with
  `StationarityCriterion`'s own turnover-time-denominated windows in a way neither docstring
  cross-references.

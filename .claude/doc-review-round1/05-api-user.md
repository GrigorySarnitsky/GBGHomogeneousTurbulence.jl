# Hat 05 — API-User (physicist-programmer building from the docs alone)

I read the whole rendered site (`manuscript-full.md`), including the Architecture page, as a
would-be user trying to construct every public type and call every public function from the docs
only. Findings are ordered most-severe first. Each names the PAGE banner + section and quotes the
rendered text.

---

## 1. `target` means two different things — decision log vs `BandRescaling` API
- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: API — Forcing › Forcing strategies › `BandRescaling`:
    "`BandRescaling(domain; target, over = :band, lowest_shell = 1, highest_shell = 2)`" and
    "The `over` keyword selects where the target applies: `:band` (default) … `:total` …"
    — here `target` is the numeric energy held, `over` ∈ {`:band`,`:total`} is the selector.
  - PAGE: Architecture › §11 Decision log:
    "`BandRescaling` can hold the band or the total energy (`target = :band | :total`). `:band`
    (default) fixes the forced band's energy … `:total` rescales the band to pin the whole-field
    energy"
- **contradicts:** The decision-log entry names the band/total selector `target = :band | :total`;
  the live `BandRescaling` docstring names that selector `over`, and repurposes `target` to be the
  numeric energy value. Axis of disagreement: what the keyword `target` is.
- **description:** A user who copies `BandRescaling(domain; target = :total)` from the (rendered,
  user-facing) decision log passes a `Symbol` to a keyword the current API expects to be a number,
  and never sets `over`. This is a live contradiction on the same site.

## 2. `PhaseShift` dropped from the `DealiasingStrategy` supertype docstring and its section intro
- **type:** contradiction · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: API — SimulationDomain › De-aliasing strategies (section intro):
    "The aliasing-control strategy passed to `FixedDomain` — the supertype, then the sharp
    2/3-rule default and the smooth Hou–Li filter."
  - PAGE: API — SimulationDomain › `DealiasingStrategy` (Type):
    "Concrete strategies: `TwoThirds` (the sharp $2/3$ rule, the default) and `HouLi` (the smooth
    Hou–Li filter)."
- **contradicts:** Same page, SimulationDomain module docstring:
  "`DealiasingStrategy` — the aliasing-control strategy, `TwoThirds`, `HouLi`, or `PhaseShift`",
  and `FixedDomain`'s `dealiasing` argument, which enumerates all three
  ("while `PhaseShift` averages a half-cell-displaced evaluation"). `PhaseShift` is also its own
  documented subtype in that very section.
- **description:** The abstract type's own docstring — the natural place a user enumerates the
  available strategies — lists only two of the three concretes, and the section header agrees with
  the incomplete pair while `PhaseShift` sits documented three paragraphs below. Stale after
  `PhaseShift` was added.

## 3. Measured `energy_spectrum` (per-shell sum) vs model `spectrum` (density integral) — is `validate_spectrum` comparing like with like?
- **type:** dimensional · **severity:** major · **confidence:** medium
- **locations:**
  - PAGE: API — Observables › Spectrum and length scale › `energy_spectrum`:
    "the turbulent kinetic energy resolved over wavenumber-magnitude shells, $k = \sum_\kappa
    E(\kappa)$ … the energy in each shell".
  - PAGE: Notation › Diagnostics: "$E(\kappa)$ energy spectrum (energy per unit wavenumber),
    $k = \sum_\kappa E(\kappa)$".
  - PAGE: Phenomenology — Reference laws › `spectrum`: "the density in wavenumber of the kinetic
    energy, $k = \int_0^\infty E(\kappa)\,d\kappa$".
  - PAGE: API — SimulationRun › `validate_spectrum`: "Returns a named tuple `(; wavenumbers,
    measured, predicted, relative_error)`: … the measured and predicted $E(\kappa)$, and the
    relative L² discrepancy".
- **contradicts:** `energy_spectrum`/Notation define `E(κ)` as *energy in a shell* (summs to `k`),
  while the Phenomenology model `spectrum` defines `E(κ)` as a *density* (integrates to `k`). The
  Notation row even calls it "energy per unit wavenumber" (density) yet writes `k = Σ E(κ)` (sum).
- **description:** `validate_spectrum` places `measured` (per-shell energy) and `predicted`
  (spectral density) in one tuple and reports their relative L² error. For the default box
  `side_length = 2π` the shell width `2π/L = 1`, so the two coincide numerically and the comparison
  looks right; for any other `side_length` the shell width `2π/L ≠ 1`, so per-shell energy and
  density differ by that factor and `relative_error` is biased. From the docs alone a user cannot
  tell whether `validate_spectrum` reconciles this. At minimum the "energy per unit wavenumber …
  `k = Σ E(κ)`" line conflates a density with a per-shell energy.

## 4. The `f(sim)` observable convenience methods are asserted but never documented at the observables, and cover only 5 of 8
- **type:** api-gap · **severity:** major · **confidence:** high
- **locations:**
  - PAGE: API — SimulationRun › Module + The simulation: "the observables (`kinetic_energy`,
    `dissipation`, `scalar_variance`, `energy_spectrum`, `integral_scale`) accept a `Simulation`
    directly."
  - PAGE: API — Observables › `dissipation`: signature shown is only "`dissipation(ω, viscosity)`".
    Likewise `kinetic_energy(u)`, `scalar_variance(φ)`, `energy_spectrum(û, domain)`,
    `integral_scale(û, domain)` — none shows a `Simulation`-taking form.
- **description:** The example on the same page relies on the convenience method
  (`push!(history, kinetic_energy(s))` with `s::Simulation`), yet no observable docstring documents
  the `Simulation`-accepting signature, its return, or what field it reads (e.g. `dissipation(sim)`
  must source `viscosity` from `sim.conditions`, unstated). Moreover only 5 of the 8 observables get
  the `sim` method: `derivative_skewness`, `scalar_dissipation`, and `max_speed` do not — despite
  `derivative_skewness` being the headline warm-up gate. A user cannot learn any of this from the
  observable home docstrings; it lives only in prose on other pages.

## 5. `scalar_dissipation` names a spectral-representation argument `φ`, not `φ̂`, against the convention every sibling uses
- **type:** api-gap · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: API — Observables › Dissipation rates › `scalar_dissipation`:
    "`scalar_dissipation(φ, domain, diffusivity)`" … "from the scalar field `φ` $\varphi$
    (in spectral representation)".
- **contradicts:** Every other operation names the spectral scalar `φ̂`:
  `scalar_to_physical!(φ, φ̂, domain, scalar_copy)`, `random_scalar!(φ̂, domain; …)`,
  `scalar_nonlinear!(nonlinear, û, φ̂, u, φ, …)`; and the spectral velocity is always `û`
  (`derivative_skewness(û, domain)`, `energy_spectrum(û, domain)`, `integral_scale(û, domain)`).
- **description:** The only diagnostic that takes a *spectral* field but names it with the
  physical-space symbol. A user matching the naming convention ("`φ̂` = scalar in spectral
  representation") would wrongly pass a physical scalar. Should be
  `scalar_dissipation(φ̂, domain, diffusivity)`.

## 6. `flow_parameters(sim)` silently leaves `scalar_dissipation` unset (NaN) — scalar laws evaluate to NaN
- **type:** api-gap · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: API — SimulationRun › `flow_parameters`: "The viscosity $\nu$ and the Schmidt number are
    read from `sim.conditions`; the dissipation $\varepsilon$, the r.m.s. velocity $u'$ …, and the
    longitudinal integral scale $L_{11}$ are measured".
  - PAGE: Phenomenology — Reference laws › `FlowParameters`: "`scalar_dissipation` … default `NaN`
    (unset)".
  - PAGE: Phenomenology — Spectra › `ObukhovCorrsin1949`: "`spectrum` reads the scalar dissipation
    $\varepsilon_\varphi$ (`fp.scalar_dissipation`, which must be set)".
- **description:** `flow_parameters` enumerates ν, Sc, ε, u′, L₁₁ but not `scalar_dissipation`, so
  the bridged bundle carries `NaN` there. A user who does `spectrum(ObukhovCorrsin1949(), κ,
  flow_parameters(sim))` or a `Yaglom1949` structure function gets NaN with no hint why. The
  `flow_parameters` docstring should state it does not populate `scalar_dissipation` (and how to
  supply it).

## 7. Stale forcing keyword names in the (rendered) decision log
- **type:** api-gap · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: Architecture › §11 Decision log: "Operator-free forcing construction via `ForcingSpec`.
    `ConstantPower(power = 0.1)` (and the other banded forcings) return a `ForcingSpec`".
  - PAGE: Architecture › §11 Decision log ("Resolution-based `viscosity`"): "a `BandRescaling`
    holds the total energy at `energy`, default `1.5`".
- **contradicts:** Current API uses `target`, not `power`
  (PAGE: Architecture §2 example "`ConstantPower(target = 0.1)`"; PAGE: API — Forcing
  "`ConstantPower(domain; target, …)`"), and the held-energy keyword is `kinetic_energy`, not
  `energy` (PAGE: API — SimulationRun "`kinetic_energy = 1.5`").
- **description:** Two forcing keywords in the append-only log no longer match the shipped API
  (`power`→`target`, `energy`→`kinetic_energy`). Since the decision log renders on the public site,
  a user copying `ConstantPower(power = 0.1)` gets a `MethodError`. (`ForcingSpec`→`DeferredForcing`
  is separately noted as superseded within the log, so that one is at least self-flagged.)

## 8. Operator-free `BandRescaling(; target)` keyword set is under-documented; the default run needs `over = :total`, unstated
- **type:** api-gap · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: API — Forcing › Deferred forcing › `DeferredForcing`: "The operator-free keyword
    constructors — `Linear(; rate)`, `ConstantPower(; target)`, and `BandRescaling(; target)`".
  - PAGE: API — SimulationRun › `Simulation` (keywords): "`velocity_forcing` defaults to a
    `BandRescaling` holding the total energy at `kinetic_energy`".
  - PAGE: API — Forcing › `BandRescaling`: "`:band` (default) — hold the band's own value; the
    whole-field value then floats … `:total` … pins the r.m.s. velocity $u'$".
- **description:** The default `Simulation` forcing "holds the total energy" — which requires
  `over = :total` — yet (a) the operator-free `BandRescaling(; target)` form shows no `over` /
  `lowest_shell` / `highest_shell` keywords at all, so a user cannot tell whether the deferred form
  can even request `:total`, and (b) "the default `BandRescaling`" is ambiguous: the type's *own*
  default is `over = :band` (holds the band, total floats), the opposite of the run's default
  behavior. The "`kinetic_energy = 1.5` … gives `u' = 1`" claim is only exact under `:total`.

## 9. `scaling_exponent` / `structure_function` argument-name and default drift for the moment order
- **type:** api-gap · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: Phenomenology — Reference laws › `scaling_exponent`: "`scaling_exponent(law, order) ->
    Float64`" (arg named `order`).
  - PAGE: Phenomenology — StructureFunctions › `SheLeveque1994` / `Kolmogorov1962`: "Its
    `scaling_exponent`(law, p) gives …" (arg named `p`).
  - PAGE: Phenomenology — Reference laws › `structure_function`: "`structure_function(law, r, fp;
    order) -> Float64`" (no default) vs PAGE: StructureFunctions › `Yaglom1949` / `Lundgren2002`:
    "`structure_function`(law, r, fp; order = 3)".
- **description:** The same moment index is `order` in the generic `scaling_exponent` but `p` in the
  law docstrings; and `structure_function`'s `order` is shown required in the generic home but
  defaulted (`order = 3`) at two laws and multi-valued (2 or 3) at `Kolmogorov1941`. A user cannot
  tell from the generic whether `order` is required or has a default.

## 10. `Kolmogorov1941`'s `scaling_exponent` (the `p/3` law) is advertised in the module map but absent from its own docstring
- **type:** api-gap · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: Phenomenology — StructureFunctions (module map): "`Kolmogorov1941` — the K41 inertial-range
    laws: the exact 4/5 law, the 2/3 law, and the self-similar exponents (via `scaling_exponent`)".
  - PAGE: Phenomenology — StructureFunctions › `Kolmogorov1941` (Type): documents only
    "`structure_function`(law, r, fp; order)" for `order = 2` and `order = 3`; no mention of
    `scaling_exponent` or `ζ_p = p/3`.
- **description:** The home docstring for `Kolmogorov1941` omits the `scaling_exponent` method the
  map promises, so a user reading the type would not know `scaling_exponent(Kolmogorov1941(), p)`
  returns `p/3`. Map claims a capability the home does not carry.

## 11. `Simulation(domain; …)` — the positional `domain` argument is not enumerated
- **type:** api-gap · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: API — SimulationRun › The simulation › `Simulation`: second form
    "`Simulation(domain; k_max_η = 2, kinetic_energy = 1.5, kwargs...)`"; prose "the second takes a
    `FixedDomain` you built yourself." The Keywords bullet list has no `domain` entry.
- **description:** Every keyword gets its own bullet, but the sole positional argument of the
  second constructor (`domain`) is described only in a passing clause, not enumerated with the other
  arguments — exactly the "signature argument not documented from the signature" gap the project's
  own checklist warns about (`domain`/`buffers` slipping past).

## 12. `Simulation` keyword names drift from the `Tracers` constructor they forward to
- **type:** api-gap · **severity:** minor · **confidence:** high
- **locations:**
  - PAGE: API — SimulationRun › `Simulation` (keywords): "`ntracers = 0`, `tracer_scheme =
    CatmullRom` — the number of Lagrangian `Tracers` and their interpolation scheme."
  - PAGE: API — Particles › `Tracers`: "`Tracers(domain, count; scheme = CatmullRom, …)`", and the
    accessor "`ntracers(tracers)`".
- **description:** The count is `ntracers` as a `Simulation` keyword but `count` as the `Tracers`
  positional; the interpolation scheme is `tracer_scheme` on `Simulation` but `scheme` on `Tracers`.
  `ntracers` also names the read accessor. Harmless to call, but a user mapping the front door onto
  the underlying constructor meets three names for two things.

## 13. "Default `BandRescaling`" is ambiguous — the type default (`:band`) is the opposite of the run default (total)
- **type:** clarity · **severity:** minor · **confidence:** medium
- **locations:**
  - PAGE: API — Forcing › `BandRescaling`: "`:band` (default) — hold the band's own value; the
    whole-field value then floats".
  - PAGE: API — SimulationRun › `Simulation`: "By default the run is forced and stationary — a
    `BandRescaling` holds the total energy at `kinetic_energy`".
- **description:** Reading `BandRescaling` in isolation, a user concludes the default holds only the
  forcing band and lets the total float; reading `Simulation`, the default forcing holds the total.
  Both are true (the run overrides `over`), but the shared phrase "a `BandRescaling` … default"
  points at opposite behaviors, and the override is never stated at the run layer.

## 14. `max_speed(u)` does not state the representation of `u`
- **type:** clarity · **severity:** nit · **confidence:** medium
- **locations:**
  - PAGE: API — Observables › Timestep control › `max_speed`: "The largest velocity component in
    absolute value, $\max_i\lvert u_i\rvert$ — an allocation-free reduction used to set the
    advective CFL timestep."
- **description:** `max_speed` is a physical-space max over grid points, but unlike its siblings
  (`kinetic_energy(u)` states "either representation"; `dissipation` states "physical `ω`";
  `derivative_skewness(û)` states spectral) it never says `u` must be in physical representation.
  A user cannot infer from the docstring that spectral input is meaningless here.

## 15. Return-type annotation is inconsistent across the public surface
- **type:** format · **severity:** nit · **confidence:** high
- **locations:**
  - PAGE: Phenomenology — Reference laws: derived-scale and evaluator signatures annotate returns,
    e.g. "`kolmogorov_length(fp) -> Float64`", "`spectrum(law, κ, fp) -> Float64`".
  - PAGE: API — Observables: no observable annotates its return, e.g. "`kinetic_energy(u)`",
    "`dissipation(ω, viscosity)`", "`integral_scale(û, domain)`".
- **description:** The scalar-returning Phenomenology functions carry `-> Float64`; the equally
  scalar-returning Observables carry none. A user scanning signatures for return types gets an
  inconsistent picture of which functions return a scalar vs a tuple/field (only `energy_spectrum`
  and `validate_spectrum` describe non-scalar returns, and only in prose).

## 16. Spectrum presets render as `— Function` while the other law presets render as `— Type`
- **type:** format · **severity:** nit · **confidence:** high
- **locations:**
  - PAGE: Phenomenology — Spectra: "`…Spectra.Pope2000` — Function", "`…VonKarman1948` — Function",
    "`…Pao1965` — Function".
  - PAGE: Phenomenology — Spectra / StructureFunctions / Scalings: "`…ObukhovCorrsin1949` — Type",
    "`…Kolmogorov1941` — Type", "`…Sreenivasan1998` — Type".
- **description:** Velocity-spectrum presets are factory *functions* returning a `ModelSpectrum`,
  while every other named law is a *type* with a keyword constructor. Both are invoked identically
  (`Name(; kwargs)`), so calling is uniform, but the rendered "Function"/"Type" split is a subtle
  inconsistency, and it means there is no `Pope2000` type to dispatch on or annotate (`::Pope2000`),
  unlike `::Kolmogorov1941`.

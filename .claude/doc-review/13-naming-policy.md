# Naming-policy hat — findings

Reviewed against `CLAUDE.md`'s Naming rules: (a) name for what it means to the user, never the
backend mechanism; (b) unambiguous and precise; (c) field math variables are Unicode symbols,
storage/functions descriptive; (d) one concept, one name. Corpus read: `CLAUDE.md`, the rendered
manuscript (Home, architecture, notation, observables_cache, phenomenology, and every `api/*` page),
and `src/*.jl` for cross-checking the rendered names against the actual bindings.

---

## Finding 1 — `record_trajectory_velocity!` keeps the one root word the particle/tracer rename swept away everywhere else

- **Type:** clarity
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE `api / Particles` (module docstring): "`record_trajectory_velocity!` — store the flow velocity at the tracers' current positions" sits in the same export list as `particle_positions`, `number_of_particles`, `particle_velocities`, `interpolate_at_particles!`.
  - Same page: "the trajectory velocities are read from the run's observables cache through `particle_velocities`" — both roots used for the identical quantity in one sentence.
  - PAGE `architecture` §11 decision (2026-08, user-directed, "Particle is the category, tracer the kind"): "Hence `number_of_tracers` becomes `number_of_particles`... and `sample!` becomes `interpolate_at_particles!`."
- **Contradicts:** the decision-log rename explicitly states the rule "name by what the operation is true of" and enumerates only two vocabulary roots, *particle* (whole ladder) and *tracer* (massless kind); `record_trajectory_velocity!` uses a third root, "trajectory," that the decision never mentions and never sweeps.
- **Description:** The single Lagrangian quantity $\boldsymbol u(t_n,\boldsymbol X(t_n))$ is named `particle_velocities` everywhere it is stored or read (the `Tracers` field, the `Cache` slot, the accessor) but is *written* by a verb rooted in a different word, `record_trajectory_velocity!`. The decision-51 sweep renamed every sibling in the same export list (`number_of_tracers`→`number_of_particles`, `sample!`→`interpolate_at_particles!`) but missed this one verb, so the module's own contents list juxtaposes both roots for one concept. Per the decision's own taxonomy the operation is arguably tracer-specific (an inertial particle's velocity is state, not an interpolated sample), so neither existing root cleanly covers it — but "trajectory" is a third, unexamined choice.
- **Resolution hint:** rename to `record_particle_velocity!` (matching the noun everywhere else) or, if the tracer-specificity argument is intended, to `record_tracer_velocity!` — either beats the unswept third root.

---

## Finding 2 — `max_wavenumber` reads as the grid Nyquist and isn't; the docstring has to say so

- **Type:** clarity
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE `api / SimulationDomain`: `max_wavenumber(domain)` — "The highest wavenumber magnitude that `domain`... actually evolves"
  - Same docstring: "It is the cutoff the dealiasing sets — not the grid Nyquist $\tfrac{N}{2}\tfrac{2\pi}{L}$ itself."
- **Description:** "Maximum wavenumber" is the plain-English name for the grid's Nyquist wavenumber $\kappa_{\mathrm{Ny}} = \tfrac{N}{2}\tfrac{2\pi}{L}$ — the literal largest wavenumber the grid can represent. The function instead returns the smaller, strategy-dependent dealiasing cutoff $\kappa_{\max} = f\kappa_{\mathrm{Ny}}$, and its own docstring must explicitly warn against the more natural reading. This is exactly the category-error risk the project's own doc-policy guards against elsewhere (a rate vs. its field, a density vs. an energy) — here applied to the name itself rather than a formula.
- **Resolution hint:** `dealiased_max_wavenumber` or `resolved_max_wavenumber` would state the qualifier the docstring currently has to supply after the fact.

---

## Finding 3 — `FlowConditions` and `FlowParameters` are near-identical names for an input bundle and a measured bundle, sharing field names

- **Type:** clarity
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Generator`: `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)` — "Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names: this type holds what a run is configured with, that one holds what a run has been measured to have."
  - PAGE `api / phenomenology / Phenomenology`: `FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale, schmidt = 1.0, ...)`.
- **Description:** Two types differing only by "Conditions" vs. "Parameters" — both prefixed `Flow`, both carrying `viscosity` and `schmidt` — represent categorically different things: a configuration input and a measured output. The docstring's own disclaimer ("not to be confused with") is itself evidence the names sit too close together for rule (b)'s "one reading." A reader skimming a signature or an error message with `FlowConditions`/`FlowParameters` in scope has no lexical cue for which one is which without opening the docs.
- **Resolution hint:** a name that encodes the input/measured axis directly (e.g. `MeasuredFlowState` for the latter) would remove the need for the disclaimer.

---

## Finding 4 — "spectrum" names two dimensionally different objects: a per-shell sum and a spectral density

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Observables`: `energy_spectrum(û, domain)` — "a model spectrum $E(\kappa)$ from `Phenomenology` is instead a density per unit wavenumber... and are not interchangeable."
  - PAGE `api / phenomenology / Phenomenology`: `spectrum(law, κ, fp) -> Float64` — "the velocity energy spectrum $E(\kappa)$."
  - PAGE `notation`: $E_n$ (dimensions $L^2T^{-2}$) vs. $E(\kappa)$ (dimensions $L^3T^{-2}$).
- **Description:** `Observables.energy_spectrum` returns the measured per-shell energy $E_n$; `Phenomenology.spectrum` returns the model density $E(\kappa)$. Both are called "spectrum" in their identifiers, and the two are explicitly non-interchangeable by a factor of the shell width. The name alone gives no hint which of the two dimensionally distinct quantities a caller gets — the disambiguation lives entirely in prose the project elsewhere insists on carrying in the identifier itself (e.g. `energy_spectrum` vs. a hypothetical `spectral_density`).
- **Resolution hint:** none required if the corpus's convention is "Observables measures, Phenomenology predicts, and the shape difference is inherent" — but a `energy_per_shell` or `shell_energy` name would remove the ambiguity outright.

---

## Finding 5 — `integral_scale` returns specifically $L_{11}$, one of (at least) three named integral scales its own docstring discusses

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Observables`: `integral_scale(û, domain)` — "$L_{11}$ is the large-eddy scale"; same docstring: "the transverse integral scale is $L_{22} = L_{11}/2$"; "$L_E = \tfrac{2}{3}L_{11}$."
- **Description:** The function name is generic ("the" integral scale) while the docstring immediately distinguishes three specifically-named scales ($L_{11}$, $L_{22}$, $L_E$) and returns only the first. A reader who has not opened the docstring has no way to know which of the three is meant — a violation of rule (b)'s "the exact thing, not an approximate cover word," especially notable given the project's care distinguishing $E_n$ from $E(\kappa)$ elsewhere.
- **Resolution hint:** `longitudinal_integral_scale` (matching the $L_{11}$ subscript convention already used in the notation table).

---

## Finding 6 — the Heun/RK2 "predictor" concept is named `*_star_spectral` on the field side and `predictor*` on the particle side

- **Type:** design
- **Severity:** minor
- **Confidence:** low-medium
- **Locations:**
  - PAGE `api / Propagator`: `IntegratorBuffers` — "`stage2`, `velocity_star_spectral` — the second stage register and the substage velocity **predictor** $\hat{\boldsymbol{u}}^{*}$ in spectral representation."
  - PAGE `api / Particles`: `ParticleIntegratorBuffers` — "`predictor` — the $(M,3)$ predicted positions... `predictor_velocity` — the velocity interpolated at the predicted positions."
- **Contradicts:** the architecture text draws the two buffer types as one deliberate parallel ("exactly as `ResolvedFields` is held apart from `IntegratorBuffers` on the field side," decision 50), yet the shared role — a scheme's provisional/predictor value — is stored under two different name roots ("star" vs. "predictor").
- **Description:** Both buffers hold the same structural role for their respective Heun-family scheme: a provisional midpoint value used only to compute the second-stage right-hand side. The field-side struct field spells it `velocity_star_spectral` (naming the math notation $\hat u^*$) while its own docstring prose calls it "the substage velocity predictor" — and the particle-side struct field takes that prose word literally as its field name (`predictor`, `predictor_velocity`). One concept, two storage-name conventions, in two types the docs explicitly present as parallel.
- **Resolution hint:** low stakes given each is confined to its own scheme's internals, but `velocity_predictor_spectral` would align the field-side name with both its own docstring prose and the particle side.

---

## Finding 7 — `BandRescaling`'s `over` keyword is a bare preposition standing in for "which quantity this rescale holds fixed"

- **Type:** clarity
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE `api / Forcing`: `BandRescaling(domain; target, over, lowest_shell = 1, highest_shell = 2)` — "The `over` keyword selects where the target applies. It is required."
- **Description:** `over` alone, read cold, does not say what it ranges *over* — a value's scope, a time window, or (as it actually is) which of two energy budgets (`:band` vs. `:total`) the rescale pins. The keyword is thoroughly justified and its required-ness carefully decided (architecture §11), but the word itself is a short function word rather than a term naming the choice it makes.
- **Resolution hint:** something like `hold` or `pin_scope` would name the choice rather than its grammatical role.

---

## Finding 8 — `κ_max_η` is a raw symbol used as a settings keyword, breaking the descriptive-parameter convention every sibling setting follows

- **Type:** design
- **Severity:** nit
- **Confidence:** low
- **Locations:**
  - PAGE `api / SimulationRun`: `Simulation(; grid_points_per_axis, κ_max_η = 2, kinetic_energy = 1.5, ...)` — "`κ_max_η = 2` — the resolution criterion $\kappa_{\max}\eta$ used to set $\nu$ in grid mode."
- **Description:** Every other scalar setting in the same constructor is an English descriptive word (`viscosity`, `side_length`, `injection_rate`, `envelope_wavenumber`), consistent with CLAUDE.md's rule that a field math variable takes a symbol while a storage slot or setting is descriptive. `κ_max_η` is not a field math variable (it is a resolution-criterion threshold, a setting) yet is spelled as a bare compound symbol — the one keyword in the front door's argument list that departs from the descriptive-name convention its neighbors all follow.
- **Resolution hint:** `resolution_criterion` (with the symbol given once in the docstring) would match its neighbors; low priority since the symbol is precise and the docstring explains it immediately.

# Naming-policy hat — findings

Reviewed against `CLAUDE.md`'s "Naming" rules (physicist-facing meaning, unambiguous + precise,
math-symbols-for-variables / descriptive-names-for-storage, one concept one name), the rendered
manuscript, and `src/*.jl`. Findings already covered by `.claude/doc-review-adjudicated.md` (the
`integrator`→SciML false-cognate ruling, `CatmullRom` bare, PascalCase spectrum-preset aliases, the
`max_speed` cost split, `HouLi`'s shared `36`, `Tracers`' two construction paths) are not repeated.

---

## 1. `deposit!` is claimed by `Cache`'s own module map, but is owned by `Propagator`

**Type:** contradiction · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE `api / Cache`, module docstring bullet list: *"The cache's operations: … `deposit!`,
  `deposit_sample!` — the writers: the first fills every field slot at the iteration's end…"*
- Same page, next paragraph: *"That verb lives in `Propagator` rather than here because it needs
  the scheme's own scratch to recover the fields, and that is the module owning the iteration it
  closes."*
- PAGE `api / GBGIsotropicTurbulence`, Index: `GBGIsotropicTurbulence.Propagator.deposit!` (not
  listed under `Cache`).

**Contradicts:** the `Cache` module docstring's own bullet list names `deposit!` as one of "the
cache's operations" (a `Cache` binding), then the prose two sentences later says the verb "lives in
`Propagator` rather than here" — and the API index confirms `Propagator` is the true owner. A
module docstring is supposed to be a "map" (`CLAUDE.md`: "identity → contents list → optional
trailing remark, in that order"); this map names an export it does not carry.

**Description:** A reader who trusts the Cache page's own contents list will `import`-hunt for
`Cache.deposit!` and fail, or assume the Cache module re-exports it. The fix is either to say
"consumes" rather than list it as a Cache operation, or to footnote the cross-module home
immediately in the bullet, not two paragraphs later.

---

## 2. `FlowConditions` and `FlowParameters` are near-homonyms for two different bundles

**Type:** clarity · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE `api / Generator`, `FlowConditions` docstring: *"Not to be confused with `Phenomenology`'s
  `FlowParameters`, which shares two field names: this type holds what a run is configured with,
  that one holds what a run has been measured to have."*
- PAGE `api / phenomenology / Phenomenology`, `FlowParameters` docstring: *"the analogue of
  `FlowConditions` and `FixedDomain` on the phenomenology side."*

**Description:** Two public types differing only in "Conditions" vs "Parameters" — words that are
near-synonyms in ordinary physics prose ("the flow conditions", "the flow parameters") — hold
different content (config-time vs measured-time) and, by the docstring's own admission, share field
names. The docstring needed a "not to be confused with" disclaimer to keep the two straight, which
is itself the signal that the pair fails the "unambiguous (one reading)" rule: a reader recalling
"the `Flow*` bundle" from one context cannot tell which type they mean without checking. A pair like
`FlowConditions` (configured) / `MeasuredFlowState` or `FlowConditions` / `FlowMeasurements` would
carry the config-vs-measured distinction in the name itself rather than in a footnote.

---

## 3. The assembled right-hand side is `N̂` in one protocol verb and `nonlinear` in another

**Type:** clarity · **Severity:** minor · **Confidence:** medium-high

**Locations:**
- PAGE `api / Generator`, `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)`: *"Assemble the
  explicit right-hand side of the momentum equation into `N̂`…"*
- PAGE `api / Forcing`, `add_forcing_source!(forcing, nonlinear, domain) -> nonlinear`: *"Add the
  strategy `forcing`'s additive source to the dealiased nonlinear-term buffer `nonlinear` at each
  Runge–Kutta stage…"*
- PAGE `notation`, Code column for $\widehat{\boldsymbol N}$: *"velocity_rhs!, scalar_rhs!"* — the
  glossary's own binding does not list `add_forcing_source!` as a code home for the same quantity.

**Contradicts:** `velocity_rhs!`/`scalar_rhs!` assemble into and name the argument `N̂` — the
glossaried math variable $\widehat{\boldsymbol N}$ — while `add_forcing_source!` is documented as
writing its source into that exact same buffer (the nonlinear term "plus the per-stage additive
source of the generator's velocity forcing (its `add_forcing_source!` hook)"), under the plain
English word `nonlinear` instead.

**Description:** `CLAUDE.md`'s naming rule is explicit: "A field **math variable** (a function
parameter or a local) is named by its symbol." `add_forcing_source!`'s `nonlinear` parameter is the
same field, at the same point in its lifecycle, as `velocity_rhs!`'s `N̂` — one concept, two names
across the six-verb protocol.

---

## 4. `Simulation`'s two particle-tracking fields split the same subsystem's vocabulary

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / SimulationRun`, `Simulation` Fields: *"`tracers`, `trajectory_scheme`,
  `particle_buffers` — the `Tracers` being advected along with the fields, the trajectory scheme
  advancing them, and that scheme's registers…"*
- PAGE `api / Particles`: `AbstractParticleIntegrator`, `ParticleIntegratorBuffers` — *"the
  supertype of the trajectory time-integration schemes"* built by `allocate_buffers(scheme,
  tracers)`.

**Description:** One `Simulation` documents its two halves of one subsystem — the scheme and its
registers — as `trajectory_scheme` and `particle_buffers`: "trajectory" names the scheme, "particle"
names its buffers, inside the *same* field list, for what the Particles page itself calls a matched
pair (`allocate_buffers(scheme, tracers)` builds the registers "that scheme needs"). The type names
(`AbstractParticleIntegrator`, `ParticleIntegratorBuffers`) use "particle", the field-side keyword
and `Simulation` field use "trajectory" (`trajectory_scheme`). Decision 51 fixed "particle is the
category, tracer the kind" for the positions/count/sample surface but left this third term
("trajectory") loose on the scheme/buffers surface. Picking one head noun (`particle_scheme` +
`particle_buffers`, matching the types) would close it.

---

## 5. `Linear` is a bare, over-generic forcing name next to its siblings

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / Forcing`, module docstring: *"The strategies are `NoForcing`, `BandRescaling`,
  `Linear` and `ConstantPower`…"*
- PAGE `api / Forcing`, `Linear(domain; rate, lowest_shell = 1, highest_shell = 2)`: *"Linear
  (negative-damping) forcing $f = A\,\texttt{field}$ in a low-wavenumber band…"*

**Description:** `NoForcing`, `BandRescaling`, and `ConstantPower` each carry enough of their own
content in the name to read as a forcing strategy even out of context (a rescaling of a band, a
constant power). `Linear` alone is a generic mathematical adjective with no anchor to forcing, energy
injection, or a rate — a physicist skimming `using GBGIsotropicTurbulence`'s exported names would not
guess `Linear` is an `AbstractForcing` rather than, say, a linear operator or an interpolation
scheme. `LinearRateForcing` or `LinearDamping` would keep the precision the naming rule asks for.

---

## 6. `EnergySpectrum` / `ScalarSpectrum` name the velocity/scalar pair on two different axes

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE `api / phenomenology / Spectra`: *"`EnergySpectrum` — the velocity-spectrum family root…"*
- Same page: *"`ScalarSpectrum` — the passive-scalar spectra…"*

**Description:** The two roots of the one `Spectra` family are named on different axes: one by
*quantity* ("Energy" — but energy is also true of the scalar's variance spectrum in the loose sense
of "spectral energy"), the other by *field* ("Scalar" — velocity is implicit only by elimination).
A reader cannot infer from the pair alone that `EnergySpectrum` means "velocity" specifically;
elsewhere in the same corpus the parallel pair is kept explicit (`Observables.kinetic_energy` vs
`scalar_variance`, `dissipation` vs `scalar_dissipation`). A symmetric pair — `VelocitySpectrum` /
`ScalarSpectrum`, or `KineticEnergySpectrum` / `ScalarVarianceSpectrum` — would carry the same
information the doc's cold-read currently supplies only by exclusion.

---

## 7. `predictor_velocity` and `velocity_predictor_spectral` invert word order for the same role

**Type:** clarity · **Severity:** nit · **Confidence:** medium

**Locations:**
- PAGE `api / Particles`, `ParticleIntegratorBuffers` Fields: *"`predictor_velocity` — the velocity
  interpolated at the predicted positions."*
- PAGE `api / Propagator`, `IntegratorBuffers` Fields: *"`stage2`, `velocity_predictor_spectral` —
  the second stage register and the substage velocity predictor $\hat{\boldsymbol u}^{*}$ in spectral
  representation; `IFRK2` only…"*

**Description:** Both are the same shape of object — a scheme-owned stage register holding a
predicted/predictor velocity, explicitly disclaimed in both docstrings as "not a sample of the flow
at any instant" — yet the noun order flips: `predictor_velocity` (particle side) vs
`velocity_predictor_spectral` (field side). A single order across the two sibling buffer types would
make the shared concept legible at a glance rather than requiring the reader to notice the two are
analogous despite reading differently.

---

## 8. `record_particle_velocity!` (singular) writes into `particle_velocities` (plural)

**Type:** clarity · **Severity:** nit · **Confidence:** low-medium

**Locations:**
- PAGE `api / Particles`, `record_particle_velocity!(tracers, u) -> tracers`: *"Store the Lagrangian
  velocity … by interpolating the velocity field `u` … onto the positions of the tracer set
  `tracers`…"*
- Same page, `Tracers` Fields: *"`particle_velocities` — the interpolated velocity at the positions
  the tracers occupy…"* and `Cache.particle_velocities(cache)`.

**Description:** The mutator that fills the $M \times 3$ `particle_velocities` slot for every
tracer in the set is named in the singular (`record_particle_velocity!`), while the slot, its
accessor, and its notation.md binding are all plural. The verb reads as "record one particle's
velocity" when it in fact records all $M$ at once — a small but real drift against "one concept, one
name" for the noun it operates on.

---

## 9. The IC-shaping keyword is `spectrum` at the seeder, `initial_spectrum` at the front door

**Type:** clarity · **Severity:** nit · **Confidence:** medium

**Locations:**
- PAGE `api / State`, `random_solenoidal_velocity_spectral!(û, domain; kinetic_energy,
  envelope_wavenumber, spectrum = nothing, rng = default_rng())`.
- PAGE `api / SimulationRun`, `Simulation` Arguments: *"`initial_spectrum = nothing` — draw the
  initial velocity from a `Phenomenology` `EnergySpectrum` … instead of the default large-scale
  Gaussian."*

**Description:** The same concept — a target radial spectrum shape overriding the default Gaussian
envelope — is named `spectrum` at the low-level seeder and `initial_spectrum` at the `Simulation`
front door that forwards to it. Since `Simulation` has no competing non-initial spectrum keyword to
disambiguate against, the rename adds a qualifier the low-level API doesn't carry, so a reader
moving between the two surfaces must remember the two names denote one setting.

---

## 10. `truncate_to_band!`'s name reads as complete dealiasing; under `PhaseShift` it is half of it

**Type:** clarity · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE `api / SimulationDomain`, `truncate_to_band!(field, domain)`: *"Truncating the band is not
  always the whole of dealiasing … Under `PhaseShift` it is only the second half, so calling it on a
  product assembled without the displaced-evaluation average leaves that product aliased…"*

**Description:** The name promises the complete operation ("truncate to the retained band" reads as
"dealias"), and the docstring has to spend an admonition correcting the impression for two of the
three strategies (`HouLi` only damps; `PhaseShift` needs a second call the function alone can't
perform). The self-correction is honest and load-bearing, but it is exactly the class the hat's
brief calls out — a name that promises an outcome one call cannot always deliver. A name scoped
to what it always does regardless of strategy (e.g. `apply_dealias_kernel!`) would need no such
caveat.

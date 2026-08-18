# Doc-review panel — hat: physicist-programmer API user

Reviewed the full rendered manuscript (Home, api overview, architecture, notation,
observables_cache, phenomenology landing, and every `api/*` + `api/phenomenology/*` module page)
as a user trying to assemble a `Simulation`, run it with `run!`/`warmup!`, read `sim.cache`, and
sample tracers. Findings below, most-severe first.

---

## 1. `advance!`'s own docstring never mentions the closing deposit it performs

- **Type:** api-gap
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE `api / SimulationRun`, `advance!`: *"Advance `sim` by one timestep in place and return it. … Advects the tracers, if any, … and updates the clock."*
  - PAGE `api / Propagator`, `step!`: *"the caller closes the iteration with `deposit!` … the run layer's `advance!` does both."*
  - PAGE `api / Propagator`, `deposit!`: *"the run layer's `advance!` performs it after `step!`"*
- **Description:** `advance!` is the function nearly every example calls directly (including the Particles page's own usage example, which calls `advance!(sim)` and then reads `sim.cache` right after). Yet its own docstring — the "home" for that operation per the package's own doc policy — says nothing about the closing `deposit!` that is precisely what makes `sim.cache` readable afterward. A cold read of `advance!` alone gives no idea the cache becomes valid as a side effect; that fact must be pieced together from two *other* pages' docstrings (`step!`, `deposit!`).

---

## 2. `ObservablesCache`'s `particle_velocities` keyword: type and required wiring undocumented

- **Type:** api-gap
- **Severity:** major
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Cache`, `ObservablesCache`: *"pass … `particle_velocities` — the tracer set's own point-value storage — when the run advects tracers: the slot IS that storage"*
  - PAGE `api / Particles`, `record_trajectory_velocity!`: *"which is also the observables cache's particle-velocities slot"*
- **Description:** Neither docstring says what value to actually pass (e.g. `tracers.trajectory_velocity`) or shows a worked hand-assembly example — the `observables_cache` design page's own build example (`ObservablesCache(domain; scalar = true)`) omits tracers entirely, and the Particles page's hand-run-loop example bypasses `ObservablesCache` altogether. Architecture.md explicitly invites a user to "drop straight to §4" and assemble pieces by hand, but nothing shows how to wire the cache's slot to the tracer set's storage. `record_trajectory_velocity!`'s docstring then states the aliasing as an unconditional fact rather than a consequence of that (undocumented) wiring.

---

## 3. `Tracers`'s two-line signature block visually implies dispatch the architecture says is impossible

- **Type:** contradiction
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Particles`, `Tracers`: `Tracers(domain; number_of_particles, interpolation_scheme, rng = default_rng())` / `Tracers(domain; positions, interpolation_scheme)`
  - PAGE `architecture`, decision log (2026-08): *"keyword arguments do not participate in dispatch … `Tracers` is therefore a single method … a merge forced by the language"*
- **Contradicts:** whether `Tracers` is two genuinely dispatched constructors or one method with a runtime check — the API page's two-signature-block formatting (the same convention used for real multi-dispatch elsewhere, e.g. `dissipation`, `max_speed`) versus the architecture's explicit statement that two all-keyword forms "cannot be two methods."
- **Description:** The `Tracers` docstring's own prose does clarify the runtime `ArgumentError` behavior, so a careful reader isn't actually misled — but the signature-block convention itself doesn't distinguish "two real methods" from "one method, two valid call shapes," and `Tracers` is the one place in the whole surface where that convention is applied to the latter.

---

## 4. "What does this return?" is documented three incompatible ways across modules

- **Type:** format
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - PAGE `api / Generator`, `prepare!`: *"Returns `generator`."*
  - PAGE `api / Propagator`, `deposit!`: *"Returns `cache` (or `sim`)."*
  - PAGE `api / Forcing`, `set_forcing_rate!`: `set_forcing_rate!(forcing, rate, field, domain) -> rate`
  - PAGE `api / Particles`, `record_trajectory_velocity!`: `record_trajectory_velocity!(tracers, u) -> tracers`
- **Description:** For functionally identical "this mutator hands back its mutated argument" cases, `Generator`/`Propagator`/`Observables` use a trailing "Returns X." sentence while `Forcing`/`Particles`/`Phenomenology` put `-> X` in the signature block itself. No page states a rule for which style applies where, so a reader can't tell from the signature alone whether an omitted arrow means "returns nothing interesting" or "this module just doesn't use arrows."

---

## 5. `Observables`' plain scalar reductions never show a return-type arrow, unlike `Phenomenology`'s equivalents

- **Type:** format
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Observables`, `kinetic_energy`: `kinetic_energy(u)` — no return annotation anywhere in the block.
  - PAGE `api / phenomenology / Phenomenology`, `kolmogorov_length`: `kolmogorov_length(fp) -> Float64`
- **Description:** Both are pure scalar-returning query functions over a state bundle, yet every `Observables` reduction (`kinetic_energy`, `dissipation`, `scalar_variance`, `derivative_skewness`, `max_speed`) omits a return-type arrow while every structurally identical `Phenomenology` accessor includes one — an inconsistent signature-block convention for the same kind of operation, one module apart.

---

## 6. Bare, physical-convention symbol names (`u`, `ω`, `φ`) are documented to accept — and an example passes — spectral data

- **Type:** clarity
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Observables`, `kinetic_energy`: `kinetic_energy(u)` … *"it accepts `u` in either representation"*
  - PAGE `Home`: *"kinetic_energy(sim.state.velocity_spectral)"*
- **Description:** The house convention (CLAUDE.md, notation.md) reserves the bare symbol for the physical representation and the hatted symbol (`û`) for spectral. `kinetic_energy`/`scalar_variance`/`dissipation`'s field arguments keep the bare, physical-looking name yet are documented — and the flagship Home-page quick-start actually demonstrates — passing the *spectral* field into it, cutting against the very field-vs-representation discipline the docs elsewhere insist is a category-error class to guard against.

---

## 7. `advect!`'s argument order diverges from `step!`'s despite the docs advertising a shared convention

- **Type:** api-gap
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - PAGE `api / Propagator`, `step!`: `step!(scheme, state, generator, domain, buffers, cache, dt)`
  - PAGE `api / Particles`, `advect!`: `advect!(scheme, tracers, buffers, velocity_end, domain, dt)`
- **Description:** `buffers` precedes `domain` in `advect!` but follows it in `step!`. The docs elsewhere take explicit pride in a shared positional convention across the field and particle sides (`allocate_buffers` is "one generic … because both sides keep the same separation") and in `step!`/`deposit!`'s shared order specifically ("the chained pair transposes nothing"), which makes the one mismatched pair stand out as unexplained.

---

## 8. `tracer_scheme` (front door) vs `interpolation_scheme` (`Tracers`) is a renamed forward with no stated reason

- **Type:** clarity
- **Severity:** nit
- **Confidence:** medium
- **Locations:**
  - PAGE `api / SimulationRun`, `Simulation`: *"`tracer_scheme = CatmullRom` … forwarded to the `Tracers` constructor as its `interpolation_scheme`"*
  - PAGE `api / SimulationRun`, `Simulation`: *"`particle_scheme = EndpointHeun()` … a different axis from `tracer_scheme` despite the neighbouring names"*
- **Description:** The front door renames the keyword it forwards (`interpolation_scheme` → `tracer_scheme`) for no stated reason, landing the new name one letter-shuffle from the unrelated `particle_scheme` keyword. The risk is self-acknowledged in the same docstring ("despite the neighbouring names") but not resolved — simply keeping the name `interpolation_scheme` at the front door, matching `Tracers`, would have removed the collision the note has to warn about.

---

## Positive cross-checks (not findings, recorded to show the ground covered)

- Every export listed in the `api / GBGIsotropicTurbulence` Index has a matching documented
  entry on its module's page, for every core-DNS module (`SimulationDomain`, `State`,
  `Observables`, `Cache`, `Forcing`, `Generator`, `Propagator`, `Particles`, `SimulationRun`) — no
  exported-but-undocumented or documented-but-not-exported items found.
- All constructors checked against the "source object positional, settings keyword" decision
  (`FixedDomain`, `ObservablesCache`, `ResolvedGenerator`, `Tracers`, `BandRescaling`,
  `FlowConditions`, `ResolvedFields`, `Simulation`) comply with it.
- `squared_wavenumber_kernel` (notation.md, `Observables.dissipation`/`scalar_dissipation`) is
  consistently documented as the lazy `RadialKernel` field on `FixedDomain` across every page that
  names it — an apparent staleness risk against the "the stored real |κ|² array is gone" decision
  that turned out not to be one.

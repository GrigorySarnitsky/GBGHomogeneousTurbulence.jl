# Naming-policy hat — findings

Audits the public surface against CLAUDE.md's Naming rules: (a) named for what it means to the
physicist-user, never the backend/mechanism; (b) unambiguous and precise; (c) math variables
symbolic, storage/functions descriptive; (d) one concept, one name, across the whole surface.

---

## 1. `tracer_scheme` / `particle_scheme` swap the very axis decision 51 assigns them

- **Type:** other (naming-convention violation)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - ARCHITECTURE.md decision log (2026-08, "Particle is the category, tracer the kind"): "Anything true of the whole deferred ladder of §7 takes particle — ... interpolation at positions; only what is specific to the massless ... kind takes tracer — the `Tracers` type and its construction... `advect!` stays generic ... its `EndpointHeun` method carrying the tracer-specific assumption."
  - `api / SimulationRun`: "`number_of_particles = 0`, `tracer_scheme = CatmullRom` — ... forwarded to the `Tracers` constructor as its `interpolation_scheme`." and "`particle_scheme = EndpointHeun()` — the temporal scheme ... a different axis from `tracer_scheme` despite the neighbouring names".
- **Contradicts:** Decision 51 makes "particle" the word for what generalizes across the whole probe ladder (explicitly interpolation — hence `interpolate_at_particles!`) and "tracer" the word for what is specific to the massless tracer kind (explicitly the temporal push, whose `EndpointHeun` carries "the tracer-specific assumption that the particle velocity is the fluid velocity"). The front-door keywords invert this: the ladder-general interpolation axis is named `tracer_scheme`, and the kind-specific temporal-integration axis is named `particle_scheme` — backwards relative to the rule the package itself states.
- **Description:** This is not a cosmetic near-collision — the docstring's own hedge ("despite the neighbouring names") shows the tension is known but unresolved. Per decision 51's own test, the interpolation-scheme keyword should read `particle_scheme` (it is `interpolate_at_particles!`, true of the whole ladder) and the temporal-integrator keyword should carry the tracer-specific flavor. Today it is exactly reversed.
- **Resolution hint:** Rename the front-door keywords to track decision 51: e.g. `particle_scheme` for interpolation (or keep `interpolation_scheme` verbatim, avoiding both loaded words) and a tracer-flavored name (`tracer_integrator`?) for the temporal scheme.

---

## 2. `Linear` claims an identity `ConstantPower` shares — the sibling literally calls itself "a linear forcing" too

- **Type:** other (imprecise / non-exclusive name)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `api / Forcing`, `Linear` docstring: "Linear (negative-damping) forcing `f = A·field`..."
  - `api / Forcing`, `ConstantPower` docstring: "Constant-injection-rate forcing... **a banded linear forcing** `f = A·field`... like `Linear`, it preserves a solenoidal velocity."
  - ARCHITECTURE §4.4: "`Linear` (fixed-rate negative damping...) and `ConstantPower` (its rate reset each step...) — **the two linear forcings folded into 𝓔**".
- **Contradicts:** `ConstantPower`'s own docstring names itself "a banded linear forcing," and ARCHITECTURE calls both `Linear` and `ConstantPower` "the two linear forcings." Yet only one type is bare-named `Linear` in the export list, alongside `NoForcing`, `BandRescaling`, `ConstantPower` — the other three all read as forcing-specific from the name alone.
- **Description:** A reader scanning the exported `AbstractForcing` family sees `Linear` and reasonably reads it as *the* linear forcing (also the bare word collides with "linear" used pervasively elsewhere for the general concept — a linear rate, "linear in the field"). It is really the fixed-rate member of a two-member linear-forcing family the docs name explicitly; `ConstantPower` is the other, dynamically-rate-adjusted member, but its name gives no hint it belongs to the same family.
- **Resolution hint:** A name distinguishing the two by what's fixed — e.g. `FixedRate` / `ConstantPower`, or `LinearDamping` — would be precise without claiming sole ownership of "linear."

---

## 3. `peak_wavenumber` promises a spectrum peak the code does not deliver

- **Type:** other (name promises an outcome the call cannot deliver)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `api / State`, `random_solenoidal_velocity_spectral!`: "the shell-summed energy spectrum ∝ κ²exp(−2κ²/κp²) **peaks at κp/√2, not at κp itself**."
  - `api / SimulationRun`, `Simulation`: "`peak_wavenumber = 2.0` — the large-scale envelope wavenumber κ_p of the initial condition ... (each shell-summed spectrum **peaks at κ_p/√2**)."
- **Contradicts:** The keyword's own name asserts it is where the spectrum peaks; three separate docstrings (velocity IC, scalar IC, and the front-door keyword) must each independently caveat that the actual measured (shell-summed) peak sits at a different wavenumber, κ_p/√2 ≈ 0.71 κ_p.
- **Description:** This is the textbook "name promises an outcome one call cannot deliver" pattern the hat is built to catch. The value genuinely fixes the Gaussian *envelope's* characteristic wavenumber (which the docs elsewhere correctly call "the large-scale envelope wavenumber") — that is the precise, deliverable meaning; "peak" is the imprecise one, and needing to correct it in every docstring that mentions it is the tell.
- **Resolution hint:** `envelope_wavenumber` (already used in prose) states exactly what the code delivers.

---

## 4. `k_max_η` spells the wavenumber magnitude with the letter the package reserves for kinetic energy

- **Type:** other (notation/naming collision)
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - `notation` page, "Wavenumber clash": "italic scalar $k$ is **the turbulent kinetic energy**... kept distinct" from $\boldsymbol\kappa$/$\kappa$.
  - `api / SimulationRun`: "`k_max_η = 2` — the resolution criterion $\kappa_{\max}\eta$ ... (**the keyword spells $\kappa_{\max}$ in ASCII**)."
- **Contradicts:** The notation page's own house rule keeps $k$ (kinetic energy) and $\kappa$ (wavenumber) deliberately distinct glyphs — "kept distinct" is the literal wording — yet the keyword `k_max_η` uses ASCII `k` to stand for $\kappa_{\max}$, the exact collision the glyph table exists to prevent, in an identifier that sits right beside `kinetic_energy` in the same constructor's keyword list.
- **Description:** The docstring's own aside ("spells κ_max in ASCII") shows the author noticed the transliteration is not self-evident, but the chosen ASCII stand-in reuses the one letter the package's own notation table says never to reuse for wavenumber.
- **Resolution hint:** `kappa_max_eta` (or `resolution_criterion`) avoids the collision the current spelling walks into.

---

## 5. `target` names two different physical *kinds* of quantity across sibling forcings

- **Type:** other (ambiguous shared keyword)
- **Severity:** minor
- **Confidence:** high
- **Locations:**
  - `api / Forcing`, `BandRescaling`: "The `target` is a number: **the value the held observable is to keep**" (an amplitude — kinetic energy or scalar variance).
  - `api / Forcing`, `ConstantPower`: "`target` is a number: the value of the **dissipation rate** to hold... **Note what kind of quantity that is: here the held observable is a rate, where `BandRescaling` holds an amplitude.**"
- **Contradicts:** Same keyword name, same `AbstractForcing` family, two different physical kinds (an amplitude vs. a rate) — the second docstring's explicit warning is itself evidence the ambiguity is real and known, not resolved by a naming distinction.
- **Description:** Rule (b) asks for precision, not merely internal consistency of use; `target` alone does not tell a reader which kind of quantity is meant without opening the specific type's docstring.
- **Resolution hint:** e.g. `target_amplitude` / `target_rate`, or leave `target` but only where a rate is meant and rename `BandRescaling`'s to `target_value`/`target_amplitude`.

---

## 6. `Tracers.trajectory_velocity` (singular) stores what `particle_velocities` (plural) reads

- **Type:** other (grammatical-number drift across an f/accessor pair)
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `api / Particles`, `Tracers` Fields: "`trajectory_velocity` — the interpolated velocity at the positions the tracers occupy... the observables cache's particle-velocities slot."
  - `api / Cache`: "`particle_velocities` — the checked read of the ... particle-velocities slot."
- **Contradicts:** One underlying `(M, 3)` array of per-tracer velocity samples is named with the singular "velocity" as the `Tracers` struct field but with the plural "velocities" as the cache accessor and slot name that reads the identical storage (decision 42 explicitly wires the slot IS the register).
- **Description:** Minor, but it is exactly the kind of one-concept-two-names drift rule (d) flags — a reader moving from `Tracers` internals to the cache accessor meets a different grammatical number for the same array.
- **Resolution hint:** Either `trajectory_velocities` on `Tracers`, or accept the asymmetry is deliberate (field = "the trajectory's velocity value," slot = "the particles' velocities") and say so once in a docstring note.

---

## 7. `Li2008(; constant = 0.9)` names its one parameter with the least specific word available

- **Type:** other (approximate cover word instead of the precise name)
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `api / phenomenology / Scalings`, `Li2008`: "The `constant` is the group value $G$ (default `0.9`)".
  - Compare sibling laws in the same module: `Sreenivasan1995(; C_K = 1.5)`, `Sreenivasan1998(; asymptote, correction)`.
- **Description:** Every scaling law in the module is a "constant" in the loose sense — that's the module's whole subject — so naming one law's single field literally `constant` fails the precision test relative to its siblings, which each name their coefficient for what it specifically is ($C_K$, the plateau, the correction). A reader skimming a `Reference`/provenance table sees `constant` and has to open the docstring to learn it means $G$.
- **Resolution hint:** `G` (matching the rendered symbol used throughout the same docstring) or `box_normalized_constant`.

---

## 8. `stationary_dissipation`'s `energy` argument breaks with the package-wide `kinetic_energy` name for the same quantity

- **Type:** other (one concept, two names)
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `api / phenomenology / Scalings`: "`stationary_dissipation(law, energy, side_length)` ... from the turbulent kinetic energy `energy` ($k$)".
  - Everywhere else on the public surface the identical quantity is named `kinetic_energy` — the `Observables.kinetic_energy` function, and the `Simulation(; kinetic_energy = 1.5, ...)` keyword.
- **Description:** `energy` alone is imprecise (potential vs. kinetic, total vs. per-mass) exactly where the rest of the package is careful to say `kinetic_energy`; this is a small but clean instance of rule (d)'s "one concept, one name" not holding across a module boundary (DNS surface vs. `Phenomenology`).
- **Resolution hint:** Rename the argument `kinetic_energy` to match its only other spelling in the package.

---

## 9. `finalize!` borrows a software-engineering term where the physics is a specific, nameable action

- **Type:** other (software-engineering term where a physics/mathematics word is exact)
- **Severity:** minor
- **Confidence:** medium
- **Locations:**
  - `api / Generator`: "`finalize!` — close a step: apply the post-step forcing projections to the advanced state."
  - ARCHITECTURE decision log: "`finalize!` on the generator is a recorded deviation from the solver-library precedent (the SciML/PETSc/SUNDIALS right-hand-side objects are pure evaluators, with post-step action in callback layers)".
- **Description:** "Finalize" is standard OOP/RAII vocabulary (a finalizer/destructor releasing a resource), not a physics term, and the decision log itself flags that this verb's meaning here — apply a forcing's post-step projection or rescale — deviates from what a reader coming from the solver-library tradition (which the log cites by name) would expect from "finalize." The prepare!/finalize! bracketing metaphor is intuitive, but the specific action (a forcing projection) has a more exact physics-facing name available.
- **Resolution hint:** Something in the family of `apply_forcing_projections!` (mirroring `finalize!`'s own summary sentence) would read correctly to a physicist without the SWE overtone; if `prepare!`/`finalize!` symmetry is judged more valuable, at least the docstring already carries the needed caveat, so this is a low-cost, low-urgency rename.

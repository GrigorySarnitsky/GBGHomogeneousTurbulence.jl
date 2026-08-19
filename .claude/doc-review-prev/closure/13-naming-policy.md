# Closure — 13-naming-policy

## 1. `deposit!` claimed by Cache's own module map, owned by Propagator
**VERDICT: ABSENT**
`src/Cache.jl:21-24` now attributes `deposit!` inline in the same bullet: "The field slots are
filled by [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!), which `Propagator` owns
because it needs the scheme's scratch to recover the fields." No separate contradictory bullet
listing it as a Cache operation remains; `deposit_sample!` is now the only op the bullet calls "the
one writer this module owns." Rendered build (`docs/build/api/Cache/index.html`) reflects the source.

## 2. `FlowConditions` / `FlowParameters` near-homonyms
**VERDICT: PRESENT**
Both names unchanged. `src/Generator.jl:52-63`: `FlowConditions` docstring still carries the "Not
to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names" disclaimer.
`src/Phenomenology.jl:68-71`: `FlowParameters` still "the analogue of `FlowConditions`...". The
disambiguation-by-footnote pattern the finding flags is still exactly in place.

## 3. Assembled RHS is `N̂` in `velocity_rhs!`/`scalar_rhs!` but `nonlinear` in `add_forcing_source!`
**VERDICT: ABSENT**
`src/Forcing.jl:191-198`: signature is now `add_forcing_source!(forcing, N̂, domain) -> N̂`, docstring
reads "Add the strategy `forcing`'s additive source to the assembled right-hand side `N̂`". Parameter
renamed from `nonlinear` to `N̂`, matching `velocity_rhs!`/`scalar_rhs!` and the notation.md glossary
binding for ``\widehat{\boldsymbol N}``.

## 4. `Simulation`'s two particle-tracking fields split vocabulary (trajectory vs particle)
**VERDICT: PRESENT**
Unchanged. `src/SimulationRun.jl:210,225-226`: fields still `trajectory_scheme` and
`particle_buffers`. `src/Particles.jl:175,215`: types still `AbstractParticleIntegrator` and
`ParticleIntegratorBuffers` ("particle" head noun). The "trajectory" vs "particle" split the finding
flags is intact.

## 5. `Linear` bare forcing name
**VERDICT: PRESENT**
Unchanged. `src/Forcing.jl:35,54,331,346`: strategy is still exported and documented as plain
`Linear`, next to `NoForcing`, `BandRescaling`, `ConstantPower`.

## 6. `EnergySpectrum` / `ScalarSpectrum` name velocity/scalar pair on different axes
**VERDICT: PRESENT**
Unchanged. `src/phenomenology/Spectra.jl:41-46,395-401`: abstract types still `EnergySpectrum` (by
quantity) and `ScalarSpectrum` (by field) — the asymmetric pair the finding flags.

## 7. `velocity_predictor` vs `velocity_predictor_spectral` invert word order
**VERDICT: PRESENT**
Unchanged. `src/Particles.jl:208-209,218`: field still `velocity_predictor`, docstring now
explicitly says "the particle-side counterpart of the field schemes' `velocity_predictor_spectral`"
— cross-referenced but not renamed. `src/Propagator.jl:109,121`: field still
`velocity_predictor_spectral`. The order inversion persists.

## 8. `record_particle_velocities!` (singular) writes `particle_velocities` (plural)
**VERDICT: PRESENT**
Unchanged. `src/Particles.jl:230,251`: mutator still named `record_particle_velocities!` (singular),
still fills the plural `tracers.particle_velocities` slot (`src/Particles.jl:133,252`).

## 9. IC-shaping keyword is `spectrum` at seeder, `initial_spectrum` at front door
**VERDICT: PRESENT**
Unchanged. `src/State.jl:67,145`: seeder keyword still `spectrum = nothing`.
`src/SimulationRun.jl:162,247`: `Simulation` keyword still `initial_spectrum`. `State.jl:81` now
explicitly cross-references ("front door forwards its `initial_spectrum` keyword here") but the two
names still differ.

## 10. `truncate_to_band!` name reads as complete dealiasing; under `PhaseShift` it's half
**VERDICT: PRESENT**
Unchanged. `src/SimulationDomain.jl:378`: function still named `truncate_to_band!`. The caveat is
now a titled admonition (`src/SimulationDomain.jl:372-376`, "This verb truncates; under PhaseShift
that is half the dealiasing") but the name itself — the defect the finding identifies — is
unchanged and still needs the caveat to correct the reader's expectation.

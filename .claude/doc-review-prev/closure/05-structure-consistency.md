# Closure audit — hat: 05-structure-consistency

One verdict per banked finding, adjudicated against the current corpus only (no fix-pass artifacts consulted).

---

## Finding 1 — Three different shapes for "enumerate each constructor argument"
**VERDICT: PARTIAL**

Evidence: All four originally-named locations now converge on one shape — a `# Arguments` heading
followed by an "All keyword[, all required]:" line and a bulleted list: `FixedDomain`
(`src/SimulationDomain.jl:145-146`), `Simulation` (`src/SimulationRun.jl:123-126`),
`StationarityCriterion` (`src/SimulationRun.jl:548-549`, now headed and bulleted where it previously
had no heading), `FlowConditions` (`src/Generator.jl:60-61`, now headed and bulleted where it
previously had none). No `# Keywords` heading remains anywhere in `src/*.jl`.

surviving_class: The same class (prose-only keyword explanation, no `# Arguments` heading, no
bulleted enumeration) is alive elsewhere: `Tracers(domain; number_of_particles, interpolation_scheme,
rng)` (`src/Particles.jl:47-67`, pure prose, no heading/bullets), `ObservablesCache(domain; scalar,
particle_velocities)` (`src/Cache.jl:65-83`, pure prose), `ResolvedGenerator` (`src/Generator.jl:175-181`,
pure prose: "Build it on the `FixedDomain` `domain` from the `conditions`; pass `scalar = true`...").

---

## Finding 2 — Named-method citation placement: front-loaded vs. deferred
**VERDICT: ABSENT**

Evidence: All three previously-deferred instances now front-load. `HouLi` (`src/SimulationDomain.jl:64-65`):
"The smooth spectral filter of Hou & Li (2007) — ..." is now the opening clause (was the closing
sentence). `Lundgren2002` (`src/phenomenology/StructureFunctions.jl:175`): "Lundgren's (2002)
finite-Reynolds-number correction..." opens the identity sentence. `ObukhovCorrsin1949`
(`src/phenomenology/Spectra.jl:383`): "The Obukhov–Corrsin inertial-convective scalar spectrum" opens
the docstring; the dual-eponym sentence is now mid-body, not the final sentence. Grep for `"is due
to"` / `"The name is a"` across `src/**/*.jl` returns only the one mid-body `ObukhovCorrsin1949`
instance, no closing-sentence deferrals.

---

## Finding 3 — Module-docstring "map" bullet order does not track the page's physical section order
**VERDICT: ABSENT**

Evidence: `Cache` module docstring (`src/Cache.jl:9-47`) now orders `ObservablesCache`,
`fields_modified!`/`particles_modified!`, `velocity_physical`/`vorticity_physical`/`scalar_physical`,
`max_speed`, `particle_velocities` — matching `docs/src/api/Cache.md`'s section order (`## The
observables cache` then `## The checked reads`) exactly; the modify-announcer verbs are now second,
not last. `Particles` module docstring (`src/Particles.jl:16-30`) now orders `Tracers`,
`particle_positions`/`number_of_particles`, `AbstractParticleIntegrator`/`EndpointHeun`,
`record_trajectory_velocity!`, `advect!`, `interpolate_at_particles!` — matching
`docs/src/api/Particles.md`'s four `##` subsections in order; the readouts are now second, not last.

---

## Finding 4 — Two documented, page-headed operations absent from their own module's contents map
**VERDICT: ABSENT**

Evidence: `Forcing` module docstring (`src/Forcing.jl:25-27`) now names and `@ref`-links
`DeferredForcing`: "A fifth name is not a hook: [`DeferredForcing`](@ref) is the operator-free keyword
form of a strategy..." — reachable and explained, not merely a trailing unlinked sentence.
`phenomenology/Scalings` module docstring (`src/phenomenology/Scalings.jl:11-13`) now bullets
`stationary_dissipation` explicitly: "- [`stationary_dissipation`](@ref) — the dissipation a
stationary run sustains, predicted from its energy and box side." Both operations the page documents
under their own `##` subsections are now named in their module's map.

---

## Finding 5 — "The plain constructor … takes the field(s) directly" preamble: present on some `Fields` sections, absent on most
**VERDICT: PARTIAL**

Evidence: `FlowConditions` (`src/Generator.jl:68-69`) and every `phenomenology/Spectra.jl` /
`StructureFunctions.jl` / `Scalings.jl` type named in the original "Absent" list (`PopeLargeScale`,
`PopeDissipation`, `VonKarmanLarge`, `PaoDissipation`, `ExponentialDissipation`,
`ObukhovCorrsin1949`, `ModelSpectrum`, `Kolmogorov1941`, `Kolmogorov1962`, `Sreenivasan1998`,
`Sreenivasan1995`, `Li2008`) now carry the "The plain constructor `X(...)` takes the N field(s)
directly" sentence.

surviving_class: `ObservablesCache` (`src/Cache.jl:97`, straight into bullets, no preamble),
`DeferredForcing` (`src/Forcing.jl:111`, straight into bullets), `ResolvedGenerator`
(`src/Generator.jl:181`, straight into bullets), `Tracers` (`src/Particles.jl:104`, straight into
bullets), `ParticleIntegratorBuffers` (`src/Particles.jl:191`, straight into bullets), `Simulation`
(`src/SimulationRun.jl:185`, straight into bullets) all still omit the preamble sentence — the two most
central front-door types (`Simulation`, `ObservablesCache`) are still in the omitted set, exactly as
the original finding flagged.

---

## Finding 6 — `StationarityCriterion`'s two field-like lists enumerate different, mismatched sets
**VERDICT: PRESENT**

Evidence: `src/SimulationRun.jl:548-577`. The `# Arguments` bullets are still `gate_scalar`,
`gate_skewness`, `min_turnovers`, `window_turnovers`, `tol`, `skew_floor`, `max_turnovers` (7 items);
the `# Fields` bullets are still `monitor`, `max_turnovers`, `gate_scalar`, `elapsed_turn`,
`last_time`, `started` (6 items) — only `gate_scalar`/`max_turnovers` name-match, unchanged from the
banked finding. A new explanatory sentence was added ("Note the keyword arguments above do not map
one-to-one onto these fields... stored inside `monitor`"), so the mismatch is no longer silent, but
the structural shape the finding contrasts against the corpus's 1:1-correspondence convention
(verified still true for `FlowConditions`, `src/Generator.jl:60-72`) is unchanged.

---

## Finding 7 — `IntegratorBuffers` is the only `Fields` section broken into sub-headings
**VERDICT: ABSENT**

Evidence: `src/Propagator.jl:89-99` now presents `IntegratorBuffers`'s `# Fields` as one flat bulleted
list (`stage1`, `nonlinear`, `stage2`/`velocity_star_spectral`, `scalar`) with no "Shared —" /
"Scheme-specific —" / "Nested:" sub-headings. `rg -n "Shared —|Scheme-specific|^Nested:" src/*.jl`
returns no matches anywhere in the corpus.

---

## Finding 8 — `Phenomenology`'s standing in the "Components" map differs between Home and `api`
**VERDICT: ABSENT**

Evidence: `docs/src/api.md:19` now gives `Phenomenology` its own top-level bullet — "- [Phenomenology]
(phenomenology.md): the reference turbulence laws — model spectra, structure-function laws, and
scaling constants — to validate a run against. A separate, opt-in group..." — a peer of the other nine
module bullets, no longer folded into `SimulationRun`'s bullet. `docs/src/index.md:114` carries the
matching peer bullet. Both pages now agree.

---

## Finding 9 — `dissipation`'s multi-signature explanation uses a bulleted "routes" list
**VERDICT: ABSENT**

Evidence: `src/Observables.jl:85-91` now reads as inline prose: "Two routes reach the same rate; take
the one whose input is already in hand. The first form measures from a vorticity field... The second
measures straight from the velocity..." — no bulleted list of call forms remains; the shape now
matches the sibling multi-signature functions the finding cites as the norm.

---

## Finding 10 — `Examples` heading used on some complex constructors, absent from others
**VERDICT: ABSENT**

Evidence: `# Examples` headings now appear on all three types the finding names as missing:
`Tracers` (`src/Particles.jl:69`), `FlowParameters` (`src/Phenomenology.jl:95`), and `FixedDomain`
(`src/SimulationDomain.jl:159`) — in addition to `Simulation` (`src/SimulationRun.jl:170`), `run!`
(`src/SimulationRun.jl:413`), and `warmup!` (`src/SimulationRun.jl:634`). The heading has grown from 2
to 6 uses, covering every constructor the finding named as an inconsistent omission.

---

## Finding 11 — `Scalings` module docstring embeds full formulas in two of its three per-law bullets
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Scalings.jl:1-15` now reads: "- [`Sreenivasan1998`](@ref) — the
normalized dissipation constant ``C_\varepsilon`` (``L_{11}`` the longitudinal integral scale), a
high-Reynolds-number plateau..." and "- [`Li2008`](@ref) — the box-normalized dissipation group
``G``..." — both bullets now name only the symbol, with no embedded formula (`C_ε = εL₁₁/u'³` and the
`k/(Lε)^{2/3}` expression are both gone from the module-docstring bullets), matching the
formula-free convention the finding cites everywhere else.

---

## Finding 12 — `FlowConditions` skips the argument-bullet step other >2-argument constructors use
**VERDICT: ABSENT**

Evidence: `src/Generator.jl:60-65`. `FlowConditions` now carries "# Arguments\nAll keyword, all
required:" followed by a four-item bulleted list (`viscosity`, `schmidt`, `velocity_forcing`,
`scalar_forcing`) — the pure-prose-only, zero-bullets shape the finding flagged as unique to this type
no longer exists.

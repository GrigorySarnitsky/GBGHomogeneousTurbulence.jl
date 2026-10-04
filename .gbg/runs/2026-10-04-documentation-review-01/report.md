# Documentation Review — 2026-10-04-documentation-review-01

!!! info "Written by AI, not regularly reviewed"
    This page is written by AI and is not reviewed regularly by a human.

Run `2026-10-04-documentation-review-01` of `GBGHomogeneousTurbulence`, by GBGCodingTools dev, from commit `f2ee28d9`.

It ran to the end. It launched 40 agent(s), with the bound readers, and made 1 of 1 fix pass(es). 46 line(s) went to the work queue, under the heading the end-of-turn hook does not count.

| Stage | Pass | Agents | Cache write | Cache read | Input | Output |
|---|---|---|---|---|---|---|
| find | 0 | 18 | 1421273 | 20571880 | 270 | 52461 |
| verify | 1 | 22 | 1185366 | 6655827 | 238 | 14409 |

Tokens, summed from each agent's transcript by `gbg run cost`.

## Not judged — 1

No reader of this package was given what these need. Nothing below says anything about them.

- RULE.DOC.COORD_FREE needs a differential_geometry reader and GBGHomogeneousTurbulence declares none, so nobody judges it

## Findings — 93

### 2026-10-04-documentation-review-01-001  The field reductions kinetic_energy, scalar_variance, max_speed and the vorticity form of dissipation also reduce over a point set (GBGPeriodicFields point values, e.g. the velocity sampled at the tracers), but their docstrings document only the grid base (physical or spectral representation).

Rule: `RULE.DOC.COVERAGE_BASES`.  
Reported by `full`, decided by an agent.

The four methods are untyped and forward to PF's inner / maximum, which accept ReducibleSection = Union{AbstractFieldPhysical, AbstractPointValues}. Ran: kinetic_energy(VectorPointValues(rand(5,3))) == sum(abs2, data)/5/2 (0.3688 both); scalar_variance(ScalarPointValues(...)), max_speed(VectorPointValues(...)), dissipation(VectorPointValues(...), 0.1) all return numbers (the mean over tracers, the max over tracers).

**Fix.** State the point-set base where each operation is documented (the sample mean over the M tracers, the maximum over tracers, e.g. kinetic_energy of new_vector_point_values filled by interpolate_at_particles!), or restrict the methods to grid fields if the point base is not meant to be supported.

- `src/Observables.jl`:70  (kinetic_energy)
- `src/Observables.jl`:324  (scalar_variance)
- `src/Observables.jl`:251  (max_speed)
- `src/Observables.jl`:106  (dissipation)
- pass 1: verifier `FIXED`  (commit `ee8fe971`)

### 2026-10-04-documentation-review-01-002  Several surfaces still describe the steady linear forcing rate as a stored array/field that prepare! 'arms' each step; the code builds it once as a lazy radial kernel stored nowhere and prepare! never touches it. One page also says every field-proportional forcing folds its rate into the exponential, which is false for ConstantPower and VarianceController.

Rule: `RULE.DOC.VERIFIED`.  
Reported by `full`, decided by an agent.

Forcing.steady_linear_rate(::Linear) returns radial_kernel(κ² -> ifelse(...), domain.multipliers); ResolvedGenerator stores it once at construction; Generator.prepare! docstring: 'The steady per-mode linear forcing rates are not touched here: they were fixed once, when the generator was built.' Linear docstring: 'the rate is a radial kernel on the same edges, so neither is stored.' ConstantPower and VarianceController (f = A field) go through add_forcing_source!.

**Fix.** Rewrite each site to the current mechanism: the rate is fixed once at generator construction as a lazy radial kernel (or, for a non-radial rate, a stored scalar field), passed as the integrating factor's offset; only a steady rate takes that route.

- `docs/ARCHITECTURE.md`:335  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:306  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:332  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:768  (Architecture / 7. Deliberately deferred)
- `docs/src/observables_cache.md`:288  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `docs/src/observables_cache.md`:289  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `src/Propagator.jl`:104  (IntegratorBuffers)
- pass 1: verifier `FIXED`  (commit `bb7a787d`)

### 2026-10-04-documentation-review-01-003  Prose claims that the code (or the same page) contradicts: StochasticOU's process is said to be advanced on the host; the hook lifecycle is listed with steady_linear_rate as a per-step hook called after prepare_forcing!; ResolvedFields' positional form is said to leave modeled empty; HouLi's materialized storage is given in MiB at MB values; validation.md counts three (and 'both') published files while listing six.

Rule: `RULE.DOC.VERIFIED`.  
Reported by `full`, decided by an agent.

StochasticOU: only randn! runs on a host array, then adapt! moves it to the companion grid built with array_type = domain.storage_family, and combine!/to_spectral!/helmholtz_projection! run there. steady_linear_rate is called once in ResolvedGenerator's constructor, before any prepare_forcing!. ResolvedFields(velocity_spectral, scalar_spectral, modeled) sets modeled from its third argument (read_state uses it). HouLi: 65·128²·16 B = 16.25 MiB (17.0 MB); 129·256²·16 B = 129 MiB (135 MB). validation.md's curl block lists six .h5 files with six hashes.

**Fix.** Say the draw is made on the host and the process advanced on the run's backend; list steady_linear_rate as the build-time hook (not per step, not after prepare_forcing!); say the keyword form leaves modeled empty and the positional form takes it; give ≈16 / ≈129 MiB (or MB units); give the actual file count.

- `docs/ARCHITECTURE.md`:424  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `docs/ARCHITECTURE.md`:384  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `src/Forcing.jl`:124  (AbstractForcing)
- `src/State.jl`:80  (ResolvedFields)
- `src/SimulationDomain.jl`:101  (HouLi)
- `docs/src/validation.md`:218  (Validation — code-to-code comparison against TurTLE / Reproducing the comparison)
- `docs/src/validation.md`:5  (Validation — code-to-code comparison against TurTLE)
- pass 1: verifier `FIXED`  (commit `56dd914a`)

### 2026-10-04-documentation-review-01-004  The notation page reserves κ_max for the resolved-band edge and κ_max^ret for the retained edge, but some docstrings write bare κ_max for the retained edge, and others introduce synonyms (κ_max^res, κ_eff) for the resolved edge.

Rule: `RULE.DOC.ONE_NOTATION`.  
Reported by `full`, decided by an agent.

notation.md rows: κ_max^ret 'retained-band edge ... prices the advective-CFL step'; κ_max 'resolved-band edge ... equals the retained edge for the sharp strategies, 4/5 of Nyquist for HouLi'. kinetic_energy's alias condition and recommended_cfl's 1/κ_max scaling are about the retained band (HouLi 'out to the Nyquist'), where retained ≠ resolved.

**Fix.** Write κ_max^ret where the retained edge is meant (alias condition, CFL scaling); use bare κ_max, not κ_max^res or κ_eff, for the resolved edge.

- `src/Observables.jl`:76  (kinetic_energy)
- `src/Propagator.jl`:887  (recommended_cfl)
- `src/SimulationDomain.jl`:424  (max_resolved_wavenumber)
- `docs/src/validation.md`:39  (Validation — code-to-code comparison against TurTLE / The physics point)

### 2026-10-04-documentation-review-01-005  Symbols and terms the notation page binds are reused for another concept or replaced by a synonym: τ also names the autocorrelation lag; N also counts registers; f also names the Nyquist fraction; the tracer position is written x instead of X; the injection rate is both ε_inj and ε_target on one page; and 'iteration' is defined as 'a step plus the deposit', not the vocabulary row's timestep choice + step + deposit + tracer push.

Rule: `RULE.DOC.ONE_NOTATION`.  
Reported by `full`, decided by an agent.

notation.md: τ = eddy-turnover time (and RK substep, already flagged as a double use); N = grid points per side; f = body forcing; X(t) = tracer position, 'capitalised, to keep it distinct from the Eulerian coordinate x'; ε_target = the injection rate a ConstantPower holds; Vocabulary 'iteration' includes the tracer push and is 'wider than a step'.

**Fix.** Use a fresh glyph for the lag (e.g. s or Δ), for the register count and for the fraction (f_res, as max_resolved_wavenumber does); write X for tracer positions; use ε_target throughout; define iteration only by reference to the vocabulary row.

- `docs/src/validation.md`:118  (Validation — code-to-code comparison against TurTLE / Results / Lagrangian velocity autocorrelation, ``\rho_u(\tau)``)
- `src/Propagator.jl`:264  (IFLowStorageRK3)
- `src/SimulationRun.jl`:134  (Simulation)
- `docs/ARCHITECTURE.md`:486  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/src/validation.md`:31  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:148  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `src/State.jl`:69  (ResolvedFields)
- `src/Observables.jl`:257  (max_speed)
- `docs/src/validation.md`:123  (Validation — code-to-code comparison against TurTLE / Results / Lagrangian velocity autocorrelation, ``\rho_u(\tau)``)
- `docs/ARCHITECTURE.md`:466  (Architecture / 4. Modules / 4.5 `Propagator` — the map that advances the state in time)
- `docs/ARCHITECTURE.md`:487  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/ARCHITECTURE.md`:753  (Architecture / 7. Deliberately deferred)
- `docs/ARCHITECTURE.md`:754  (Architecture / 7. Deliberately deferred)
- `docs/src/notation.md`:19  (Notation / Conventions)
- `docs/src/notation.md`:20  (Notation / Conventions)
- `docs/src/notation.md`:40  (Notation / Physical variables)
- `docs/src/notation.md`:41  (Notation / Physical variables)
- `docs/src/notation.md`:113  (Notation / Numerics)
- `docs/src/observables_cache.md`:101  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:366  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:391  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/src/observables_cache.md`:392  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `src/Forcing.jl`:1122  (StochasticOU)
- `src/Forcing.jl`:1228  (StochasticOUState)
- `src/Observables.jl`:250  (max_speed)
- `src/Observables.jl`:497  (integral_scale)
- `src/Propagator.jl`:862  (recommended_cfl)
- pass 1: verifier `LINE_ONLY`  (commit `1c1b4a89`)

### 2026-10-04-documentation-review-01-006  The per-scheme update formulas of the particle schemes Heun and AdamsBashforth are homed in the generic advect! docstring, and the scheme docstrings defer to it. The rule puts per-scheme specifics in the scheme's own docstring, and the field side does that: IFLowStorageRK3/IFHeun/IFSSPRK3 carry their own formulas, step! none.

Rule: `RULE.DOC.ONE_HOME`.  
Reported by `full`, decided by an agent.

Heun: 'the formula is given with advect!'; AdamsBashforth: 'the update formula is given with advect!'; advect! carries both display formulas ('Under Heun ...', 'Under AdamsBashforth ...'). step! carries no scheme formula; each AbstractIntegrator docstring carries its own.

**Fix.** Move the Heun display formula into Heun's docstring and the Adams–Bashforth update into AdamsBashforth's, and have advect! link to the scheme docstrings as step! does.

- `src/Particles.jl`:314  (Heun)
- `src/Particles.jl`:435  (AdamsBashforth)
- `src/Particles.jl`:662  (advect!)

### 2026-10-04-documentation-review-01-007  Three module maps break the identity → one-linked-line-per-family → remark form: the umbrella module docstring has no contents list at all; SimulationRun's map omits the exported predicted_stationary_state; Forcing's map introduces its list as 'four hook methods ... called in the order listed', but the list holds fifteen entries (types, strategies, helpers), and its order is not the call order.

Rule: `RULE.DOC.MODULE_MAP`.  
Reported by `full`, decided by an agent.

SimulationRun exports predicted_stationary_state and it is not among the map's entries. Forcing's list: AbstractForcing, initial_forcing_state, prepare_forcing!, steady_linear_rate, add_forcing_source!, project_forcing!, NoForcing, Linear, ConstantPower, VarianceController, VarianceRescaling, StochasticOU, kinetic_energy_in_box_units/band_energy_fraction, DeferredForcing, write/read_forcing. The umbrella docstring is prose with links only to write_simulation/read_simulation.

**Fix.** Give the umbrella a linked one-liner per submodule; add predicted_stationary_state to SimulationRun's map; reword Forcing's lead to introduce the whole list, and keep the hook order claim out of the map.

- `src/GBGHomogeneousTurbulence.jl`:37  (GBGHomogeneousTurbulence)
- `src/SimulationRun.jl`:36  (SimulationRun)
- `src/Forcing.jl`:36  (Forcing)
- pass 1: verifier `FIXED`  (commit `eed75b46`)

### 2026-10-04-documentation-review-01-008  Citation form is broken on two surfaces. validation.md names all four authors of Lalescu et al. (2022) in the text, where four or more authors should be written 'First et al.'. Five inline docstring references are cut off mid-entry ('**1*'), so the volume markup is unclosed and the pages are missing. ARCHITECTURE §References has those pages.

Rule: `RULE.CIT.STYLE`.  
Reported by `full`, decided by an agent.

§References lists Lalescu, Bramas, Rampp & Wilczek (4 authors). The docstring copies end at a line break: Betchov '*J. Fluid Mech.* **1*' vs §References '**1**(5), 497–504'; Sullivan '**6*' vs '**6**(4), 1612–1614'; Nosé '**81*' vs '**81**(1), 511–519'; Hoover '**31*' vs '**31**(3), 1695–1697'; Lalescu 2010 '**229*' vs '**229**(17), 5862–5869'.

**Fix.** Write 'Lalescu et al. (2022)' in validation.md; restore each truncated inline entry to its full §References form on one line.

- `docs/src/validation.md`:9  (Validation — code-to-code comparison against TurTLE)
- `src/Observables.jl`:415  (derivative_skewness)
- `src/Forcing.jl`:529  (VarianceRescaling)
- `src/Forcing.jl`:784  (VarianceController)
- `src/Forcing.jl`:786  (VarianceController)
- `src/Particles.jl`:483  (AdamsBashforth)
- `docs/ARCHITECTURE.md`:3230  (Architecture / References)
- `docs/ARCHITECTURE.md`:3254  (Architecture / References)
- `docs/ARCHITECTURE.md`:3259  (Architecture / References)
- `docs/ARCHITECTURE.md`:3269  (Architecture / References)
- `src/Forcing.jl`:785  (VarianceController)
- `docs/ARCHITECTURE.md`:3261  (Architecture / References)
- `docs/ARCHITECTURE.md`:3248  (Architecture / References)
- pass 1: verifier `FIXED`  (commit `3a831bee`)

### 2026-10-04-documentation-review-01-009  Some home docstrings are out of the identity → when-to-use → arguments → formula → citation → caveats order. Tracers opens with an implementation remark (keyword dispatch) before its identity sentence. dissipation puts its when-to-use guidance after # Arguments. VarianceController places the thermostat-analogy rationale and its inline citations ahead of # Arguments.

Rule: `RULE.DOC.HOME_ORDER`.  
Reported by `full`, decided by an agent.

Tracers line 1 of the docstring body is the parenthetical about one method / keywords not dispatching, and the identity 'A set of Lagrangian tracers' follows. dissipation: '# Arguments' list, then 'Two routes reach the same rate; take the one whose input is already in hand.' VarianceController: Berendsen et al. 1984 / Nosé 1984 / Hoover 1985 discussion precedes '# Arguments'. That discussion is design rationale, which HOME_ORDER excludes.

**Fix.** Lead Tracers with its identity and move the dispatch remark to a # comment; move dissipation's route guidance above # Arguments; move VarianceController's thermostat analogy to ARCHITECTURE (or after the arguments as a citation-backed note).

- `src/Particles.jl`:66  (Tracers)
- `src/Observables.jl`:112  (dissipation)
- `src/Forcing.jl`:740  (VarianceController)
- pass 1: verifier `LINE_ONLY`  (commit `4dd1dabe`)

### 2026-10-04-documentation-review-01-010  Operations take result-changing arguments as keywords: the seeders' target energy/variance and envelope, the timestep of advance!/run!/warmup!, the forcing and state inputs of predicted_stationary_state, the Reynolds number of the two stationary-state helpers, and allocate_buffers' scalar flag. No Switch on RULE.API.POSITIONAL is declared in .gbg/config.jl.

Rule: `RULE.API.POSITIONAL`.  
Reported by `full`, decided by an agent.

Each keyword changes the value returned or the state produced (kinetic_energy rescales û; dt sets the step; reynolds_box/reynolds_taylor select the evaluation point; scalar = true changes the buffers built). The owner chose the reynolds_box / reynolds_taylor keywords on 2026-09-29, but the rule only allows an exception through a Switch with its reason, and switches.md lists only RULE.GIT.MANIFEST_TRACKED.

**Fix.** Make these arguments positional, or declare a Switch for RULE.API.POSITIONAL in .gbg/config.jl naming the operations and the reason (e.g. the owner's keyword ruling for the stationary-state helpers).

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/State.jl`:148  (random_solenoidal_velocity_spectral!)
- `src/State.jl`:250  (random_scalar_spectral!)
- `src/SimulationRun.jl`:1038  (advance!)
- `src/SimulationRun.jl`:1269  (run!)
- `src/SimulationRun.jl`:434  (predicted_stationary_state)
- `src/Forcing.jl`:940  (kinetic_energy_in_box_units)
- `src/Propagator.jl`:153  (allocate_buffers)
- `src/Forcing.jl`:970  (kinetic_energy_in_box_units)

### 2026-10-04-documentation-review-01-011  Docstring example code blocks carry lines of 90-102 columns (long trailing comments, or a constructor call left on one line) that overflow the docstring's code box and render with a horizontal scrollbar.

Rule: `RULE.TEX.NO_HSCROLL`.  
Reported by `rendered`, decided by an agent.

Built pages: theme gives a docstring <pre> about 88 columns (52rem column, .875rem monospace, .75rem section padding). Measured line lengths: Forcing DeferredForcing example 99 and 93; Particles Tracers example 102, 92, 90; SimulationDomain FixedDomain example 92; SimulationRun Simulation example 97 and 90, run! example 94, warmup! example 96.

**Fix.** Hand-wrap: move trailing comments onto their own line above the statement, and break the long keyword calls with a hanging indent under the first argument.

- `src/Forcing.jl`:211  (DeferredForcing)
- `src/Forcing.jl`:214  (DeferredForcing)
- `src/Particles.jl`:110  (Tracers)
- `src/Particles.jl`:125  (Tracers)
- `src/Particles.jl`:109  (Tracers)
- `src/SimulationDomain.jl`:232  (FixedDomain)
- `src/SimulationRun.jl`:321  (Simulation)
- `src/SimulationRun.jl`:330  (Simulation)
- `src/SimulationRun.jl`:1306  (run!)
- `src/SimulationRun.jl`:1573  (warmup!)
- `docs/src/observables_cache.md`:428  (The observables cache / 3. The code / 3.1 The calls)
- `docs/src/observables_cache.md`:429  (The observables cache / 3. The code / 3.1 The calls)
- pass 1: verifier `FIXED`  (commit `ee06458e`)

### 2026-10-04-documentation-review-01-012  The validation page's download block renders 106-107-column lines: the release URL on one line and each file name padded to a column before its 64-hex SHA-256, so the block scrolls horizontally.

Rule: `RULE.TEX.NO_HSCROLL`.  
Reported by `rendered`, decided by an agent.

Built validation/index.html <pre>: base=... line is 107 columns; six '# <file>  <sha256>' lines are 106 columns each, against roughly 91 columns available on a page-level code block.

**Fix.** Split the URL across two shell variables (owner/repo and release tag), and put each hash on its own line under its file name, or drop the alignment padding.

- `docs/src/validation.md`:221  (Validation — code-to-code comparison against TurTLE / Reproducing the comparison)
- `docs/src/validation.md`:229  (Validation — code-to-code comparison against TurTLE / Reproducing the comparison)
- `docs/src/validation.md`:234  (Validation — code-to-code comparison against TurTLE / Reproducing the comparison)
- pass 1: verifier `FIXED`  (commit `00ea4dfb`)

### 2026-10-04-documentation-review-01-013  The page uses several of the package's own terms that it never defines and never links. A reader new to the package cannot tell what they mean: 'extraction-bound leaf', 'include order', 'band edges' (and how 'retained' differs from 'resolved'), the generator's 'fixed set of verbs', 'deposited' observables, and a 'fused pair'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api`, decided by an agent.

Each term appears in the intro or in a submodule entry with no defining clause before it and no link to a definition. 'Deposited' appears in the SimulationRun entry, before the Cache entry explains it with 'leaves the observables it produced'. The retained and resolved band edges are named side by side, and nothing says what separates them.

**Fix.** Define each term in a clause where it is first used, or replace it with plain words. For example: 'a self-contained module designed to be split out into its own package', 'two cutoff wavenumbers: the highest mode kept in storage and the highest mode free of aliasing', 'a fixed set of functions', 'the observables each step stores', 'computed together in one pass'.

- `docs/src/api.md`:5  (API overview)
- `docs/src/api.md`:13  (API overview)
- `docs/src/api.md`:18  (API overview)
- `docs/src/api.md`:12  (API overview)
- `docs/src/api.md`:15  (API overview)
- `docs/src/index.md`:116  (GBGHomogeneousTurbulence.jl / Components)
- pass 1: verifier `FIXED`  (commit `0400d839`)

### 2026-10-04-documentation-review-01-014  The page contradicts itself about what `using GBGHomogeneousTurbulence` brings into scope, and it never says how to reach the Phenomenology module. It states that the umbrella brings 'everything' into scope, but it also states that Phenomenology is not re-exported, and its only hint is 'reach it opt-in'.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api`, decided by an agent.

The intro says Phenomenology 'is not re-exported (reach it opt-in)'. Two sentences later it says '`using GBGHomogeneousTurbulence` brings everything into scope'. The Phenomenology entry repeats 'opt-in' and 'not re-exported by the umbrella', and no sentence on the page shows the statement that loads it.

**Fix.** Change 'everything' to 'the public surface of the listed submodules'. State how to load Phenomenology once, for example by naming the `using` statement that brings it into scope.

- `docs/src/api.md`:9  (API overview)
- `docs/src/api.md`:6  (API overview)
- pass 1: verifier `NOT_FIXED`  (commit `517cab91`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-015  Some text on the page is written as fragments with no verb or as stacked noun phrases rather than sentences. 'A separate, opt-in group: …' has no main verb. 'reach it opt-in' uses an adjective where an adverb or a way of loading is needed. The Particles entry joins a noun phrase and a bare `advect!` clause with a semicolon, and that clause has no verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api`, decided by an agent.

'A separate, opt-in group: not re-exported by the umbrella, and designed to be extractable into a standalone package.' has no finite verb. 'today the massless `Tracers`; `advect!` under a selectable particle integration scheme (`Heun` default, `AdamsBashforth` available), and `interpolate_at_particles!` for…' lists items with no predicate.

**Fix.** Rewrite as sentences, for example: 'It is a separate, opt-in group: the umbrella does not re-export it, and it is designed to be extracted into a standalone package.' and 'Today it tracks massless `Tracers`: `advect!` moves them under a selectable integration scheme (`Heun` by default, or `AdamsBashforth`), and `interpolate_at_particles!` samples fields at their positions.'

- `docs/src/api.md`:21  (API overview)
- `docs/src/api.md`:20  (API overview)
- `docs/src/api.md`:6  (API overview)
- pass 1: verifier `FIXED`  (commit `ae43f9d1`)

### 2026-10-04-documentation-review-01-016  The module docstring uses the package terms 'epochs', 'deposit' and 'tracer push' in its opening list and contract paragraphs before it says what any of them is; epoch is defined only three paragraphs later, the push never on the module map.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Cache`, decided by an agent.

A cold reader meets 'epochs' and 'the next deposit' in the operations list; the sentence 'The cache keeps one epoch counter per dynamical factor' and 'The field slots are filled by deposit!' come after. 'Push' is never glossed on the page as the tracer advance by advect!.

**Fix.** Define epoch and deposit in the module docstring's identity paragraph (or reorder so the epoch paragraph precedes the list), and gloss the push as the tracer advance at first use.

- `src/Cache.jl`:18  (Cache)
- `src/Cache.jl`:21  (Cache)
- `src/Cache.jl`:35  (Cache)
- pass 1: verifier `NOT_FIXED`  (commit `3a75d277`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-017  Several package-internal nouns are used and never defined anywhere on the page: 'point-value section', 'stage recoveries', 'the clock', 'the statistics', 'sanctioned push', 'history-keeping announcement'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Cache`, decided by an agent.

None of these nouns is glossed in a clause or linked to a definition; each assumes the reader knows the module's internals (what a section is, what a stage recovery is, which clock, which statistics).

**Fix.** Replace each with plain words (an M-by-3 array of point values; the intermediate physical-space fields of each stage; the run's step counter; the caller's statistics) or link a definition.

- `src/Cache.jl`:98  (ObservablesCache)
- `src/Cache.jl`:120  (ObservablesCache)
- `src/Cache.jl`:47  (Cache)
- `src/Cache.jl`:267  (velocity_at_particles)
- `src/Cache.jl`:403  (particles_modified!)
- `docs/ARCHITECTURE.md`:2234  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2737  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3197  (Architecture / 11. Decision log)
- pass 1: verifier `NOT_FIXED`  (commit `5447e195`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-018  Symbols are used without a plain-language binding at first use: $t_n$ and $\boldsymbol{X}$ in both docstrings that write the particle velocity, and $M$ in the ObservablesCache docstring.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Cache`, decided by an agent.

Neither docstring says that $\boldsymbol{X}$ is the tracer position or that $t_n$ is the current time instant; in ObservablesCache $M$ is never tied to number_of_particles (velocity_at_particles binds M, but only later and in another docstring).

**Fix.** Bind each at first use: 'at the tracer positions $\boldsymbol{X}$ at the current time $t_n$', and '$M$ = number_of_particles'.

- `src/Cache.jl`:76  (ObservablesCache)
- `src/Cache.jl`:99  (ObservablesCache)
- `src/Cache.jl`:265  (velocity_at_particles)
- `docs/ARCHITECTURE.md`:235  (Architecture / 4. Modules / 4.1 `State` and `SimulationDomain` — the field and the frame it lives on)
- `docs/ARCHITECTURE.md`:493  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/ARCHITECTURE.md`:1692  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2231  (Architecture / 11. Decision log)
- `docs/src/notation.md`:42  (Notation / Physical variables)
- `docs/src/observables_cache.md`:335  (The observables cache / 2. The system / 2.3 Transforms and arrays)
- `docs/src/observables_cache.md`:364  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:400  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/ARCHITECTURE.md`:2234  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2737  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3197  (Architecture / 11. Decision log)
- pass 1: verifier `NOT_FIXED`  (commit `408e699b`)

### 2026-10-04-documentation-review-01-019  A verbless noun phrase serves as a label before a colon, and an appositive hangs off a clause it does not describe.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Cache`, decided by an agent.

'The checked read of ... slot:' has no verb (a label-colon tag); 'a history-keeping announcement' is in apposition to 'the particles epoch' grammatically, but is meant to describe the push.

**Fix.** 'This is the checked read of ... slot: it serves ...'; 'advect! moves the particles epoch itself, and, unlike this verb, its announcement keeps the history: the push extends it.'

- `src/Cache.jl`:268  (velocity_at_particles)
- `src/Cache.jl`:404  (particles_modified!)
- pass 1: verifier `NOT_FIXED`  (commit `4eeecd12`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-020  Several identity lines and section introductions are verbless noun-phrase fragments rather than sentences: a type identity, two section intros and the persistence intro have no main verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Forcing`, decided by an agent.

Each quoted line ends without a finite verb: 'A forcing named before its domain exists.' uses only a participle; 'Supertype of ... strategies — ...' and 'A strategy's HDF5 persistence — ...' are noun phrases; the section intros 'The operator-free deferred form a strategy's constructor returns, materialized ...' and 'The method that starts ..., then the four methods ...' likewise.

**Fix.** Give each a subject and verb, e.g. 'A DeferredForcing is a forcing named before its domain exists.'; 'This section documents the deferred form ...'.

- `src/Forcing.jl`:168  (DeferredForcing)
- `src/Forcing.jl`:121  (AbstractForcing)
- `docs/src/api/Forcing.md`:49  (Forcing / Deferred forcing)
- `docs/src/api/Forcing.md`:58  (Forcing / Forcing methods)
- `docs/src/api/Forcing.md`:73  (Forcing / Persistence)
- `docs/src/api/Forcing.md`:39  (Forcing / The stationary-state model)
- `docs/ARCHITECTURE.md`:44  (Architecture / 1. Identity)
- `docs/ARCHITECTURE.md`:46  (Architecture / 1. Identity)
- `docs/ARCHITECTURE.md`:436  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `docs/ARCHITECTURE.md`:549  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:890  (Architecture / 9. Invariants — the deliberate absences)
- `docs/ARCHITECTURE.md`:3104  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3108  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3113  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3148  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3151  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3153  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3159  (Architecture / 11. Decision log)
- `docs/src/notation.md`:21  (Notation / Conventions)
- `docs/src/notation.md`:98  (Notation / Derived scales)
- `src/Forcing.jl`:57  (Forcing)
- `src/Forcing.jl`:761  (VarianceController)
- `src/Forcing.jl`:943  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:947  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:948  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:1004  (band_energy_fraction)
- `src/Forcing.jl`:1005  (band_energy_fraction)
- `src/Observables.jl`:540  (reynolds_box)
- `src/Observables.jl`:576  (reynolds_taylor)
- `src/SimulationRun.jl`:117  (Simulation)
- `src/SimulationRun.jl`:133  (Simulation)
- `src/SimulationRun.jl`:151  (Simulation)
- `src/SimulationRun.jl`:200  (Simulation)
- `src/SimulationRun.jl`:342  (Simulation)
- `src/SimulationRun.jl`:349  (Simulation)
- `src/SimulationRun.jl`:444  (predicted_stationary_state)
- `src/SimulationRun.jl`:467  (predicted_stationary_state)
- pass 1: verifier `FIXED`  (commit `0184e094`)

### 2026-10-04-documentation-review-01-021  Symbols appear in formulas before the page binds them: VarianceController's display formula uses k_infinity, G and t_ell, which are bound only later in its Arguments list; Linear uses k_band in its rate formula without saying what it is (first defined later, in ConstantPower and band_energy_fraction).

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Forcing`, decided by an agent.

Line order in the page: the VarianceController display formula 'G[k(t) - k_\infty]/t_\ell' comes before '`target` — the whole-field variance $k_\infty$', '`gain = 1` — the dimensionless gain $G$' and the turnover_time entry. Linear's 'A = \varepsilon/(2 k_{\mathrm{band}})' is the page's first k_band and is not glossed there.

**Fix.** Bind k_infinity, G and t_ell in a clause right after the display formula; in Linear say 'with k_band the kinetic energy held in the forced band'.

- `src/Forcing.jl`:720  (VarianceController)
- `src/Forcing.jl`:604  (Linear)

### 2026-10-04-documentation-review-01-022  The page uses package terms of art without defining them in a clause or linking them: 'operator-free' (form/constructors), a 'lazy' band-pass kernel, a 'radial kernel', 'the scalar binding', 'the balance is not anchored', and 'predicted state' (predicted_stationary_state is linked only in the DeferredForcing docstring, much later on the page).

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Forcing`, decided by an agent.

A cold reader cannot tell what 'operator-free' excludes (the domain? the transform plans?), what makes a kernel 'lazy' or 'radial' here, what 'the scalar binding' is, or what 'anchored' means for the balance. 'Predicted state' is used in Linear and VarianceController before the page links what produces it.

**Fix.** Define each once where first used, e.g. 'operator-free (built without a FixedDomain)'; 'lazy (evaluated per mode on the fly, never stored)'; replace 'the scalar binding' with 'FlowConditions, when given it as a scalar_forcing'; link predicted_stationary_state at first use.

- `src/Forcing.jl`:58  (Forcing)
- `src/Forcing.jl`:612  (Linear)
- `src/Forcing.jl`:791  (VarianceController)
- `src/Forcing.jl`:605  (Linear)
- `src/Forcing.jl`:260  (steady_linear_rate)
- `docs/ARCHITECTURE.md`:1478  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1507  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1508  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1514  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1530  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1532  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1537  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1542  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1584  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1589  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2142  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2150  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3177  (Architecture / 11. Decision log)
- `docs/src/observables_cache.md`:285  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `docs/src/validation.md`:71  (Validation — code-to-code comparison against TurTLE / The shared initial state, and the import witnesses)
- pass 1: verifier `FIXED`  (commit `b7612b27`)

### 2026-10-04-documentation-review-01-023  Three reference entries render broken: the volume number's bold markup is never closed, so the journal volume and pages are cut off and a stray '**' or '*' shows instead of the full reference.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Forcing`, decided by an agent.

The rendered text stops at 'J. Chem. Phys. **81*' and 'Phys. Rev. A **31*' and 'Phys. Fluids **6*', unlike the neighbouring entries that read e.g. 'Phys. Fluids 28, 035114.'

**Fix.** Fix the bold markup on the volume number in these §References entries (or drop the bold, as the other entries do) so the volume and pages render.

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/Forcing.jl`:785  (VarianceController)
- `src/Forcing.jl`:786  (VarianceController)
- `src/Forcing.jl`:529  (VarianceRescaling)

### 2026-10-04-documentation-review-01-024  The package's term 'field sampling' is used without saying where the field is sampled; a cold reader cannot tell whether it means sampling at the Lagrangian particle positions, at fixed probes, or on sub-grids, and the follow-up 'the values sampled from it' does not resolve it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-GBGHomogeneousTurbulence`, decided by an agent.

Nothing on the page binds what is sampled or at which points; the sentence that follows refers back to 'the values sampled from it' without saying where.

**Fix.** Say where: 'with Lagrangian particle tracking and sampling of the fields along the particle trajectories.'

- `docs/src/api/GBGHomogeneousTurbulence.md`  — **the text here has moved and was not found again**
- pass 1: verifier `NOT_FIXED`  (commit `7660ef3d`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-025  Several package terms of art are used without a defining clause or link on this page; a cold reader cannot tell what they mean: the 'deposit' at which the iteration closes, the observables cache with its 'vorticity slot' and 'velocity slot', 'assembly scratch', and 'stage hooks'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Generator`, decided by an agent.

Nothing on the page says what 'the deposit' is or when it happens. 'Observables cache' and its 'slots' are named in the ResolvedGenerator docstring, but neither is defined or linked there. 'Assembly scratch' gets its first gloss only in the ResolvedGenerator docstring, after the module map has used it.

**Fix.** Define each term in a clause at its first use (e.g. 'the deposit, where the step's observables are written to the cache'), or @ref-link it to its definition.

- `src/Generator.jl`:28  (Generator)
- `src/Generator.jl`:245  (ResolvedGenerator)
- `src/Generator.jl`:21  (Generator)
- `src/Generator.jl`:295  (ResolvedGenerator)
- `docs/ARCHITECTURE.md`:1734  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2088  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2925  (Architecture / 11. Decision log)
- `docs/src/notation.md`:35  (Notation / Physical variables)
- `docs/src/observables_cache.md`:310  (The observables cache / 2. The system / 2.3 Transforms and arrays)
- `docs/src/observables_cache.md`:369  (The observables cache / 2. The system / 2.4 What it caches)
- pass 1: verifier `NOT_FIXED`  (commit `4a13bfde`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-026  'Displaced' fields, buffers and evaluation, and the 'mask strategy', are used before the page explains them. The half-cell-shifted grid is first explained in the velocity_rhs! body. 'Mask strategy' appears in an argument entry before the sentence that names TwoThirds and HouLi as its members.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Generator`, decided by an agent.

The gloss 'from the fields recovered on a grid displaced by half a cell' appears only further down, in the velocity_rhs! body. 'A mask strategy ([`TwoThirds`], [`HouLi`])' likewise appears only after the argument list.

**Fix.** Gloss 'displaced' (evaluated on the grid shifted by half a cell) at its first use in the module map. Gloss 'mask strategy' at its first use in the argument entry.

- `src/Generator.jl`:30  (Generator)
- `src/Generator.jl`:239  (ResolvedGenerator)
- `src/Generator.jl`:437  (velocity_rhs!)
- pass 1: verifier `FIXED`  (commit `c76d0a6d`)

### 2026-10-04-documentation-review-01-027  Some symbols are used without being bound: $N$ in the resident $N^{3}$ cost, the bold forcing $\boldsymbol{f}$ in the momentum equation, and $L$ (and $u'$) in the Reynolds-number formula. The text calls $L$ only 'the shipped' value and never says which length it is.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Generator`, decided by an agent.

Nowhere on the page is N said to be the grid points per axis, f the forcing per unit mass, or L the box side.

**Fix.** Bind each symbol in a clause at its first use: 'N the grid points per axis', 'f the forcing', 'L the box side'.

- `src/Generator.jl`:485  (velocity_rhs!)
- `docs/ARCHITECTURE.md`:283  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `src/Generator.jl`:54  (FlowConditions)
- `docs/ARCHITECTURE.md`:268  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/src/notation.md`:52  (Notation / Parameters)
- `docs/ARCHITECTURE.md`:269  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:1076  (Architecture / 11. Decision log)
- `docs/src/validation.md`:28  (Validation — code-to-code comparison against TurTLE / The physics point)
- pass 1: verifier `NOT_FIXED`  (commit `20f79154`)

### 2026-10-04-documentation-review-01-028  Several identity and section-intro sentences have no main verb. They are noun phrases followed by a dash or comma.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Generator`, decided by an agent.

Read aloud, none of these is a sentence. 'X as Y' and 'X — list' carry no finite main verb.

**Fix.** Give each one a subject and a verb, e.g. 'Holds the flow's generator as one value a scheme can hold' or 'Returns the parameters of the velocity's exact linear subflow over a substep τ'.

- `src/Generator.jl`:237  (ResolvedGenerator)
- `src/Generator.jl`:550  (velocity_integrating_factor)
- `src/Generator.jl`:583  (scalar_integrating_factor)
- `docs/src/api/Generator.md`:19  (Generator / The generator as one value)
- `docs/src/api/Generator.md`:10  (Generator / Flow conditions)
- `src/Generator.jl`:14  (Generator)
- `docs/src/api/Generator.md`:28  (Generator / The generator protocol)
- pass 1: verifier `NOT_FIXED`  (commit `37ca02d4`) — the verifier said LINE_ONLY, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-029  In the FlowConditions docstring, one sentence opens with a bare participle and has no subject. It reads as an imperative to the reader, not as a statement about the type.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Generator`, decided by an agent.

The intended reading is 'The conditions are read through …', but the subject is missing.

**Fix.** Write 'A scheme reads the conditions through the ResolvedGenerator it is handed; step! never holds them itself.'

- `src/Generator.jl`:64  (FlowConditions)
- pass 1: verifier `FIXED`  (commit `4378f3f2`)

### 2026-10-04-documentation-review-01-030  The cache vocabulary (generic 'homed' here, deposit, closing deposit, iteration, cached read, the state) is used as if known; no sentence on this page says what the cache is, what a deposit is, or when it is current.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

A cold reader meets 'deposit' and 'iteration' in the module map and max_speed with no definition; the max_speed parenthesis '(a step plus the deposit that closes it)' defines iteration by deposit, which is itself never defined.

**Fix.** Bind once in the module map: the run's observables cache holds values measured at the end of each step (the deposit); link Cache for the rest, and drop 'homed'.

- `src/Observables.jl`:20  (Observables)
- `src/Observables.jl`:255  (max_speed)
- `src/Observables.jl`:293  (vorticity_physical!)
- pass 1: verifier `FIXED`  (commit `e00d434c`)

### 2026-10-04-documentation-review-01-031  Package-internal implementation jargon stands unexplained in user-facing argument and method prose: 'lazy reduction weights', 'fused mapped mean', 'pure representation recovery', 'preservation copy', 'traversal'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

Nothing on the page says what a 'representation recovery' is or why it would need a 'preservation copy'; 'lazy reduction weights' names machinery, not physics.

**Fix.** Say what the reader needs (e.g. 'the domain supplies the |κ|² weights'; 'û is left unchanged'), or move the mechanism to a # comment.

- `src/Observables.jl`:167  (kinetic_energy_and_dissipation)
- `src/Observables.jl`:299  (vorticity_physical!)
- `src/Observables.jl`:388  (derivative_skewness)
- `docs/ARCHITECTURE.md`:363  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:1050  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1626  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3204  (Architecture / 11. Decision log)
- pass 1: verifier `NOT_FIXED`  (commit `2e4d7a7b`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-032  'Pricing' an aliasing residual or a CFL margin is a package idiom used without definition, as is 'per-strategy standing'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

A scientist reads 'priced' as cost; the intended sense (bounded/quantified) is never stated.

**Fix.** Replace with 'bounded' / 'accounted for', or define once.

- `src/Observables.jl`:47  (Observables)
- `src/Observables.jl`:396  (derivative_skewness)
- `src/Observables.jl`:263  (max_speed)
- pass 1: verifier `FIXED`  (commit `5b5a3560`)

### 2026-10-04-documentation-review-01-033  'Box units' and the symbols built on it are unbound: $\tilde{k}$ appears with no definition, $\tilde{\nu}$ is glossed only as 'the viscosity in box units', and 'box units' themselves (the scaling by L and ε) are never stated.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

The relation Re_λ = k̃√((20/3)Re_box) is uncheckable without k̃ = k/(εL)^{2/3}; the page never gives it.

**Fix.** Bind the box units once: lengths in L, velocities in (εL)^{1/3}, so ν̃ = ν/(ε^{1/3}L^{4/3}), k̃ = k/(εL)^{2/3}.

- `src/Observables.jl`:539  (reynolds_box)
- `src/Observables.jl`:539  (reynolds_box)
- `src/Observables.jl`:575  (reynolds_taylor)
- `docs/ARCHITECTURE.md`:44  (Architecture / 1. Identity)
- `docs/ARCHITECTURE.md`:46  (Architecture / 1. Identity)
- `docs/ARCHITECTURE.md`:436  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `docs/ARCHITECTURE.md`:549  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:890  (Architecture / 9. Invariants — the deliberate absences)
- `docs/ARCHITECTURE.md`:3104  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3108  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3113  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3148  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3151  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3153  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3159  (Architecture / 11. Decision log)
- `docs/src/api/Forcing.md`:39  (Forcing / The stationary-state model)
- `docs/src/notation.md`:21  (Notation / Conventions)
- `docs/src/notation.md`:98  (Notation / Derived scales)
- `src/Forcing.jl`:57  (Forcing)
- `src/Forcing.jl`:761  (VarianceController)
- `src/Forcing.jl`:943  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:947  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:948  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:1004  (band_energy_fraction)
- `src/Forcing.jl`:1005  (band_energy_fraction)
- `src/Observables.jl`:540  (reynolds_box)
- `src/Observables.jl`:576  (reynolds_taylor)
- `src/SimulationRun.jl`:117  (Simulation)
- `src/SimulationRun.jl`:133  (Simulation)
- `src/SimulationRun.jl`:151  (Simulation)
- `src/SimulationRun.jl`:200  (Simulation)
- `src/SimulationRun.jl`:342  (Simulation)
- `src/SimulationRun.jl`:349  (Simulation)
- `src/SimulationRun.jl`:444  (predicted_stationary_state)
- `src/SimulationRun.jl`:467  (predicted_stationary_state)
- `docs/ARCHITECTURE.md`:3115  (Architecture / 11. Decision log)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- pass 1: verifier `NOT_FIXED`  (commit `f85b4f80`)

### 2026-10-04-documentation-review-01-034  Symbols used in a docstring before (or without) being bound there: $\kappa_{\max}$, $N$ and $L$ in kinetic_energy's alias condition; $\kappa_{\max}\eta$ in reynolds_box; $L$ and $\kappa_n$ in energy_spectrum's shell width.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

κ_max (the retained cutoff wavenumber), N (grid points per side) and L (box side) are first bound only further down the page in a different docstring (kinetic_energy_and_dissipation_below_scale), if at all; κ_max is never bound.

**Fix.** Bind at first use: 'with N grid points per side of a box of side L and κ_max the largest retained wavenumber'.

- `src/Observables.jl`:75  (kinetic_energy)
- `src/Observables.jl`:541  (reynolds_box)
- `src/Observables.jl`:450  (energy_spectrum)
- `docs/ARCHITECTURE.md`:1089  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1101  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1928  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2498  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2676  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2960  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2963  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2968  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3001  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3158  (Architecture / 11. Decision log)
- `docs/src/api/SimulationDomain.md`:32  (SimulationDomain / Dealiasing strategies)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- `docs/src/notation.md`:117  (Notation / Numerics)
- `docs/src/notation.md`:153  (Notation / Vocabulary)
- `docs/src/validation.md`:38  (Validation — code-to-code comparison against TurTLE / The physics point)
- `src/SimulationDomain.jl`:561  (SimulationDomain)
- `docs/ARCHITECTURE.md`:3159  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1076  (Architecture / 11. Decision log)
- `docs/src/notation.md`:79  (Notation / Diagnostics)

### 2026-10-04-documentation-review-01-035  The page's section intros are verbless noun phrases rather than sentences.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Observables`, decided by an agent.

Six of the eight section intros (also 'The fastest flow speed on the grid, which sets the advective-CFL step — a reduction, not a physics invariant.') lack a main verb.

**Fix.** Give each a verb: 'This section measures the velocity kinetic energy and ...'.

- `docs/src/api/Observables.md`:10  (Observables / Energy and variance)
- `docs/src/api/Observables.md`:19  (Observables / Dissipation rates)
- `docs/src/api/Observables.md`:28  (Observables / The fused energy–dissipation pair)
- `docs/src/api/Observables.md`:55  (Observables / Derivative skewness)
- `docs/src/api/Observables.md`:82  (Observables / Spectrum and length scale)
- `docs/ARCHITECTURE.md`:44  (Architecture / 1. Identity)
- `docs/ARCHITECTURE.md`:91  (Architecture / 2. Running a simulation)
- `docs/ARCHITECTURE.md`:351  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:353  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:370  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:433  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `docs/ARCHITECTURE.md`:437  (Architecture / 4. Modules / 4.4 `Forcing` — the source)
- `docs/ARCHITECTURE.md`:560  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:561  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:563  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:625  (Architecture / 4. Modules / 4.8 `Phenomenology` — the reference laws (extraction-bound))
- `docs/ARCHITECTURE.md`:631  (Architecture / 4. Modules / 4.8 `Phenomenology` — the reference laws (extraction-bound))
- `docs/ARCHITECTURE.md`:639  (Architecture / 4. Modules / 4.8 `Phenomenology` — the reference laws (extraction-bound))
- `docs/ARCHITECTURE.md`:802  (Architecture / 7. Deliberately deferred)
- `docs/ARCHITECTURE.md`:889  (Architecture / 9. Invariants — the deliberate absences)
- `docs/ARCHITECTURE.md`:890  (Architecture / 9. Invariants — the deliberate absences)
- `docs/ARCHITECTURE.md`:937  (Architecture / 10. Conventions)
- `docs/ARCHITECTURE.md`:959  (Architecture / 10. Conventions)
- `docs/ARCHITECTURE.md`:1015  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1016  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1034  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1070  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1088  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1293  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1494  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1719  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1722  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1777  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2039  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2042  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2075  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2109  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2110  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2114  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2152  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2161  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2398  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2407  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2423  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2684  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2686  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2695  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2705  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2961  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2970  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2981  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2985  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2990  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2993  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2994  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3000  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3001  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3003  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3018  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3019  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3105  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3108  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3110  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3113  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3115  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3116  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3140  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3141  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3147  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3160  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3161  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3164  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3168  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3169  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3266  (Architecture / References)
- `docs/src/api/Observables.md`:46  (Observables / Reynolds numbers)
- `docs/src/api/SimulationRun.md`:21  (SimulationRun / The predicted stationary state)
- `docs/src/notation.md`:19  (Notation / Conventions)
- `docs/src/notation.md`:21  (Notation / Conventions)
- `docs/src/notation.md`:76  (Notation / Diagnostics)
- `docs/src/notation.md`:80  (Notation / Diagnostics)
- `docs/src/notation.md`:82  (Notation / Diagnostics)
- `docs/src/notation.md`:84  (Notation / Diagnostics)
- `docs/src/notation.md`:94  (Notation / Derived scales)
- `docs/src/notation.md`:96  (Notation / Derived scales)
- `docs/src/notation.md`:97  (Notation / Derived scales)
- `docs/src/notation.md`:98  (Notation / Derived scales)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- `docs/src/notation.md`:101  (Notation / Derived scales)
- `docs/src/notation.md`:102  (Notation / Derived scales)
- `docs/src/notation.md`:103  (Notation / Derived scales)
- `docs/src/notation.md`:104  (Notation / Derived scales)
- `docs/src/notation.md`:127  (Notation / Forcing)
- `docs/src/observables_cache.md`:87  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:148  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:196  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:370  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:394  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/src/validation.md`:31  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:36  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:41  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:44  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:78  (Validation — code-to-code comparison against TurTLE / The shared initial state, and the import witnesses)
- `docs/src/validation.md`:85  (Validation — code-to-code comparison against TurTLE / Results / Energy and dissipation, ``k(t)`` and ``\varepsilon(t)``)
- `docs/src/validation.md`:93  (Validation — code-to-code comparison against TurTLE / Results / Energy and dissipation, ``k(t)`` and ``\varepsilon(t)``)
- `docs/src/validation.md`:148  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:167  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:173  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:193  (Validation — code-to-code comparison against TurTLE / Results / Robustness across integrators: `IFLowStorageRK4` at its adaptive step)
- `docs/src/validation.md`:198  (Validation — code-to-code comparison against TurTLE / Results / Robustness across integrators: `IFLowStorageRK4` at its adaptive step)
- `src/Forcing.jl`:188  (DeferredForcing)
- `src/Forcing.jl`:190  (DeferredForcing)
- `src/Forcing.jl`:193  (DeferredForcing)
- `src/Forcing.jl`:194  (DeferredForcing)
- `src/Forcing.jl`:195  (DeferredForcing)
- `src/Forcing.jl`:200  (DeferredForcing)
- `src/Forcing.jl`:604  (Linear)
- `src/Forcing.jl`:654  (ConstantPower)
- `src/Forcing.jl`:656  (ConstantPower)
- `src/Forcing.jl`:658  (ConstantPower)
- `src/Forcing.jl`:671  (ConstantPower)
- `src/Forcing.jl`:716  (VarianceController)
- `src/Forcing.jl`:720  (VarianceController)
- `src/Forcing.jl`:728  (VarianceController)
- `src/Forcing.jl`:757  (VarianceController)
- `src/Forcing.jl`:758  (VarianceController)
- `src/Forcing.jl`:761  (VarianceController)
- `src/Forcing.jl`:771  (VarianceController)
- `src/Forcing.jl`:943  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:944  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:945  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:946  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:947  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:948  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:955  (kinetic_energy_in_box_units)
- `src/Forcing.jl`:986  (band_energy_fraction)
- `src/Forcing.jl`:1001  (band_energy_fraction)
- `src/Forcing.jl`:1155  (StochasticOU)
- `src/Forcing.jl`:1156  (StochasticOU)
- `src/Forcing.jl`:1158  (StochasticOU)
- `src/Forcing.jl`:1159  (StochasticOU)
- `src/Observables.jl`:15  (Observables)
- `src/Observables.jl`:39  (Observables)
- `src/Observables.jl`:95  (dissipation)
- `src/Observables.jl`:151  (kinetic_energy_and_dissipation)
- `src/Observables.jl`:159  (kinetic_energy_and_dissipation)
- `src/Observables.jl`:187  (kinetic_energy_and_dissipation_below_scale)
- `src/Observables.jl`:197  (kinetic_energy_and_dissipation_below_scale)
- `src/Observables.jl`:204  (kinetic_energy_and_dissipation_below_scale)
- `src/Observables.jl`:206  (kinetic_energy_and_dissipation_below_scale)
- `src/Observables.jl`:221  (kinetic_energy_and_dissipation_below_scale)
- `src/Observables.jl`:333  (scalar_dissipation)
- `src/Observables.jl`:532  (reynolds_box)
- `src/Observables.jl`:536  (reynolds_box)
- `src/Observables.jl`:546  (reynolds_box)
- `src/Observables.jl`:568  (reynolds_taylor)
- `src/Observables.jl`:571  (reynolds_taylor)
- `src/Observables.jl`:580  (reynolds_taylor)
- `src/SimulationRun.jl`:111  (Simulation)
- `src/SimulationRun.jl`:117  (Simulation)
- `src/SimulationRun.jl`:125  (Simulation)
- `src/SimulationRun.jl`:129  (Simulation)
- `src/SimulationRun.jl`:134  (Simulation)
- `src/SimulationRun.jl`:136  (Simulation)
- `src/SimulationRun.jl`:150  (Simulation)
- `src/SimulationRun.jl`:152  (Simulation)
- `src/SimulationRun.jl`:163  (Simulation)
- `src/SimulationRun.jl`:165  (Simulation)
- `src/SimulationRun.jl`:198  (Simulation)
- `src/SimulationRun.jl`:218  (Simulation)
- `src/SimulationRun.jl`:238  (Simulation)
- `src/SimulationRun.jl`:341  (Simulation)
- `src/SimulationRun.jl`:351  (Simulation)
- `src/SimulationRun.jl`:439  (predicted_stationary_state)
- `src/SimulationRun.jl`:444  (predicted_stationary_state)
- `src/SimulationRun.jl`:446  (predicted_stationary_state)
- `src/SimulationRun.jl`:454  (predicted_stationary_state)
- `src/SimulationRun.jl`:458  (predicted_stationary_state)
- `src/SimulationRun.jl`:468  (predicted_stationary_state)
- `src/SimulationRun.jl`:899  (flow_parameters)
- `src/SimulationRun.jl`:901  (flow_parameters)
- `src/SimulationRun.jl`:1287  (run!)
- `src/SimulationRun.jl`:1428  (StationarityCriterion)
- `src/SimulationRun.jl`:1431  (StationarityCriterion)
- `src/SimulationRun.jl`:1432  (StationarityCriterion)
- `src/SimulationRun.jl`:1434  (StationarityCriterion)
- `src/SimulationRun.jl`:1435  (StationarityCriterion)
- `src/SimulationRun.jl`:1448  (StationarityCriterion)
- `src/SimulationRun.jl`:1474  (StationarityCriterion)
- pass 1: verifier `FIXED`  (commit `3b8284ab`)

### 2026-10-04-documentation-review-01-036  'The eddy-turnover clock' is used in the module map and a section intro before it is defined (it is first given as Δt ε/k only inside kinetic_energy_and_dissipation).

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

A reader of the module map does not know the clock is the accumulated Δt ε/k; 'normalizes the clock' is opaque.

**Fix.** Gloss at first use: 'the eddy-turnover clock (elapsed time in units of k/ε)'.

- `src/Observables.jl`:41  (Observables)
- `docs/src/api/Observables.md`:28  (Observables / The fused energy–dissipation pair)

### 2026-10-04-documentation-review-01-037  The module map names two forcing kinds by package-internal labels ('constant-energy forcing', 'fixed-injection forcing') and an unexplained 'truncating dealiasing band'/'sharp truncations' without saying which strategies they are.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

No forcing is linked or named on the page; the reader cannot map these labels to any type.

**Fix.** Link the forcing types meant, or describe them physically ('a forcing that holds k fixed', 'a forcing injecting a fixed power').

- `src/Observables.jl`:40  (Observables)
- pass 1: verifier `NOT_FIXED`  (commit `0d7e9931`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-038  The Betchov (1956) reference renders truncated with an unclosed bold marker, so the citation lacks its volume/pages and shows raw markup.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Observables`, decided by an agent.

The References entry of derivative_skewness ends at 'J. Fluid Mech. **1*', with no closing markup, volume, or pages.

**Fix.** Repair the reference markup so it reads 'J. Fluid Mech. **1**, 497–504.'

!!! warning "The code may be what is wrong"
    The reader believed the documentation and the code disagree, and that the code is the wrong half. That is a question for the owner, not a documentation fix.

- `src/Observables.jl`:415  (derivative_skewness)

### 2026-10-04-documentation-review-01-039  The page leans on the observables-cache vocabulary (deposit, closing deposit, slot, checked read, particles counter, reading stale, run layer, out-of-band reposition) without defining any of it; a cold reader cannot tell what a 'checked read' or a 'closing deposit' is, or what makes a sample 'stale'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Particles`, decided by an agent.

None of these nouns is defined in a clause on the page; the only gloss is the module map's one-line description of the particle deposit! method, which does not explain checked, stale, slot, counter or out-of-band.

**Fix.** Define the cache contract once on the page (a deposited value is served by a read that throws if the state changed since the deposit; a push or reposition marks it stale) or link the Cache page's definition at the first use of each term.

- `src/Particles.jl`:35  (Particles)
- `src/Particles.jl`:136  (Tracers)
- `src/Particles.jl`:677  (advect!)
- `src/Particles.jl`:695  (advect!)
- `src/Particles.jl`:698  (advect!)
- `docs/src/api/Particles.md`:97  (Particles / Wiring tracers into a run)
- pass 1: verifier `FIXED`  (commit `d1cff0f6`)

### 2026-10-04-documentation-review-01-040  Design-internal vocabulary leaks onto the user page: 'a fitness question', a field of another type (`velocity_predictor_spectral`) the page never shows, and 'the field library' used as a name for GBGPeriodicFields without ever being bound to it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Particles`, decided by an agent.

'fitness' is not a physics or numerics term and is not defined; `velocity_predictor_spectral` appears nowhere else on the page; 'the field library' is used in the examples and docstrings while the page only ever names `GBGPeriodicFields`.

**Fix.** Replace 'fitness question' with plain words (a trade the user chooses by measurement); drop or explain the velocity_predictor_spectral comparison; bind 'the field library' to GBGPeriodicFields at first use or say GBGPeriodicFields.

- `src/Particles.jl`:297  (AbstractParticleIntegrator)
- `src/Particles.jl`:382  (ParticleIntegratorBuffers)
- `src/Particles.jl`:204  (ParticleTraversal)
- pass 1: verifier `FIXED`  (commit `c6f0672e`)

### 2026-10-04-documentation-review-01-041  Several docstrings use symbols they never bind: the tracer count M (bound only inside the Tracers fields list, used bare in other docstrings), the box side L, the position X, the grid count N, and kappa_max eta in the Heun caveat.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Particles`, decided by an agent.

advect! writes positions as X and wraps into [0, L) without saying X is the tracer positions or L the box side; ParticleIntegratorBuffers and the point-value allocators use M with no binding in their own docstrings; Heun's caveat measures at N = 16-32 and N = 128 without saying N is grid points per axis, then asks to read N as kappa_max eta, neither bound.

**Fix.** Bind each at first use in its docstring: X the tracer positions, L the box side length, M the number of tracers, N the grid points per axis, kappa_max the largest resolved wavenumber and eta the Kolmogorov length.

- `src/Particles.jl`:674  (advect!)
- `src/Particles.jl`:379  (ParticleIntegratorBuffers)
- `src/Particles.jl`:798  (new_scalar_point_values)
- `src/Particles.jl`:322  (Heun)
- `src/Particles.jl`:328  (Heun)
- `src/Particles.jl`:764  (unwrapped_positions)
- `docs/ARCHITECTURE.md`:2201  (Architecture / 11. Decision log)

### 2026-10-04-documentation-review-01-042  Verbless fragments stand as sentences in running prose.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Particles`, decided by an agent.

Each quoted unit ends with a full stop or colon and has no finite verb; the Heun parenthetical strings noun phrases ('floor ... against time error ...') without a verb.

**Fix.** Give each a subject and verb: 'The module tracks Lagrangian particles; today it provides the massless tracer:', 'The one value has two consumers:', 'The family has two members today:', 'at N = 128 the floor is ... against a time error of ...'.

- `src/Particles.jl`:19  (Particles)
- `src/Particles.jl`:32  (Particles)
- `src/Particles.jl`:295  (AbstractParticleIntegrator)
- `src/Particles.jl`:323  (Heun)
- `src/Particles.jl`:319  (Heun)
- `src/Particles.jl`:324  (Heun)
- `src/Particles.jl`:469  (AdamsBashforth)
- pass 1: verifier `NOT_FIXED`  (commit `88ac5435`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-043  The second AdamsBashforth reference renders truncated with broken bold markup: the volume shows as '**229*' and the pages are missing, so the citation does not read complete.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Particles`, decided by an agent.

The rendered References entry stops at 'J. Comput. Phys. **229*' with a literal asterisk run and no page number, unlike the first entry, which renders volume and pages.

**Fix.** Close the bold markup on the volume and supply the pages, matching the first reference's form.

- `src/Particles.jl`:483  (AdamsBashforth)

### 2026-10-04-documentation-review-01-044  Section introductions and some docstring openings are verbless noun phrases, not sentences.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Propagator`, decided by an agent.

Each has no finite verb; the page heads three of its four sections with such a fragment.

**Fix.** Give each a subject and verb, e.g. 'This section documents one in-place step ... and the deposit that closes the iteration.'

- `docs/src/api/Propagator.md`:39  (Propagator / Time stepping)
- `docs/src/api/Propagator.md`:49  (Propagator / Timestep ceiling)
- `docs/src/api/Propagator.md`:26  (Propagator / Step scratch)
- `docs/src/api/Propagator.md`:10  (Propagator / Integrator schemes)
- `src/Propagator.jl`:24  (Propagator)
- `src/Propagator.jl`:454  (IFHeun)

### 2026-10-04-documentation-review-01-045  The IFLowStorageRK4 cost paragraph is one run-on sentence chained by dashes and a colon, starting as a fragment hanging off the display.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-Propagator`, decided by an agent.

The span from 'a factor 1.93' through 'as its docstring records' carries five clauses joined by dashes; 'at 5/3 the nonlinear evaluations' has no verb and the claim of 16% more time per compute is buried mid-run.

**Fix.** Rewrite as three or four sentences: the stability gain, the measured cost, the net gain, the accuracy consequence for tracers.

- `src/Propagator.jl`:303  (IFLowStorageRK4)
- `docs/ARCHITECTURE.md`:2559  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2571  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2904  (Architecture / 11. Decision log)
- `docs/src/notation.md`:119  (Notation / Numerics)
- `src/Propagator.jl`:236  (IFLowStorageRK3)
- `src/Propagator.jl`:566  (IFSSPRK3)
- `src/Propagator.jl`:878  (recommended_cfl)
- `src/Propagator.jl`:882  (recommended_cfl)
- pass 1: verifier `NOT_FIXED`  (commit `d11eafcc`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-046  Symbols N, L and kappa are used unbound, and N is bound to two different meanings on the same page.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

N is bound once as a register count, then reused unbound as grid points per axis; L (box side) is never named; kappa and kappa_max (wavenumber magnitude, largest retained wavenumber) are never bound on the page; widehat N additionally denotes the right-hand side.

**Fix.** Bind N as grid points per axis and L as box side at first grid use; write the 2N count without reusing N (or say 'Williamson's 2N-storage label'); bind kappa as wavenumber magnitude and kappa_max as the largest retained one.

- `src/Propagator.jl`:264  (IFLowStorageRK3)
- `src/Propagator.jl`:806  (deposit!)
- `src/Propagator.jl`:863  (recommended_cfl)
- `src/Propagator.jl`:595  (IFSSPRK3)
- `docs/ARCHITECTURE.md`:2234  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2737  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3197  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2476  (Architecture / 11. Decision log)
- pass 1: verifier `NOT_FIXED`  (commit `9a0d78ec`) — the verifier said LINE_ONLY, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-047  A sentence sends the reader to another docstring for a fact it needs.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

'as its docstring records' points outside the page instead of stating the fact in full.

**Fix.** Drop 'as its docstring records'; the claim itself already stands.

- `src/Propagator.jl`:309  (IFLowStorageRK4)
- pass 1: verifier `FIXED`  (commit `8eedd145`)

### 2026-10-04-documentation-review-01-048  Observables-cache vocabulary (epoch, slot, iteration, producer, dynamical factor, particles epoch, seeding deposit, out of band) is used before or without definition.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

'epoch' is first glossed ('the freshness counter') only in step!, after the map uses it; 'producer', 'dynamical factor', the 'particles epoch' as a second counter, 'seeding deposits' and 'out of band' are never defined; 'iteration' (step plus deposit) is only implied.

**Fix.** Define each in a clause at first use, or link the cache's docstring where it is defined (e.g. 'a producer — the step or the tracer push that makes an observable measurable').

- `src/Propagator.jl`:37  (Propagator)
- `src/Propagator.jl`:765  (deposit!)
- `src/Propagator.jl`:769  (deposit!)
- `src/Propagator.jl`:799  (deposit!)
- `src/Propagator.jl`:810  (deposit!)
- pass 1: verifier `FIXED`  (commit `bbb043cd`)

### 2026-10-04-documentation-review-01-049  'Register' and 'TurTLE' are used in the module map and section intro before the page defines them.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

'register' is defined only in IntegratorBuffers ('storage a scheme computes one stage into'); TurTLE is glossed only in the IFSSPRK3 docstring ('the reference pseudospectral solver').

**Fix.** Gloss at first use: 'two field-sized stage arrays (registers)', 'TurTLE, a reference pseudospectral DNS code'.

- `src/Propagator.jl`:31  (Propagator)
- `docs/src/api/Propagator.md`:11  (Propagator / Integrator schemes)
- pass 1: verifier `FIXED`  (commit `1cb43880`)

### 2026-10-04-documentation-review-01-050  Architecture nouns of the package are used as if known: 'the backend', 'the run layer', 'the generator protocol', 'post-step forcing'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

Which backend (the field library) is never named on first use; 'run layer', 'generator protocol' and the post-step/rate distinction of forcings are never defined on the page.

**Fix.** Name the backend package (with its link) at first use; replace 'the run layer' by 'Simulation / advance!'; list the protocol verbs or link them; say what makes a forcing post-step.

- `src/Propagator.jl`:244  (IFLowStorageRK3)
- `src/Propagator.jl`:158  (allocate_buffers)
- `src/Propagator.jl`:206  (step!)
- `src/Propagator.jl`:588  (IFSSPRK3)
- `src/Propagator.jl`:261  (IFLowStorageRK3)
- pass 1: verifier `FIXED`  (commit `0f4e5f5a`)

### 2026-10-04-documentation-review-01-051  Applying the integrating factor to the accumulator is called a 'rotation' without the term being introduced.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-Propagator`, decided by an agent.

The displayed update multiplies h by a real decaying exponential; nothing on the page says this is what 'rotation' means, and a numerical analyst would read rotation as a register swap or a phase rotation.

**Fix.** Say 'the accumulator's transport by the integrating factor' or define 'rotation' at its first use.

- `src/Propagator.jl`:257  (IFLowStorageRK3)
- `src/Propagator.jl`:591  (IFSSPRK3)
- pass 1: verifier `FIXED`  (commit `a7f6871c`)

### 2026-10-04-documentation-review-01-052  Verbless fragments stand as sentences: a label-colon list, a noun-phrase verdict, and a section lead-in that never reaches its verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-SimulationDomain`, decided by an agent.

Each sentence lacks a finite verb: 'Concrete strategies: X, Y, and Z.'; 'Exact dealiasing of ..., with ...'; 'The two band edges it sets — A and B.' (the only verb, 'sets', is inside a relative clause).

**Fix.** 'The concrete strategies are ...'; 'It dealiases the quadratic nonlinearity exactly, ...'; 'A strategy sets two band edges: ...'.

- `src/SimulationDomain.jl`:52  (DealiasingStrategy)
- `src/SimulationDomain.jl`:67  (TwoThirds)
- `docs/src/api/SimulationDomain.md`:30  (SimulationDomain / Dealiasing strategies)
- pass 1: verifier `FIXED`  (commit `3efc4fe8`)

### 2026-10-04-documentation-review-01-053  The PhaseShift identity sentence splices a report title and series number into its subject between dashes, so the sentence reads as 'Phase-shift dealiasing — ... Numerical experiments in homogeneous turbulence, NASA TM-81315 (no DOI): assemble ...' with no verb for its subject.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-SimulationDomain`, decided by an agent.

The second em dash, meant to close the parenthetical, instead opens the report title, which then runs into the colon and an imperative.

**Fix.** State the identity as a sentence ('Phase-shift dealiasing, after Patterson & Orszag (1971) with the spherical truncation of Rogallo (1981), assembles ...') and move the Rogallo report to the References section.

- `src/SimulationDomain.jl`:143  (PhaseShift)
- pass 1: verifier `FIXED`  (commit `e722eb90`)

### 2026-10-04-documentation-review-01-054  Package terms of art are used without definition on this page: 'the generator' (twice), 'the sharp strategies' (the page defined mask/shift families, and 'sharp' cuts across them: HouLi is a mask but not sharp, PhaseShift is a shift and sharp), 'pass', 'resident complex spectral scalar', 'the random-seed spectrum', 'the empty-shell warnings of the forcing layer'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-SimulationDomain`, decided by an agent.

A cold reader of this page alone has no referent for 'the generator', 'pass', 'spectral scalar' as a memory unit, 'random-seed spectrum' or 'forcing layer'; none is glossed or @ref-linked. 'Sharp strategies' is introduced only implicitly (TwoThirds and PhaseShift) and conflicts with the defined mask/shift split.

**Fix.** Gloss each in a clause or link it ('the Navier–Stokes right-hand-side assembly', 'every traversal of the spectral array', 'one complex array of one spectral-mode size', 'the sharp-cutoff strategies, TwoThirds and PhaseShift'), or link the generator / initial-condition / forcing objects.

- `docs/src/api/SimulationDomain.md`:57  (SimulationDomain / Band truncation)
- `docs/src/api/SimulationDomain.md`:33  (SimulationDomain / Dealiasing strategies)
- `src/SimulationDomain.jl`:101  (HouLi)
- `src/SimulationDomain.jl`:405  (max_retained_wavenumber)
- `src/SimulationDomain.jl`:527  (truncate_to_band!)
- `docs/ARCHITECTURE.md`:2543  (Architecture / 11. Decision log)
- `src/SimulationDomain.jl`:102  (HouLi)
- pass 1: verifier `LINE_ONLY`  (commit `cfdb825d`)

### 2026-10-04-documentation-review-01-055  Symbols are used without being bound: h_a and Δx_a in the PhaseShift caveat; η in the HouLi caveat and in the band-edge intro, before max_resolved_wavenumber binds it lower on the page; f in the unit_kernel field.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-SimulationDomain`, decided by an agent.

h_a (the displacement along axis a) and Δx_a (the grid spacing along axis a) appear nowhere else; η is first glossed as 'the Kolmogorov (dissipation) microscale' only in max_resolved_wavenumber, after two uses; f and the bracket ⟨·,·⟩ are not bound.

**Fix.** Bind h_a and Δx_a in the caveat ('a displacement h_a along axis a, with grid spacing Δx_a = L/N'); gloss η as the Kolmogorov microscale at its first use; say 'for a field f'.

- `src/SimulationDomain.jl`:167  (PhaseShift)
- `src/SimulationDomain.jl`:117  (HouLi)
- `docs/src/api/SimulationDomain.md`:32  (SimulationDomain / Dealiasing strategies)
- `src/SimulationDomain.jl`:264  (FixedDomain)
- `docs/ARCHITECTURE.md`:1089  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1101  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1928  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2498  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2676  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2960  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2963  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2968  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3001  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3158  (Architecture / 11. Decision log)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- `docs/src/notation.md`:117  (Notation / Numerics)
- `docs/src/notation.md`:153  (Notation / Vocabulary)
- `docs/src/validation.md`:38  (Validation — code-to-code comparison against TurTLE / The physics point)
- `src/SimulationDomain.jl`:561  (SimulationDomain)
- `docs/ARCHITECTURE.md`:1103  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1105  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1218  (Architecture / 11. Decision log)
- `docs/src/notation.md`:116  (Notation / Numerics)
- pass 1: verifier `NOT_FIXED`  (commit `3d334e56`)

### 2026-10-04-documentation-review-01-056  Verbless noun-phrase fragments stand as whole sentences in section intros and identity lines: a noun followed by a dash or colon gloss, with no finite verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

Each quoted sentence is a noun phrase only ("The assembled, ready-to-run simulation — ...", "Callback helpers that fire ..." where the verb sits inside a relative clause, "The elapsed simulation time and the step count."). The class covers the intros of The simulation, The predicted stationary state, Clock accessors, Cadence predicates, Persistence, and the opening of the Simulation docstring.

**Fix.** Give each a subject and verb, e.g. "This section documents the assembled, ready-to-run simulation ...", "These callback helpers fire on a schedule ...", "`Simulation` bundles everything the next iteration needs: ...".

- `docs/src/api/SimulationRun.md`:10  (SimulationRun / The simulation)
- `docs/src/api/SimulationRun.md`:21  (SimulationRun / The predicted stationary state)
- `docs/src/api/SimulationRun.md`:45  (SimulationRun / Clock accessors)
- `docs/src/api/SimulationRun.md`:54  (SimulationRun / Cadence predicates)
- `docs/src/api/SimulationRun.md`:74  (SimulationRun / Persistence)
- `src/SimulationRun.jl`:89  (Simulation)
- pass 1: verifier `FIXED`  (commit `c65a712f`)

### 2026-10-04-documentation-review-01-057  Subjectless sentences and label-colon tags: sentences open on a bare verb with no subject, or on a 'Label: ...' tag in place of a sentence.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

"Closes the iteration with deposit!, ..." and "Advects the tracers, ..." have no subject; "Derived viscosity (...): ..." and "Supplied viscosity: ..." are label tags rather than sentences.

**Fix.** Write "Each call closes the iteration with `deposit!` ...", "It advects the tracers ..."; turn the viscosity labels into a sentence ("When no `viscosity` is passed, $\nu$ is set so that ...") or a sub-heading.

- `src/SimulationRun.jl`:1048  (advance!)
- `src/SimulationRun.jl`:127  (Simulation)
- `src/SimulationRun.jl`:161  (Simulation)
- `docs/ARCHITECTURE.md`:1089  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1101  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1928  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2498  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2676  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2960  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2963  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2968  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3001  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3158  (Architecture / 11. Decision log)
- `docs/src/api/SimulationDomain.md`:32  (SimulationDomain / Dealiasing strategies)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- `docs/src/notation.md`:117  (Notation / Numerics)
- `docs/src/notation.md`:153  (Notation / Vocabulary)
- `docs/src/validation.md`:38  (Validation — code-to-code comparison against TurTLE / The physics point)
- `src/SimulationDomain.jl`:561  (SimulationDomain)
- pass 1: verifier `FIXED`  (commit `d9815af1`)

### 2026-10-04-documentation-review-01-058  Symbols in formulas are used without being bound anywhere on the page.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

$\kappa_{\mathrm{Ny}}$ (Nyquist wavenumber) appears only in the HouLi cutoff; $C$ and $u_{\max}$ in the advective rule are never tied to `cfl` and the maximum speed; $\Delta x$ is never called the grid spacing $L/N$; $M$ in the shape `(M, 3)` is never said to be the tracer count; $S$ appears after 'velocity-derivative skewness' without the binding.

**Fix.** Bind each at first use: "$\kappa_{\mathrm{Ny}} = N\pi/L$ the Nyquist wavenumber", "with $C$ the `cfl` coefficient and $u_{\max}$ the maximum speed", "$\Delta x = L/N$ the grid spacing", "the $M\times 3$ positions of the $M$ tracers", "the velocity-derivative skewness $S$".

- `src/SimulationRun.jl`:140  (Simulation)
- `src/SimulationRun.jl`:254  (Simulation)
- `src/SimulationRun.jl`:134  (Simulation)
- `src/SimulationRun.jl`:290  (Simulation)
- `src/SimulationRun.jl`:1443  (StationarityCriterion)

### 2026-10-04-documentation-review-01-059  The cache's vocabulary — 'deposit/deposited', 'Lagrangian sample history', 'epoch', 'fields epoch', 'announced out-of-band mutation', 'seeding deposit' — is used as if known; none is defined on the page before use.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

The module map reads the run 'through sim.cache' as 'deposited observables' and speaks of 'the cache's Lagrangian sample history'; current_step contrasts the step count with 'the observables cache's epoch' and an 'announced out-of-band mutation' without saying what announcing is or what the epoch is attached to.

**Fix.** Define once in a clause where first used: deposited = the observables the step stores in the cache at its end; sample history = the tracer velocities at earlier steps a multistep particle scheme needs; an announced mutation = a change to the state reported with `fields_modified!` (linked).

- `docs/src/api/SimulationRun.md`  — **the text here has moved and was not found again**
- `src/SimulationRun.jl`:25  (SimulationRun)
- `src/SimulationRun.jl`:929  (current_step)
- `src/SimulationRun.jl`:931  (current_step)
- pass 1: verifier `NOT_FIXED`  (commit `889cbd04`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-060  Forcing-construction terms of the package — 'deferred keyword form', 'operator-free constructor', 'the band' / 'forced band', 'the model' (the stationary-state prediction model) — are used before (or without) a definition.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

'the band's share of the energy' appears before any forced band is introduced; 'A forcing the model does not cover' presumes a model never named as such; predicted_stationary_state says 'built or in its deferred keyword form' with no link or gloss; 'a DeferredForcing from an operator-free constructor' leaves 'operator-free' unexplained.

**Fix.** Gloss each: 'the forced band (the wavenumber shells the forcing acts on)', 'the prediction model (the placeholder $\tilde{k}$ and band fraction)', 'a forcing built without a domain (a `DeferredForcing`, completed when the run is built)'.

- `src/SimulationRun.jl`:119  (Simulation)
- `src/SimulationRun.jl`:157  (Simulation)
- `src/SimulationRun.jl`:451  (predicted_stationary_state)
- `src/SimulationRun.jl`:215  (Simulation)
- pass 1: verifier `FIXED`  (commit `4009a34a`)

### 2026-10-04-documentation-review-01-061  Tracer- and seeding-machinery terms are used undefined: 'tile count', 'bootstrap', 'fill-aware', 'pre-rescale seed', 'the mask', 'the frame', 'the generator's conditions', 'observation-first loop'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

'two of the tile count' assumes a tiling the page never mentions; 'starts from its bootstrap' and 'fill-aware' assume knowledge of how a multistep scheme starts; 'build the frame yourself' calls the domain by an alias the page never introduces; flow_parameters reads ν 'from the generator's conditions' without saying what they are.

**Fix.** Replace each with its plain meaning or define it in a clause: 'the number of spatial tiles the traversal sorts tracers into', 'starts with lower-order steps until its history fills', 'build the domain yourself', 'read from the run's `FlowConditions`'.

- `src/SimulationRun.jl`:289  (Simulation)
- `src/SimulationRun.jl`:311  (Simulation)
- `src/SimulationRun.jl`:1623  (read_simulation)
- `src/SimulationRun.jl`:231  (Simulation)
- `src/SimulationRun.jl`:329  (Simulation)
- `src/SimulationRun.jl`:898  (flow_parameters)
- pass 1: verifier `LINE_ONLY`  (commit `9b11033d`)

### 2026-10-04-documentation-review-01-062  Mathematical symbols for the fields are set as code spans instead of math, where the same docstring writes them as math elsewhere.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@api-SimulationRun`, decided by an agent.

The Fields entry writes `û`, `φ̂` in backticks, while the opening of the same Simulation docstring sets them as $\hat{\boldsymbol{u}}$ and $\hat\varphi$; a bare Unicode ν also appears in running prose outside math.

**Fix.** Write "the evolving $\hat{\boldsymbol{u}}$, $\hat\varphi$" and "under a derived $\nu$".

- `src/SimulationRun.jl`:359  (Simulation)
- `src/SimulationRun.jl`:225  (Simulation)

### 2026-10-04-documentation-review-01-063  Verbless fragments stand as sentences in the module map's closing line and in the Persistence section introduction.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@api-State`, decided by an agent.

Neither has a finite verb; each is a noun phrase closed by a full stop.

**Fix.** Give each a verb: 'All of them are sized to a FixedDomain.'; 'The state persists to HDF5 as one self-describing group holding ...'.

- `src/State.jl`:22  (State)
- `docs/src/api/State.md`:31  (State / Persistence)
- pass 1: verifier `FIXED`  (commit `2d422083`)

### 2026-10-04-documentation-review-01-064  The noun 'deposit' (the package's end-of-iteration step that fills the observables cache) is used as a term of art before the page defines it or links it; the deposit! link arrives only later, in the admonition.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-State`, decided by an agent.

On a cold read, 'the deposit' is a package concept (what is deposited, when, by whom), and the ResolvedFields gloss of 'iteration' leans on it without defining it.

**Fix.** Bind it at first use, e.g. 'the deposit — the end-of-step write of the observables into the cache, see deposit! —', or link deposit! there.

- `src/State.jl`:68  (ResolvedFields)
- `src/State.jl`:190  (random_solenoidal_velocity_spectral!)
- `src/State.jl`:290  (random_scalar_spectral!)
- pass 1: verifier `NOT_FIXED`  (commit `fdeb90c4`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-065  'the mask' (the package's dealiasing mask) appears with no antecedent on the page; only 'dealiased' and 'the dealias cutoff' precede it, and no mask is defined or linked.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@api-State`, decided by an agent.

The definite article presumes a specific mask object the page never introduces; the cutoff's value and which domain setting fixes it are also left unstated.

**Fix.** Say 'the shells the dealiasing truncation zeroes' or link the domain's dealiasing setting at first mention.

- `src/State.jl`:174  (random_solenoidal_velocity_spectral!)
- `src/State.jl`:275  (random_scalar_spectral!)
- pass 1: verifier `FIXED`  (commit `3947707b`)

### 2026-10-04-documentation-review-01-066  The inventory of what a Simulation holds names package-internal components as if the reader already knew them: the integrator's registers, the assembly scratch, the observables cache, the domain's precomputed symbols. None is defined in a clause or linked, so a cold reader cannot tell what each is or why it costs memory.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@gpu`, decided by an agent.

First and only use of each term on the page; no gloss and no @ref link, while Simulation beside them is linked.

**Fix.** Gloss each in a few words (e.g. registers = the intermediate stages a Runge-Kutta step keeps; assembly scratch = workspace for the nonlinear term) or link each to its API entry.

- `docs/src/gpu.md`:12  (Memory footprint on a GPU / What a run keeps in memory)
- pass 1: verifier `FIXED`  (commit `0ab9c414`)

### 2026-10-04-documentation-review-01-067  The page leans on 'the field library' and 'the transform library' without ever naming them; the field library's identity only surfaces later inside a code block (GBGPeriodicFields), and the transform library (cuFFT/rocFFT) is never named.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@gpu`, decided by an agent.

'field library' is a package-ecosystem term; first use is unglossed and the link text does not name the package.

**Fix.** Name it at first use: 'the field library, GBGPeriodicFields,' and 'the FFT library's (cuFFT's) workspace'.

- `docs/src/gpu.md`:7  (Memory footprint on a GPU)
- `docs/src/gpu.md`:36  (Memory footprint on a GPU / What a run keeps in memory)
- pass 1: verifier `FIXED`  (commit `9b02a172`)

### 2026-10-04-documentation-review-01-068  The code example uses a variable `sim` that the page never binds; the reader must guess it is a Simulation built elsewhere.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@gpu`, decided by an agent.

No line on the page constructs or names `sim`; the preceding sentence says only 'read the memory kind of the velocity'.

**Fix.** Say 'for a Simulation `sim`' in the lead-in sentence, or add a construction line to the block.

- `docs/src/gpu.md`:59  (Memory footprint on a GPU / Fields larger than GPU memory)
- pass 1: verifier `FIXED`  (commit `753a8f1f`)

### 2026-10-04-documentation-review-01-069  The opening uses `array_type` and `element_type` as the run's settings without saying what they are settings of (keywords of the Simulation constructor) or where they are passed.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@gpu`, decided by an agent.

The first link to Simulation comes a paragraph later; 'its' refers to 'a run', which is not yet tied to any constructor.

**Fix.** Write 'through the `array_type` keyword of `Simulation`' with the link at that first mention.

- `docs/src/gpu.md`:3  (Memory footprint on a GPU)
- `docs/src/gpu.md`:4  (Memory footprint on a GPU)
- pass 1: verifier `FIXED`  (commit `b79070b8`)

### 2026-10-04-documentation-review-01-070  The `materialized = true` option of HouLi is cited as adding storage, but what materializing means is never stated, so the reader cannot judge whether to use it.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@gpu`, decided by an agent.

'materialized' is a package term; no clause defines it and the HouLi link at the earlier mention is to the type, not this option.

**Fix.** Add a clause: 'which stores the filter as a full per-mode array instead of evaluating it on the fly'.

- `docs/src/gpu.md`:30  (Memory footprint on a GPU / What a run keeps in memory)
- pass 1: verifier `FIXED`  (commit `d894bf4d`)

### 2026-10-04-documentation-review-01-071  'The printed run' is not defined; a cold reader cannot tell that it means the displayed Simulation (its show output) rather than some log line.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@gpu`, decided by an agent.

No earlier sentence mentions printing or displaying a run.

**Fix.** Write 'A displayed `Simulation` shows `CuArray` either way…'.

- `docs/src/gpu.md`:62  (Memory footprint on a GPU / Fields larger than GPU memory)
- pass 1: verifier `FIXED`  (commit `c1e43c1d`)

### 2026-10-04-documentation-review-01-072  Verbless fragments stand as sentences in the prose: a parenthetical with no main verb after the install block, and a noun phrase with no verb in the Phenomenology entry.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@home`, decided by an agent.

Neither has a subject and a finite verb; the first reads as a dangling note on the commands rather than a sentence.

**Fix.** E.g. 'Add the field-library backend first: both are unregistered, so Julia cannot resolve GBGPeriodicFields on its own. Julia 1.12 or later is required.' and 'It is a separate, opt-in group …'.

- `docs/src/index.md`:25  (GBGHomogeneousTurbulence.jl / Installation)
- `docs/src/index.md`:143  (GBGHomogeneousTurbulence.jl / Components)
- pass 1: verifier `FIXED`  (commit `68ac476b`)

### 2026-10-04-documentation-review-01-073  The Components entries are written as label-colon tags followed by noun phrases, with no verb, e.g. the Propagator and Forcing entries.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@home`, decided by an agent.

Every entry from SimulationDomain to Phenomenology follows the 'Name: noun phrase' pattern; the house style bans label-colon tags in prose.

**Fix.** Give each entry a verb ('`Propagator` holds the interchangeable …'), or render the list as bullets where the fragment form is clearly a list.

- `docs/src/index.md`:134  (GBGHomogeneousTurbulence.jl / Components)
- `docs/src/index.md`:126  (GBGHomogeneousTurbulence.jl / Components)

### 2026-10-04-documentation-review-01-074  The quick-start comments use the symbol k without binding it anywhere on the page, and use ν before the 'What it solves' section binds it.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@home`, decided by an agent.

Nothing on the page says k is the turbulent kinetic energy (the reader might take it for a wavenumber), and ν is first bound as the kinematic viscosity only further down.

**Fix.** Say 'the kinetic energy k' and 'the viscosity ν' at these first uses.

- `docs/src/index.md`:56  (GBGHomogeneousTurbulence.jl / Quick start)
- `docs/src/index.md`:52  (GBGHomogeneousTurbulence.jl / Quick start)
- pass 1: verifier `FIXED`  (commit `9e29d2d2`)

### 2026-10-04-documentation-review-01-075  The quick start uses package terms before the page defines them: 'the cache', 'iteration', 'stale read', 'deposited'/'recorded', and the forcing name ConstantPower.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

The cache and 'iteration' are defined only later, in the Cache entry of Components; 'stale' is never defined. ConstantPower is first named here, before the forcing list, with no hint of what it does.

**Fix.** Gloss these in the comments ('the observables cache, which keeps the values from the most recent step') and say what ConstantPower holds fixed.

- `docs/src/index.md`:63  (GBGHomogeneousTurbulence.jl / Quick start)
- `docs/src/index.md`:64  (GBGHomogeneousTurbulence.jl / Quick start)
- pass 1: verifier `FIXED`  (commit `08b9379f`)

### 2026-10-04-documentation-review-01-076  Software jargon a physicist reader cannot unpack is used without a definition: 'at field scale', 'per-pass task transients', 'vertical slices', 'the fused pair', 'single source of truth'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

None of these terms is glossed on the page, and each assumes knowledge of the implementation.

**Fix.** Reword in plain terms, e.g. 'no allocation proportional to the grid size', 'one feature at a time, end to end', 'computed together in one pass'.

- `docs/src/index.md`:12  (GBGHomogeneousTurbulence.jl)
- `docs/src/index.md`:97  (GBGHomogeneousTurbulence.jl / What it solves)
- `docs/src/index.md`:116  (GBGHomogeneousTurbulence.jl / Components)
- `docs/src/api.md`:15  (API overview)
- pass 1: verifier `FIXED`  (commit `47c871e8`)

### 2026-10-04-documentation-review-01-077  The Generator entry talks of 'the protocol' and 'the two integrating-factor verbs' without defining the protocol or naming those two functions, while it names the other four.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

A cold reader cannot tell which functions 'the two integrating-factor verbs' are. 'Verbs' and 'protocol' are package jargon for a function interface.

**Fix.** Name the two functions (velocity_integrating_factor, scalar_integrating_factor) and say 'a fixed set of functions' rather than 'verbs'/'protocol'.

- `docs/src/index.md`:131  (GBGHomogeneousTurbulence.jl / Components)
- pass 1: verifier `FIXED`  (commit `955ab371`)

### 2026-10-04-documentation-review-01-078  The Phenomenology entry uses package-structure terms nowhere defined on the page: 'the umbrella', 'include order', 'dependency-light leaf'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@home`, decided by an agent.

'Umbrella' (the top-level module) and 'leaf' are never introduced, and 'include order' is distinct from the 'build order' named earlier but is not explained.

**Fix.** Say 'not re-exported by the top-level GBGHomogeneousTurbulence module; load it with using …', and drop or explain the include-order remark.

- `docs/src/index.md`:144  (GBGHomogeneousTurbulence.jl / Components)
- `docs/src/index.md`:143  (GBGHomogeneousTurbulence.jl / Components)
- pass 1: verifier `NOT_FIXED`  (commit `5fac293c`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-079  Symbols are used before (or without ever) being bound on the page: d_i appears in the integrating-factor row but is bound only later in the Numerics table; Delta x appears in the CFL row and is bound nowhere; kappa_max is used in the Re_box row before the Numerics table defines it; Omega is used in the inner-product row before the spatial-average row binds it; Re_lambda is used in the Re row before its own row.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@notation`, decided by an agent.

The integrating-factor row reads 'a Runge-Kutta stage substep $d_i\Delta t$' long before the row '$A_i, B_i, d_i$ the low-storage Runge-Kutta stage coefficients'; the CFL formula uses $\Delta x$ and no row binds the grid spacing.

**Fix.** Bind each symbol where first used (e.g. 'Delta x = L/N the grid spacing' in the CFL row; 'd_i the stage node increment' in the integrating-factor row), or add rows for Delta x and move first uses after their rows.

- `docs/src/notation.md`:67  (Notation / Spectral representation and operators)
- `docs/src/notation.md`:113  (Notation / Numerics)
- `docs/src/notation.md`:99  (Notation / Derived scales)
- `docs/src/notation.md`:19  (Notation / Conventions)
- `docs/ARCHITECTURE.md`:302  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:466  (Architecture / 4. Modules / 4.5 `Propagator` — the map that advances the state in time)
- `docs/ARCHITECTURE.md`:467  (Architecture / 4. Modules / 4.5 `Propagator` — the map that advances the state in time)
- `docs/ARCHITECTURE.md`:509  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/ARCHITECTURE.md`:553  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:563  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:1252  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1653  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1709  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1782  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1996  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2023  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2107  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2155  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2468  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2476  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2477  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2500  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2502  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2504  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2803  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3082  (Architecture / 11. Decision log)
- `docs/src/notation.md`:101  (Notation / Derived scales)
- `docs/src/notation.md`:112  (Notation / Numerics)
- `docs/src/notation.md`:130  (Notation / Forcing)
- `docs/src/observables_cache.md`:69  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:77  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:78  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:148  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:203  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:208  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:240  (The observables cache / 2. The system)
- `docs/src/observables_cache.md`:377  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:379  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:402  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/src/validation.md`:34  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:189  (Validation — code-to-code comparison against TurTLE / Results / Robustness across integrators: `IFLowStorageRK4` at its adaptive step)
- `src/Forcing.jl`:512  (VarianceRescaling)
- `src/Forcing.jl`:1130  (StochasticOU)
- `src/Forcing.jl`:1134  (StochasticOU)
- `src/Observables.jl`:159  (kinetic_energy_and_dissipation)
- `src/Observables.jl`:272  (max_speed)
- `src/Particles.jl`:317  (Heun)
- `src/Particles.jl`:325  (Heun)
- `src/Particles.jl`:438  (AdamsBashforth)
- `src/Particles.jl`:464  (AdamsBashforth)
- `src/Particles.jl`:472  (AdamsBashforth)
- `src/Particles.jl`:657  (advect!)
- `src/Particles.jl`:668  (advect!)
- `src/Particles.jl`:670  (advect!)
- `src/Propagator.jl`:250  (IFLowStorageRK3)
- `src/Propagator.jl`:252  (IFLowStorageRK3)
- `src/Propagator.jl`:253  (IFLowStorageRK3)
- `src/Propagator.jl`:441  (IFHeun)
- `src/Propagator.jl`:447  (IFHeun)
- `src/Propagator.jl`:448  (IFHeun)
- `src/Propagator.jl`:578  (IFSSPRK3)
- `src/Propagator.jl`:579  (IFSSPRK3)
- `src/Propagator.jl`:580  (IFSSPRK3)
- `src/Propagator.jl`:581  (IFSSPRK3)
- `src/Propagator.jl`:582  (IFSSPRK3)
- `src/Propagator.jl`:595  (IFSSPRK3)
- `src/Propagator.jl`:596  (IFSSPRK3)
- `src/Propagator.jl`:598  (IFSSPRK3)
- `src/Propagator.jl`:796  (deposit!)
- `src/Propagator.jl`:862  (recommended_cfl)
- `src/Propagator.jl`:867  (recommended_cfl)
- `src/SimulationDomain.jl`:114  (HouLi)
- `src/SimulationDomain.jl`:435  (max_resolved_wavenumber)
- `src/SimulationDomain.jl`:442  (max_resolved_wavenumber)
- `src/SimulationRun.jl`:254  (Simulation)
- `src/SimulationRun.jl`:1287  (run!)
- `src/SimulationRun.jl`:1432  (StationarityCriterion)
- `docs/ARCHITECTURE.md`:1089  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1101  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1928  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2498  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2676  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2960  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2963  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2968  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3001  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3158  (Architecture / 11. Decision log)
- `docs/src/api/SimulationDomain.md`:32  (SimulationDomain / Dealiasing strategies)
- `docs/src/notation.md`:117  (Notation / Numerics)
- `docs/src/notation.md`:153  (Notation / Vocabulary)
- `docs/src/validation.md`:38  (Validation — code-to-code comparison against TurTLE / The physics point)
- `src/SimulationDomain.jl`:561  (SimulationDomain)
- `docs/ARCHITECTURE.md`:3159  (Architecture / 11. Decision log)

### 2026-10-04-documentation-review-01-080  The 'front door' entry sends the reader to documents the page withholds (the decision log, the architecture's section 4.7) and depends on them for its meaning; a user-facing page cites a design-document section number.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@notation`, decided by an agent.

The row's meaning (where the term is used and in what wider sense) is carried by references to 'the decision log' and 'The architecture's §4.7 heading', neither of which the reader has.

**Fix.** State the meaning on the page itself (the name formerly used for the domain-building Simulation constructor) and drop the decision-log and section-number references.

- `docs/src/notation.md`:147  (Notation / Vocabulary)
- `docs/src/notation.md`:147  (Notation / Vocabulary)
- pass 1: verifier `NOT_FIXED`  (commit `8da0bb84`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-081  Package terms of art are used without a definition or link anywhere on the page: 'dynamical factor', 'close' (a deposit closes the fields), 'announced out-of-band mutation', 'optimality audit', 'the generator protocol', 'the run layer', 'sharp strategies', 'the resolved state'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@notation`, decided by an agent.

The Vocabulary section defines deposit and epoch in terms of 'each dynamical factor' and an 'announced out-of-band mutation', none of which is defined; the tau row names 'the generator protocol's argument' and 'the run layer's unit of progress'; kappa_max contrasts 'the sharp strategies' with HouLi without saying what a sharp strategy is.

**Fix.** Define each in a clause where first used (e.g. 'each dynamical factor - the fields and the tracer positions, which advance separately'), or add them to the Vocabulary table.

- `docs/src/notation.md`:141  (Notation / Vocabulary)
- `docs/src/notation.md`:143  (Notation / Vocabulary)
- `docs/src/notation.md`:149  (Notation / Vocabulary)
- `docs/src/notation.md`:101  (Notation / Derived scales)
- `docs/src/notation.md`:101  (Notation / Derived scales)
- `docs/src/notation.md`:117  (Notation / Numerics)
- `docs/src/notation.md`:89  (Notation / Derived scales)
- `src/SimulationDomain.jl`:118  (HouLi)
- `src/SimulationDomain.jl`:444  (max_resolved_wavenumber)
- `src/SimulationRun.jl`:142  (Simulation)
- pass 1: verifier `FIXED`  (commit `932efd73`)

### 2026-10-04-documentation-review-01-082  Terms the Vocabulary section defines are used earlier on the page, before their definition: 'cached', 'iterations', 'deposit', 'the cache', 'the forced/forcing band'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@notation`, decided by an agent.

The vorticity row says 'the cached field' and the tracer row 'between iterations' tables before the Vocabulary section defines iteration, deposit and slot; the k-tilde row speaks of 'provisional values per forcing band' before the k_band row defines the forced band; the deposit entry says 'into the cache' before the slot entry links ObservablesCache.

**Fix.** Move the Vocabulary section ahead of the symbol tables, or link each early use to its Vocabulary entry.

- `docs/src/notation.md`:34  (Notation / Physical variables)
- `docs/src/notation.md`:42  (Notation / Physical variables)
- `docs/src/notation.md`:98  (Notation / Derived scales)
- `docs/src/notation.md`:141  (Notation / Vocabulary)
- pass 1: verifier `FIXED`  (commit `38bc17c3`)

### 2026-10-04-documentation-review-01-083  The Code column names package objects that are neither defined nor linked, so a cold reader cannot tell what they are: `conditions`, `domain`, `tracers`, `scalar_forcing`, `element_type`, `envelope_wavenumber`, `HouLi`, `PhaseShift`, `FlowParameters`, `ResolvedFields`; and 'the velocity state' / 'the scalar state' are given as code names though the column promises 'the name each symbol carries in the package'.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@notation`, decided by an agent.

`conditions.viscosity`, `domain.squared_wavenumber_kernel`, `tracers.positions` presuppose objects named conditions, domain and tracers that the page never introduces; HouLi and PhaseShift appear as dealiasing strategies with no gloss or link.

**Fix.** Link each to its API entry (or name its owning type, e.g. 'the FlowConditions field viscosity'), and give the actual storage names for the velocity and scalar state.

- `docs/src/notation.md`:49  (Notation / Parameters)
- `docs/src/notation.md`:63  (Notation / Spectral representation and operators)
- `docs/src/notation.md`:33  (Notation / Physical variables)
- `docs/src/notation.md`:116  (Notation / Numerics)
- `src/Observables.jl`:119  (dissipation)
- `src/Observables.jl`:344  (scalar_dissipation)
- `docs/ARCHITECTURE.md`:321  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:779  (Architecture / 7. Deliberately deferred)
- `docs/ARCHITECTURE.md`:1218  (Architecture / 11. Decision log)
- pass 1: verifier `LINE_ONLY`  (commit `85f17b9c`)

### 2026-10-04-documentation-review-01-084  Several prose sentences are verbless fragments.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@notation`, decided by an agent.

'Italic, taken in order.' and 'Measured from the resolved state, or derived from it ...' have no subject and verb; 'Not the variance of the field, which is what a VarianceController holds' and 'Wider than a step, which is only the first half, and than a stage ...' are fragments standing as sentences.

**Fix.** Give each a subject and verb, e.g. 'Indices are italic and taken in order.'; 'These scales are measured from the state, or derived from it through ...'; 'It is not the variance of the field ...'; 'An iteration is wider than a step ...'.

- `docs/src/notation.md`:18  (Notation / Conventions)
- `docs/src/notation.md`:89  (Notation / Derived scales)
- `docs/src/notation.md`:128  (Notation / Forcing)
- `docs/src/notation.md`:140  (Notation / Vocabulary)
- pass 1: verifier `FIXED`  (commit `e005032e`)

### 2026-10-04-documentation-review-01-085  A code span holds an ordinary English word rather than code.

Rule: `RULE.TEX.CODE_SPAN_JULIA`.  
Reported by `withheld@notation`, decided by an agent.

'appears in `backticks`' sets the word backticks as code; it is neither literal code nor input.

**Fix.** Write 'appears in backticks' (or show a literal example such as `curl`).

- `docs/src/notation.md`:4  (Notation)
- pass 1: verifier `FIXED`  (commit `5e3de47a`)

### 2026-10-04-documentation-review-01-086  Package-internal terms of art appear with no defining clause and no link anywhere on the page: the cost-accounting 'ledger' (frozen ledgers), the 'cleared sentinel', the 'slot=register merge', the 'budget vocabulary', the 'skewness gate', a 'fused mapped mean', a 'transform axis' (the page defined only arithmetic, traffic and memory axes), and the 'class' the ledger is bounded in. A cold reader cannot tell what any of them names.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@observables_cache`, decided by an agent.

**Fix.** Define each in a clause at first use (e.g. 'the audit ledger, the suite's frozen per-iteration count of transforms and passes'), or link it, or drop the term where it is history (budget vocabulary, slot=register merge).

- `docs/src/observables_cache.md`:126  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:179  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:444  (The observables cache / 3. The code / 3.2 Coverage — the page against the code)
- `docs/src/observables_cache.md`:447  (The observables cache / 3. The code / 3.2 Coverage — the page against the code)
- `docs/src/observables_cache.md`:373  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:373  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:203  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:229  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/ARCHITECTURE.md`:362  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:363  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:932  (Architecture / 10. Conventions)
- `docs/ARCHITECTURE.md`:1050  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1456  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1626  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3204  (Architecture / 11. Decision log)
- `src/Observables.jl`:365  (derivative_skewness)
- `src/Observables.jl`:366  (derivative_skewness)
- `src/Observables.jl`:370  (derivative_skewness)
- `src/Observables.jl`:371  (derivative_skewness)
- `src/Observables.jl`:376  (derivative_skewness)
- `src/Observables.jl`:377  (derivative_skewness)
- `src/Observables.jl`:379  (derivative_skewness)
- `src/Observables.jl`:380  (derivative_skewness)
- `src/Observables.jl`:388  (derivative_skewness)
- `src/Observables.jl`:392  (derivative_skewness)
- `src/Observables.jl`:394  (derivative_skewness)
- pass 1: verifier `NOT_FIXED`  (commit `16503900`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-087  Package components are named as known before the page says what they are: 'the generator' (the right-hand-side assembler) and 'the closing deposits' appear in section 1.1, while deposit is only explained in section 1.3; the forcing types VarianceController and VarianceRescaling(over = :total) are named with no statement that they are forcings or what they do, and are later called 'a constant-energy forcing' without the link being made.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@observables_cache`, decided by an agent.

**Fix.** Gloss 'generator' as the component that assembles the right-hand side; define a deposit at its first use in 1.1; introduce the two forcings as 'the constant-energy forcings VarianceController and VarianceRescaling' with a link.

- `docs/src/observables_cache.md`:18  (The observables cache / 1. The design / 1.1 What it is for)
- `docs/src/observables_cache.md`:29  (The observables cache / 1. The design / 1.1 What it is for)
- `docs/src/observables_cache.md`:91  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:95  (The observables cache / 1. The design / 1.2 What the cache holds)
- pass 1: verifier `FIXED`  (commit `25945f17`)

### 2026-10-04-documentation-review-01-088  Symbols are used without being bound: M (the number of particles), N (grid points per axis), the wavenumber vector and magnitude (bold kappa, kappa, kappa_n), the strain-rate tensor S and S_ij, and the f in the Runge-Kutta stage formula, which is the right-hand side there but is bound two sections later as the forcing.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@observables_cache`, decided by an agent.

**Fix.** Bind M as the number of tracer particles and N as grid points per axis at first use; bind bold kappa as the wavenumber vector, kappa_n as the n-th shell; bind S as the strain-rate tensor; use a different letter (e.g. the right-hand side R) in the stage formula.

- `docs/src/observables_cache.md`:338  (The observables cache / 2. The system / 2.3 Transforms and arrays)
- `docs/src/observables_cache.md`:220  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:275  (The observables cache / 2. The system / 2.1 The equations)
- `docs/src/observables_cache.md`:371  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:373  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:390  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/src/observables_cache.md`:77  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/ARCHITECTURE.md`:505  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/ARCHITECTURE.md`:1492  (Architecture / 11. Decision log)
- `docs/src/observables_cache.md`:343  (The observables cache / 2. The system / 2.3 Transforms and arrays)
- `docs/src/observables_cache.md`:364  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:365  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:380  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:276  (The observables cache / 2. The system / 2.1 The equations)
- `docs/ARCHITECTURE.md`:1075  (Architecture / 11. Decision log)
- `docs/src/notation.md`:79  (Notation / Diagnostics)
- `docs/ARCHITECTURE.md`:362  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:363  (Architecture / 4. Modules / 4.3 `Observables` — the measured functions of the state)
- `docs/ARCHITECTURE.md`:932  (Architecture / 10. Conventions)
- `docs/ARCHITECTURE.md`:1050  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1456  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1626  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3204  (Architecture / 11. Decision log)
- `src/Observables.jl`:365  (derivative_skewness)
- `src/Observables.jl`:366  (derivative_skewness)
- `src/Observables.jl`:370  (derivative_skewness)
- `src/Observables.jl`:371  (derivative_skewness)
- `src/Observables.jl`:376  (derivative_skewness)
- `src/Observables.jl`:377  (derivative_skewness)
- `src/Observables.jl`:379  (derivative_skewness)
- `src/Observables.jl`:380  (derivative_skewness)
- `src/Observables.jl`:388  (derivative_skewness)
- `src/Observables.jl`:392  (derivative_skewness)
- `src/Observables.jl`:394  (derivative_skewness)
- `docs/src/observables_cache.md`:391  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/ARCHITECTURE.md`:302  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:466  (Architecture / 4. Modules / 4.5 `Propagator` — the map that advances the state in time)
- `docs/ARCHITECTURE.md`:467  (Architecture / 4. Modules / 4.5 `Propagator` — the map that advances the state in time)
- `docs/ARCHITECTURE.md`:509  (Architecture / 4. Modules / 4.6 `Particles` — Lagrangian instruments)
- `docs/ARCHITECTURE.md`:553  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:563  (Architecture / 4. Modules / 4.7 `SimulationRun` — the front door)
- `docs/ARCHITECTURE.md`:1252  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1653  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1709  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1782  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:1996  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2005  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2023  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2107  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2155  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2468  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2476  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2477  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2500  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2502  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2504  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2803  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:3082  (Architecture / 11. Decision log)
- `docs/src/notation.md`:67  (Notation / Spectral representation and operators)
- `docs/src/notation.md`:101  (Notation / Derived scales)
- `docs/src/notation.md`:112  (Notation / Numerics)
- `docs/src/notation.md`:113  (Notation / Numerics)
- `docs/src/notation.md`:130  (Notation / Forcing)
- `docs/src/observables_cache.md`:69  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:78  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:148  (The observables cache / 1. The design / 1.3 When a cached value is valid)
- `docs/src/observables_cache.md`:203  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:208  (The observables cache / 1. The design / 1.4 What caching costs)
- `docs/src/observables_cache.md`:240  (The observables cache / 2. The system)
- `docs/src/observables_cache.md`:377  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:379  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/src/observables_cache.md`:402  (The observables cache / 2. The system / 2.5 Three points the table alone does not settle)
- `docs/src/validation.md`:34  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:189  (Validation — code-to-code comparison against TurTLE / Results / Robustness across integrators: `IFLowStorageRK4` at its adaptive step)
- `src/Forcing.jl`:512  (VarianceRescaling)
- `src/Forcing.jl`:1130  (StochasticOU)
- `src/Forcing.jl`:1134  (StochasticOU)
- `src/Observables.jl`:159  (kinetic_energy_and_dissipation)
- `src/Observables.jl`:272  (max_speed)
- `src/Particles.jl`:317  (Heun)
- `src/Particles.jl`:325  (Heun)
- `src/Particles.jl`:438  (AdamsBashforth)
- `src/Particles.jl`:464  (AdamsBashforth)
- `src/Particles.jl`:472  (AdamsBashforth)
- `src/Particles.jl`:657  (advect!)
- `src/Particles.jl`:668  (advect!)
- `src/Particles.jl`:670  (advect!)
- `src/Propagator.jl`:250  (IFLowStorageRK3)
- `src/Propagator.jl`:252  (IFLowStorageRK3)
- `src/Propagator.jl`:253  (IFLowStorageRK3)
- `src/Propagator.jl`:441  (IFHeun)
- `src/Propagator.jl`:447  (IFHeun)
- `src/Propagator.jl`:448  (IFHeun)
- `src/Propagator.jl`:578  (IFSSPRK3)
- `src/Propagator.jl`:579  (IFSSPRK3)
- `src/Propagator.jl`:580  (IFSSPRK3)
- `src/Propagator.jl`:581  (IFSSPRK3)
- `src/Propagator.jl`:582  (IFSSPRK3)
- `src/Propagator.jl`:595  (IFSSPRK3)
- `src/Propagator.jl`:596  (IFSSPRK3)
- `src/Propagator.jl`:598  (IFSSPRK3)
- `src/Propagator.jl`:796  (deposit!)
- `src/Propagator.jl`:862  (recommended_cfl)
- `src/Propagator.jl`:867  (recommended_cfl)
- `src/SimulationDomain.jl`:114  (HouLi)
- `src/SimulationDomain.jl`:435  (max_resolved_wavenumber)
- `src/SimulationDomain.jl`:442  (max_resolved_wavenumber)
- `src/SimulationRun.jl`:254  (Simulation)
- `src/SimulationRun.jl`:1287  (run!)
- `src/SimulationRun.jl`:1432  (StationarityCriterion)

### 2026-10-04-documentation-review-01-089  Verbless label fragments stand as sentences: the four cache tests open with a bare participle and a dash, and section 2.2 uses label-colon fragments with no verb.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@observables_cache`, decided by an agent.

**Fix.** Write each as a sentence: 'Is it computed? Some component must produce it anyway.'; 'The quadratic terms ... are evaluated as fields.'; 'The viscous terms are never formed.'

- `docs/src/observables_cache.md`:84  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:98  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:106  (The observables cache / 1. The design / 1.2 What the cache holds)
- `docs/src/observables_cache.md`:281  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `docs/src/observables_cache.md`:283  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `docs/ARCHITECTURE.md`:2942  (Architecture / 11. Decision log)
- `docs/src/observables_cache.md`:263  (The observables cache / 2. The system / 2.1 The equations)
- `docs/src/observables_cache.md`:367  (The observables cache / 2. The system / 2.4 What it caches)
- `docs/ARCHITECTURE.md`:320  (Architecture / 4. Modules / 4.2 `Generator` — the evolution, split reversible and irreversible)
- `docs/ARCHITECTURE.md`:1735  (Architecture / 11. Decision log)
- `docs/src/observables_cache.md`:266  (The observables cache / 2. The system / 2.1 The equations)
- `docs/src/observables_cache.md`:282  (The observables cache / 2. The system / 2.2 How a step treats each term)
- `docs/src/observables_cache.md`:368  (The observables cache / 2. The system / 2.4 What it caches)
- pass 1: verifier `NOT_FIXED`  (commit `20e37a1d`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-090  Verbless fragments stand as sentences and as label-colon tags: run-in lead-ins to the findings paragraphs, a bare count label, and a version label.

Rule: `RULE.DOC.GRAMMAR`.  
Reported by `withheld@validation`, decided by an agent.

None of the quoted units has a finite verb; 'Same agreement structure.' and 'Three findings:' are labels, and the version line is a label-colon tag.

**Fix.** Give each a verb, e.g. 'The agreement has the same structure.' and 'The comparison used TurTLE 8.2.1, its current release at the time.' and 'The repetition gave three findings.'

- `docs/src/validation.md`:155  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:157  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:193  (Validation — code-to-code comparison against TurTLE / Results / Robustness across integrators: `IFLowStorageRK4` at its adaptive step)
- `docs/src/validation.md`:20  (Validation — code-to-code comparison against TurTLE)
- pass 1: verifier `NOT_FIXED`  (commit `09f67bb7`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-091  Several symbols are used with no binding anywhere on the page: kappa_max, kappa_Ny (only later glossed as 'the Nyquist'), X_0, epsilon_target, and k_band (glossed only two subsections later as 'band energy').

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@validation`, decided by an agent.

A cold reader cannot tell what kappa_max is or how it relates to kappa_eff, what X_0 is (the tracer positions at t_0 are never named as X), or what epsilon_target and k_band are at their first use.

**Fix.** Bind each at first use in a clause: kappa_Ny = N/2 the Nyquist wavenumber; kappa_max the largest resolved wavenumber (here kappa_eff); X_0 the tracer positions at t_0; epsilon_target the target injection rate (1); k_band the kinetic energy in shells 1-2.

- `docs/src/validation.md`:38  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:39  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:80  (Validation — code-to-code comparison against TurTLE / The shared initial state, and the import witnesses)
- `docs/src/validation.md`:148  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/ARCHITECTURE.md`:2963  (Architecture / 11. Decision log)
- `docs/ARCHITECTURE.md`:2968  (Architecture / 11. Decision log)
- pass 1: verifier `FIXED`  (commit `861121a7`)

### 2026-10-04-documentation-review-01-092  Terms of art from the package or the comparison's vocabulary are used before (or without) a definition: 'handoff state' appears in the table before the section that explains it; 'registers', 'observation callback', 'anchored forcings', 'I4O3', 'AB4' and the scheme name `IFSSPRK3` are never defined or linked at first use.

Rule: `RULE.DOC.TERMS_DEFINED`.  
Reported by `withheld@validation`, decided by an agent.

The 'handoff' is explained only in the next section ('was frozen as handoff_initial_state_iter100.h5'); 'registers' and 'observation callback' are package nouns; 'anchored' is only inferable by contrast; I4O3 (TurTLE's interpolation order) is never expanded; AB4 is expanded only in the following section; `IFSSPRK3` is neither linked nor glossed while `IFLowStorageRK4` later is linked.

**Fix.** Define in a clause or @ref-link at first use: e.g. 'the frozen handoff state (the shared initial state described below)', 'AB4 (fourth-order Adams–Bashforth)', link `IFSSPRK3` to its API entry, gloss I4O3 as TurTLE's interpolation kernel, gloss 'anchored' as a forcing that reads the state to pin the injection rate, and replace 'registers' with 'stored sample history'.

- `docs/src/validation.md`:36  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:72  (Validation — code-to-code comparison against TurTLE / The shared initial state, and the import witnesses)
- `docs/src/validation.md`:127  (Validation — code-to-code comparison against TurTLE / Results / Lagrangian velocity autocorrelation, ``\rho_u(\tau)``)
- `docs/src/validation.md`:170  (Validation — code-to-code comparison against TurTLE / Results / Robustness across forcings: the Linear (Lundgren) pair)
- `docs/src/validation.md`:80  (Validation — code-to-code comparison against TurTLE / The shared initial state, and the import witnesses)
- `docs/src/validation.md`:35  (Validation — code-to-code comparison against TurTLE / The physics point)
- `docs/src/validation.md`:33  (Validation — code-to-code comparison against TurTLE / The physics point)
- pass 1: verifier `NOT_FIXED`  (commit `1a410977`) — the verifier said FIXED, but its quote is not in the text; read as NOT_FIXED

### 2026-10-04-documentation-review-01-093  The reproduction section announces three published files and then lists six, so the page contradicts itself.

Rule: `RULE.DOC.SELF_CONTAINED`.  
Reported by `withheld@validation`, decided by an agent.

The following shell block downloads and hashes six .h5 files (handoff, two constant-power, two linear, one rk4adaptive); the opening paragraph also speaks of 'both reference-data files'.

**Fix.** Say 'The six published files' and update the opening paragraph's 'both reference-data files' to match.

- `docs/src/validation.md`:218  (Validation — code-to-code comparison against TurTLE / Reproducing the comparison)

## Locations that could not be found again — 2

The text each of these named has changed since it was read. They are named rather than
pointed at whatever now sits on the old line, and no fix was attempted at any of them.

## Questions

### 2026-10-04-documentation-review-01-010-code

This finding needs a change only you may make. Will you make it?

Making the seeders' energy and envelope, the timestep of advance!/run!/warmup!, the stationary-state helpers' inputs and allocate_buffers' scalar flag positional changes the public API (code), or else needs a Switch in the config — either is the owner's decision.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
  RULE.ASK.NO_HOUSE_TERMS       context: a word of this package's own: switch
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-010-code "<option>"`

### 2026-10-04-documentation-review-01-006-code

This finding needs a change only you may make. Will you make it?

Moving the Heun and Adams–Bashforth update formulas from the generic advect! docstring into each scheme's own docstring moves mathematics between docstrings, which the change guard treats as a formula change.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-006-code "<option>"`

### 2026-10-04-documentation-review-01-004-code

This finding needs a change only you may make. Will you make it?

Writing the retained edge as kappa_max with the ret superscript, and the resolved edge as bare kappa_max (not res or eff), changes the symbols inside formulas in kinetic_energy, recommended_cfl, max_resolved_wavenumber and the validation page.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-004-code "<option>"`

### 2026-10-04-documentation-review-01-021-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-021-code "<option>"`

### 2026-10-04-documentation-review-01-034-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-034-code "<option>"`

### 2026-10-04-documentation-review-01-036-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-036-code "<option>"`

### 2026-10-04-documentation-review-01-041-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-041-code "<option>"`

### 2026-10-04-documentation-review-01-044-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-044-code "<option>"`

### 2026-10-04-documentation-review-01-058-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-058-code "<option>"`

### 2026-10-04-documentation-review-01-062-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-062-code "<option>"`

### 2026-10-04-documentation-review-01-079-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-079-code "<option>"`

### 2026-10-04-documentation-review-01-088-code

This finding needs a change only you may make. Will you make it?

Binding a symbol in words at its first use (for example: with k_band the energy in the forced band) needs a new one-symbol math span, which the change guard counts as changing mathematics.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-088-code "<option>"`

### 2026-10-04-documentation-review-01-023-code

This finding needs a change only you may make. Will you make it?

Already fixed: the four truncated inline references, including Sullivan, Nose and Hoover in the forcing docstrings, were restored by the commit for finding 008.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-023-code "<option>"`

### 2026-10-04-documentation-review-01-043-code

This finding needs a change only you may make. Will you make it?

Already fixed: the truncated Lalescu 2010 reference in the particle docstrings was restored by the commit for finding 008.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-043-code "<option>"`

### 2026-10-04-documentation-review-01-038-code

This finding needs a change only you may make. Will you make it?

A duplicate of finding 008 (same location and fix), already fixed by its commit.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-038-code "<option>"`

### 2026-10-04-documentation-review-01-093-code

This finding needs a change only you may make. Will you make it?

A duplicate of finding 003: its commit already gives the validation page's count of six published files.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-093-code "<option>"`

### 2026-10-04-documentation-review-01-073-code

This finding needs a change only you may make. Will you make it?

False positive: the Components entries on the index page are already a bulleted list, the second remedy the finding offers.

- **I make the change** (recommended) — the change is yours: the finding goes on your list, and the run leaves it
- **fix it on my ruling** — the fixer makes it as your --direction says; the finding is open again, and a verifier closes it
- **not a defect** — nothing changes, and the finding is closed

This question does not read as the rules ask:

```
  RULE.ASK.ONE_DECISION         decision: more than one sentence: This finding needs a change only you may make. Will you make it?
```

Answer with: `gbg answer 2026-10-04-documentation-review-01-073-code "<option>"`


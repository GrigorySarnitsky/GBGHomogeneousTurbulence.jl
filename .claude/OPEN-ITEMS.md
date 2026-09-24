# Open items — GBGIsotropicTurbulence

**RE-VERIFIED 2026-08-30** (three-agent sweep, every item checked against the current tree: git
history, promoted regressions in `test/regressions/`, current docs, the adjudication files). The
consolidated 2026-08-23 list below was written days before the fixes landed and was never ticked —
**of its 107 items, 91 are CLOSED, 12 SUPERSEDED (adjudicated / owner-ruled), 2 PARTIAL, 6 OPEN.**
Read the list below as HISTORY; the live remainder is exactly this:

## LIVE REMAINDER (2026-08-30)

Open — small, actionable:
- [ ] **G3** — the AbstractFFTs no-in-place-real-plan constraint is still unrecorded in the audit
      (the item's own proposed resolution: record it and state what the ledger therefore does not
      bound on the in-place-transform axis).
- [ ] **G4** *(upstream)* — the dead `ldiv!` forward buffer (stake now 1 scalar-equivalent after
      decisions 76/81; memory_audit.jl:311 cites it) and the redundant preserving copy; both PF /
      FFT-stack territory, listed "not requested" in the 2026-08-26 residency request.
- [ ] **B3-M17** — return-shape drift: plain tuple `(kinetic_energy, dissipation)` vs named tuples
      elsewhere; unifying touches `kinetic_energy_and_dissipation`'s API — owner call.
- [ ] **B3-M43** — the `\mathbf` ban is a PF-parity divergence never dispositioned; needs one
      recorded ruling (deliberate divergence, or raise to PF).
- [ ] **B4-N9** — Phenomenology field-naming drift: `Sreenivasan1998(asymptote, correction)` vs
      `Sreenivasan1995(C_K)`; owner-flavored naming call.
- [ ] **B4-N13** — no run-the-examples pipeline and no recorded deliberate-absence; needs a ruling
      or a task.

Partial:
- [ ] **B3-M26** — `stage1` still names different roles per scheme (now disclosed inline; no
      rename or recorded disposition).
- [ ] **B4-N7** — one unbraced `\,\mathrm dt` survives in ARCH §4.4 current text (history hits
      stay).

Science — the G law (owner-set first goal, decisions 94–95):
- [ ] **G-LAW-1** *(paper)* — the dissipation-group law must relate ε not only to the whole-field k
      but to the **forced band's own energy** k_band. `Linear`'s stationary rate is A = ε/(2 k_band),
      so it can take its rate from the run's state only once k_band(forcing, Re_λ, band) is modelled;
      until then `Linear(; rate)` stays required (owner-ruled 2026-09-24). Measure it alongside G.
- [ ] **G-LAW-2** *(later, a project in itself)* — the scalar side: a scalar forcing states its own
      target, because predicting ε_φ from ⟨φ²⟩ needs the mechanical-to-scalar time-scale ratio,
      unmeasured here. Left as is by owner ruling 2026-09-24.

Cosmetic residue found by the sweep:
- [ ] memory_audit.jl:27 comment still says "open item G2" (G2 is closed by decision 79).

Owner-decision section **E** remains open by nature (E1 Sc warn-vs-refuse, E8 the vorticity
formulation with its written plan, and the rest) — decisions, not tasks.

Everything else below is closed; per-item evidence lives in the 2026-08-30 sweep reports
(three agent reports, this session) — headline closers: 690ff52 (A-list, same day as the list),
6b00484 (attack round C + dismissals + D residue), 6a8193d (verify.js round), the 08-26/27 panel
fix commits, decisions 76–85.

---

## The consolidated 2026-08-23 list (HISTORICAL — see the sweep verdict above)

Everything open from every investigation, in one list.

**Sources:** `/bug-hunt` witnesses (re-verified by running them), the 2026-08-22 doc panel (both arms, 242 raw findings merged to 90), `attack-design.js` on the panel, `/audit-changes` round 2 residue, and decisions never taken.

**Not included:** anything already fixed and pushed. Every item below was open at the time of writing.


---

## A. Code defects — witness-confirmed, each fails a program

Re-verified 2026-08-22 by running every witness; the pile had gone stale on the renames and five of seven were reporting nothing. Witnesses live in `.claude/bug-hunt/witnesses/`.

- [ ] **A1** *(major)* `FlowConditions`'s documented positional constructor bypasses ALL THREE keyword guards  
      Shared mutable forcing, `viscosity > 0`, `schmidt > 0` — none fires on the positional form the docstring advertises. Witness `02-r5-aliasing-and-mutation-02`.

- [ ] **A2** *(major)* `step!` makes a fixed per-call host allocation — invariant 4 violation  
      1152 B for `IFLowStorageRK3`, 720 B for `IFRK2`, constant in N, with `NoForcing` and no tracers. Witness `r5-gpu-and-hot-loop-01`.

- [ ] **A3** *(major)* The κ=0 velocity mode is neither conserved nor damped  
      ⟨u×ω⟩ = 0 is not enforced, so a spurious uniform drift grows — 6% of u′ after 3000 Float32 steps. The only one that silently corrupts physics. Witness `01-r5-free-modules-01`.

- [ ] **A4** *(minor)* A mutable `StochasticOU` shared by two `Simulation`s couples their forcing state  
      `FlowConditions` guards this only within one build. Witness `r5-aliasing-and-mutation-01`.

- [ ] **A5** *(minor)* `deposit!`'s scalar-pairing guard is one-sided  
      Scalar state + scalar cache + scalar-free `IntegratorBuffers` dies as a `MethodError` inside the private `_recovery_scratch` instead of an `ArgumentError`. Witness `03-r5-free-hot-path-03`.


---

## B. Documentation findings — the 2026-08-22 panel

242 raw findings from both arms, merged to 90 unique. `hats` names every lane that found it — more than one is corroboration; `arms` = A (23-hat) / B (6-hat).


### B1. Blockers (5)

- [ ] **B1** Architecture says one trajectory scheme exists; AdamsBashforth is fully built and wired  
      `15 hats` · arms A+B · PAGE: architecture §4.6: "the trajectory scheme — today the single second-order `EndpointHeun`, with higher-or

- [ ] **B2** "Four strategies are provided" enumerates five  
      `11 hats` · arms A+B · PAGE: architecture §4.4: "Four strategies are provided. `NoForcing`... `Linear`... `ConstantPower`... `Varianc

- [ ] **B3** Module include order stated three different ways  
      `5 hats` · arms A+B · Architecture §4.9 'Layout summary': "SimulationDomain → Observables → State → Cache → Forcing → Generator → Pr

- [ ] **B4** `particles_modified!` says the run's own tracer advance both is and is not announced  
      `4 hats` · arms A+B · PAGE: api / Cache, `particles_modified!`: "The run's own tracer advance is not such a change and keeps its his

- [ ] **B5** ConstantPower's band-kernel storage contradicts itself across pages  
      `cold-reader` · arms A · PAGE api / Forcing, ConstantPower Fields: "band — the band-pass kernel, lazy: ... so no indicator array is sto


### B2. Major (26)

- [ ] **M1** Two different "eddy-turnover times" in one corpus — k/ε and 2k/3ε  
      `9 hats` · arms A+B · PAGE: api / Forcing, `VarianceController`: "the large-eddy turnover time $t_\ell$. When omitted it is taken as

- [ ] **M2** Three incompatible conventions for documenting a mutator's return value  
      `4 hats` · arms A+B · PAGE: api / Forcing — `set_forcing_rate!(...) -> rate`, `add_forcing_source!(...) -> N̂`, `project_forcing!(..

- [ ] **M3** observables_cache.md's content table/cost analysis omit the Lagrangian sample-history slots  
      `5 hats` · arms A+B · PAGE observables_cache §2.4: "The table below lists the observables of this system, one row each." (no history

- [ ] **M4** ObservablesCache's shown constructor signature omits its own documented history_depth keyword  
      `4 hats` · arms A+B · PAGE api/Cache: "ObservablesCache(domain; scalar = false, particle_velocities = nothing)"

- [ ] **M5** Which call completes the particle-velocity deposit  
      `3 hats` · arms A+B · Architecture §4.6: "record_particle_velocities! records the new sample at the new positions from the same depo

- [ ] **M6** The glossary defines "resolved" as reification; the architecture defines it as resolved-versus-filtered  
      `2 hats` · arms A+B · PAGE: notation, Vocabulary: "resolved | in ResolvedFields and ResolvedGenerator, made concrete as one value."

- [ ] **M7** `recommended_cfl` refers to "the same scaling" before the scaling is introduced  
      `2 hats` · arms A+B · PAGE: api / Propagator, `recommended_cfl`: "The same $1/\kappa_{\max}$ scaling is applied to both schemes' bas

- [ ] **M8** INCONSISTENT RULE PAIR: three incompatible mechanisms guard the PhaseShift displaced-velocity reuse  
      `2 hats` · arms A · PAGE: decisions, decision 56 — "`prepare!` opens every step with the mark cleared" / "not load-bearing for cor

- [ ] **M9** Module's own identity says "tracer" where the naming rule requires "particle"  
      `2 hats` · arms A · PAGE: Home, §Components — "`Particles`: Lagrangian tracer tracking — second-order advection and field sampling

- [ ] **M10** allocate_buffers documented with two methods; a three-argument call used elsewhere  
      `2 hats` · arms B · api/Propagator, allocate_buffers: shows only allocate_buffers(scheme, domain; scalar=false) -> IntegratorBuffe

- [ ] **M11** EQUIVOCATION: `ConstantPower`'s rate is re-solved "each step" and "at every stage" in one docstring  
      `2 hats` · arms A · PAGE: api / Forcing, `ConstantPower` — "whose rate $A$ is set each step so the field's injection rate holds th

- [ ] **M12** Same DOI, two different paper titles for the Lalescu et al. (2022) citation  
      `2 hats` · arms A · api / Particles, AdamsBashforth docstring: "Lalescu et al. 2022, TurTLE: a fast and scalable code for turbulen

- [ ] **M13** Phenomenology's roll-off-factor pieces are positional-only, contradicting the module's stated 'every preset is keyword' rule  
      `existence-auditor` · arms A · PAGE: api / phenomenology / Spectra, module docstring — "Every preset is a type with a keyword constructor, in

- [ ] **M14** energy_spectrum (measured) and EnergySpectrum (predicted) share a name for non-interchangeable objects  
      `naming-policy` · arms A · PAGE: api / Observables — 'What is returned is a per-shell energy E_n ... a model spectrum E(κ) from Phenomeno

- [ ] **M15** "chart" is given two incompatible identity conditions for vorticity  
      `conceptual-clarity` · arms A · PAGE: notation, §Vocabulary — "chart | a physical-representation view of the spectral state — the velocity, vo

- [ ] **M16** Subjectless sentence in `max_wavenumber`  
      `plain-sense` · arms B · PAGE: api / SimulationDomain, `max_wavenumber`: "For the two sharp strategies sits strictly below the grid Nyq

- [ ] **M17** UNFALSIFIABILITY: decision 40 re-admits the chart-liveness tautology decision 37 retired  
      `logician` · arms A · PAGE: decisions, decision 37 — "Extending those and then reporting the result as the bound made the physical-v

- [ ] **M18** Quick start: "drives k to that value" — "that value" has no antecedent  
      `plain-sense` · arms A · PAGE: Home, Quick start: "# (the default forcing drives k to that value —"

- [ ] **M19** Decision 46 states the include order backwards vs. §4.9, CLAUDE.md, and the actual source  
      `invariants-and-decisions` · arms A · ARCHITECTURE.md decision 46: "The include order becomes `State → Observables → Cache`"

- [ ] **M20** Front-page quick start: "that value" has no antecedent  
      `plain-sense` · arms B · PAGE: Home, "Quick start": "warmup!(sim)   # spin up to statistical stationarity … (the default forcing drives

- [ ] **M21** "One piece of prior art is excluded by name" — and no name follows  
      `plain-sense` · arms B · PAGE: architecture, §8 Lenses and prior art: "One piece of prior art is excluded by name."

- [ ] **M22** "epoch" used unglossed on the very first page of the site  
      `cold-reader` · arms A · PAGE Home, Quick start comment: "each recorded against the epoch of the state it came from."

- [ ] **M23** The Decision log page precedes the glossary that defines its own vocabulary  
      `cold-reader` · arms A · PAGE decisions (page 3): "epoch-dated, memoized charts," "the armed-rate pin," "a slot doubles as its producer

- [ ] **M24** Admonition-title rule: PF unconditional, IT conditional  
      `pf-parity` · arms A · IT CLAUDE.md Template conventions: 'stays a bare `!!! note` when it is a general aside'

- [ ] **M25** PF has a consent gate for expensive verification lanes; IT has none  
      `pf-parity` · arms A · PF CLAUDE.md: 'Consent gate (user-directed 2026-08-04) — unasked, run ONLY Pkg.test()'

- [ ] **M26** IT's type-docstring template is richer (constructor-first, Examples policy) than PF's minimal fields-only rule  
      `pf-parity` · arms A · PF CLAUDE.md: 'A type... documents them under `The fields are`... prose is reserved for the one-sentence ident


### B3. Minor (44)

- [ ] **M1** The glossary gives E_φ(κ) no code object, though `spectrum` evaluates it  
      `2 hats` · arms A+B · PAGE: notation, Diagnostics — "$E_\varphi(\kappa)$ | the scalar-variance spectrum … | —"

- [ ] **M2** L reused for the roll-off length, against its glossary binding as the box side  
      `2 hats` · arms A+B · PAGE: notation — Numerics: "$L$ | box side ($\Omega = [0,L)^3$)"

- [ ] **M3** Load-bearing caveat left as plain prose instead of an admonition; Returns trails it  
      `4 hats` · arms A+B · src/Cache.jl, fields_modified!: 'It also discards the Lagrangian sample history this cache carries… would blen

- [ ] **M4** Two measured CatmullRom interpolation floors that the stated Δx^(d+1) scaling cannot reconcile  
      `3 hats` · arms A+B · PAGE: api / Particles, EndpointHeun — "a degree-$d$ interpolant's trajectory floor falls as $\Delta x^{d+1}$ …

- [ ] **M5** The IFRK2-vs-RK3 register count does not decompose as the architecture claims  
      `2 hats` · arms A · PAGE: architecture §4.5: "three spectral registers per field against the low-storage scheme's two, counting th

- [ ] **M6** EQUIVOCATION: `set_forcing_rate!` is gated by linearity in one docstring and steadiness in its neighbours  
      `logician` · arms A · PAGE: api / Forcing, `set_forcing_rate!` — "For a strategy `forcing` linear in the field, fill the per-mode ra

- [ ] **M7** NON SEQUITUR: `Kolmogorov1941`'s order guard is justified by a universality its own bullet denies  
      `2 hats` · arms A · PAGE: api / phenomenology / StructureFunctions, `Kolmogorov1941` — "any other `order` throws an `ArgumentError

- [ ] **M8** FlowConditions and FlowParameters are a naming-collision risk the docs must explicitly defuse  
      `2 hats` · arms A · PAGE api/Generator, FlowConditions docstring: "Not to be confused with Phenomenology's FlowParameters, which s

- [ ] **M9** EQUIVOCATION: `Li2008` is an author-year handle for a fit the docstring says is not theirs  
      `2 hats` · arms A · PAGE: api / phenomenology / Scalings, `Li2008` — "The value is this package's own reduction of the Johns Hopki

- [ ] **M10** current_step used at the Cache page before its own definition  
      `2 hats` · arms A+B · PAGE api / Cache, ObservablesCache docstring: "the clock's current_step answers 'how far has the run gone?'"

- [ ] **M11** IT built a docstring-growth/shape lint; PF's build lints lack an equivalent despite the same bloat history  
      `pf-parity` · arms A · IT CLAUDE.md: 'lint_docstring_shape() fails on a docstring that grew since docstring_shape.csv was last writte

- [ ] **M12** Architecture run-on sentences: 110 words and five clauses in one breath  
      `plain-sense` · arms A · PAGE: architecture, §4.1: "Its concrete type is the `FixedDomain`, the fixed, unsheared cube, realized by the 

- [ ] **M13** u_consumed / ω_consumed name the argument for an implementation side effect, and inconsistently across siblings  
      `naming-policy` · arms A · PAGE: api / Generator — 'velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)'

- [ ] **M14** 'Uniform-mean-gradient scalar mixing' named as a built System with no visible implementing mechanism  
      `free-reader-a` · arms B · PAGE: architecture §3: "The System: … forced homogeneous isotropic turbulence, freely decaying turbulence, uni

- [ ] **M15** VACUOUS DISCRIMINATION: the `valid_Reλ` guard excludes nothing by default and no shipped consumer enforces it  
      `logician` · arms A · PAGE: api / phenomenology / Phenomenology, `Reference` — "`Reference(citation; valid_Reλ = (0.0, Inf))`"

- [ ] **M16** AdamsBashforth stores a field but has no # Fields section  
      `structure-consistency` · arms A · PAGE: api / Particles, `AdamsBashforth(; order = 4)` — docstring ends after the caveat and Reference line with

- [ ] **M17** Named-tuple return shape stated two different ways  
      `structure-consistency` · arms A · PAGE: api / Observables, `energy_spectrum` — dedicated closing sentence "Returns a named tuple `(; wavenumbers

- [ ] **M18** ModelSpectrum's Fields sentence duplicates its own top signature verbatim  
      `structure-consistency` · arms A · PAGE: api / phenomenology / Spectra, `ModelSpectrum(C_K, large_scale, dissipation)` shown as the sole top sign

- [ ] **M19** `IFLowStorageRK3` denies two symbol collisions it alone introduces  
      `plain-sense` · arms B · PAGE: api / Propagator, `IFLowStorageRK3`: "unrelated to the forcing rate $A(\boldsymbol{\kappa})$ of the `For

- [ ] **M20** particles_modified!(sim)'s effect on the particle scheme's own registers is asserted on one page, absent from its home docstring  
      `free-reader-b` · arms A · PAGE: api / Cache, particles_modified!: describes discarding the cache's own sample history and says the Simul

- [ ] **M21** The Sc = O(1) restriction is a load-bearing invariant absent from the architecture's own Invariants catalogue  
      `free-reader-b` · arms A · PAGE: api / SimulationRun, Simulation's schmidt argument: 'This package targets Sc = O(1) and carries no Batch

- [ ] **M22** VarianceRescaling summarized as holding "a band's amplitude", which over = :total does not do  
      `turbulence-theoretician` · arms A · PAGE: api / Forcing, module map — "`VarianceRescaling` — hold a band's amplitude by deterministic rescaling, a

- [ ] **M23** VarianceRescaling's `over` keyword is explained twice at different granularities  
      `structure-consistency` · arms A · PAGE: api / Forcing, `VarianceRescaling` — full bulleted `:band`/`:total` breakdown in prose before Arguments,

- [ ] **M24** Three house-reserved glyphs (ε, L, T) reused, undisclosed, in one admonition  
      `latex-typesetter` · arms A · src/Particles.jl:321-325 — "for a perturbation ``\epsilon`` and Lipschitz constant ``L``, Grönwall bounds the 

- [ ] **M25** Named methods (Nosé–Hoover; 'Kaneda's' result) invoked with no citation  
      `citations-integrity` · arms A · api / Forcing, VarianceController docstring: "is the Nosé–Hoover move. A gain-limited relaxation ... is Berend

- [ ] **M26** IntegratorBuffers.stage1 denotes different objects per scheme  
      `naming-policy` · arms A · PAGE: api / Propagator — '`stage1` — the first Runge–Kutta stage register, allocated by every scheme (the accu

- [ ] **M27** kinetic_energy names both a measuring function and a configured target  
      `naming-policy` · arms A · PAGE: api / Observables — 'kinetic_energy(u) / kinetic_energy(û) — The turbulent kinetic energy ... of the vel

- [ ] **M28** Caveat admonition is not the docstring's last substantive block  
      `doc-policy` · arms A · src/Observables.jl, derivative_skewness: after `!!! note "This is the run's largest transient allocation"`, a 

- [ ] **M29** The same staleness recurs on the Home and api-overview pages  
      `software-architect` · arms A · PAGE Home, Components: "second-order advection and field sampling along trajectories"

- [ ] **M30** IFRK2's CFL margin is an unguarded, Reynolds-number-blind constant  
      `dns-practitioner` · arms A · PAGE: api / Propagator, recommended_cfl: "its 0.25 is an empirical margin rather than a computed limit... The 

- [ ] **M31** Obukhov's (1962) co-discovery of Kolmogorov1962 cited inline but absent from the page's References list  
      `citations-integrity` · arms A · api / phenomenology / StructureFunctions, Kolmogorov1962 docstring: "proposed independently by Obukhov (1962, 

- [ ] **M32** Subject-verb disagreement: "Bassenne report O(1-10)"  
      `style-editor` · arms A · api/Forcing, VarianceController Arguments: "Larger relaxes faster; Bassenne report $O(1-10)$." (verified in do

- [ ] **M33** Three different "no DOI" formats inside Phenomenology's own reference lists  
      `style-editor` · arms A · StructureFunctions References: "...30, 301–305 (the 2/3 law) and 32, 16–18 (the exact 4/5 law); no DOI, the 19

- [ ] **M34** Phenomenology's page-level References sections use the labelled DOI link form, not the bare-autolink form assigned to a References surface  
      `style-editor` · arms A · decisions page (carries ARCHITECTURE's Sec-References): renders as bare autolink, link text = the URL itself, 

- [ ] **M35** Top-level Observables summaries omit max_speed  
      `cold-reader` · arms A · PAGE Home, Observables bullet lists diagnostics, skewness, spectrum scales, vorticity recovery — no max_speed.

- [ ] **M36** Three names in circulation for one cached quantity  
      `naming-policy` · arms A · PAGE: api / Particles — 'the trajectory velocities are read from the run's observables cache through particle_

- [ ] **M37** The longitudinal integral scale wears two glyphs, L11 and ℓ11  
      `turbulence-theoretician` · arms B · PAGE: notation, Derived scales — "$L_{11}$ | longitudinal (parallel) integral length scale"

- [ ] **M38** `DeferredForcing`'s example is introduced by editorial housekeeping  
      `plain-sense` · arms B · PAGE: api / Forcing, `DeferredForcing` → Examples: "The two-form construction is the non-obvious part of this 

- [ ] **M39** "close" spans two nested scopes (step vs. iteration) without signposting  
      `conceptual-clarity` · arms A · PAGE: api / Generator — "finalize! — close a step: apply the post-step forcing projections to the advanced sta

- [ ] **M40** Citation link form: PF one titled form everywhere; IT two different forms by surface  
      `pf-parity` · arms A · PF CLAUDE.md: 'Every reference carries a clickable DOI on its title — [*Title*](https://doi.org/…)... verbatim

- [ ] **M41** PF codifies an author-count truncation rule for citations; IT's rulebook never states one  
      `pf-parity` · arms A · PF CLAUDE.md: 'Name up to three authors... four or more → First et al.'

- [ ] **M42** Citation placement: PF places it last in the docstring template, IT lets it open the identity sentence  
      `pf-parity` · arms A · PF CLAUDE.md: citation is order-item (6) of 7, after the formula, before cross-links

- [ ] **M43** IT bans \mathbf outright (build-enforced); PF has no such ban and uses it deliberately  
      `pf-parity` · arms A · IT CLAUDE.md: 'never upright \mathbf (build-enforced)'

- [ ] **M44** `fit` restates its own first sentence  
      `plain-sense` · arms B · PAGE: api / phenomenology / Phenomenology, `fit`: "No methods are defined yet; it is the recorded extension po


### B4. Nits (15)

- [ ] **N1** The "resolution bound" on Δt is a lowest-mode diffusive-decay cap  
      `dimensional` · arms A · PAGE: api / SimulationRun — Simulation, max_dt: "a resolution bound $1/(D\kappa_{\min}^{2})$ built from the ru

- [ ] **N2** A few caveats read as continuous prose rather than a titled aside  
      `structure-consistency` · arms A · PAGE: api / SimulationDomain, `FixedDomain` — "Nothing here defaults: …" placed like a caveat before # Fields 

- [ ] **N3** Elliptical "Larger relaxes faster" compounds the awkwardness of the adjacent grammar slip  
      `style-editor` · arms A · api/Forcing, VarianceController Arguments: 'Larger relaxes faster; Bassenne report O(1-10).'

- [ ] **N4** "band" used repeatedly before any definition of the concept  
      `cold-reader` · arms A · PAGE api / Forcing, module map: "Linear — a fixed linear rate on a band." (first use, undefined)

- [ ] **N5** VarianceController's default gain=1 sits at the low edge of its own cited O(1-10) range with no stated reason  
      `free-reader-b` · arms B · PAGE: api / Forcing, `VarianceController` Arguments: "gain = 1 — the dimensionless gain G. Larger relaxes fast

- [ ] **N6** `ScalingLaw`: a trailing modifier with nothing to modify  
      `plain-sense` · arms B · PAGE: api / phenomenology / Scalings, `ScalingLaw`: "— here the normalized dissipation $C_\varepsilon$, the Ko

- [ ] **N7** \mathrm d bracing drifts across the corpus for the identical differential  
      `latex-typesetter` · arms A · src/Forcing.jl:197 — ``\int A\,\mathrm dt`` (unbraced)

- [ ] **N8** Delimiter sizing for the Lamb-vector gradient term is not applied by one rule  
      `latex-typesetter` · arms A · src/Generator.jl:417 (display math) — ``\nabla\bigl(\tfrac{1}{2}\lvert\boldsymbol{u}\rvert^{2}\bigr)`` (sized)

- [ ] **N9** Sreenivasan1998's fields break from the symbol-naming convention its siblings use  
      `naming-policy` · arms A · PAGE: api / phenomenology / Scalings — 'Sreenivasan1998(; asymptote = 0.5, correction = 0.0)' vs. 'Sreenivasan

- [ ] **N10** A parenthetical that concedes three names for one quantity  
      `plain-sense` · arms A · PAGE: api / Particles, module map: "the same quantity the docs also call the Lagrangian velocity or the trajec

- [ ] **N11** "Front door" is a software/business idiom promoted to formal glossary vocabulary  
      `naming-policy` · arms A · PAGE: notation (Vocabulary) — 'front door | the Simulation constructor that builds every component from a few 

- [ ] **N12** IT's TeX-idiom block credits PF wholesale but adds a \mid rule PF's own list lacks  
      `pf-parity` · arms A · IT CLAUDE.md: '(adopted from PF 2026-08-06...); a conditional bar is \mid'

- [ ] **N13** PF has a documented examples/ pipeline and a 'run the examples' definition-of-done item; IT has neither  
      `pf-parity` · arms A · PF CLAUDE.md: extensive examples/ Literate-doc-page rules + 'Definition of done' item 6 'The examples, RUN'

- [ ] **N14** IT's 'Known weaknesses — self-guards' section has no PF counterpart  
      `pf-parity` · arms A · IT CLAUDE.md: four-item 'Known weaknesses — self-guards' section

- [ ] **N15** IT's 'Template conventions' is a consolidated checkable-rules list; PF's equivalent material is scattered and missing two discriminators  
      `pf-parity` · arms A · IT CLAUDE.md: 'Template conventions, stated so the split is checkable' — eight bullets including Returns x. an


---

## C. Instrument gaps — `attack-design.js` on the panel

13 open. The 3 fatal are closed (two were the same defect; one was reverted as wrongly-dispositioned).

- [x] **C1** *(serious, logician)* THE SPACE IS MISDEFINED AS "defects IN the text". Every one of the 23 lanes is a predicate evaluated on tokens that are PRESENT in some substrate. The instrument has exactly two absence-detectors, and…  
      → A REQUIRED-CONTENT lane, seeded not by the corpus but by the domain: a DNS reviewer handed a checklist of the constraints any such solver's documentation must state (reso

- [x] **C2** *(serious, logician)* NO LANE HOLDS THE PREDICATE "this docstring describes what the function does". The instrument's cover relation is text-against-text: docs vs docs (3, 5, 6, 13, 14, 15), docs vs the rulebook (19, 20, 2…  
      → A DOC-VERSUS-BODY lane whose unit of work is one docstring and the function body directly beneath it, read together, with one question: does the body do only and exactly 

- [x] **C3** *(serious, logician)* NO LANE COMPOSES. Every lens is a predicate on one item — a formula, a name, a docstring, an entity's cross-page versions. The only lane that reads a SEQUENCE is hat 13, and its route is fixed in adva…  
      → A CONJUNCTION lane that takes as its unit a PAIR: every caveat, admonition and stated limitation, crossed against the option set / argument domain the API makes reachable

- [x] **C4** *(worth-fixing, logician)* DUAL NOT COVERED — SURVIVING TEXT vs UNSURVIVED TEXT, and the one-directional argument check. Hat 22 detects text that OUTLIVED its referent ("git grep the OLD name"); nothing detects a referent that …  
      → A SIGNATURE-FIDELITY check, mechanical enough to belong in the /check-docs battery rather than the panel: parse each docstring's displayed signature, reflect on the actua

- [x] **C5** *(serious, philosopher)* THE STATUS QUO IS MADE NORMATIVE, AND NOTHING EXTERNAL ADJUDICATES. Two lanes are instructed to derive the standard from the corpus: hat 16 — "derive the norm from the corpus itself (majority style), …  
      → Two changes. (1) Give hats 11 and 16 a direction rule: a divergence is reported as a divergence, and the lane is FORBIDDEN to name the majority as the norm — the resoluti

- [x] **C6** *(serious, philosopher)* "JUSTIFIED" IS INDEXED TO THE AUTHOR'S RECORDED RATIONALE, NOT TO THE READER'S ABILITY TO CHECK — and recording a decision immunizes it. Hat 7 is chartered to report MISSING-MEMBER; hat 21 is simultan…  
      → A STANDPOINT lane: for each public keyword and each returned diagnostic, ask only "what could the reader set or read here that yields a WRONG NUMBER with no error, no war

- [x] **C7** *(serious, philosopher)* THE PANEL HAS NO DENOMINATOR, SO ITS OUTPUT IS EVIDENCE OF YIELD AND IS USED AS EVIDENCE OF COVERAGE. Nothing in the design measures recall. There is no held-out set, no seeded-defect calibration, no …  
      → No lens — this needs a different mechanism. (1) SEEDED-DEFECT CALIBRATION: before each round, inject k known defects of each named class into the rendered corpus, run the

- [x] **C8** *(serious, counterexample)* THE ADVERTISED SIGNATURE IS NEVER CHECKED AGAINST THE DEFINED ONE. Two lanes touch arguments (13 api-user, 20 doc-policy) and both traverse the same single direction — signature line → documented bull…  
      → No new READING lane — this one is fully mechanical and belongs in `/check-docs`, not in a judgement panel: parse each docstring's signature line, parse the corresponding 

- [x] **C9** *(worth-fixing, counterexample)* A COMPOSED IDENTITY THAT NO SINGLE PAGE STATES AND NO LANE TESTS. The consistency-matrix hat — the panel's declared spine — builds a matrix of each recurring ENTITY and diffs the versions of THAT enti…  
      → No lens — this needs a different mechanism. A reading hat cannot reliably form and test derived identities across docstrings; the check is executable. The package already

- [ ] **C10** *(serious, measurement)* Severity and confidence are asserted exactly once, by the same interested agent that produced the finding, are explicitly shielded from override at the one human-facing stage ('a severity in the summa…  
      → Add a blind severity-recalibration pass, structurally identical to rubric_audit's blind-run design: sample N banked findings, strip the hat's self-assigned severity, show

- [x] **C11** *(serious, measurement)* The per-hat 25-finding cap has no accompanying signal of how much was cut, so a hat that legitimately found far more defects than the cap silently discards the tail with zero trace -- one stage before…  
      → Extend the panel SCHEMA with a required `candidates_considered: integer` (or `truncated: boolean`) field, mirroring the `findings_in_file` self-report already used downst

- [x] **C12** *(worth-fixing, measurement)* The summary's stated ranking heuristic ('severity x corroboration -- a defect found by many hats is a strong signal') structurally discounts source-grounded defects, because only a small minority of t…  
      → Weight corroboration by the substrate-exposure denominator, not the raw panel size -- e.g. report corroboration as 'k of n hats that could plausibly see this class' (rend

- [x] **C13** *(serious, measurement)* The panel's false-negative rate is fundamentally unmeasured on any recurring basis: the one instrument built to estimate rubric recall is bounded to a frozen, historical set of already-human-discovere…  
      → Seeded-defect (mutation-testing) injection, run every round rather than once: before each panel round, inject N deliberately fabricated, categorized, ground-truth-labeled


---

## D. `/audit-changes` round-2 residue

- [x] **D1** The compute-audit's new guard is satisfiable by any wrong number  
      `_forcing_pass_delta(tag) != _forcing_pass_delta(:ou)` proves only that a tag is modelled, not that its cell is right.

- [x] **D2** A recorded 'verified' claim has no persisted witness  
      The controller converging from k₀ = 2.6 → 1.5 is asserted in a commit message; only its mirror (k₀ = 0.4) is tested.

- [x] **D3** Decision 39's residency claim may have been falsified and left standing  
      Flagged by the audit, never verified either way.

- [x] **D4** The round-2 notable/minor tier was triaged, not swept  
      ~30 items read and classified; only the distinct classes were closed.


---

## E. Decisions — yours, not mine

- [ ] **E1** Should `schmidt` be guarded, or only documented?  
      Grid mode resolves the velocity; at Sc > 1 the scalar is under-resolved by √Sc. Now documented with the remedy. Whether the API should warn or refuse above some value is an API decision I did not take.

- [x] **E2** ~~`VarianceController` refuses `gain = 0`~~ — **stale premise; closed 2026-08-26**  
      The first branch was taken in the code and the item was never ticked. `gain = 0` is
      *allowed* — `Forcing.jl:676` guards `isfinite(gain) && gain >= 0` — and documented as the
      bare marginal law together with its physics: exact reinjection of the instantaneous
      ``\varepsilon`` makes ``\mathrm{d}k/\mathrm{d}t = 0``, so ``k`` is conserved at its initial
      value, `target` never enters the rate, every level is a *neutral* equilibrium, and the
      uncorrected integration bias (~1% of ``k`` per 1000 steps at ``24^3``/`Float64`) is stated as
      the caveat rather than left implicit. Decision 77's scalar-binding refusal is gain-scoped for
      exactly this reason.

      Pinned in both directions, so the resolution is verified rather than asserted:
      `test/forcing.jl:312` ("gain = 0 is the marginal law: k conserved, and NEVER restored") and
      `test/regressions/r6-controller-restores-from-above.jl` for the restoring branch. Confirmed
      by construction on 2026-08-26 rather than by reading — `VarianceController(target = 1.0,
      gain = 0)` builds through the `DeferredForcing` form and reaches `FlowConditions` intact,
      with `turnover_time_derived = true` and the decision-77 guard correctly standing down.

      **The finding is the bookkeeping gap, not the code**: a decision item that outlived its own
      resolution by an unknown number of rounds, and would have been read as an open question by
      anyone consulting this list. Surfaced only because a run's commented-out `scalar_forcing`
      line happened to use `gain = 0` and I checked it against the source instead of trusting the
      list.

- [ ] **E3** `viscosity > 0` forecloses the inviscid (Euler) limit  
      Long-standing, never decided. Deliberate, or should Euler be reachable?

- [ ] **E4** The 21 grandfathered over-cap paragraphs  
      Enumerated in `SHAPE_CAP_GRANDFATHERED`; the list may only shrink. Work the debt down, or leave it as a ratchet?

- [ ] **E5** The 14 non-`core` panel hats  
      They re-enter by repeating across runs. Do you want a second paired run to settle them, or leave them opt-in?

- [ ] **E6** Demonstrated validation numbers in the docs  
      Owner 2026-08-25: planned once the package is somewhat ready to ship. The 16-row checklist from the HIT-validation report is the template; needs runs, not edits.

- [ ] **E7** Reconsider the module-map divergence from PF in detail  
      The "deliberately tighter, list-first" clause was ratified 2026-08-25, with a standing todo: study whether any IT module map would benefit from PF's scope-and-invariants preamble, and either confirm the tighter rule or adopt PF's shape.


---

## F. Unfinished instrument work

- [ ] **F1** `verify.js` has never run  
      The manifest emission is now proven; the reading half is untested code.

- [x] **F2** `dismissals.js` has never been executed  
      Every NOT-REPRODUCED verdict any `/bug-hunt` round made is unaudited.

- [x] **F3** A `core` panel run has not been done since the profile landed  
      Confirms the profile behaves and gives the second data point admission needs.


---

## G. GPU residency — measured 2026-08-25 on CUDA

First real CUDA runs of the package (Enteropia, RTX 5070 Ti, Float32, `TwoThirds`, 128³ and 256³,
`warmup!` to 10 turnovers). The physics scaled exactly (ν ∝ N^{-4/3} and Re_λ ∝ N^{2/3} to six and
five digits) and the wall-clock ratio sat where an N⁴log N estimate puts it. Memory did not.

- [x] **G1** *(major, footprint)* ~~`tensor_plans` is built eagerly~~ — **FIXED 2026-08-26 (decision 78), then the whole cost class DELETED 2026-08-28**: PF's decision 76 made the plans rank-blind, and IT's decision 81 consolidated to ONE pair — per-plan buffers are now two component-sized arrays total, whatever fields a run transforms. Decision 78's lazy memo is retired.
      Lazy `tensor_plans` accessor + memo cell on `FixedDomain`, and `gate_skewness` now defaults to
      `false` so the default warm-up no longer builds them. `test/simulation_run.jl` asserts both
      that nothing is built until asked and that asking twice builds once. Original finding below.

      `tensor_plans` was built eagerly and cost ~1.16 GiB of device
      residency at 256³ for a diagnostic a run may never call
      Every transform plan carries **two field-sized device arrays of its own** — CUDA.jl's
      `plan_rfft` allocates a full spectral-sized `CuArray` and `plan_brfft` a full physical-sized
      one, because an out-of-place c2r always overwrites its input, so `mul!` copies first. IT
      builds one pair per plan component: velocity 3 + scalar 1 + **tensor 9** = 13.

      `tensor_plans` is 9 of the 13, and has exactly one consumer — the strain-tensor diagnostic at
      `Observables.jl:344`. Build it lazily (or per-call, matching invariant 4's "per-call
      allocation of an *occasional* diagnostic over resident scratch") and ~69% of the overhead
      goes: ~145 MiB at 128³, ~1.16 GiB at 256³, ~486 MiB on the 192³ `PhaseShift` run — about a
      third of that run's whole pool, roughly the size of its entire evolving state.

      The prediction 13 × (one spectral scalar + one physical scalar) holds to better than 1% on
      every configuration measured — 128³/256³ `TwoThirds` F32, 192³ `PhaseShift` F32 and F64, and
      ROCm matching CUDA to the displayed digit. So the sizing is solid and the mechanism is now
      read from the allocation site rather than inferred.

- [ ] **G2** *(serious, instrument)* The memory audit has never been run on the backend the package
      targets, so a whole class of allocation is unmeasured by construction
      Decision 36's completeness invariant requires the working-set and frame ledgers to account for
      every field-scale array a live `Simulation` can reach. **The gap is not one of reach.**
      `collect_field_arrays!` recurses through any struct's `fieldnames`, and the path
      `FieldTransformPlans → :plan_inverse_fft → ScaledPlan → :p → CuFFTPlan → :buffer` is plain
      struct fields ending in a `CuArray`, which is an `AbstractArray` of field scale. The walk
      would find all 26.

      The gap is one of **backend**: every domain the audit builds passes `array_type = Array`
      (`memory_audit.jl:324`, `:353`, `:425`, `:527`). On CPU an FFTW plan's `:plan` field is an
      opaque `PlanPtr` holding no Julia array, so the walk correctly finds nothing and the frame
      ledger correctly reads all zero. A true statement about the CPU backend has been standing in
      for a statement about the package — whose stated primary target is the GPU, and on which a
      class of allocation comparable to the whole working set lives.

      So "fix it" does not mean teaching the walk to descend. It means running the ledgers where the
      class exists, which raises the question the item has to settle: a GPU-gated audit cannot run
      in CI without a card, so where does a backend-conditional ledger live, and what does the CPU
      suite assert in its absence?

      (An earlier version of this item said the buffers were "outside it by construction" because
      the walk follows Julia fields. That was wrong, and wrong in the direction that made the audit
      look better than it is: an unreachable exclusion is a limitation, an unrun backend is a blind
      spot.)

- [ ] **G4** *(upstream; stake reduced 2026-08-28)* Two independent defects in the GPU plan buffers, both measured — **A's stake fell from 868 MiB to ~65 MiB at 384³/F32** with decisions 76/81 (one rank-blind pair: the dead forward buffer is now a single component-sized array). B (the double preserving copy) is unchanged in kind; its buffer is smaller too.
      **A — half the buffers are allocated and never used.** `plan_rfft` allocates a spectral-sized
      buffer whose only consumer is `ldiv!` (CUDA.jl says so in a comment at the allocation site).
      PF never calls `ldiv!` on a plan; it drives both directions through `mul!`. A sentinel test on
      the card confirms it: fill both plan buffers with a marker, run a forward transform and then
      an inverse — **the forward plan's buffer survives both untouched**, the inverse plan's does
      not. So 13 of the 26 spectral fields are dead weight; after decision 78 removed the rank-2
      family, 4 of the remaining 8 are — **868 MiB at ``384³``/Float32**.

      **B — the source-preserving copy is redundant on GPU.** PF's four-argument `to_physical!`
      copies the spectral field into scratch so the source survives, then calls `mul!`, which copies
      *again* into the plan's buffer. Measured on the card: the **three**-argument form — the one PF
      documents as consuming its source — **preserves it on CUDA and destroys it on CPU**. So on GPU
      the extra copy buys a guarantee the backend already provides. Cost: **14.7%** of
      inverse-transform time (48.5 ms vs 42.3 ms for 200 inverse transforms at ``128³``/Float32),
      and IT uses the four-argument form at 9 of its 11 `to_physical!` call sites — essentially
      every one in the hot loop.

      Both are upstream of IT. **A** is a small, well-defined CUDA.jl/AMDGPU.jl change: allocate the
      forward plan's buffer lazily, on first `ldiv!`. **B** is the harder one, and the tempting fix
      is the wrong one: PF must *not* simply skip its copy on GPU, because that would depend on an
      implementation detail — the day a backend fixes **A** by making buffers lazy, or optimizes the
      copy away, PF's assumption silently corrupts state. It needs either a declared trait
      (`preserves_input(plan)`) that changes when the backend changes, or the real fix: a transform
      path that is *permitted* to destroy its input, which removes the buffer and the copy together
      and needs no trait at all.

      AMDGPU.jl's `fft.jl` is the same design line for line (`ROCArray{complex(T)}(undef, ydims)`,
      `ROCArray{T}(undef, size(X))`, `z = p.buffer; copyto!(z, x)`), so a fix has one shape for both
      backends. What is **not** verified: whether AMDGPU's `mul!` preserves in practice — the source
      says it copies, but no AMD card was available to run the sentinel. Any trait-based fix must
      test it there before claiming it.

- [ ] **G3** *(serious, instrument)* The memory audit's shape classes presuppose out-of-place
      transforms, so a whole memory axis is outside what it can bound
      The working-set ledger decomposes into `spectral_vector` / `physical_vector` /
      `spectral_scalar` / `physical_scalar` / `real_spectral_scalar` and bounds each against
      liveness. That decomposition is only meaningful if a field's two representations occupy
      **different storage**. hit3d (`fields(nx+2,ny,nz,n)`, `m_fields.f90:21`) and TurTLE
      (`&buffer[0]` on both plan arguments, `cpp/fft/fftw.hpp:196–216`) transform **in place**: one
      padded real array *is* both representations. Under that formulation the count is over slots,
      not over physical-slots-plus-spectral-slots, and the audit has no class in which to express
      it — so it reports every cell AT bound while an entire design axis goes unmeasured.

      This is structurally the same failure as the per-plan buffers (G2): a real memory axis lying
      outside the instrument, with the instrument certifying optimality regardless. Two in one
      week. The pattern is worth naming rather than patching twice — **what else does the shape
      decomposition assume?**

      Not a defect to fix by rewriting: **AbstractFFTs' interface has no in-place real plan**, and
      both backends follow it — FFTW.jl exposes `plan_fft!` / `plan_bfft!` / `plan_dct!` /
      `plan_idct!` and no `plan_rfft!` or `plan_irfft!`; CUDA.jl imports only the complex in-place
      plans and hardcodes `inplace = false` in its `plan_rfft` (`fft.jl:274`), though its
      `CuFFTPlan` type carries an `inplace` parameter, so the machinery exists and is simply unused
      for real transforms. (Checked 2026-08-26 in both installed sources, after an earlier version
      of this item wrongly blamed FFTW.jl alone.) IT is therefore out-of-place by ecosystem
      constraint, and PF's physical/spectral *type* split is the discipline that makes the
      field-vs-representation rule enforceable. The honest resolution is probably to **record that
      constraint in the audit and state what the ledger therefore does not bound** — the same
      treatment the per-plan buffers' named exclusion gets — rather than to claim a completeness
      the classes cannot deliver.

      Sizing, so the priority is visible: at 192³ / `PhaseShift` / Float32 the four physical
      vectors are 324.0 MiB of a 733.2 MiB ledger — that is the *ceiling* on what in-place could
      recover, and only if every physical slot merged. The eagerly-built `tensor_plans` alone is
      ~486 MiB on the same run. **G1 is worth more than in-place would be, at a fraction of the
      cost.**

- [ ] **E8** *(future feature, owner-flagged 2026-08-28)* A vorticity formulation beside the velocity one
      Add, not swap: a second resolved representation — ``\hat{\omega}`` the state, ``u`` recovered by
      inverse curl, RHS the curl of the Lamb vector, Leray deleted, same integrating factors. The
      architecture admits it additively because the schemes are protocol-driven, the cache is
      formulation-blind, and the linear band forcings commute with the curl (only their band-energy
      observable changes, to ``\tfrac{1}{2}\sum|\hat{\omega}|^2/\kappa^2``).

      Ordered plan when taken up:
      1. THE PREREQUISITE REFACTOR — move the stage-recovery direction behind the generator protocol
         (today `step!` and `deposit!` hard-code `to_physical!(u, û, …)` / `vorticity_physical!(ω, û, …)`).
         Behaviour-preserving for the velocity path; verify BIT-IDENTICAL, stage by stage, as the
         2026-07 ResolvedGenerator migration was.
      2. A second state record (`vorticity_spectral` — not a reused field name) + a vorticity
         generator on the same six verbs.
      3. Forcing energy observables in ω̂ variables; ε from the state's own norm; E(κ) with the
         1/κ² weighting; checkpoint formulation tag (cross-formulation restart is free via
         curl/inverse-curl); audit op lists gain the axis (transform counts identical, curl ↔
         inverse curl, Leray deleted against a curl added).
      4. TWO DECISIONS, not code: the κ=0 mode (unrepresentable in ω̂-form — pins A3's mean-drift
         defect by construction, but the formulations then differ on exactly that mode and the
         comparison tests must say so); and whether PF's exports already express the solenoidal
         inverse curl as a composition — EXPAND against current exports before raising a gap.

      Estimate: a focused week, the bit-identical step-1 verification as the safety rail. Payoff
      beyond TurTLE parity: IT-velocity vs IT-vorticity, same FFTs/forcing/everything, is a
      self-validation axis where any disagreement is a bug with all else controlled.

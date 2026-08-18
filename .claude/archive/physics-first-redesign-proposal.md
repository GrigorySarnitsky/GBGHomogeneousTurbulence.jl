# Physics-first redesign — nine-lens panel synthesis

> A 9-lens debate (Mori–Zwanzig · category theory · metriplectic/GENERIC · Hamiltonian/Arnold · symmetry/representation · Lagrangian · kinetic-PDF · ergodic · continuum) → cross-rebuttal → 3 critics → synthesis. 22 agents, 0 errors, ~1.29M subagent tokens. **Proposal only — no src/ touched.**

## Organizing spine

A layered Mori–Zwanzig spine, set inside the codebase's own recorded specification × realization frame (§3, decision 7), with symmetry as the interior justification and ergodicity as the run-layer reading. Three altitudes, not three rivals: (1) the MZ triad — State / Generator / Observables — names the top-level PHYSICS roles a physicist reasons about (already latent: Dynamics.jl:3 calls its RHS "the generator of the full dynamics", Observables.jl:2 calls itself "the observables"), and gives the missing state a home; (2) the SYSTEM (Re via ν, Sc, forcing) is the §3 specification held fixed under method-independence, so it lives with the Generator that its coefficients define, upstream of the numerics; (3) symmetry supplies the Generator's interior (homogeneity = the translation-irrep basis, so −∇² is diagonal and, by Schur, the viscous integrating factor is an EXACT per-mode multiplier), and ergodicity supplies the run layer's intent (warmup! is relaxation onto the attractor; streaming-stats-with-no-snapshots is legitimate only because time-average = ensemble-average). Infrastructure keeps job-names (decision 16). Two decisive rulings: the state is REIFIED as a bare inert record while the morphisms stay primary (reify the carrier, hang no methods on it); and the reversible/irreversible generator split stays an INTERIOR seam (a function boundary + comment), never a module wall — verified against Dynamics.jl:111, where a linear FORCING rate is folded into the very exp() a metriplectic reading would label "irreversible dissipation", so that boundary tracks the numerical stiff/non-stiff partition, not entropy production. GENERIC is read through MZ, exactly as decision 8 records.

## Module map (the physics-first carving)

### FlowState (NEW)

The resolved phase point as one first-class, INERT data record: the spectral velocity û and the optional spectral scalar φ̂ (the primary truth), their cached physical chart (the current physical u and vorticity ω that the flux assembly and the diagnostics read), and the clock (time, step). Its constructors are the initial-condition draws random_solenoidal_velocity! (divergence-free velocity) and random_scalar! (mean-zero φ), which seed the initial phase point from a spectral envelope. No methods hang on it; every verb is an external morphism (step!(state, …) mutates it in place but does not belong to it).

**Why (physics):** In the Mori–Zwanzig reading the state is the carrier the whole formalism is written on — the generator flows it, the observables are functions of it, the run samples it — so it cannot be a byproduct of the machinery. Today it is genuinely scattered: û/φ̂ sit in the Simulation struct (SimulationRun.jl:110-111) while kinetic_energy(sim) reads buffers.velocity and dissipation(sim) reads buffers.vorticity_start out of FieldBuffers (SimulationRun.jl:192-193). Reifying it as a bare record de-conflates the cached physical face (state) from the RK registers (scratch) and gives the physicist and the diagnostics one thing to call 'the field now', while keeping the arrows primary.

**Re-carves:** The state scattered across the Simulation struct (û, φ̂), the state-caching slots of FieldBuffers (velocity, vorticity_start), and the initial-condition routines of the SimulationState module.

### SimulationDomain (KEEP name; module renamed from SimulationState)

The discretized triple-periodic box and its spectral realization: the Grid3D, the real-to-complex transform plans (velocity, scalar, and the rank-2 strain tensor of the skewness diagnostic), the wavenumber multipliers iκ, the squared-wavenumber field |κ|² (the symbol of −∇²), the de-alias kernel, and the pluggable DealiasingStrategy (TwoThirds / HouLi). Precision (Float32/Float64) and backend (Array/CuArray/ROCArray) enter here and flow everywhere by similar.

**Why (physics):** This is the flow's frame — the concrete box the run lives on (§4.1) — named by its job, per the rule that physics concerns take MZ names and infrastructure is named by what it is. It is deliberately NOT renamed to a projection / phase-space / symmetry-basis: those over-theorize the most-navigated object (the cold-read and smell-hunter both reject the renames). Its docstring should instead RECORD the symmetry that makes spectral the right chart: the plane waves e^{iκ·x} are the characters of the translation group, so −∇² is diagonal here and, by Schur's lemma, the integrating factor is an exact per-mode multiplier — symmetry as interior justification, not as the module name.

**Re-carves:** The domain, allocators, and dealiasing strategies of the SimulationState module; the module takes the name of its central object, shedding the FieldBuffers and initial-condition contents that misled the 'State' name.

### Generator (was Dynamics; absorbs Physics as System)

The infinitesimal generator L and the specification that defines it. The reversible advection ℙ(u×ω) in rotational form, the passive-scalar advection −∇·(uφ), and the EXACT irreversible diffusion built as the integrating factor ℰ(κ)=exp(−D|κ|²Δt) (D=ν for the velocity, ν/Sc for the scalar). It carries the System specification — ν (Re=1/ν), Sc, and the two forcing choices — the coefficients and driving terms that define L. A comment + function boundary make the reversible/irreversible sub-seam legible INTERIOR to the module.

**Why (physics):** L is the generator the propagator advances; ν and Sc are its coefficients and the forcing is its driving term, so they belong with L, not inside the time-stepper that merely consumes them — struct Physics at TimeIntegration.jl:49 inverts the dependency, letting the numerics own the problem. The exact integrating factor is the exact finite exponential of the linear part of the semigroup (physics, not numerics); it is already BUILT here (Dynamics.jl:106) and only APPLIED in the propagator, so keeping the operator with the generator and its application in the Method honors the build/apply seam the code already draws (decision 1).

**Re-carves:** Dynamics (RHS + integrating factor) plus the Physics struct lifted out of TimeIntegration (renamed System).

### Forcing (KEEP)

The pluggable driving-term strategy family: AbstractForcing and its concretes (NoForcing, BandRescaling, Linear, ConstantPower, and the present-but-unexported StochasticOU) with the four protocol hooks (forcing_rate!, apply_forcing!, prepare_forcing!, forcing_source!). The operator-free constructors return a DeferredForcing (was ForcingSpec) — a forcing named before its box exists, materialized against the SimulationDomain at assembly.

**Why (physics):** Forcing is the driving term f in ∂_t u = ℙ(u×ω) + ν∇²u + f — a component of the generator and the System axis of the §3 specification. It is a substantial, independently-varying pluggable family (a 4-hook protocol), so it stays its own module beside the Generator rather than folding in. A deferred forcing is a physical object — a source not yet bound to a wavenumber lattice — so it is named for that, not with a builder-pattern 'Spec' nor cat's FP 'curried morphism'.

**Re-carves:** Forcing (kept); ForcingSpec (the closure-wrapper struct at Forcing.jl:66) → DeferredForcing.

### Observables (KEEP; MZ-correct name)

The measured functions of the state A(FlowState), regrouped by physical role: energetics (kinetic_energy, dissipation, max_speed), small-scale structure (derivative_skewness), scalar mixing (scalar_variance, scalar_dissipation), and spectral distribution (energy_spectrum, integral_scale). Each takes a FlowState (reading its spectral or cached physical face), not raw buffers.

**Why (physics):** Observables are the functions on phase space the MZ projection acts through and that warmup! and validate_spectrum read as fitness functionals — the third leg of the triad, already correctly named from the lens (decision 16). The carving sharpens two things: they consume a named FlowState (not scratch), and the API/doc groups them by the physical quantity measured — what the physicist reasons about — the physical-meaning-first grouping the documentation policy already demands.

**Re-carves:** Observables (kept; regrouped by physical role in the @docs blocks; retargeted from raw buffer fields to FlowState).

### Propagation (was TimeIntegration; Physics evicted)

The discrete flow map exp(ΔtL): the integrating-factor Runge–Kutta schemes (IFLowStorageRK3 default, IFRK2), the step! kernel that advances û and φ̂ in lockstep, the CFL ceilings (recommended_cfl, default_integrator), and the per-step scratch StepScratch — what remains of FieldBuffers once the state-cache migrates to FlowState: the RK stage registers and predictors, the applied integrating-factor buffer, the per-stage vorticity / Lamb-vector / transform scratch, the forcing-rate arrays, and the ScalarBuffers. Holds NO physics parameters.

**Why (physics):** The flow map S_Δt = exp(ΔtL) is a physical object; the RK scheme is its numerical realization — the Method, named by its job. Housing the transient scratch here (not masquerading as state) keeps the hot loop allocation-free (invariant 4) while making explicit that this module realizes propagation and does not own the physics it propagates. Evicting Physics makes method-independence checkable: two integrators are two realizations of the same L that must agree (§3).

**Re-carves:** TimeIntegration (minus the Physics struct) + the scratch slots of FieldBuffers, renamed StepScratch.

### Particles (KEEP)

Lagrangian tracer tracking as an auxiliary co-evolving state plus its instruments: the Tracers value (positions + pluggable grid→point interpolation, CatmullRom / LalescuSpline / LagrangeSpline), advect! (the second-order Heun push on the start/end-of-step velocities the propagator already produces), and sample! (reading any field along the trajectories).

**Why (physics):** Tracers follow the characteristic flow of u on the periodic torus — a different flow from the Eulerian fields — and sampling is field evaluation along trajectories. They are a co-evolving auxiliary state with first-class numerics (§4.5, decision 10), the Lagrangian companion to the Eulerian triad. 'Particles' is kept: an honest physical name that also accommodates the deferred inertial/oriented-particle ladder (§7), which 'Tracers'/'Probes' would foreclose.

**Re-carves:** Particles (kept; no rename).

### SimulationRun (KEEP; job-named run layer, ergodic framing)

The ergonomic run layer: the Simulation value that assembles SimulationDomain + Generator/System + Forcing + a FlowState + Propagation + Particles, and advance! / run! / warmup! that drive the CFL-adaptive loop and fire callbacks; flow_parameters, validate_spectrum, and the StationarityMonitor.

**Why (physics):** Assembling and iterating the triad is infrastructure, named by its job (decision 16). Its intent is read ergodically: warmup! is relaxation onto the attractor (the ε(t)+skewness gate at SimulationRun.jl:449-488 is a mixing-time detector, decision 13, not a convenience), and run!'s callback is the ergodic time-average accumulator — the reading that justifies the codebase's largest recorded decision, streaming statistics with no flow-state storage and no reruns (legitimate only if time-average = ensemble-average). This framing lives in prose/docstrings; it mints no thin Attractor/ErgodicAveraging modules (names over a stopping condition and a callback).

**Re-carves:** SimulationRun (kept; the state it held migrates to FlowState; ergodic framing added to the docs).

### Phenomenology (KEEP; untouched)

The reference turbulence laws — model spectra, structure-function laws, dimensionless-constant fits — as author-year parametrizations of one abstract law family per quantity; the FlowParameters bridge; the extraction-bound leaf.

**Why (physics):** These are the theoretical targets the measured Observables are validated against — the prediction/closure side. It stays a dependency-light, extraction-bound leaf (no GBGPeriodicFields / GBGStreamingStatistics / dynamics dependency, not re-exported), designed to cut into a standalone GBGTurbulencePhenomenology with no rewrite (§4.7, decision 18). No rename: the debate's ScaleSimilarityLaws / Closure are gratuitous churn the critiques did not endorse.

**Re-carves:** Phenomenology (unchanged).

## How it resolves the tensions

**(a) The missing first-class state — is a state type the right fix, or is that the OO reflex with the morphisms primary?**

Both, with no contradiction. Reify the state as FlowState — a first-class but INERT data record (û, φ̂, cached physical u/ω, clock) — because the code forces it (the state is genuinely split across the Simulation struct and FieldBuffers, and the diagnostics need one named 'current state' to read) and the physics demands it (the phase point is what the generator flows, the observables measure, the run samples). STATE IS A TYPE. But the MORPHISMS stay primary: every verb (step!, the RHS assembly, the observables, forcing, advection) is an external function, and FlowState hangs no methods. The in-place, allocation-free loop means 'state' is simply which arrays are load-bearing, so the fix is to NAME them, not to build an object. This adopts cat's guardrail (bare record, arrows primary) and rejects cat's dissolution, which would ratify the leak.

**(b) What remains in FieldBuffers (it reads as scratch but caches state the diagnostics secretly read)?**

Nothing — the name FieldBuffers dies, split by role. The two cached physical fields the diagnostics read and that survive a step, velocity (u) and vorticity_start (ω), are the physical chart of the state and migrate to FlowState. Everything genuinely transient becomes StepScratch: the RK stage registers (stage1, stage2), the predictors (velocity_star_spectral, velocity_copy), the applied integrating-factor buffer, the per-stage vorticity / Lamb / transform scratch (vorticity_physical, velocity_star, lamb, scratch, nonlinear, vorticity_spectral), the forcing-rate arrays (velocity_rate), and the ScalarBuffers. StepScratch is the preallocated codomain the Generator / Forcing / Propagation morphisms write into — cat's one true observation — allocated from the SimulationDomain and owned by the Method; it holds no state.

**(c) Where does Physics (ν, Sc, forcing) live? It is defined inside TimeIntegration (the numerics) at line 49, which merely consumes it.**

Lift it out and rename it System — the §3 specification bundle {ν, Sc, velocity_forcing, scalar_forcing} that method-independence holds fixed. ν and Sc are the coefficients that define the generator L and the forcings are its driving terms, so System sits WITH the Generator (upstream of the Method), and Propagation holds no physics parameters at all. The forcing STRATEGY family stays its own Forcing module that System references. The initial condition, the other half of the §3 System, is realized separately as a FlowState constructor (the IC draw the scenario calls for). This reverses the recorded-frame inversion: the numerics now consume the specification instead of owning it.

**(d) The naming leaks: SimulationDomain (once SpectralOperators), FieldBuffers, ForcingSpec.**

SimulationDomain (the type) is KEPT — it is a recent recorded rename that names the box, not its backend contents, and §4.1 justifies it as the flow's frame; do NOT rename it to ResolvedSubspace / PhaseSpace / SymmetryAdaptedBasis (over-theorized or navigation-hostile). FieldBuffers is dissolved: state → FlowState, scratch → StepScratch, each named for what it actually is. ForcingSpec → DeferredForcing (it is a real closure-wrapper struct at Forcing.jl:66; 'Spec' is builder-pattern idiom, the physical meaning is 'a forcing named before its box exists'). Physics → System. The SimulationState MODULE — which never held the state — is renamed to SimulationDomain, its misnamed contents redistributed (state name → FlowState, buffers → StepScratch, IC → FlowState constructors).

**(e) Observables and API docs grouped by module/implementation rather than physical role.**

Regroup Observables and the @docs API blocks by the physical quantity measured — energetics, small-scale structure, scalar mixing, spectral distribution — the physical-meaning-first grouping the documentation policy already requires (each object once, an f/f! pair together with the ! home first). The module carving itself now follows physical role at the top level (State / Generator / Observables, the MZ triad), so 'grouped by implementation' is cured structurally, not only in the docs.

## Key renames

- **struct Physics (in TimeIntegration.jl:49) → System (relocated to head the Generator module)** — It bundles exactly {ν, Sc, velocity_forcing, scalar_forcing} — the §3 System specification (the problem posed) — but 'Physics' is vague here (everything in the package is physics) and it sits misplaced inside the numerics that merely consume it. 'System' is the recorded §3 term for precisely this bundle, and relocating it upstream of the Method fixes the dependency inversion.
- **FieldBuffers (one struct) → FlowState (the two cached-state fields) + StepScratch (the rest)** — The struct conflates the cached physical state the diagnostics read (velocity, vorticity_start) with the disposable RK registers. Splitting by role cures the 'scratch that secretly caches state' leak: the state gets a first-class home and the scratch is named for what it is. This goes beyond the recent Workspace → FieldBuffers rename, which kept state and scratch together.
- **ForcingSpec → DeferredForcing** — It is a thin closure-wrapper (struct ForcingSpec{F}; build::F) for a forcing named before its box exists. 'Spec' is builder-pattern / software-engineer idiom the later naming policy forbids for the physicist-user; 'DeferredForcing' states the physical meaning. (Refines the name in decision 14; the deferred-construction mechanism is unchanged.)
- **Dynamics (module) → Generator (module)** — The module's own docstring already calls its RHS 'the generator of the full dynamics' (Dynamics.jl:3, §4.2); 'Generator' is the precise MZ object where 'Dynamics' is broader, and the rename signals the real semantic change — the module now owns ν, Sc, the coefficients that define L. (Refines the MZ naming of decision 16.)
- **SimulationState (module) → SimulationDomain (module)** — The module holds the domain, buffers, and initial conditions — none of which is the state — so its name has always misled. Once FlowState claims the state name, the IC routines become FlowState constructors, and the buffers split to StepScratch/FlowState, what remains is the domain machinery, so the module should take its central object's name. (Overturns the SimulationState/SimulationRun pairing of decision 16 — flag for the user.)
- **TimeIntegration (module) → Propagation (module)** — Once Physics is evicted, the module is purely the numerical flow map exp(ΔtL); 'Propagation' names what it produces — advancing the state — where 'TimeIntegration' can read as owning the equations. Low-priority cosmetic churn that overturns decision 16's deliberate job-name; the load-bearing change is evicting Physics and giving the module StepScratch ownership, so the user may keep 'TimeIntegration'.

## Strongest dissent (rejected — overrule if you disagree)

The strongest physics-first minority I rejected is the metriplectic/geometric reversible–irreversible generator split (metri, geo; both scored ~8–9 on physics-first): carve today's Dynamics into a ReversibleTransport module ({·,E}, the explicit rotational-form advection that conserves energy) and an IrreversibleDissipation module ([·,S], the exact integrating factor that produces entropy). It is genuinely deep — it maps onto the code's exact-linear / explicit-nonlinear structure and correctly locates ν, Sc as coefficients of the dissipative bracket — and a physicist who weights GENERIC structure-preservation highly could reasonably prefer it. I reject it as a MODULE boundary on three grounds. (1) Verified against the code: integrating_factor! folds a linear FORCING rate — energy-injecting, entropy-DECREASING — into the very exp((A−D|κ|²)Δt) a metriplectic reading would call 'irreversible dissipation' (Dynamics.jl:111), so the proposed module wall tracks the numerical stiff/diagonal-vs-non-stiff partition, not entropy production: a thermodynamic label painted on a numerical bucket. (2) The code is ALWAYS forced (the default is BandRescaling, decision 15) for a nonequilibrium stationary state, so a closed-system {·,E}/[·,S] framing mis-frames the term that defines the problem. (3) §8 and decision 8 already record GENERIC as an understanding-lens read through MZ and 'not load-bearing on the code' — which is exactly my placement: the reversible/irreversible distinction is real physics kept as an INTERIOR seam (a function boundary + comment inside Generator), not a module. Overrule me if you decide the structure-preservation story should be surfaced as top-level modules; then split Generator along the bracket, but keep the forcing rate out of the 'irreversible' half to make the label honest. Secondary dissent: cat (dissolve the state, morphisms sole-primary) is the sharpest challenge to reifying FlowState, and I keep its guardrail (bare inert record) while rejecting its dissolution, because 'the buffers are just the codomain' ratifies the exact leak the refactor exists to cure. And sym-as-spine (symmetry-forward module NAMES like SymmetryAdaptedBasis) I demote to interior justification only — its physics is the deepest single account of the spectral realization, but its names fail the cold-read navigation test.

## Open questions for you

- Recorded-decision collisions the user must ratify: Dynamics→Generator and TimeIntegration→Propagation refine/overturn the MZ/job naming of decision 16; the SimulationState dissolution breaks the SimulationState↔SimulationRun pairing decision 16 explicitly chose; ForcingSpec→DeferredForcing refines decision 14 under the later naming policy. All are legitimate under this synthesis, but each edits an append-only decision-log entry and needs your sign-off.
- Does the {ν, Sc, forcings} bundle stay a named System value co-located with the Generator (my recommendation, matching §3), or dissolve into bare Generator fields (ν, Sc) plus forcings held by the run assembly? §3's System also includes the initial condition, which I route to FlowState's constructor rather than the bundle — confirm that the parametric part (System) and the IC draw (FlowState constructor) is the split you want.
- Do the tracer positions migrate INTO a unified FlowState (the complete phase point, as the MZ lens argues), or stay as auxiliary co-evolving state inside Particles (my recommendation, keeping the cohesive Tracers struct whole)? The complete-phase-point view is cleaner ontologically; the modular view avoids splitting Tracers' positions from its advect scratch.
- Are the cached physical u/ω the physical CHART of FlowState (my placement — they survive a step and the diagnostics read them), or should FlowState hold only the spectral truth (û, φ̂) with the physical fields treated as a Method-refreshed cache? The first names them state; the second keeps a single spectral source of truth and risks re-introducing a scratch-that-caches-state ambiguity.
- Where is StepScratch defined — as a machinery struct in the SimulationDomain module (built from its allocators, as FieldBuffers is today) or moved into Propagation (the Method that owns it)? It is threaded through Generator + Forcing + Propagation, so it is shared realization scratch; its defining module is a minor call, but the include-order shift (Generator now depends on Forcing; Propagation on Generator + FlowState) should be settled with it.
- StochasticOU is implemented in Forcing.jl but is NOT in the export list (Forcing.jl:42) — is that a deliberate deferral or an oversight to correct during the recarve, and should the Forcing docstring's capability list name it (the current module docstring omits it)?


---

## ⚠ Missing requirement (raised after the debate): must accommodate future Models

The debate was briefed on the CURRENT code (DNS + tracers + online stats) and did NOT carry the
planned future Models as a hard requirement: **LES** (a coarser field Model — a filter + a subgrid
closure), **inertial / oriented particles** ((x,v) with drag, then (x,v,L) with torque), and
**statistical Models** (PDF / moment closures — where the state is a *distribution* and the generator
a *moment/PDF evolution*). A good carving admits these by EXTENSION, never by RE-CARVE.

First-pass fit of the synthesis:
- **LES — fits well.** MZ *is* the coarse-graining theory; LES = a coarser projection 𝒫 + a
  subgrid-closure term in the `Generator`. The §3 Model ladder already names it. Extends `Generator`.
- **Inertial particles — extends `Particles`** (a richer state (x,v) + a drag pusher). Sharpens
  open-question 2 (is the particle state part of THE phase point?).
- **Statistical Models — the stress test.** The concrete `FlowState` (û, φ̂ *fields*) and `Generator`
  (a *field* RHS) are the DNS/LES instance; a statistical Model needs `state` = a distribution/moments
  and `generator` = a moment/PDF evolution. MZ handles this at the CONCEPT level (state/generator/
  observables are level-agnostic), but the carving must position `FlowState`/`Generator` as **instances
  of level-agnostic MZ roles**, not the only ones.

**Principle refinement.** "No abstraction without a second concrete caller" is right for *implementation*
(don't write speculative LES/PDF code) but wrong for *module carving*: LES / inertial / statistical are
KNOWN-planned, not speculative, so the boundaries must be designed to fit them. YAGNI governs code, not
module boundaries. The test of a carving: a known future arrives by EXTENSION, never by RE-CARVE.

---

## Future-Model fit — panel revision (LES/FDF · inertial · transported-PDF · EDQNM)

_5-agent stress-test (4 specialists + reviser). All four futures returned **extends-with-generalization** — the Mori–Zwanzig spine survives; none re-carves. The reify-inert-state and interior-metriplectic-seam rulings are vindicated._

**Spine.** Yes. All four specialists independently return "extends-with-generalization" — none re-carves the spine. The spine IS the model-ladder theory: §8 already declares Mori-Zwanzig the central lens and the Model axis a "ladder of projections," and §3/§7 already name LES, FDF, and moment Models as coarser rungs — the four futures are exactly those rungs plus the dispersed-phase axis. What must change is not the spine but the ARITY and CONCRETENESS of its four roles: the concrete DNS types (FlowState-as-field-record, Generator-as-field-RHS, the FFT-bundled domain) lift from "the field instance" to "the level-agnostic role, DNS as one concrete." Because ruling #1 already makes the state INERT with every morphism EXTERNAL — confirmed in the code, where step!/Observables take bare û/φ̂ and no method hangs on state — this lift moves no method and no module boundary: it is an extension, not a re-carve. The two rulings are VINDICATED, not merely survived: reification is precisely what turns every apparent "re-carve" into an extension (the EDQNM specialist's decisive point), and the interior metriplectic seam REPEATS inside every generator instance (FDF closures are net-dissipative → irreversible side; inertial drag-relaxation is the irreversible seam; EDQNM's transfer/diffusion split is the same seam), so a module wall there would have been wrong exactly because the closure spans both halves (EDQNM) or the seam recurs per sub-state (inertial). Adjudicating the one disagreement — FDF/PDF label FlowState "re-carves," EDQNM labels it "extends" — I rule with EDQNM: they prescribe the identical move (lift FlowState → abstract State); under the inert-record design "the contents must change" is exactly what a level-agnostic role with per-Model instances delivers, with no morphism migrating. So the spine holds under all four futures by extension.

**Hardest case.** FDF (LES/FDF) is the hardest — it is the ONLY future where a field, a distribution, AND a notional-particle ensemble are all primary state in one run, with TWO-WAY coupling, so it stresses the most commitments at once: it breaks the fixed field-only slot set, inverts the 'particle = instrument' axiom (notional particles ARE state and feed back), demands the new Closure module (subgrid stress + micromixing), and puts an RNG (Wiener increments) in the allocation-free hot loop. Decisive requirement: State must be an OPEN, HETEROGENEOUS PRODUCT of first-class co-evolving sub-state slots with two-way inter-slot coupling — not a single record with a fixed slot set — and the 'particle = instrument' premise must be demoted from carving axiom to a DNS-specific fact (splitting Particles' shared numerics from role). That one move (State{S} on its slot tuple + numerics/role split) simultaneously serves inertial particles along the dispersed-phase axis, so one generalization covers two known futures. Runner-up: EDQNM imposes the sharpest constraint on the state CONTENTS specifically — discarding û and the physical chart entirely, proving the chart must be an optional DNS-cache and the contents fully abstract — but it is single-slot and one-way, hence a cleaner extension once State is lifted.

### Core generalizations — lift the four roles to level-agnostic; DNS stays the one built concrete

- **FlowState — one spectral-field record {û, φ̂, cached physical chart u/ω, clock}  →  State — the reified MZ phase point at the active projection rung: an OPEN, possibly heterogeneous PRODUCT of first-class inert sub-state slots + the clock. DNS instantiates one substantive slot (û, φ̂ + optional physical chart); FDF a filtered-field + notional-ensemble PAIR; inertial a FlowState × ParticleState product; EDQNM a shell-spectrum record {E(κ), E_φ(κ)}; PDF a composition-space ensemble.**

  FDF and inertial each need TWO co-primary slots evolving in one run (FDF two-way coupled), so a single-slot tagged union covers EDQNM/PDF but NOT them — the minimal shape covering all four is a product whose DNS instance has one slot. The cached physical chart demotes from a State MEMBER to a DNS-specific optional cache: EDQNM discards û's phases entirely and one-point PDF has no pointwise field, so nothing to cache. Kept verbatim: the inert-record ruling, morphisms-external ruling, the clock, and the IC-draw constructors reread as 'sample the initial distribution.'

- **Generator (was Dynamics) — the field RHS L: field → field-tendency, ℙ(u×ω) − ∇·(uφ) + viscous ℰ, carrying System {ν, Sc, forcing}  →  Generator — the MZ generator L: State → State-tendency, dispatching on State, broadened with (a) an optional Wiener/noise term (the MZ noise made literal, for FDF/PDF SDEs) and (b) a Model-fibered CLOSURE plug (subgrid stress + micromixing for LES/FDF; eddy-damped triad transfer T(k) for EDQNM) — the physical content DNS lacks (DNS's closure is the identity).**

  System {ν, Sc, forcing} is Model-agnostic and carries over unchanged; the reversible field body ℙ(u×ω)/−∇·(uφ) becomes the DNS-specific instance, replaced by modeled transfer/mixing on coarser rungs — exactly the MZ memory+noise made concrete. Closure constants (C_φ, eddy-damping λ, C_0) parametrize the PROJECTION and live on the closure INSTANCE like Butcher coefficients — NOT in the System bundle, or method-independence breaks.

- **Observables A(FlowState) — reductions of a resolved field (û, physical chart)  →  Observables A(State) — same interface, Model-specific implementation, each tagged by its state-dependence: spectral-moment observables (k, ε, E(κ), integral scale) read a spectrum accessor uniformly and become Model-agnostic (primary for EDQNM/PDF, derived for DNS); physical-chart observables (derivative_skewness via the strain tensor, max_speed) become DNS specializations.**

  Across the ladder the relation inverts: for EDQNM/PDF the observable IS the state or a trivial marginal (E(κ) is literally EDQNM's state; ⟨φ²⟩ a PDF marginal), for DNS a field reduction. Some are Model-polymorphic with two generators — EDQNM predicts the same physical skewness S through the transfer integral it cannot form from a strain tensor. The ⟨φ⟩_L filtered mean is a weighted local mean → raise to PF/SS, do not reimplement (consumer boundary, §5).

- **Propagation (was TimeIntegration) — step!(…, û, φ̂, buffers, …) on bare field args; scratch embedded in FieldBuffers  →  Propagation — step! dispatches on State as a splitting scheme over its slots with inter-slot coupling; StepScratch sized 'similar to the State' (field buffers / particle arrays / shell vectors); the integrating-factor family generalizes from 'exp(−D|κ|²Δt) on a field' to 'exact flow of the linear-diagonal part of the generator.'**

  The integrating factor is the single most-reused piece across all four futures: viscous ℰ (DNS + EDQNM's −2νκ²E sink), IEM exponential variance-relaxation (FDF/PDF), the OU Langevin factor (VFDF — the archived StochasticOU mathematics), the per-particle drag exp(−Δt/τ_p) (inertial). Genuinely NEW and NOT unified by it: SDE pushes (Euler–Maruyama/Milstein) and the SO(3) geometric orientation integrator (§4.5/§8 already flag the latter).

- **SimulationDomain — the box with ALL representation machinery bundled (grid, FFT plans, iκ, |κ|², dealias, dealiasing strategy)  →  A Model-agnostic FRAME (box side L; precision scalar_type; backend array_type) + a Model-fibered REPRESENTATION discretization: 3-D FFT plans + iκ + |κ|² + dealias for the field Model; a first-class ShellDecomposition + triad-geometry table b(k,p,q) for EDQNM; a composition-space grid or nothing for one-point PDF; the LES filter kernel + width Δ beside the dealias kernel for LES/FDF.**

  The frame axes are genuinely Model-agnostic (precision/backend cut across every Model, §3/§6); the representation machinery is Model-fibered and currently glued in. Promote ShellDecomposition NOW from inside the energy_spectrum reduction to a named domain member — for EDQNM it is the PRIMARY state carrier and integration measure, not an occasional diagnostic; it is a present smell independent of the futures.

### Module revisions

- **FlowState → State:** Generalize from a fixed field record to a product-of-slots role parametrized State{S} on its slot tuple; DNS instantiates one substantive slot. This single revision absorbs the FDF two-way-coupled notional ensemble, the inertial dispersed phase (FlowState × ParticleState), the PDF ensemble, and the EDQNM spectrum WITHOUT touching the field slot. Demote the physical chart to a DNS-specific optional cache.

- **Closure (NEW module):** Add the one genuinely new home all of FDF/LES/PDF/EDQNM demand and DNS lacks (DNS's closure is the identity): AbstractClosure, a second Model-fibered strategy family PARALLEL to Forcing, carried by the Generator — AbstractMixingModel (IEM/Curl/EMST) + AbstractSubgridStress (Smagorinsky/dynamic) for FDF/LES; eddy-damping/Markovianization (λ, triad transfer) for EDQNM. Lands on the IRREVERSIBLE side of the metriplectic seam (GENERIC net-dissipative, §8). Reuses the existing strategy-pattern machinery. Do NOT fold into Forcing: forcing DRIVES (System), closure DISSIPATES the residual (Model). Satisfies invariant 6 — pluggable + validated, not assumed.

- **Particles:** Split the shared Lagrangian NUMERICS (push/interpolate/sample) from the ROLE. Demote decision 10 ('particle = instrument, not a second physics') from carving axiom to a DNS/tracer-specific FACT: FDF notional particles ARE the subgrid physics and feed back two-way; PDF particles ARE the primary state; it holds for inertial only under one-way coupling. One pusher/interpolant serves three roles — tracer (instrument, Observables side, one-way), inertial/oriented (State slot with its own generator+integrator, one-way), notional/PDF (State slot, SDE, two-way). Additive growth mirroring the fluid's state/generator/propagation triple for the dispersed phase.

- **Generator:** Carry the Model-fibered Closure plug and an optional noise term; keep System {ν, Sc, forcing} unchanged. Make the reversible/irreversible metriplectic seam an explicit interior function boundary (as proposed), now understood to REPEAT per sub-state (inertial advection reversible / drag relaxation irreversible; EDQNM transfer / diffusion).

- **SimulationDomain:** Split conceptually into a Model-agnostic frame (side L, precision, backend) and a Model-fibered representation; promote ShellDecomposition to a first-class member NOW; reserve the LES filter kernel + Δ and the EDQNM triad table b(k,p,q) to attach beside |κ|² when those Models are built.

- **Observables:** Regroup by physical role (energetics / small-scale structure / scalar mixing / spectral distribution) AND tag each by state-dependence (spectrum-reading = Model-agnostic; physical-chart = DNS-specific). Raise the ⟨φ⟩_L weighted-ensemble-mean to PF/SS rather than reimplement.

- **Propagation:** step! dispatches on State; StepScratch sized-to-State; the integrating-factor family generalizes to 'exact linear-diagonal flow'; add SDE pushers and the SO(3) geometric integrator as Model-fibered integrator families when FDF/oriented arrive.

- **SimulationRun:** Assembly grows to build a multi-slot State + representation + closure bundle and wire inter-slot coupling; the ergodic warmup framing survives directly (FDF/EDQNM both relax onto the attractor — the two-mode micromixing benchmark of §7 IS warmup!'s reading); flow_parameters/validate_spectrum still bridge to Phenomenology. Run-layer shape holds; owns no physics.

- **Forcing:** Unaffected. Still the System driving-term strategy family with four hooks; must NOT absorb the closure. Hooks written against the abstract State/tendency, with the solenoidal projection demoted to a DNS-only specialization.

- **Phenomenology:** Untouched leaf. FDF/EDQNM reference constants (C_0, C_φ, Obukhov–Corrsin) are additional author-year subtypes in the existing strategy pattern; the Model/Phenomenology seam SHARPENS — EDQNM is a dynamical closure Model producing E(κ), distinct from a static evaluated law.

### Residual risks

- Over-abstraction ahead of the second case (invariant 9 / decision 7): the mandate is to fit the futures by extension WITHOUT building them. Lift ONLY the four role-types to abstract (near-zero cost given the already-inert state) and keep DNS the sole concrete instance; do NOT populate the Closure module, the notional-particle slot, or the SO(3) integrator until FDF/inertial is actually built. Abstraction-READY, not abstraction-POPULATED.
- Allocation-free hot loop (invariant 4) vs. SDE Wiener increments: FDF/PDF/VFDF put a per-step RNG in step! — the exact concern already recorded for the archived Eswaran–Pope OU forcing (§7, the one allocation-free exception, gated on a GPU-tuned generator). Reuse that recorded exception; Wiener scratch lives in the State-sized StepScratch; do not multiply it silently across slots.
- Two-way coupling vs. the one-way factorization that keeps particles cheap: tracers/inertial are one-way (dilute, no back-reaction), FDF is two-way. Make inter-slot coupling a property of the Generator wiring (which slot reads which), not a hard-wired property of the State container — else the one-way cases pay for FDF's coupling or FDF cannot be expressed.
- Frame/representation fission of SimulationDomain risks fragmenting a currently-clean bundle for no present benefit: promote only ShellDecomposition now (a real present smell inside energy_spectrum); defer the full FFT-plans-vs-box separation until EDQNM/PDF forces it.
- Observables/GBGStreamingStatistics boundary blur: ⟨φ⟩_L and notional-ensemble averages are statistics-over-ensembles straddling the §5 line. Hold the consumer boundary — raise the weighted grid-projection / local weighted mean to PF/SS, never reimplement here.
- Closure constants (C_φ, eddy-damping λ, C_0) misfiled as System: they parametrize the projection (Method/Model), not the flow scenario. Keep them on the closure INSTANCE like Butcher coefficients; filing them in Physics/{ν,Sc,forcing} would couple specification to closure and break method-independence (§3).
- 'Spectrum state' straddling Model vs Phenomenology: an EDQNM run PRODUCES the same E(κ) object Phenomenology's Spectra PREDICT. Keep EDQNM on the Model axis (state + generator + run evolved in time); keep Phenomenology a leaf of evaluated author-year laws — the seam sharpens rather than blurs.


---

## Status & parked items (this session)

- **Proposal COMPLETE** (nine-lens debate synthesis + four-future fit revision). **Nothing implemented;
  no `src/` touched.** It is a proposal awaiting decisions.
- **Gating decisions (need the user) before any implementation:**
  - decision-log ratifications: `Dynamics→Generator`, `TimeIntegration→Propagation`, dissolving the
    `SimulationState` module, `ForcingSpec→DeferredForcing` (each edits a recorded decision);
  - tracer-state placement (into `State` vs stay in `Particles`);
  - the cached physical `u/ω` (state-cache vs spectral-only truth);
  - `System` as a named bundle vs bare `Generator` fields; where `StepScratch` is defined.
- **Parked:**
  - `ShellDecomposition` → **PF request** — deferred until the architecture is in place (a present
    smell; the shell object belongs in `GBGPeriodicFields`, then IT stores it in `SimulationDomain`).
  - the **documentation track** (31 items in `docstring-review-pile.md`) — postponed to do the redesign
    first.
  - the **Alloy formal spec + Julia interface skeleton** — offered, awaiting go (would give a
    machine-checkable architecture for fresh-eye agents).
- **Done + committed separately:** D9 — archived `StochasticOU` (`92f5c2d`, pushed).

---

## Formal-spec review — nine lenses (fresh eyes) on `.claude/architecture.als`

**Verdict.** Faithful in its SPINE, useful as a scaffold, but NOT yet a genuine mechanical check — consistent with the panel's unanimous "faithful-with-gaps." What it gets right is real and load-bearing: the four level-agnostic ROLES over the renamed physics modules (Generator=Dynamics, Propagation=TimeIntegration), the inert-state ruling (no Strategy plugs into FlowState, `no FlowState.depends`), the System-vs-Model strategy fibration, FlowState as an open product of Slots, and the acyclic module DAG that matches the §4.8 include order. But three things sink it as a CHECK rather than a diagram. (1) Its load-bearing asserts do not check anything: `extendsNeverRecarves` is a type-level tautology (`s.hostModule in Module` cannot fail), `roleCoverage`/`instantiates = Role` hard-codes the panel's central result ("every future extends the spine") as a fact so it can never fail, and `stateProductArity`/`systemModelAgnostic` merely re-derive `stateSlots`/`dependencyGraph` — so the ONLY non-vacuous property in the whole model is `acyclic`, a build-order concern. The artifact currently cannot fail any property it exists to verify. (2) The headline redesign claim (State{slots} on the ONE FlowState module) lives only in a code comment `// all hostModule = FlowState`, never a fact — so it is not modeled at all. (3) One of the two rulings the spec exists to formalize — the metriplectic reversible/irreversible seam (§8, decision 2) — is entirely absent, and the Model ladder (§8: the projection structure "is what makes the Model axis a ladder rather than a list") is flattened to an unordered six-element set, reproducing the exact list-not-ladder collapse §8 warns against. Verdict: a sound spine wrapped in asserts that document intent in Alloy syntax instead of testing it; one bounded pass fixes it.

**Residual bias (confirmed).** Objects-over-morphisms — confirmed, exactly as the category lens predicted, and echoed by all nine reviews. The formalization reifies every concern as an inert sig related only by containment (`hostedBy`, `hostModule`, `pluggedInto`, `slots`, `instantiates`) plus one compile-time dependency DAG (`depends`); there is no composition, identity, idempotent, or commuting diagram anywhere, and the roles that ARE arrows (generate, propagate, observe) are one-sig tags with a `hostedBy` pointer. The tell is that the sole non-vacuous checkable property is `acyclic`, a software build-order concern — a programmer's artifact — while every physics assert is a downstream tautology, a type-level vacuity, or a hard-coded fact that cannot fail. But the honest sharpening, which the panel as a whole missed, comes from §10 and decision 12: this package verifies its DYNAMICAL claims by numerical oracle and deliberately keeps NO formalization ledger, because it introduces no novel mathematical objects (they are GBGPeriodicFields' and GBGStreamingStatistics'). So the flow semigroup S_{t+s}=S_t∘S_s, the MZ memory kernel and noise, the invariant measure, the Pi∘S=S∘Pi statistical commutation, method-independence as distributional equality, and the FFT-as-change-of-basis / Schur-diagonality internal to the deliberately-opaque SimulationDomain are correctly OUT of this artifact's scope — the many panel invariants demanding them are over-reach, not gaps. What is WRONGLY missing is the STRUCTURAL shadow of the arrows the architecture itself makes primary and Alloy can express: the Model→Model ladder refinement (§8 'ladder not list', flattened to an unordered set), the interior reversible/irreversible generator seam with net-dissipative closures (§8 GENERIC ruling, absent entirely), and per-Model role realization (the level-agnostic roles, welded to fixed DNS host modules). Running underneath is a residual DNS/field-centrism: the state module keeps the field-flavored name FlowState after the State{slots} generalization, FieldSlot is the privileged single-slot default (`one DNS.slots`), and the coarse rungs are named but their state is untyped atoms and their generators forced into the NS Generator host — the model still thinks in DNS objects rather than level-agnostic structure, inside a spec whose whole claim is 'DNS is one rung, not a thing apart.'

### Bounded second pass (re-carves nothing)

**Fixes:**
- De-vacuum `extendsNeverRecarves` and pin slots to the State module. `s.hostModule in Module` is true by the declaration `hostModule: one Module`, so it checks nothing; the intended constraint sits only in the comment `// all hostModule = FlowState`. Add `fact { all s: Slot | s.hostModule = FlowState }` and rewrite the assert to `s.hostModule = FlowState`. This is the #1 consensus finding — every lens flagged it.
- Replace the constant `roleCoverage { all m: Model | m.instantiates = Role }` and the fixed `Role.hostedBy: one Module` with a per-Model `RoleRealization(role, model, host)`. As written, `instantiates` carries zero information (identical for every rung, so 'futures extend the spine' cannot fail), and `hostedBy` welds each level-agnostic role to a single DNS module (GeneratorRole always the NS Generator, impossible for EDQNM's spectral closure). The per-model relation makes coverage a real check and the roles genuinely level-agnostic.
- Correct the dependency edges to the code's actual `using ..` imports: ADD `SimulationRun -> SimulationDomain`, `SimulationRun -> Forcing`, `SimulationRun -> Phenomenology`, and `Propagation -> Forcing` (all present in src/). MOVE the Forcing coupling off Generator: `Dynamics.jl` imports only `SimulationState`, so `Generator -> Forcing` is wrong — the linear forcing rate is folded into the integrating factor at the `TimeIntegration` assembly, hence `Propagation -> Forcing`. Mark `Generator -> Closure` as a deferred, coarse-rung-only edge (DNS, the only built rung, has no closure), not an unconditional present one.
- REJECT the panel's most-repeated proposed edge, `Particles -> FlowState`. The code passes the velocity fields to `advect!`/`sample!` as arguments (`advect!(tracers, velocity_start, velocity_end, domain, dt)`); `Particles.jl` imports only `SimulationDomain`. The existing single Particles edge is correct — do not add. (The Lagrangian lens itself conceded this; the geometric/MZ/category/dynamical calls for the edge are misreadings.)
- Rename `morphismsExternal` to `stateIsInert`. Its body (`no s: Strategy | s.pluggedInto = FlowState` and `no FlowState.depends`) verifies the inert-state ruling — genuinely — but NOT 'morphisms primary': no morphism is modeled anywhere, so the name over-claims. Honest naming, plus recognition that 'morphisms primary' is realized structurally by the added `coarsens` ladder and the interior generator seam, not by a negative on state.
- Model the Strategy axis as specification vs realization, per decision 7 — do NOT add a third co-equal Method axis. Decision 7 explicitly revised away the 'System x Model x Method' framing (three co-equal axes) after adversarial review, so the GENERIC/kinetic/continuum 'Method collapsed into Model' error argues from an abandoned framing. The real defect is that `ClosureStrategy` (constitutes the Model — specification) and `IntegratorStrategy`/`DealiasStrategy` (realization/Method fibered over Model) are both `fibered = ModelAxis` and thus indistinguishable. Tag Forcing/Closure as specification (System/Model halves) and Integrator/Dealias (+ the deferred particle pushers and mixing models §3 names) as realization fibered over Model — encoding 'Method is fibered over Model' without resurrecting the third axis.
- Assert System-vs-Model independence in BOTH directions. `systemModelAgnostic { Closure not in Forcing.^depends }` states only one half; add `Forcing not in Closure.^depends` for the full orthogonality the name claims.
- Resolve the present/deferred conflation. The fact base mixes built (DNS) and deferred (the Closure module and its edges, the coarse-rung slots CompositionSlot/ShellSpectrumSlot/FilteredFieldSlot/NotionalEnsembleSlot) nodes as flat present-tense facts. Commit the spec to the TARGET architecture (then it MUST carry the ladder poset and the metriplectic seam to be internally consistent) and mark the deferred frontier, so a reader cannot mistake a projected edge for today's code.

**Invariants to add:**
- **Slots live on the ONE State module — the real, non-vacuous 'extend never re-carves'. This is the load-bearing redesign claim (State{slots} an open product of inert sub-states on one FlowState), currently present only as a code comment. Flagged by every lens.** — Without a FACT pinning hostModule, an instance may host ShellSpectrumSlot on SimulationDomain or Generator, and the assert that names 'extends never re-carves' passes on it — so the generalization that unifies all six rungs onto one inert State is unmodeled. Making it a fact both fixes the vacuous assert and turns the redesign into a checkable property.
  ```alloy
  fact slotsLiveOnState { all s: Slot | s.hostModule = FlowState }
assert extendsNeverRecarves { all m: Model, s: m.slots | s.hostModule = FlowState } check extendsNeverRecarves for 10
  ```
- **The reversible/irreversible (metriplectic) split is an INTERIOR seam of the Generator — both sub-generators within Generator, neither a Module — with the one architectural constraint §8 imposes: closures are net-dissipative and forcing is external driving. This is the second of the two rulings; it is absent entirely (5 lenses).** — §8 makes it load-bearing: rotational-form advection is the energy-conserving reversible generator, exact-integrating-factor diffusion the irreversible one, and GENERIC 'constrains closures to be net-dissipative'. The ruling was 'interior seam, not a module wall'; the spec honored 'not a wall' by erasing the seam, so an anti-dissipative (backscatter) closure satisfies every fact. This is the STRUCTURAL shadow (a partition tag + a sign constraint), fully Alloy-expressible and §10-compatible — not the dynamics, which stay with the numerical oracle.
  ```alloy
  abstract sig Character {} one sig Reversible, Irreversible, OpenDriving extends Character {}
abstract sig GeneratorPart { within: one Module, character: one Character }
one sig Advection extends GeneratorPart {}{ within = Generator character = Reversible }
one sig Diffusion  extends GeneratorPart {}{ within = Generator character = Irreversible }
assert seamIsInteriorNotErased {                 // one module (not a wall), yet the split is real
  all g: GeneratorPart | g.within = Generator
  Reversible + Irreversible in GeneratorPart.character } check seamIsInteriorNotErased for 10
// add  thermo: lone Character  to Strategy; then:
fact strategyThermo { ClosureStrategy.thermo = Irreversible  ForcingStrategy.thermo = OpenDriving }
assert closuresNetDissipative { ClosureStrategy.thermo = Irreversible } check closuresNetDissipative for 10
  ```
- **The Model set is a poset/ladder of projections with DNS the finest rung (projected into by nothing), NOT a flat list. A coarsening discards state. (MZ, category, kinetic, dynamical.)** — §8 says the projection structure is precisely 'what makes the Model axis a ladder rather than a list', and the spec reproduces the flat-list collapse it warns against: six unordered Models each holding a slot-bag, no refinement arrow between rungs, no statement that DNS is the identity projection. The `coarsens` relation is the structural shadow of the projection ladder (the projection idempotents and Pi∘S=S∘Pi commutation stay with the numerical oracle per §10).
  ```alloy
  // add  coarsens: set Model  to Model
fact ladder { DNS in LES.coarsens and DNS in Inertial.coarsens
              and LES in FDF.coarsens and LES in PDF.coarsens and LES in EDQNM.coarsens }
assert ladderIsDAG   { no m: Model | m in m.^coarsens } check ladderIsDAG for 10
assert dnsIsFinest   { no coarsens.DNS }               check dnsIsFinest for 10
assert coarseningDiscards { all c, f: Model | c in f.coarsens implies c.slots != f.slots } check coarseningDiscards for 10
  ```
- **Roles are realized PER MODEL (genuinely level-agnostic), not welded to a fixed DNS host module — and role coverage becomes a checkable consequence rather than a hard-coded fact. (MZ, category, GENERIC, symmetry, dynamical.)** — `Role.hostedBy: one Module` forces GeneratorRole onto the Navier-Stokes Generator module for EVERY rung, but EDQNM's generator is a spectral shell-transfer closure with no rotational-NS RHS — the 'four level-agnostic roles' are contradicted. And `roleCoverage {instantiates = Role}` pins the relation to a constant, so the panel's central result ('all futures extend the spine') is a definitional fact that cannot fail. Replacing both with a per-Model realization makes coverage a genuine check and lets the host track the rung's state kind.
  ```alloy
  sig RoleRealization { role: one Role, model: one Model, host: one Module }
fact stateAlwaysFlowState { all rr: RoleRealization | rr.role = StateRole implies rr.host = FlowState }
assert everyFutureExtendsTheSpine {              // now a consequence, not a fact
  all m: Model, r: Role | one rr: RoleRealization | rr.model = m and rr.role = r }
  check everyFutureExtendsTheSpine for 10
  ```
- **Slots are typed by kind (field-representation / statistical-moment / particle-ensemble), and closure is required EXACTLY when the advanced state is a reduced statistic — DNS's closure is trivial, coarse rungs' nontrivial. (kinetic, dynamical.)** — A field and an energy spectrum are structurally identical atoms distinguished only by name, so 'the coarse state IS statistics' and the closure hierarchy are invisible. Typing the slots lets the model state why EDQNM/PDF need a closure and DNS does not — which is also why `Generator -> Closure` cannot be an unconditional present edge. It also disambiguates ParticleSlot as genuine inertial-particle STATE (the deferred (x,v) rung with its own ODE), distinct from a tracer instrument, so `one DNS.slots` reads as intentional (tracers are instruments per decision 10), not as denying tracer runs.
  ```alloy
  abstract sig SlotKind {} one sig FieldRep, StatisticalMoment, ParticleEnsemble extends SlotKind {}
// add  kind: one SlotKind  to Slot
fact slotKinds { FieldSlot.kind = FieldRep  FilteredFieldSlot.kind = FieldRep
  ShellSpectrumSlot.kind = StatisticalMoment  CompositionSlot.kind = StatisticalMoment
  NotionalEnsembleSlot.kind = ParticleEnsemble  ParticleSlot.kind = ParticleEnsemble }
abstract sig ClosureLevel {} one sig Trivial, Nontrivial extends ClosureLevel {}
sig ClosureUse { model: one Model, level: one ClosureLevel }
fact { all m: Model | one c: ClosureUse | c.model = m }
assert closureIffReduced { all c: ClosureUse |
  (some s: c.model.slots | s.kind = StatisticalMoment) iff c.level = Nontrivial } check closureIffReduced for 10
  ```
- **Phenomenology extraction boundary: it depends on nothing, and it is consumed ONLY by the run/validation layer (SimulationRun) — never by the dynamics core (Generator/Propagation) or the State. (MZ, continuum; code-confirmed, decisions 18-20.)** — The Alloy leaves Phenomenology a fully disconnected node, so the extraction-bound-leaf invariant is neither present nor assertable — yet it is a recorded decision the code realizes (`SimulationRun` imports `Phenomenology.Scalings.Li2008`, `FlowParameters`, `Spectra` for `validate_spectrum`; decision 20 states 'only the run layer, never Phenomenology, knows both sides'). This both adds the invariant and requires the missing `SimulationRun -> Phenomenology` edge.
  ```alloy
  assert phenomenologyLeaf {
  no Phenomenology.depends
  Phenomenology not in Generator.^depends
  Phenomenology not in Propagation.^depends
  Phenomenology not in FlowState.^depends
  (SimulationRun -> Phenomenology) in depends } check phenomenologyLeaf for 10
  ```
- **The stationarity gate reads OBSERVABLES, never the raw state — decision 13's 'watch epsilon and S (measured), not the clampable k'. It lives in the run layer and gates propagation. (dynamical; decision 13.)** — It gives the otherwise-empty SimulationRun node real structural content and encodes a recorded ruling ('never clamp/gate on what you can clamp' — read the measured dissipation and derivative skewness, not the kinetic energy a constant-energy forcing pins). It is structural (which role the gate reads) and Alloy-expressible, unlike the ergodic averaging it presides over, which stays with the numerical oracle (§10).
  ```alloy
  sig StationarityGate { watches: some Role, gates: one Role, hostedIn: one Module }
fact warmupInRunLayer { all g: StationarityGate | g.hostedIn = SimulationRun and g.gates = PropagationRole }
assert gateWatchesObservablesNeverState {
  all g: StationarityGate | g.watches in ObservablesRole and StateRole not in g.watches }
  check gateWatchesObservablesNeverState for 10
  ```

**Ready for.** Needs one bounded pass before it earns its keep as a mechanical check — but the spine is sound and can already drive the Julia interface skeleton, most of which exists in src/. Split the readiness two ways. (1) The BUILT (DNS) architecture is implementation-ready now: the four-role spine, the module set and include-order DAG (once the edge corrections land), the strategy protocol, and the inert-state ruling are faithful and already realized in code — the interface skeleton needs nothing from the Alloy it doesn't already have. (2) The Alloy's actual value is for the LADDER extension (LES/FDF/PDF/EDQNM), where the poset + interior seam + typed slots + per-model role realization are precisely the contracts a new rung must satisfy — and there it is NOT yet ready, because its load-bearing asserts are vacuous/tautological/hard-coded (it cannot fail the very 'futures extend the spine' property it exists to verify), one of its two target rulings (the metriplectic seam) is absent, and it reproduces the list-not-ladder collapse §8 warns against. The second pass is bounded and non-structural — it re-carves nothing: (a) de-vacuum the two load-bearing asserts (slots-on-FlowState as a fact; per-Model RoleRealization replacing the constant roleCoverage/fixed hostedBy) so the redesign is modeled and coverage can fail; (b) add the two structural shadows the rulings require — the metriplectic interior seam with net-dissipative closures, and the Model-ladder `coarsens` poset with DNS finest; (c) correct the dependency edges to the code's `using ..` (add the SimulationRun/Propagation edges, move Forcing off Generator, reject Particles→FlowState); (d) hold scope to the structural architecture, keeping the dynamical content with the numerical oracle per §10. With those four it is a faithful, useful, genuinely-checkable spec ready to drive the coarser-rung interface skeletons and their implementations. Do not gate the DNS interface work on it.


---

## v2 formal-spec re-review — nine lenses (fresh eyes)

_v2 MECHANICALLY PASSES (consistent; all 11 asserts valid, scope 12) — but the panel is unanimous: **needs a third pass**, because passing checks are still partly tautological._

**Overall.** Partial landing — real, code-faithful structural gains, but all nine lenses correctly return needs-third-pass. v2 fixed the things that were WRONG (the dependency DAG is now verified against the actual using-imports and is the one rigorous structure; the redesign claim moved from a code comment to a guarded FACT; state is typed; the seam and the ladder now EXIST as objects; the gate reads Observables). But it did NOT fix the thing the nine lenses were really flagging: v2 answered morphism-shaped concerns by adding more labeled OBJECTS and then re-asserting their labels. Six of eleven asserts (seamInterior, closureDissipative, gateReadsObservables, extendsNeverRecarves, stateProductArity, stateRealizedEachRung) are tautological re-reads of values hard-coded in `one` sig bodies — the exact vacuity class v1 was rejected for, now relocated INTO the seam and the gate. The single genuinely new arrow-relation is `coarsens`, and even it is verified by a false-but-plausible `!=` check rather than a reduction map. Mechanical satisfiability ("run show" holds, 11 asserts pass in scope 12) is real but weak evidence — several passing asserts pass because they cannot fail. Verdict: the DNS-rung software skeleton is drivable now; the Model-ladder extensions need a third, targeted pass first. That pass is small and entirely within scope 12 (all structural shadows, zero dynamics formalization).

**Objects-over-morphisms — reduced, not resolved.** REDUCED, NOT RESOLVED — still object-first at every decisive place. Category-theory lens is exactly right: v2 added exactly ONE genuine new arrow-relation (`coarsens`); everything else new is containment/typing/assignment (hostModule, kind, within, sense, onto, actsOn, reads, home) — object attributes, not morphisms. The evidence the bias survives: (a) the metriplectic seam landed as two labeled atoms + tautological label re-reads, with NO relation tying SubGenerator to Observables — there is no Advection→preserves→Energy or Diffusion→dissipates→ε(=ν⟨|ω|²⟩) edge, so the degeneracy conditions that MAKE it metriplectic are absent and the seam is a label, not a check; (b) `coarsens` is the one real arrow but `coarseningReduces` checks set-inequality `!=`, not a projection map, so the reduction morphism is NAMED but not shadowed — and because MZ closure REINTRODUCES modeled DOF (FDF carries 2 slots vs LES's 1, PDF reintroduces an ensemble), "reduces" is the wrong verb and `!=` passes coarsenings that ADD state; (c) the single most important Mori–Zwanzig morphism — the projection P from fine to coarse state — has NO shadow, though decision 12 permits a static one; there is no resolved/unresolved (image/memory) partition, no Q=1−P complement, and DNS-as-identity (P=id) is only implicit via dnsFinest; (d) the three dynamics roles remain objects (Generator should be an endomorphism, Observables a State→ℝ arrow, Propagation a time-indexed flow), and `depends: Observables→FlowState` actually INVERTS the observable arrow; (e) forcing is mis-tagged Reversible — a physics category error — and the two Reversible/Irreversible encodings (SubGenerator.sense and Strategy.onto) can drift with no fact linking them. The only non-vacuous relational checks remain the software DAG (acyclic, phenomenologyLeaf) plus two weak new ones (systemModelOrthogonal = non-reachability, coarseningReduces = `!=`). v1's "the only rigorous thing formalized is a dependency DAG" is dented, not overturned.

**Confirmed fixed (v1→v2):**
- Dependency DAG is now code-faithful and remains the one rigorous structure — verified against the actual using-imports: Propagation(TimeIntegration.jl)→Forcing present, Generator(Dynamics.jl)→Forcing correctly ABSENT (Dynamics imports no Forcing), Particles→FlowState correctly REJECTED (Particles.jl:26 imports only SimulationDomain), SimulationRun→{all}, Phenomenology a genuine leaf (only SimulationRun imports it; its submodules import only Phenomenology). acyclic + phenomenologyLeaf stay the two non-vacuous checks.
- The redesign claim is promoted from a code COMMENT to a FACT: every Slot sig pins hostModule=FlowState and extendsNeverRecarves guards it, so the 'all state realized on the one module, extends never recarves' invariant is now structurally unfalsifiable. This is the strongest single gain.
- State is now TYPED (FieldRep / StatMoment / ParticleEnsemble) and DNS is no longer the sole real state. EDQNM moment-primacy is the ONE genuine representation-shadow CHECK: `no (EDQNM.slots & (FieldSlot+FilteredFieldSlot))` enforces a field-free reduced state, not just a rename.
- The metriplectic seam now EXISTS inside Generator with physically correct signs (Advection→Reversible/energy-conserving; Diffusion→Irreversible/dissipative) — v1's 'seam absent' void is filled at the object level, and the ClosureStrategy is tagged Irreversible.
- The Model ladder is now an ordered relation (coarsens) with ladderDAG (acyclic) + dnsFinest — the first arrow-shadow beyond `depends`, with DNS pinned as the finest rung; 'unordered list' is fixed for the DNS→LES→{EDQNM,PDF} chain.
- StationarityGate reads ObservablesRole, not StateRole — the correct ergodic content (stationarity detected from observed functions of state, never the microstate), landed as a fact.
- Particles are promoted to a co-equal state KIND (ParticleEnsemble), realized on three rungs, and `#Inertial.slots >= 2` with Inertial.slots = FieldSlot+ParticleSlot makes the material ensemble a co-equal FACTOR of the state product rather than an append-to-DNS afterthought.

**Unresolved (the third pass — small, all-structural, scope-12):**
- TAUTOLOGICAL ASSERTS (the core defect, flagged by all nine lenses): 6 of 11 asserts (seamInterior, closureDissipative, gateReadsObservables, extendsNeverRecarves, stateProductArity, stateRealizedEachRung) merely re-read a value hard-coded in a `one` sig body and cannot fail in scope — the same vacuity class v1 was rejected for, now inside the seam and gate. Each must be re-expressed as a check over a RELATION a mis-carving could actually violate.
- coarseningReduces is a false-but-plausible check: `c.slots != m.slots` tests set-inequality, not reduction — it passes by disjointness (DNS{FieldSlot} vs LES{FilteredFieldSlot}) and passes when a coarser rung ADDS slots. FIX (highest leverage): add a Slot-level `reducesTo`/`projectsTo` relation and check EXISTENCE of a fine→coarse reduction map. This ONE relation simultaneously (a) fixes coarseningReduces, (b) shadows the projection P, (c) turns the LES filter into a projection EDGE instead of a shared FieldRep label, (d) makes EDQNM's shell spectrum the many-to-one angle-average image.
- The projection morphism P — the single most important MZ arrow — has NO shadow though scope 12 permits a static one: no resolved/unresolved (image vs memory) partition per rung, no Q=1−P complement, DNS-as-identity (P=id) only implicit. Mark per rung which slots are the resolved image and which finer-rung slots are the unresolved/memory subspace (FDF's NotionalEnsembleSlot, PDF's CompositionSlot as the closure-reintroduced Q-space).
- The metriplectic CONTENT (degeneracy conditions) is absent: no Energy/Entropy referent object, no Advection→preserves→Energy / Diffusion→dissipates→ε relation to Observables, so the seam is a label not a check. Add a static Energy referent + preserve/dissipate relations with Observables measuring the same object — this makes seamInterior/closureDissipative non-vacuous. Static shadow only; the dynamical conservation stays on the numerical oracle (scope-12 compliant).
- Disconnected poset: fluidLadder wires only DNS→LES and LES→{EDQNM,PDF}; FDF and Inertial have slots but NO coarsens edges — 2 of 6 rungs float free and coarseningReduces/stateRealizedEachRung are vacuous for them. Note dnsFinest is preserved only by leaving Inertial out, since Inertial.slots=FieldSlot+ParticleSlot is a SUPERSET of DNS.slots and would force Inertial→DNS under the refinement logic. Wire FDF/Inertial in or record them as a documented off-ladder branch (deferred≠missing), and resolve the superset-vs-dnsFinest tension.
- Forcing mis-tagged onto=Reversible — a physics category error (forcing is a non-conservative external SOURCE, neither the energy-conserving reversible bracket nor the entropy-producing irreversible one). Root cause: binary GenKind has no Source/External kind; the correct idiom (`no onto`, used by Integrator/Dealias) already exists. Also loses the stationary-HIT budget P=⟨ε⟩. Add a Source kind or tag ForcingStrategy `no onto`. And unify the two parallel Reversible/Irreversible encodings (SubGenerator.sense vs Strategy.onto) with a linking fact so they cannot drift.
- Closure is decoupled from the ladder AND targets a non-existent module: there is no Closure.jl in src/, so the `Closure` module, `Closure→SimulationDomain`, and the caveated `Generator→Closure` edge are pure forward-looking fiction the DNS code denies — a deferred edge must be ABSENT, not present-with-a-comment (this inverts the codebase's own deferred≠missing discipline). Drop the caveated edge; add `requiresClosure` with `no DNS.closure` and closure required for every rung coarser than DNS, turning Closure from an inert object into the morphism (the unclosed term appears iff state is reduced).
- DNS tracers are homeless — the spec contradicts the running code: DNS.slots=FieldSlot omits any ParticleEnsemble slot, yet the Simulation struct holds tracers/tracer_velocity and advect!s them each step (SimulationRun.jl:112-113,295-298; optional, ntracers default 0). Decide and record: add an optional ParticleEnsemble slot to DNS.slots, or a Lagrangian observable role.
- ParticleEnsemble kind is overloaded across three physically-opposite slots — ParticleSlot (physical material tracers), NotionalEnsembleSlot (FDF stochastic model device), CompositionSlot (PDF phase-space samples). The distinction lives only in sig NAMES, erased as a type, so PDF's one-point density reads as a particle method. Refine ParticleEnsemble (subtype, or a physical/notional marker).
- Lagrangian numerics have no Strategy sig and the material-transport morphism is unshadowed: the pluggable tracer interpolation scheme (CatmullRom default / LalescuSpline / LagrangeSpline, a `tracer_scheme` kwarg — a genuine Realization-layer numeric parallel to IntegratorStrategy/DealiasStrategy) and the Heun-in-time push are unmodeled, and dX/dt=u(X,t) (sample the velocity field along the trajectory) has no arrow. Add a Realization Strategy for the scheme and a MaterialAdvection morphism relating a ParticleEnsemble slot to the velocity FieldRep.
- Internal inconsistency on where forcing acts: ForcingStrategy{actsOn=Generator} (physics/RHS view) vs the dependency graph's Propagation→Forcing with Generator NOT depending on Forcing (code view — TimeIntegration imports Forcing and step! applies it). Reconcile the two layers rather than asserting both.
- Lower-priority precision (Continuum/Category residuals): the reversible lump named `Advection` alone hides the Leray projection ℙ (a distinct reversible constraint operator) and pressure balance, and a single `Diffusion` atom conflates viscous ν∇²u and scalar ϰ∇²φ (two coefficients); and the three MZ dynamics roles remain objects not arrows — Propagation as a time-indexed flow/semigroup is the highest-value one to shadow for the ergodic reading. A third pass should consciously decide how far to shadow these, not leave them by accident.

**Readiness (split).** SPLIT VERDICT. (1) READY NOW — the DNS-rung Julia interface skeleton. The confirmed-fixed software spine is sound and code-faithful: the corrected dependency DAG, the four MZ role-homes, the slot-on-FlowState carving, the Specification/Realization Strategy split, and StationarityGate-reads-Observables can seed interface stubs for the modules that ACTUALLY EXIST — SimulationState (which the spec refines into FlowState≈FieldBuffers + SimulationDomain), Dynamics, Observables, Forcing, TimeIntegration, Particles, SimulationRun, Phenomenology. Two caveats to carry into the skeleton: emit NO Closure dependency (that module does not exist yet), and model the optional DNS tracer ensemble that the code already runs. (2) NOT READY — the Model-ladder extensions (LES/FDF/Inertial/PDF/EDQNM + Closure). Driving them off v2 as-is would bake in the disconnected poset, the false `!=` reduction, the absent projection P, a Closure decoupled from the ladder and pointing at a non-existent module, and the overloaded ParticleEnsemble. Do a THIRD PASS first, and it is small and all-structural (scope-12 holds — no dynamics formalization): (i) a Slot-level reducesTo/projection relation replacing coarseningReduces's `!=` — this one relation also shadows P and the LES filter; (ii) complete or explicitly branch the poset for FDF and Inertial, resolving the Inertial-superset-vs-dnsFinest tension; (iii) a static Energy referent + preserve/dissipate relations to make the seam non-vacuous; (iv) fix the Forcing tag and unify the two Reversible/Irreversible encodings; (v) tie Closure to the ladder via requiresClosure and drop the caveated Generator→Closure edge; (vi) home the DNS tracers and refine ParticleEnsemble. Net: proceed with the skeleton in parallel, but gate the ladder work on the third pass — the third pass is the objects→morphisms move all nine lenses asked for, and it converts roughly half the asserts from unfalsifiable label re-reads into real relational checks.


---

## Third pass (v3) — the objects→morphisms move, mechanically verified

Introduced first-class **arrows** so the tautological label-checks became relational ones:
- **Projection `P`** — a slot-level `fine→coarse` reduction (`Projection{fine,coarse,src,dst}`); shadows `P`,
  turns the LES filter and EDQNM angle-average into real edges. `projectionCovers` now checks the
  reduction map *exists* for every coarse resolved slot (a missing edge fails) — replacing v2's false `!=`.
- **The seam wired to measured `Referent`s** (Energy/Dissipation via `Observation`): `Advection` preserves
  Energy, `Diffusion` produces Dissipation — `seamInteriorAndMeasured` / `dissipationIsIrreversible` are
  now checks, not label re-reads.
- **`MaterialAdvection`** (`dX/dt = u`): ensemble slots advected by a `FieldRep` slot.
- **`coarsens` poset** (a plain field, DNS finest) with `resolved / modeled / extra` partition.

Fixed the v2 errors: **Forcing = `Source`** (not Reversible; new `GenKind`); **FDF on-ladder,
Inertial off-ladder** (`extra` dispersed phase, resolving the superset-vs-dnsFinest tension); **`Closure`
is a per-rung requirement, not a fictional module edge** (`needsClosure`; `dnsNoClosure`); **DNS tracers
homed** (`extra`, a `PhysicalTracer` instrument); **`ParticleEnsemble` refined** into
PhysicalTracer/NotionalDevice/CompositionSample; **`TracerScheme`** Realization strategy added.

**Verified:** `run show` SAT (consistent); all 17 checks pass; non-vacuity demonstrated (an intermediate
buggy v3 failed 4 checks). Analyzer wired locally: `java -jar ~/alloy.jar exec -f .claude/architecture.als`.

### v3 panel verdict (nine lenses, self-run analyzer)

**needs-fourth-pass** — 7 lenses fourth-pass, 2 (Geometric, Symmetry) converged (each still listing one
in-scope residual). Bias **pervasive → ~60–70 % resolved**: the *structural* arrows are done and proven
non-vacuous (`Projection`+`projectionCovers` — the buggy intermediate genuinely failed it; the
`SubGenerator` reversible/irreversible split; `MaterialAdvection`; the `coarsens` poset — all KEPT). The
residual was **four named arrows** (all in-scope structural shadows, not decision-12 dynamics) plus **one
bug**: (a) **measurement** — `Observation` a half-arrow, and `fact observed` blanket-forced every referent
observed, making `seamInteriorAndMeasured`/`gateReadsMeasured` *tautological* (the v2 defect surviving at
one remove; two lenses ran a drop-`fact observed` experiment and watched both asserts fail); (b)
**closure/memory** — `needsClosure` had only a negative consumer, LES needs closure yet had no modeled
slot; (c) **source balance** — Forcing a Strategy, never `acts→Energy`, so the P=ε triangle was three loose
tags; (d) **field self-advection** — `SubGenerator` had no `src/dst`, inconsistent with `MaterialAdvection`
being an arrow; (bug) **InertialSlot** tagged `PhysicalTracer` + forced `MaterialAdvection(InertialSlot)` —
the tracer τ→0 limit, structurally false, erasing the slip that is the inertial phase's whole reason to
exist (v2-error-class recurrence).

## Fourth pass (v4) — the bounded arrow completion, mechanically verified

The five fixes the panel enumerated, each new/changed assert paired with a **drop-a-fact experiment**:
- **(1) Measurement DERIVED, not declared.** Deleted `fact observed`; the observed set is now exactly what
  the Observables module computes — `EnergyObs` (`kinetic_energy`), `DissipationObs` (`dissipation`),
  `SpectrumObs` (`energy_spectrum`, `produces = ShellSpectrumSlot`) — each a full arrow `on:Slot →
  observes:Referent`. `seamMeasured`/`gateClosesBudget` now check coverage against an *independent* ground
  truth. `SpectrumObs.produces` homes `ShellSpectrumSlot` on DNS (the E(κ) diagnostic reaches the same
  moment slot EDQNM evolves — verified against `Observables.jl:148,167`).
- **(2) Closure has a positive consumer.** New per-rung `Model.closedBy`; `closureHoming` homes
  `ClosureStrategy` to LES/EDQNM/PDF (FDF closes via modeled DOF). `closureRepresented`:
  `needsClosure[m] ⟹ (some m.modeled or some m.closedBy)`.
- **(3) Source is a sub-generator; gate closes the budget.** New `Injection` (`within=Forcing`,
  `sense=Source`, `acts=Energy`); `StationarityGate.reads` widened to Energy+Dissipation;
  `gateClosesBudget` requires a Source-referent AND an Irreversible-referent read, both measured.
  `forcingStrategyLinked` ties the strategy's and the sub-generator's `sense`.
- **(4) Field self-advection arrow.** `SubGenerator` gains `src/dst`; Advection/Diffusion are
  `FieldSlot→FieldSlot`; `seamEndomorphic` checks the Generator's halves are endomorphisms of a DNS
  resolved slot; `seamOneSided` quantifies the degeneracy over `sense` (not by name).
- **(5) Inertial bug fixed.** New `InertialParticle` `EnsembleRole`; `InertialSlot` retagged;
  `materialAdvection` restricted to `EnsembleRole − InertialParticle`; `inertialNotMaterial` asserts the
  inertial phase is never materially advected.

**Verified (clean v4):** `run show` **SAT 1/1** (consistent); **all 23 checks UNSAT** (assertions hold).
**Non-vacuity — 7 drop-a-fact experiments, each flips its target UNSAT→SAT** under a single perturbation:
`seamMeasured` (retag DissipationObs), `closureRepresented` (drop `LES.closedBy`), `gateClosesBudget`
(read Energy only), `inertialNotMaterial` (re-admit InertialParticle), `seamEndomorphic` (Diffusion.dst→
FilteredFieldSlot), `spectrumHomedOnDNS` (drop `produces`), `seamInterior` (Injection→Generator). The three
measurement asserts that were the surviving v2-class tautology are now falsifiable-by-construction.

### v4 panel verdict — CONVERGED (unanimous)

The nine-lens panel re-read v4, each lens given its specific v3 residual → v4 fix and told to **run the
analyzer and its own drop-a-fact experiment** rather than trust the mechanical claims. **All eight
returning lenses ruled `converged`** (the GENERIC/metriplectic agent died on a StructuredOutput retry cap;
its concern — the measurement tautology — was independently verified fixed by the Mori–Zwanzig and Category
lenses). The **synthesizer reproduced the mechanical result on its own headless Alloy runner (23/23 UNSAT,
`run show` SAT) and ran 11 of its own perturbations** — verdict verbatim: *"v4 is CONVERGED and
objects-over-morphisms is RESOLVED … record v4 as the canonical shadow and seed the DNS Julia skeleton. No
fifth pass needed."* Every surviving residual is either decision-12 dynamics that legitimately stays off
Alloy (the Q→resolved memory-kernel operator — its structural shadow, closure on the Irreversible half, is
present; the propagation semigroup; the P=ε numerical equality; the inertial slip law; the invariant
measure) or an explicit non-gating nicety.

**Two ride-along cleanups (edits, not a pass):**
- **Fixed** — the `seamMeasured` non-vacuity comment overstated ("drop EnergyObs *or* DissipationObs"):
  Energy is double-covered (EnergyObs + SpectrumObs), so only DissipationObs is load-bearing. Verified by
  experiment (dropping EnergyObs leaves `seamMeasured` UNSAT); comment corrected.
- **Considered and rejected** — a `spectrumIsReducedState` coherence assert (the produced slot is a coarse
  rung's resolved state). The non-vacuity experiment showed it *cannot be falsified* with the current slot
  inventory (`ShellSpectrumSlot` is the only `StatMoment` and is already `EDQNM.resolved`), so it would be a
  near-tautology — the defect class this spec exists to avoid. Not added; a comment records why. The content
  is already carried by the (non-vacuous) `spectrumHomedOnDNS`.

**Final v4 state:** `run show` SAT 1/1; **all 23 checks hold**; **8 drop-a-fact experiments** (7 mine + the
EnergyObs-redundancy check) each behave as predicted. Objects-over-morphisms **resolved**; the v2-class
measurement tautology **dead**. **CONVERGED — ready to record as the canonical structural shadow in
`ARCHITECTURE.md` and to seed the DNS Julia skeleton** (both are user-gated forward steps).

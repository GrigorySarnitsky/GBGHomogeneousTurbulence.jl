# Docstring review pile — round 2

> **Round 1 (§1–§31 + the architecture-review pile) is fully worked off** (commits `e56583a`,
> `2e12afc`, `1ad1eca`) — see [`.claude/README.md`](./README.md) and `docstring-review-pile.md` for its
> classes and cold-read probes (reusable). This file collects a **fresh** read of the docs as they now
> stand: post-fix-pass, post-`kinetic_energy`/`scalar_variance` rename (HEAD `1ad1eca`).

**The rule (unchanged, learned the hard way).** I only **collect** here. I do **not** edit any `src`/`docs`
file, run a build, or commit — **until you explicitly say to fix** (e.g. "fix the pile" / "orchestrate
the reading"). A report is a pile entry, never a green light to touch the code. Fixing happens later, in
one pass, catching each instance *and its siblings*.

**Worked off.** Round-2 §1–§19 are fixed across commits `fd93722`, `1039f3b`, and the InterLinks commit
(§4 clickable links + §11 `Phenomenology` `@ref`); each entry's own **Status** records how. Deferred (by
decision, not omission): §27 (BandRescaling total-vs-resolved note, minor) and D3 (kwargs principle).

---

## 1 — User-facing docs cite a dependency's internal architecture choice

- **You said** (`index.md` intro, of the sentence "`GBGPeriodicFields` is deliberately time- and
  particle-free; this package is the consumer that owns time integration, forcing, the scalar transport,
  particle tracking, and the statistics."): *"no need to cite in user facing API architecture choices of
  a different package. Remove that sentence."*
- **Class.** A user-facing surface (landing page / API) states or justifies the **internal design
  rationale of a dependency** — *why PF is shaped as it is* ("deliberately time- and particle-free") —
  which the IT user does not need. The user's first read should say what **this** package does; a
  dependency's design decisions, and the IT/PF division-of-labour rationale, belong in the design doc
  (`ARCHITECTURE.md`), not the user-facing surface.
- **Probe.** Scan every user-facing surface (`index.md`, `api.md`, module/type docstrings) for a clause
  about a **dependency's** design — "PF is deliberately X", "designed to Y", "because
  `GBGPeriodicFields`/`GBGStreamingStatistics` does Z", any *why-a-dependency-is-shaped-so*. Keep
  "built on PF, which supplies …" (a fact the user needs); cut the rationale (another package's
  architecture choice).
- **Fix direction.** Remove the flagged sentence only; keep the surrounding "built on
  `GBGPeriodicFields`, which supplies every field operation …" and the GPU-primary sentence. Do **not**
  touch `ARCHITECTURE.md` — the division-of-labour rationale is exactly what the design doc is for.
- **Verified.** `docs/src/index.md:11–13`: "… interpolation, and reductions. `GBGPeriodicFields` is
  deliberately time- and particle-free; this package is the consumer that owns time integration,
  forcing, the scalar transport, particle tracking, and the statistics. The GPU is the primary target
  …" — the middle sentence is the target. **Sibling (non-rendered):** the umbrella `#`-comment header in
  `src/GBGIsotropicTurbulence.jl:3–9` carries the same citation ("`GBGPeriodicFields` is deliberately
  time- and particle-free (its invariant 12); this package is the consumer that owns …") — an internal
  comment, not user-facing, so a separate judgment at fix time. The rendered module **docstring** is
  already clean ("Built on `GBGPeriodicFields`.").
- **Status.** collected.

---

## 2 — A module's map bullet over-specifies, and cites a type from another module

- **You said** (`index.md` Components, the `Forcing` bullet): *"Do flow conditions live in the Forcing
  module? If not, you can't show in the Forcing entry. I don't think that there should be more examples
  then just Abstract forcing, just mentioning that we can force both velocity and scalar is enough. Look,
  Propagator only speaks about AbstractIntegrator and that's all."*
- **Class A — wrong-module citation (correctness).** A module's map bullet names a code object owned by
  a *different* module. `FlowConditions` is defined and exported by the **`Generator`** module (it moved
  there with the `Physics`→`FlowConditions` refactor, D4), not `Forcing` — so citing
  `FlowConditions(; velocity_forcing, scalar_forcing)` in the `Forcing` bullet attributes a neighbour's
  type to Forcing. A module entry may name only what that module owns.
- **Class B — sibling map-depth inconsistency (register).** Sibling Components bullets sit at
  inconsistent depth: `Forcing` over-specifies (a constructor example + a usage scenario) while its
  sibling `Propagator` names only the supertype ("the interchangeable integrating-factor schemes under
  `AbstractIntegrator`"). The user's standard is the minimal one — name the supertype + a one-line gist,
  no constructor examples, no cross-module mechanism.
- **Probe A.** For each module bullet, is every backticked code name it cites actually **exported by that
  module**? Flag any that names a type/function belonging to a neighbour.
- **Probe B.** Across the Components bullets, are siblings at consistent (minimal) depth — supertype +
  gist, no constructor examples or enumerated concretes? Flag the over-specified ones. (Applying this to
  *every* bullet — e.g. also trimming the `SimulationDomain` / `State` / `Observables` enumerations — is a
  consistency decision to **bring to the user**, not apply unilaterally.)
- **Fix direction (as you gave it).** `Forcing` bullet → "the interchangeable energy-injection strategies
  under `AbstractForcing`, chosen independently for the velocity and the scalar." — drop the
  `FlowConditions(...)` parenthetical and the "commonly a forced velocity with a freely-decaying scalar"
  scenario, parallel to the `Propagator` bullet.
- **Verified.** `FlowConditions` is defined in `src/Generator.jl` and exported by the `Generator` module
  (`export …, FlowConditions`); the `Forcing` module exports no `FlowConditions`. The wrong-module
  citation + over-specification appears on **two** user-facing surfaces: `docs/src/index.md` (the
  Components `Forcing` bullet) **and** `docs/src/api.md` (the API-overview `Forcing` bullet, which *also*
  enumerates `NoForcing`/`BandRescaling`/`Linear`/`ConstantPower` and repeats the
  `FlowConditions(; velocity_forcing, scalar_forcing)` mechanism + scenario). The `Propagator` bullets on
  both pages are the minimal model.
- **Status.** collected.

---

## 3 — Module docstring is a cramped prose inventory; bullet it per the API page's sections

- **You said** (`api/SimulationDomain.md`, the rendered module docstring): *"Still a little bit cramped.
  You already split the module doc page into sections — why not make a bullet for each such section in the
  module docstring? will be much more readable."*
- **Class.** A **module docstring** runs its contents together as one dense prose paragraph, when a
  **bulleted map** reads far better — and the natural grouping already exists as the module's **API-page
  `##` sections**. A module docstring and its API page should share one structure: one bullet per section,
  each a linked one-liner. (The "module docstring = map" policy — round-1 #18 — made concrete via the
  page's own grouping. The round-1 pass bulleted the `FixedDomain` *type* docstring but left the
  `SimulationDomain` *module* docstring as prose.)
- **Probe.** For each module, does its docstring mirror the `##` sections of `api/<Module>.md` as bullets,
  or is it a prose inventory? Where the API page groups the module's objects into sections (it does for
  most), the module docstring should present the same groups as bullets.
- **Fix direction.** Rewrite the `SimulationDomain` module docstring as a bulleted map, one bullet per
  API-page section (verified against the page): **the discretised box** ([`FixedDomain`](@ref));
  **de-aliasing strategies** ([`DealiasingStrategy`](@ref) / [`TwoThirds`](@ref) / [`HouLi`](@ref)) and
  the cutoff they set ([`max_wavenumber`](@ref)); **scratch-field allocators** ([`spectral_vector`](@ref),
  …); **de-alias filtering** ([`dealias!`](@ref)). Keep the closing "precision and backend enter here and
  flow everywhere from here." Then **sweep the other module docstrings** the same way against their API
  pages — a consistency pass; bring the shape to you if a module resists a clean per-section mapping.
- **Verified.** `src/SimulationDomain.jl:8–16` is a single dense paragraph. `docs/src/api/SimulationDomain.md`
  already carries four `##` sections — "The discretised box" (`FixedDomain`), "De-aliasing strategies"
  (`DealiasingStrategy`/`TwoThirds`/`HouLi`, with `max_wavenumber` as the cutoff sub-group),
  "Scratch-field allocators" (the six `*_vector`/`*_spectral`/`*_physical` allocators), "De-alias
  filtering" (`dealias!`). Every sibling module (`State`, `Forcing`, `Generator`, `Observables`,
  `Propagator`, `Particles`, `SimulationRun`) also has a sectioned API page — candidates for the same
  bullet-per-section treatment.
- **Status.** collected.

---

## 4 — External and cross-package types left backticked, not clickable links (round-1 #19, under-delivered)

- **You said** (FixedDomain docstring, of `Array (CPU) or CuArray / ROCArray (GPU)`): *"I thought
  previously I made a specific point on making Array (CPU) or CuArray / ROCArray (GPU) clickable links to
  the Julia packages. Plus Grid3D and other objects from PF should be clickable, leading to the PF docs.
  Did you miss more of my requests?"* (Round-1 #19 verbatim: *"Array/ROCArray/CuArray need to be
  clickable and lead to the appropriate Julia packages"*; *"proper clickable references to PF"*.)
- **Class.** Types a docstring names but IT does **not own** — PF types (`Grid3D`,
  `FieldSpectralMultipliers`, `PointSet`, …) and external array types (`Array`→Base, `CuArray`→CUDA,
  `ROCArray`→AMDGPU) — are left **backticked, not clickable links**. IT-internal types *are* `@ref`-linked,
  so the docstrings are **inconsistent**: some type names are links, others dead code spans. This is a
  docs-**infrastructure** gap, not a per-docstring text fix — cross-package `@ref` needs
  **`DocumenterInterLinks`** (register each package's `objects.inv` inventory), which IT's docs lack.
- **Probe.** Every backticked type IT does not own — a PF type or an external/Base type — should be a
  clickable link to that package's docs. Sweep **all** docstrings and API pages, not just `FixedDomain`
  (`Tracers`→`PointSet`/`VectorPointValues`, the allocators' PF return types, `Grid3D`,
  `FieldSpectralMultipliers`, and `Array`/`CuArray`/`ROCArray` wherever they appear).
- **Fix direction.** Docs-infra: add `DocumenterInterLinks` to `docs/Project.toml`, load the inventories
  (Base/stdlib, CUDA, AMDGPU, and PF's own `objects.inv` from its docs site) in `docs/make.jl`, then link
  every external/PF type across the docstrings. **Check whether PF/SS docs already use
  `DocumenterInterLinks` and match their approach.** (Explicit markdown URLs are the fragile fallback if
  an inventory isn't published.)
- **Verified.** `docs/Project.toml` lists only `Documenter` — no `DocumenterInterLinks`; `docs/make.jl`
  has no interlink config. In the `FixedDomain` docstring, IT-internal types (`DealiasingStrategy`,
  `TwoThirds`, `HouLi`, `dealias!`, `recommended_cfl`) are `@ref`-clickable, while PF (`Grid3D`,
  `FieldSpectralMultipliers`) and external (`Array`, `CuArray`, `ROCArray`) are backticked only.
- **Meta (owning it).** A round-1 directive (#19 + the "Clickable references" cross-cutting directive)
  the fix pass **under-delivered and under-communicated**: I backticked the external/PF types (build-safe,
  since `@ref` to them fails without interlinks) and deferred the linking without clearly flagging it.
  **Related under-delivery:** the #19 sub-directive *"See SS's package-wide consistent docstring look"* was
  approximated (bulleted args, SS-style) but not verified against SS's actual convention — a genuine pass
  is owed at fix time.
- **Status.** ✅ FIXED. `DocumenterInterLinks` wired in `docs/make.jl` (Base/CUDA/AMDGPU/PF `objects.inv`;
  PF at `dev`, the only inventory it publishes) + added to `docs/Project.toml`. Linked the **whole class** of
  standalone external/PF type spans and the `notation.md` PF functions via `@extref`: `Array`/`Float32`/
  `Float64` (Julia — role-pinned `:jl:type:` so they hit the type, not the `-Tuple{Any}` constructor method),
  `CuArray` (the CUDA `The-CuArray-type` label — no type-docstring in its inventory), `ROCArray`, `Grid3D`,
  `FieldSpectralMultipliers`, `Vector`/`ScalarPointValues`, and `to_spectral`/`to_physical`/`curl`/`divergence`/
  `helmholtz_projection`/`convolve`/`radial_spectrum`. Every resolved href verified in the built HTML; the
  bare-span residual sweep is clean; CI-style build (develop + instantiate) green. (SS-look sub-directive from
  Meta still owed.)

---

## 5 — Type-docstring structure: constructor/arguments first, fields demoted to a technical note

- **You said**: *"Also we need to think about the structure of type docstrings. First we should probably
  describe the constructor (arguments), then if needed examples, then as a technical note (section like
  arguments), the plain constructor and explanation of its fields."*
- **Class.** A **type docstring** should be ordered user-facing-first — the type analogue of the
  function-docstring policy (identity → use → arguments → …). The intended order:
  1. one-sentence **identity**;
  2. the **constructor and its arguments** — how the user builds and uses the type (promoted; the
     primary read);
  3. **examples**, if needed;
  4. a demoted **technical-note section** (formatted like the Arguments section) holding the **plain
     (all-fields positional) constructor** and the **explanation of its fields**.
  The current type docstrings invert this — they front-load the struct's internal **fields**, then the
  arguments. Fields are reference / implementation detail, not the user's first need; the constructor +
  arguments lead.
- **Probe.** For each type docstring, does it lead with the **constructor + arguments** (user-facing) or
  with the **internal fields** (implementation)? The reader's first question is "how do I make one and
  what do the arguments mean" — fields belong in a demoted technical section.
- **Fix direction.** Reorder every type docstring to: identity → `# Arguments` (the convenience
  constructor's arguments) → examples (if any) → a demoted `# Fields` / technical section (the plain
  positional constructor + the field bullets). This flips the `FixedDomain` and `IntegratorBuffers`
  docstrings written in the fix pass (both are fields-first). Sweep all type docstrings (`FixedDomain`,
  `IntegratorBuffers`, `Simulation`, `Tracers`, `ResolvedFields`, `FlowConditions`, the forcing /
  integrator structs). **Consider promoting this to a documented type-docstring structure** in
  `CLAUDE.md` — which specifies the function-docstring structure but not the type analogue; a policy call
  to bring to you. (Detail for fix time: whether to literally render a 10-arg positional constructor, or
  just the field bullets, in the technical section.)
- **Verified.** `FixedDomain` (`SimulationDomain.jl`) orders identity → "Its fields:" (bulleted) →
  `# Arguments` — fields-first. `IntegratorBuffers` (`Propagator.jl`) likewise (fields bulleted, then
  `# Arguments`). Both need the flip.
- **Status.** collected.

---

## 6 — One sentence conflates the package's own behavior with a reference-code comparison (unjustified)

- **You said** (HouLi docstring): *"'Applied isotropically in κ (the filter TurTLE uses, there
  per-axis).' Not clear, what Turtle uses. You mix in one sentence the behavior of our package in how the
  filter is applied, mention that turtle uses the same filter, and somewhere 'there' per-axis (not that
  clear what is per axis). Move whatever Turtle uses and how in a single separate sentence. If the Turtle
  mention is actually needed — why is that important for the user?"*
- **Class A — conflation + ambiguous demonstrative.** A single sentence mixes **what this package does**
  ("applied isotropically in ``\kappa``") with **what an external code does** ("the filter TurTLE uses,
  there per-axis"), so the reader can't separate the two — and the demonstrative "there" is ambiguous
  (it means *in TurTLE*, but reads as vague; "per-axis" applies to TurTLE's application, not ours). Split
  by subject: our behavior in one sentence, the external comparison (if kept) in its own.
- **Class B — unjustified reference-code citation.** A user-facing docstring cites a reference DNS code
  (TurTLE) and its differing implementation choice (per-axis vs our isotropic) with no user-facing
  reason. Prior-art comparisons are `ARCHITECTURE.md`'s job (the TurTLE / GHOST / hit3d cross-check
  references live there), not a user's docstring. Default: cut it and state only our behavior; keep only
  for a concrete user need, and then as a clean separate sentence. (Sibling of #1 — don't cite other
  codes' internal choices in user-facing docs — here a *reference* code, not a dependency.)
- **Probe A.** Does any sentence mix "what this package does" with "what an external / reference code
  does," or use an ambiguous "there" / "it" that could point to either? Split by subject.
- **Probe B.** Does any user-facing docstring cite a reference DNS (TurTLE / GHOST / hit3d) or its
  implementation detail? Is it justified by a user need? If not, cut it (or move the prior-art to
  `ARCHITECTURE.md`).
- **Fix direction.** "Applied isotropically in ``\kappa`` (the filter TurTLE uses, there per-axis)." →
  "Applied isotropically in ``\kappa``." — drop the parenthetical. If a provenance note is wanted, make
  it a separate sentence and put the "TurTLE applies it per-axis" comparison in `ARCHITECTURE.md`.
  Keep-or-cut is a call to bring to you.
- **Verified.** The only reference-DNS mention in any `src` docstring is this one — `SimulationDomain.jl:65`,
  the HouLi docstring: "… Applied isotropically in ``\kappa`` (the filter TurTLE uses, there per-axis).
  …" No `GHOST` / `hit3d` / other `TurTLE` in docstrings, so this is a single instance (the class is
  recorded for vigilance, not a wide sweep).
- **Status.** collected.

---

## 7 — General-purpose allocators documented by their current uses, not their general contract

- **You said** (Scratch-field allocators): *"Do you think we need to document the purpose of the
  allocation and provide example of which physical field is allocated? Because that might suggest those
  are the only uses and we don't want to list and maintain here the list of all the uses. It is enough
  here to state the math (the tensor field order and the representation)."*
- **Class.** A **general-purpose utility** (here the field allocators) is documented by its **specific
  current uses** — which physical field each is "used for" (the scalar ``\varphi``, the integrating
  factor, the strain-rate tensor, a time-loop buffer) — which (a) wrongly implies those are the **only**
  uses and (b) is a **maintenance burden** (the use-list goes stale as callers change). State only the
  general contract — the field's tensor **order** (scalar / vector / second-order tensor) and
  **representation** (spectral / physical), on the domain's backend and element type — never a list of
  callers. (These are thin, physics-free allocators; which field goes where is the *caller's* concern,
  not the allocator's docstring. Ties round-1 #4 — stale exhaustive lists.)
- **Probe.** For a general-purpose utility (allocator, generic helper), does its docstring enumerate
  specific current uses / callers ("used for X", "scratch for Y")? Replace with the general contract; no
  use-list.
- **Fix direction.** Strip the use-parentheticals so all six read uniformly — "Allocate a single zeroed
  {vector | scalar | second-order tensor} field in {spectral | physical} representation on `domain`'s
  backend and element type." — the form `physical_vector` already has (the clean model). Drop:
  `spectral_vector` "(a scratch buffer for the time loop)"; `scalar_spectral` "(used for the scalar
  ``\varphi``, the integrating factor, and kernel scratch)"; `scalar_physical` "(used for the scalar
  ``\varphi`` in physical space)"; `tensor_spectral` "(scratch for the strain-rate tensor
  ``\boldsymbol{S} = \operatorname{sym}\nabla\boldsymbol{u}``)". **Secondary consistency fix:**
  `tensor_spectral` and `tensor_physical` also dropped the "on `domain`'s backend and element type"
  clause the other four carry — add it so all six are uniform.
- **Verified.** `SimulationDomain.jl:198–253`. `physical_vector` (:208–212) is already clean — "Allocate
  a single zeroed vector field in physical representation on `domain`'s backend and element type." The
  other five carry use-parentheticals; `tensor_spectral` (:237–242) and `tensor_physical` (:247–252)
  additionally omit the "on `domain`'s backend and element type" clause.
- **Status.** collected.

---

## 8 — "The observables read it as external functions of (û, φ̂)" — inaccurate (joint, and spectral)

- **You said** (ResolvedFields docstring): *"'and the observables read it as external functions of (û, φ̂)'
  — is that still accurate? I thought some observable run on a single velocity or scalar field, and not
  necessarily on the spectral representation."*
- **Class.** A docstring over-specifies how a set of operations consumes the state — "external functions
  of ``(û, φ̂)``" implies each observable is a **joint** function of **both** spectral fields. In fact
  each is a thin function of a **single** field (velocity, vorticity, or scalar) in the representation
  **natural to it** — physical for `max_speed`, either (Parseval) for `kinetic_energy` / `scalar_variance`
  / `dissipation`, spectral for `derivative_skewness` / `energy_spectrum` / `integral_scale` /
  `scalar_dissipation`. The architectural point (observables are *external* functions of the inert state,
  not methods on it) is right; the "``(û, φ̂)``" is wrong on both axes (joint, and spectral). Reflects
  the round-1-established design: observables are thin, representation-agnostic, the run layer prepares
  what each needs.
- **Probe.** For any "X reads/consumes the state as functions of (a, b)" claim, check the actual
  signatures — do the ops take the joint tuple or single fields, and in which representation? A blanket
  "(û, φ̂)" / "spectral" claim is stale if some ops take one field or a physical field.
- **Fix direction.** Reword so the observables aren't cast as joint-spectral functions — keep the
  "external functions of the inert state, not methods on it" point; convey that each consumes a single
  derived field in its natural representation. **Likely mooted by #9** (which would strip the MZ-framing
  sentence from the user-facing docstring outright). Sibling: `ARCHITECTURE.md:187` (§4.1) has the same
  phrasing — but that is the developer-facing home, where "functions of the state" is defensible.
- **Verified.** `State.jl:34` (ResolvedFields): "…observables read it as external functions of
  ``(\hat{\boldsymbol u}, \hat\varphi)``." Against `Observables.jl`: `kinetic_energy(u)` (:36),
  `dissipation(ω, ν)` (:48), `scalar_variance(φ)` (:68) single-field, representation-agnostic (`inner`);
  `max_speed(u)` (:58) single-field **physical** (`maximum(abs, field_data(u))`);
  `derivative_skewness(û, domain)` (:125), `energy_spectrum(û, domain)` (:149), `integral_scale(û, domain)`
  (:168), `scalar_dissipation` single-field spectral. **None** takes the joint `(û, φ̂)`.
- **Status.** collected.

---

## 9 — Mori–Zwanzig framing appears in user-facing docstrings; bound it to the developer docs

- **You said**: *"Do we mention MZ in the user api? I would prefer it to be bounded to architecture and
  docs facing the developer of the package, not its user."*
- **Class.** The **Mori–Zwanzig lens** — the package's *architectural* framing (the State / Generator /
  Observables / Propagator roles) — leaks into **user-facing docstrings**. It's a design/developer
  concept: the API user needs to know what a type/module *is and does* (the evolving spectral state; the
  equations of motion; the measured diagnostics), not the MZ role it realises. Bound MZ to
  `ARCHITECTURE.md` and developer-facing surfaces; strip it from the rendered docstrings.
- **Probe.** Grep every user-facing surface (rendered `src` docstrings, `docs/src/*.md`) for "Mori",
  "Zwanzig", "MZ", "the … role", "in the MZ reading". Each should describe the object plainly; the MZ
  rationale lives only in `ARCHITECTURE.md` (and, a judgment call, `#` source comments — developer-facing).
- **Fix direction.** Rewrite the three MZ-role module docstrings and the `ResolvedFields` docstring to
  drop the MZ framing, keeping the plain description: `State` ("The evolving state the dynamics acts on
  and how it is seeded: `ResolvedFields` …"); `Generator` (drop "In the Mori–Zwanzig reading … this is
  the generator", keep "the flow's equations of motion — the RHS the propagator advances");
  `Observables` (drop "In the Mori–Zwanzig reading … these are the observables", keep "the measured
  functions of the flow state"); `ResolvedFields` (drop "the Mori–Zwanzig state"). **Candidate to bring
  to you:** `notation.md`'s "Lens symbols" section (the MZ projection ``\mathcal P``, the FDF, the LES
  filter — "not realised in code") is design-lens material sitting in the user glossary — relocate to
  `ARCHITECTURE.md` or clearly demarcate. The `#` source comments are developer-facing (not rendered) —
  keep or drop, your call.
- **Verified.** MZ in rendered docstrings: `State.jl:9` (module) + `:29` (ResolvedFields),
  `Observables.jl:12` (module), `Generator.jl:16` (module) — only these three modules;
  `Propagator`/`SimulationRun`/`Forcing`/`Particles`/`SimulationDomain` docstrings are already MZ-free.
  User glossary: `notation.md:90,99` (the Lens-symbols section + the ``\mathcal P`` row). `#` comments
  (dev-facing): `GBGIsotropicTurbulence.jl:11,15`, `State.jl:1`, `Observables.jl:3`, `Generator.jl:3`.
  `ARCHITECTURE.md` is the intended home — untouched.
- **Status.** collected.

---

## 10 — `ResolvedFields`: struct fields named only in passing, not documented for access

- **You said** (ResolvedFields docstring): *"Once again, a struct, but no description of its fields.
  Though one might actually want to access its fields, this needs to be documented."*
- **Class.** A user-facing struct whose **fields** are named only in passing (inline in the prose), not
  documented as an accessible **field list** — the reader can't see at a glance what's inside or how to
  read it. `ResolvedFields` holds `velocity` (``\hat{\boldsymbol u}``) and `scalar` (``\hat\varphi`` or
  `nothing`), which a user *does* reach (`sim.state.velocity`, `sim.state.scalar`) — so they need a
  proper field description. (Concrete instance of round-1 #15 and round-2 #5 — the demoted `# Fields`
  section.)
- **Probe.** For each user-facing struct, are its accessible fields documented as a described list (not
  just mentioned in prose)? Reader's question: "what's inside and how do I read it?"
- **Fix direction.** Under #5's type-docstring structure, give `ResolvedFields` a `# Fields` section
  documenting `velocity` (the spectral velocity ``\hat{\boldsymbol u}``, the single source of truth) and
  `scalar` (the spectral scalar ``\hat\varphi``, or `nothing` when the run carries no scalar). Sweep every
  user-facing struct for the same — round 1 bulleted `FixedDomain` / `IntegratorBuffers` / `Tracers` /
  `Simulation`, but `ResolvedFields`, `FlowConditions`, and the forcing / integrator structs may still
  lack a field list. Folds into the #5 reorder.
- **Verified.** `State.jl:36–39`: `struct ResolvedFields{UH, PH}` with fields `velocity` (`# û
  (spectral)`) and `scalar` (`# φ̂ (spectral), or nothing`). The docstring (:29–34) names
  `velocity`/`scalar` only inline in the prose, with no field list; `sim.state.velocity` is read by the
  run layer, so the fields are user-reachable.
- **Status.** collected.

---

## 11 — `Phenomenology` (an IT-internal submodule) not clickable, though it should be

- **You said** (random_solenoidal_velocity! / random_scalar!): *"Why Phenomenology is not clickable here?
  I thought I raised that point before."* (Round-1 #19 clickable-references directive.)
- **Class.** An **IT-owned** submodule / type named in a docstring is left backticked, not linked. Unlike
  the external / PF types of #4, `Phenomenology` is *internal* (it has its own `docs/src/phenomenology.md`
  page), so it can be linked **without** the cross-package interlink infrastructure #4 needs — the
  *fixable-now* half of the clickable-references directive.
- **Probe.** Every IT-owned object named in a docstring (submodules, types, functions) should be a
  clickable `@ref` (or a page link for a submodule not documented via `@docs`). Sweep for backticked IT
  names that resolve within IT's own docs.
- **Fix direction.** Make `Phenomenology` clickable at every mention — `[`Phenomenology`](@ref)` if the
  submodule is documented via `@docs`/`@autodocs` (**verify it resolves** — it's deliberately not
  re-exported by the umbrella), else a page link `[`Phenomenology`](phenomenology.md)`.
- **Verified.** `Phenomenology` backticked-not-linked in 7 docstring spots: `State.jl:60`
  (random_solenoidal_velocity!), `:109` (random_scalar!), `Observables.jl:147` (energy_spectrum), `:165`
  (integral_scale), `SimulationRun.jl:104` (Simulation), `:212` (flow_parameters), `:228`
  (validate_spectrum). A `docs/src/phenomenology.md` page exists.
- **Status.** ✅ FIXED. Linked the first mention in each of the 7 docstrings via
  `[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology)`. **Key finding:** the *bare* `[`Phenomenology`](@ref)`
  does NOT resolve — from a sibling module's scope Documenter reads it as `<Module>.Phenomenology` (no docstring)
  and errors that the umbrella fallback "is only allowed for fully qualified names"; the **fully-qualified** `@ref`
  target is required. The self-reference in `Phenomenology.jl`'s own module docstring and two `#` source comments
  are left bare (correct); the `.md` API pages already carried the link. The build resolves all three pages' refs.

---

## 12 — Sentences starting with a lowercase code identifier (round-1 #29, UNDER-SWEPT)

- **You said**: *"you start a sentence with the code identified, didn't I tell you not to do that? The
  problem is the capitalization. Bullet lists are fine, they often start with lower-case letter anyway.
  But not a normal sentence. Again, what else did you miss from the last time?"*
- **Class (refined).** A **normal prose sentence** must not open with a lowercase code identifier — a
  sentence starts with a capital, a lowercased `` `identifier` `` breaks that. **Bullets are exempt**
  (they routinely start lowercase). Round-1 #29 flagged this for `Tracers`; the fix pass corrected *that*
  instance but **did not sweep the class**.
- **Probe.** In prose (not bullets), does any sentence open with `` `lowercased_identifier` `` — at a
  paragraph start or after a period? Reword to lead with a capitalised word ("The `domain` …"), or move
  the argument into a bulleted `# Arguments` section (where lowercase is fine — converges with #5).
- **Verified (full sweep).** Clear violations — a prose sentence opening with a lowercased identifier:
  - `Forcing.jl:82` (`set_forcing_rate!`): "… rate. `field` is the start-of-step field …"
  - `State.jl:62` (`random_solenoidal_velocity!`) & `:111` (`random_scalar!`): "`domain` is the
    `FixedDomain` … ; …" (paragraph start) — **the flagged pair**.
  - `Observables.jl:146` (`energy_spectrum`) & `:166` (`integral_scale`): "… ½. `domain` (a `FixedDomain`)
    supplies …"
  - `SimulationRun.jl:77` (`Simulation`): "… Δx ≈ η. `kinetic_energy` and `side_length` fix the units …"
  - `SimulationDomain.jl:58` (`HouLi`): "… Nyquist wavenumber. `order` sets the sharpness …";
    `:262` (`dealias!`): "… only damps the aliasing). `field` may be a vector …"

  Borderline (semicolon clauses — user to decide; a `;` joins a clause, not a new sentence, but some read
  as near-sentences): `Forcing.jl:136`, `Observables.jl:119`, `SimulationDomain.jl:59`, and the `; rng is`
  half of `State.jl:62/111`. (Line-wrap false positives and `#` comments excluded.)
- **Meta (owning it).** Round-1 #29 was fixed at its flagged instance (`Tracers`) but the **class was not
  swept** — 8 more slipped through, two of them lines *I edited in the fix pass* (`State.jl:62/111`).
  This is the **second** class (after #4 clickable-refs) where the pass fixed the flagged line but not its
  siblings → a systematic re-audit of every round-1 *sweep*-class is owed (see the response).
- **Status.** collected.

---

## 13 — Re-audit of every round-1 sweep-class (proactive, requested)

- **Context.** After #4 and #29 proved under-swept (flagged instance fixed, class not), a read-only
  re-audit of every round-1 *sweep*-class against the current code (HEAD `1ad1eca`), to surface residuals
  before fixing.
- **Confirmed clean (rendered surfaces):**
  - **#6 jargon** — pluggable / plug / hook / knob / SE idiom / "spectral machinery" / "operator bundle":
    none on any rendered surface.
  - **#9 "symbol of −∇²"** — none (all now the physical statement).
  - **#21 argument-by-contents** (a `domain` arg re-enumerating `FixedDomain`'s contents) — none in a
    rendered docstring; the only hits are a `#` dev comment (`GBGIsotropicTurbulence.jl:14`) and the
    positional-constructor code (`SimulationDomain.jl:151`), neither user-facing.
  - **#26 citations** on the public surface — `Betchov 1956` / `Williamson 1980` carry years; "(Rogallo)"
    is an *eponym* in a `#` comment (a *Rogallo frame*, not a cited finding), not a bare citation.
- **Residual — a THIRD under-swept class (#2/#12 register asymmetry).** The map bullets were fixed in the
  pass, but ~6 **docstrings** still name the velocity by word while the scalar carries its symbol
  ``\varphi`` in a formula-free context:
  - `Forcing.jl:90` (`apply_forcing!`): "a velocity or scalar ``\varphi`` field"
  - `Forcing.jl:254` (`Linear`): "either the velocity or the scalar ``\varphi``"
  - `Generator.jl:141` (`integrating_factor!`): "``\nu`` for the velocity and ``\nu/\mathrm{Sc}`` for the
    scalar ``\varphi``"
  - `Particles.jl:118` (`sample!`/buffers): "`VectorPointValues` for the velocity, a `ScalarPointValues`
    for the scalar ``\varphi``"
  - `SimulationDomain.jl:92` (`FixedDomain` fields bullet): "the velocity (a vector field), the scalar
    ``\varphi``, and the rank-2 strain tensor"
  - `SimulationRun.jl:60` (`Simulation`): "divergence-free velocity … a mean-zero scalar ``\varphi``"
  Per round-1 #12 (formula-free ⇒ neither sibling carries a symbol), the fix drops the ``\varphi`` — or
  adds ``\boldsymbol u`` for symmetry, a **consistency call to bring to the user**.

  **Grep gap (corrected).** The bullets above were found by grepping ``\varphi`` (LaTeX); the sweep
  **missed Unicode-`φ`** instances — two of them **user-facing doc pages**: `docs/src/api/Generator.md:19`
  ("the physical velocity, vorticity, and scalar φ") and `docs/src/api/State.md:20` ("random solenoidal
  velocity, or a mean-zero scalar φ"), plus the `Forcing.jl:10` `#` comment. The register sweep must
  cover **both** ``\varphi`` and Unicode `φ` — grepping one representation is not a sweep.
- **Residual — low priority (archived):** a bare "(Eswaran–Pope)" (no year) in the `StochasticOU`
  docstring (`Forcing.jl:236`); `StochasticOU` is archived / un-exported, so *not rendered publicly* —
  fix to "(Eswaran & Pope 1988)" when it is de-archived.
- **Not re-grepped, flagged for fix-time:** **#13/#14** (uniform code-name / method naming across map
  bullets) was addressed on `api.md`; `index.md` Components uses uniform backticked names — double-check
  at fix time.
- **Tally.** Three round-1 sweep-classes were under-swept — **#4** (clickable refs), **#29**
  (sentence-starts), **#2/#12** (register). The rest are clean. Recorded so the fix pass sweeps the
  *class*, not the flagged line.
- **Status.** collected.

---

## 14 — `BandRescaling(; kinetic_energy)` over-specifies a field-neutral forcing (#10 over-applied)

- **You said** (BandRescaling / Linear / ConstantPower): *"We need to think here about the naming,
  because for the scalar argument name kinetic_energy is not very fitting, and forcings are designed to
  work on any field. We need something field-neutral or physics-neutral."*
- **Class.** A **field-neutral** operation carries a **field-specific** argument name. `BandRescaling`
  holds a target ``\tfrac12\langle\lvert\cdot\rvert^2\rangle`` — the field's L² energy, which is *kinetic
  energy* for the velocity but *half the scalar variance* (``\tfrac12\langle\varphi^2\rangle``) for the
  scalar — yet its kwarg is `kinetic_energy` (velocity-specific). The forcing works on any field, so the
  name must be field-/physics-neutral.
- **Probe.** Does any field-neutral operation (a forcing, a generic field op) carry a field-specific
  argument name (`kinetic_energy`, `scalar_variance`, `velocity_…`)? A field-neutral op needs a neutral
  name for the generic quantity.
- **Fix direction.** Rename `BandRescaling`'s kwarg to a field-neutral name for
  ``\tfrac12\langle\lvert\cdot\rvert^2\rangle`` — **recommend `energy`** (the field's L² / Parseval energy;
  "kinetic energy" for velocity = "scalar energy" for φ, both ``\tfrac12\langle\lvert\cdot\rvert^2\rangle``;
  the original name; matches the internal `target_energy` field and the docstring's own "the band's own
  energy"; parallels `ConstantPower`'s field-neutral `power` — `energy` = held *level*, `power` = injection
  *rate*). This **refines #10**: field-specific IC amplitudes stay qualified (`kinetic_energy` for
  `Simulation` / `random_solenoidal_velocity!`, `scalar_variance` for `random_scalar!`); the field-neutral
  forcing takes the neutral name. `Simulation` keeps `kinetic_energy` (its default forcing is on the
  velocity) and forwards `BandRescaling(; energy = kinetic_energy, …)`. Also revert the docstring formulas
  ``… = \texttt{kinetic\_energy}`` → ``… = \texttt{energy}``. Alternatives to weigh with the user:
  `target_energy` / `intensity` / `level`.
- **Verified.** `Forcing.jl`: `BandRescaling(domain; kinetic_energy::Real, …)` (:149), deferred ctor
  (:314), docstring formulas ``… = \texttt{kinetic\_energy}`` (:138–139); the struct field is already the
  neutral `target_energy` (`# the energy ½⟨|·|²⟩ to hold`, :145). `Linear` (`rate`) and `ConstantPower`
  (`power`) are already field-neutral.
- **Meta.** The #10 rename I executed was **over-applied** — I renamed the field-neutral `BandRescaling`
  along with the velocity-specific IC amplitudes. Fourth item where the pass over-reached; the fix walks
  `BandRescaling` back to a neutral name.
- **Math + consistency (user Q — settled reasoning).** ½⟨|·|²⟩ = half the mean-square = ½ the *squared*
  L² norm (not the L² norm), = the spectral energy ∫E(κ)dκ. Velocity → kinetic energy `k`; scalar →
  ½⟨φ²⟩ = **half** the scalar variance. **Name settled: `energy`** (its L²/spectral-energy math name);
  the docstring states "KE for velocity, half the scalar variance for the scalar." **Wrinkle uncovered:**
  `random_scalar!`'s `scalar_variance` is the **full** ⟨φ²⟩ (it rescales `inner(φ̂,φ̂)=scalar_variance`),
  so BandRescaling's scalar target ½⟨φ²⟩ differs by ×2 from the IC's `scalar_variance` (⟨φ²⟩).
  **RESOLVED (B — targets agree with the observables).** The amplitude arg is renamed **`target`** in
  both `BandRescaling` and `ConstantPower`, field-neutral, holding the **field-appropriate observable**:
  `BandRescaling` `target` = `kinetic_energy` (velocity, ½⟨|u|²⟩) / `scalar_variance` (scalar, ⟨φ²⟩);
  `ConstantPower` `target` = `dissipation` (velocity, ε) / `scalar_dissipation` (scalar, ε_φ). The forcings
  become **field-aware** (½ for the vector KE, no ½ for the scalar variance — matching how the observables
  themselves are defined); docstrings note "= the observable it holds." **Behaviour change** (not just a
  rename): the scalar target shifts ×2, from today's ½⟨φ²⟩ to the full ⟨φ²⟩. **Collision:** `BandRescaling`
  already has `target = :band/:total` — rename that selector (candidate `over` / `scope`); "agrees with the
  observable" is exact for `:total` (whole-field), while `:band` holds the band's own energy (not a
  whole-field observable — note it). **`Linear` is NOT in the rename** (its `rate` is the growth
  coefficient A, not an energy/dissipation target) — but its docstring IS de-velocity-framed.
- **Propagates to `ConstantPower` / `Linear` (user Q).** The ½-convention is not just `BandRescaling`:
  (i) all three forcings are **velocity-framed** though field-neutral — `Linear`/`ConstantPower` write
  "``f = A\boldsymbol u``", "``\langle\boldsymbol u\cdot\boldsymbol f\rangle``", "solenoidal velocity"
  (extend the #14 field-neutral rewrite to them). (ii) `ConstantPower`'s ε (`power`) = the injection rate
  ``\langle\text{field}\cdot\boldsymbol f\rangle`` into ½⟨|·|²⟩; in stationarity it equals
  `Observables.dissipation` for the velocity but **½·`Observables.scalar_dissipation`** for the scalar
  (since `dissipation = ν⟨|ω|²⟩` destroys ½⟨|u|²⟩ while `scalar_dissipation = 2ϰ⟨|∇φ|²⟩` destroys the full
  ⟨φ²⟩). The forcing docstrings must **state this convention + the ×2** (a user setting `power = ε` on the
  scalar gets `scalar_dissipation = 2ε`). Keep the observables standard (they match the literature); make
  the forcing docstrings explicit.
- **Status.** collected.

---

## 15 — User-facing docstrings cite the architecture / design doc (violates the CLAUDE.md exclude-rationale policy)

- **You said**: *"Didn't we have a policy not to cite architecture in the user-facing API?"* — and,
  reinforcing: *"Also, no MZ in the user-facing API."*
- **The policy (confirmed).** `CLAUDE.md:119–120` (documentation policy): a function docstring must
  **"Exclude: implementation internals (→ `#` comments) and architectural rationale (→
  `ARCHITECTURE.md`)."** So a rendered docstring must not cite the design doc ("design doc §8",
  "`ARCHITECTURE.md` §4.7") or carry architectural rationale (the MZ reading). The user reads what a
  thing *is and does*; the *why* / architecture lives in `ARCHITECTURE.md`.
- **Class.** A rendered docstring **cites the architecture / design document** (a `§`-reference or
  "design doc" pointer) or carries architectural rationale. Two overlapping strands: (a) the **MZ
  framing** (entry #9) — "in the Mori–Zwanzig reading (design doc §8) …"; (b) **non-MZ architecture
  citations** — `Phenomenology`'s "See `ARCHITECTURE.md` §4.7." Both belong only in `ARCHITECTURE.md`
  and `#` source comments (developer-facing).
- **Probe.** Grep every rendered docstring for "design doc", "ARCHITECTURE", "§[0-9]". A `#` comment
  citing `ARCHITECTURE` is a fine dev pointer; a **rendered docstring** citing it is not.
- **Fix direction.** Strip the design-doc citations from rendered docstrings: `Generator` /
  `Observables` module docstrings (drop the whole "In the Mori–Zwanzig reading (design doc §8) …"
  sentence — folds into #9); `Phenomenology` module docstring (`:42` "See `ARCHITECTURE.md` §4.7"), its
  provenance-type docstring (`:152` "verbatim-consistent with `ARCHITECTURE.md` §References" — a
  maintainer note) and `:225` ("extension point (`ARCHITECTURE.md` §4.7)"). Keep the `#` source comments
  (dev-facing). `notation.md:89`'s "the design document's Lenses section" is the same Lens-symbols block
  flagged in #9.
- **Verified.** Rendered-docstring architecture citations: `Generator.jl:16`, `Observables.jl:12` (both
  "design doc §8", with MZ framing), `Phenomenology.jl:42` / `:152` / `:225` (`ARCHITECTURE.md` §4.7 /
  §References). `#` comments (dev-facing, fine): `GBGIsotropicTurbulence.jl:43`, `Phenomenology.jl:5`,
  `Generator.jl:3`, `Observables.jl:3`, `SimulationDomain.jl:5`.
- **Cross-ref.** Overlaps #9 (MZ) on `Generator` / `Observables`; adds the non-MZ `Phenomenology` §4.7
  citations and grounds both in the explicit CLAUDE.md policy. The user's *"no MZ in the user-facing
  API"* **hardens #9's fix-direction to: remove every MZ mention from rendered docstrings + doc pages,
  no exceptions.**
- **Status.** collected.

---

## 16 — Module docstring characterizes sibling modules instead of describing itself

- **You said** (Generator module docstring): *"And what's the point of 'Observables are the functions of
  that state, and Propagator the numerical propagator.' We are talking here only about generator, you
  don't link to any specific object from these modules in this docstring."*
- **Class.** A **module docstring** characterizes **other (sibling) modules** — "`Observables` are the
  functions of that state, and `Propagator` the numerical propagator" — instead of confining itself to
  what **this** module is and does. Each module's docstring describes itself; a sibling is described by
  its own docstring (and the umbrella map). Worse, it names the siblings without linking any specific
  object — pure editorial, not a useful cross-reference. The user's test: if you reference a sibling,
  **link a specific object for a reason** ("advanced by [`step!`](@ref)"), never gloss what the sibling
  module *is*.
- **Probe.** Does a module docstring describe or characterize *other* modules (what they are / do)? A
  sibling reference must be a specific-object `@ref` with a reason, not a gloss of the sibling's role.
- **Fix direction.** In `Generator`, drop the whole "In the Mori–Zwanzig reading (design doc §8) this is
  the generator of the full dynamics — it advances the flow state; `Observables` are the functions of
  that state, and `Propagator` the numerical propagator." sentence (converges with #9 + #15). The
  docstring keeps only "the flow's equations of motion — the NS RHS …, the passive-scalar advection, and
  the exact viscous integrating factor," then its bulleted operations. Sweep siblings: `Observables`
  ("these are the observables *of the `Generator`*") and `Propagator` (glosses `FlowConditions`) do the
  same — apply the same test.
- **Verified.** `Generator.jl:16–18`: "… this is the *generator of the full dynamics* — it advances the
  flow state; `Observables` are the functions of that state, and `Propagator` the numerical propagator."
  Neither `Observables` nor `Propagator` is an `@ref` to a specific object — bare module-role glosses.
- **Cross-ref.** Same sentence as #9 (MZ) and #15 (architecture citation) — condemned on three counts
  (MZ framing, design-doc citation, sibling-editorializing). One deletion resolves all three; the *class*
  here (don't characterize siblings) is the reusable probe.
- **Status.** collected.

---

## 17 — Docstring explains an architectural design decision inline (rationale, not usage)

- **You said** (Generator module docstring): *"'so the module names no buffer bundle;' you cite an
  architectural decision. Why would the user be interested in the history of our architecture?"*
- **Class.** A docstring **explains an architectural / design decision** inline — the *rationale* for a
  structural choice — rather than stating only the user-relevant fact. "so the module names no buffer
  bundle" is the *why* (a consequence of the individual-scratch-field design, a D1/D2 refactor choice);
  the user needs the *how* (each operation takes `domain` + the individual scratch field(s) it writes
  into as final arguments). Architectural rationale → `ARCHITECTURE.md` (same CLAUDE.md policy as #15),
  even when it's an inline clause and not a `§`-citation.
- **Probe.** Does a docstring explain *why* a design choice was made — "so the module …", "hence …",
  "this is why …", "we chose …", any consequence-of-our-structure clause? That's rationale; state only
  the user-facing fact, move the *why* to `ARCHITECTURE.md`.
- **Fix direction.** In `Generator`, cut "so the module names no buffer bundle" and simplify to usage
  only: "Each field-transforming or nonlinear-assembly operation takes the `domain` (a
  [`FixedDomain`](@ref)) and, as its final argument(s), the individual preallocated scratch field(s) it
  writes into; `integrating_factor!` takes `domain` alone." Sweep other docstrings for
  consequence-of-architecture clauses.
- **Verified.** `Generator.jl` module docstring: "… it writes into as its final argument(s), **so the
  module names no buffer bundle**; `integrating_factor!` takes `domain` alone." The clause is the D1/D2
  rationale (why `Generator` has no `IntegratorBuffers`-style bundle), not usage.
- **Cross-ref.** Same policy as #15 (exclude architectural rationale) — a distinct manifestation: an
  inline design-decision *explanation*, not a `§`-citation or MZ. This probe (rationale-clauses)
  complements #15's (citation-greps).
- **Status.** collected.

---

## 18 — Representation-as-adjective jargon: "spectral vector field", "physical scalar", "physical velocity"

- **You said** (vorticity_to_physical!): *"'a spectral vector field' — that's jargon. Correct is vector
  field in spectral representation. Even PF have an explicit policy not to use such jargon."* — and
  (scalar_to_physical!): *"'physical scalar' — that jargon is not allowed."*
- **Class.** Compressing "*X* in *{spectral|physical}* representation" into the adjective-noun "a
  *{spectral|physical}* *X*" is jargon — it makes the *representation* read as a *kind* of field/quantity,
  when a field is one physical object and *spectral* / *physical* are its two **representations** (PF's
  explicit convention; `CLAUDE.md`'s physical-meaning-first policy: "a field is a real physical object;
  spectral is only a representation"). Covers the scratch parentheticals ("a spectral vector field", "a
  spectral scalar field", "a physical vector field") **and** the operation openings ("Compute the
  **physical scalar** …", "Compute the **physical velocity / vorticity** …", "the **spectral** velocity").
  The PF *type* name `VectorFieldSpectral` (code) does not license the prose form.
- **Probe.** Any "{spectral|physical} {velocity|vorticity|scalar|vector|tensor} [field|buffer]" in prose →
  "{…} in {spectral|physical} representation" (or reword). The allocator docstrings already model the
  correct form ("a vector field in spectral representation").
- **Fix direction.** Rewrite the `Generator` scratch parentheticals (`:67,82,114`, + the line-wrapped
  `scalar_to_physical!` "(a spectral scalar field)") and the `to_physical!` openings. **Scope call for the
  user:** whether the highly idiomatic "physical velocity" / "spectral velocity" are rewritten too, or
  only the less-idiomatic "physical scalar" / "spectral X field" — PF's policy says all; the exact wording
  ("… in physical representation" vs "the physical-space velocity") is a consistency call.
- **Verified (grep incomplete).** `Generator.jl:67,82,114`; `scalar_to_physical!`'s "(a spectral scalar
  field)" line-wrapped past the grep; the "Compute the physical {velocity|vorticity|scalar}" openings
  across all three `to_physical!` docstrings.
- **Status.** collected.

---

## 19 — Symbol overload: too many φ in one sentence; redundant code-`φ` beside math-``\varphi``

- **You said** (scalar_to_physical!): *"Quite a lot of phis in a single sentence, and the latex \varphi
  not in brackets."*
- **Class.** A docstring crams many variants of one symbol into a single sentence — "the physical scalar
  `φ` ``\varphi`` from `φ̂` … into `φ`, leaving `φ̂`" — six φ-family glyphs, and it prints the **code
  identifier `φ` directly beside the math ``\varphi``** (rendering "φ φ", a redundant doubling), with the
  math symbol **bare / unbracketed**. Redundant and hard to read: the *argument* is the code `φ`, the
  *math symbol* is φ — don't print both adjacent. (Contrast `vorticity_to_physical!`: math
  ``\boldsymbol\omega = \nabla\times\boldsymbol u`` once, then the code arg "into `ω`".)
- **Probe.** Does a sentence repeat one quantity's symbol variants (code `x`, math ``x``, `x̂`,
  ``\hat x``) beyond need? Is a code identifier printed adjacent to its own math symbol ("φ φ")? Use the
  code arg name for the argument; the math symbol only where a formula needs it, set apart, never doubled.
- **Fix direction.** Rewrite `scalar_to_physical!`'s first sentence — name the argument once (code `φ`),
  use ``\varphi`` only if a formula needs it — e.g. "Recover the scalar in physical representation into
  `φ` from the spectral `φ̂`, leaving `φ̂` unchanged." (folds in #18). Drop the "`φ` ``\varphi``" doubling
  and the bare adjacent math symbol.
- **Verified.** `scalar_to_physical!`: "Compute the physical scalar `φ` ``\\varphi`` from `φ̂` (the scalar
  in spectral representation ``\\hat{\\varphi}``) into `φ`, leaving `φ̂` unchanged." — code `φ` + math
  ``\varphi`` adjacent, six φ-glyphs.
- **Status.** collected.

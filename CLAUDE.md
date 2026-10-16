<!-- gbg:managed begin v2.0.0-rc.73 — rewritten by `gbg sync`; do not edit -->
@.gbg/policy/00-index.md

The rulebook above is the whole of it: the rules, the terms they use, and what GBGHomogeneousTurbulence has
switched off with its reason. Nothing restates a rule outside it — a rule quoted in two files is a
rule that will be reworded in one.

Unasked, run `Pkg.test()` and nothing else; before every push the docs build runs too, through the
push hook, and a failing build stops the push. What a rule finds is reported, never fixed silently:
documentation may be fixed without asking, and anything else waits for an answer.

The readers of a review are derived from the rules and the tool's catalogue of disciplines. A
reader or a discipline this package needs and the tool lacks is requested of the tool, as a request
file the owner has approved, never written here.

A run an earlier session left open is continued before anything else, and the chat says so:
`gbg run next` says what to launch or that the stage is ready to collect, and the run goes on to
its close. It waits for the owner only when `gbg run next` says the tree moved since the launch.
<!-- gbg:managed end -->

# CLAUDE.md — GBGHomogeneousTurbulence

Julia package: a small, focused **pseudospectral direct numerical simulation (DNS) of homogeneous
isotropic turbulence** — one incompressible velocity field ``\boldsymbol u`` and one passive scalar
``\varphi`` on a triple-periodic box, each optionally forced, advanced by interchangeable
integrating-factor time-stepping, with Lagrangian particle tracking and field sampling along the
trajectories (accumulating statistics over those values is the caller's analysis, not this package's). **GPU is the primary target**: the time loop is in-place and field-scale-allocation-free over
preallocated buffers, backend-agnostic (CPU `Array`, CUDA, ROCm) through the field library.

Built on two sibling backends: **GBGPeriodicFields** ("PF", the field mathematics) and
**GBGStreamingStatistics** ("SS", the online statistics). The division is exact — **PF is all field
mathematics, no physics; SS is all statistics, no physics; this package is the physics**: the
equations of motion, forcing, scalar transport, time integration, particle tracking, and the run
layer. Reference clones of PF and SS live under the gitignored `inspiration/` (study-only), alongside
the DNS references (TurTLE, GHOST, hit3d).

Before any structural or design change, read `docs/ARCHITECTURE.md` — it explains *why* the
architecture is the way it is (the System × Model × Method framing, the Mori–Zwanzig reading, the
thin-physics / rich-numerics split). Do not re-litigate a recorded decision (its §11 decision log)
without the user. The conceptual model and the writing conventions are recorded once — in
`docs/ARCHITECTURE.md` and this file; the umbrella module `src/GBGHomogeneousTurbulence.jl` only points
there.

## Modules and wiring

Each concern is its own file (`docs/ARCHITECTURE.md` §4). **Physics** concerns take their names from
the **Mori–Zwanzig lens** — the *dynamics* (the generator / RHS) and its *observables* (the measured
functions of state); **realization / infrastructure** concerns are named by their job.

- `SimulationDomain` — the discretised periodic box a run lives on: the reusable, read-only frame
  (`FixedDomain` — grid, transform plans, spectral multipliers, dealiasing strategy, scratch allocators).
- `State` — the evolving fields a run advances (`ResolvedFields` — the velocity `û` and scalar `φ̂` in
  spectral representation, the single source of truth, plus each forcing's evolving state in its
  `modeled` slot) and the random initial conditions. The
  physical representations are recovered by the source-preserving four-argument form of PF's
  `to_physical!` at the consuming sites; the vorticity by `Observables.vorticity_physical!` (decision 47).
- `Observables` — the measured functions of state (energy and dissipation diagnostics of flow and
  scalar, the spectrum-derived quantities, the CFL `max_speed`, the field-valued vorticity
  recovery, …). The MZ *observables*; an observable with a cached value is one generic — the field
  method measures, the cache method serves the deposit (decision 46).
- `Cache` — the observables cache (`ObservablesCache`): the storage the iteration deposits
  its observables into at its end (no-recompute — the checked accessors serve the deposited value or
  throw; a slot doubles as its producer's stage register; `fields_modified!` announces an
  out-of-band state mutation). The design is `docs/src/observables_cache.md`.
- `Generator` — the Navier–Stokes RHS (rotational form) + scalar advection + the exact integrating
  factor, gathered into `ResolvedGenerator` (conditions + assembly scratch) behind the protocol
  `prepare!` / `velocity_rhs!` / `scalar_rhs!` / `velocity_integrating_factor` /
  `scalar_integrating_factor` / `finalize!`.
  The MZ *generator*.
- `Forcing` — pluggable energy-injection strategies (`AbstractForcing`).
- `Propagator` — pluggable integrating-factor schemes (`AbstractIntegrator`) and the per-step scratch
  (`IntegratorBuffers`). Every scheme's exit re-imposes the two linear constraints the discretisation
  does not hold by construction: divergence-free (`helmholtz_projection!`, decision 61) and the
  reality condition on the self-conjugate planes (`reality_projection!`, decision 88 — a forcing
  proportional to the field amplifies its round-off violation until the flow dies).
- `Particles` — Lagrangian particle tracking: the trajectory state (`Tracers`) held apart from the
  pluggable trajectory integrator (`AbstractParticleIntegrator`: `EndpointHeun`, `AdamsBashforth`) and its per-scheme
  registers (`ParticleIntegratorBuffers`) — decision 50. *Particle* names anything true of the whole
  deferred ladder, *tracer* only the massless kind (decision 51).
- `SimulationRun` — the ergonomic run layer (`Simulation` + `run!` / `warmup!` / `advance!`).

Include order: `SimulationDomain → Observables → State → Cache → Forcing → Generator → Propagator →
Particles → SimulationRun`. Cross-module access only through explicit `using ..Module: name` — never a
bare `using`.

**The reference-law module `Phenomenology` is parked** (the owner, 2026-10-16, decision 113). Its
source, oracle tests and pages live whole under `parked/Phenomenology/`, in the layout of the standalone
`GBGTurbulencePhenomenology` it becomes when extracted; its tests run on demand with
`julia --project parked/Phenomenology/test/runtests.jl`. Nothing in the package includes it, builds it,
or names it on a user-facing surface: a quantity the run layer needs (``\eta``, ``\mathrm{Re}_\lambda``)
is an `Observables` function of measured scalars (decision 112), and a model spectrum is "a model
spectrum from the literature" where a docstring needs the idea. The guard is `test/parked_modules.jl`:
the umbrella defines no `Phenomenology`, and the word appears in no file under `src/`, `docs/src/` or
`README.md`. `docs/ARCHITECTURE.md` §4.8 keeps the design it was built to.

## Core invariants — do not violate

1. **Thin physics, rich numerics + statistics.** This package owns only the physics — the equations,
   forcing, transport, run control. The numerics and statistics stay rich; the physics stays thin.
2. **Belongs-in-PF / SS → raise, don't reimplement.** A general, physics-free field operation (a fused
   reduction, a differential or tensor operator) belongs in PF; an online statistic (a density, a
   moment, a conditional expectation) in SS. When HT needs one, **raise it to the backend** — never
   reimplement field or statistics machinery here. A deferred backend feature is a *request*, not a
   local workaround.
3. **Deferred ≠ missing.** A recorded coverage gap or a deferred capability is a *decision*, not an
   omission; "for symmetry", "for completeness", or "it's convenient" is never a valid justification (a
   missing capability encodes a decision — the PF / SS discipline).
4. **GPU-primary, minimal footprint.** The hot loop (`step!`) is in-place and allocation-free AT FIELD SCALE over the
   preallocated buffers (the state, the integrator's `IntegratorBuffers`, the generator's assembly
   scratch, and the observables cache's slots); storage is generic
   `AbstractArray` (no scalar indexing of device arrays).
   **Minimal memory footprint trumps compute cost** — prefer low-storage integrators, and per-call
   allocation of an *occasional* diagnostic over resident scratch. Precision (`Float32` / `Float64`)
   and footprint are **studied fitness axes**, not afterthoughts.
5. **Named from the Mori–Zwanzig lens** (see Modules) — physics concerns from the MZ reading,
   infrastructure by its job.

## Style

Two-space indentation; two blank lines between top-level definitions; section banner comments;
moderately long lines are fine. When unsure about Base / stdlib / package behavior, check the official
docs — don't guess. For a linear solve use `\` / factorizations / `ldiv!`, never an explicit matrix
inverse. Operators and extended Base functions are imported before being extended; no type piracy.
**Every concrete struct type carries a `Base.show`** in the field library's convention (decision 87,
adopting PF's decision 82): a one-line self-delimiting `Type(body)` carrying what the package
refuses on, a `MIME"text/plain"` form only where that line abbreviates, an optional part printed
through its own display when present and as `no …` when absent, `name = value` reserved for a
constructor call that round-trips, nothing reading an element. The gate is derived —
`test/display.jl` enumerates the concrete types and fails on one without a display or a cited
exemption — so a new type is caught by the suite, not by memory.

**Naming — flow-field math variables are Unicode math symbols.** A field **math variable** (a function
parameter or a local) is named by its symbol: physical velocity / vorticity / scalar are `u` / `ω` /
`φ`; their spectral representations `û` / `φ̂`. **Storage slots keep descriptive names** —
`cache.vorticity_physical`, `generator.product_spectral`, `state.velocity_spectral`,
`cache.velocity_at_particles` — as do
function names (`vorticity_physical!`, `velocity_rhs!`), `conditions.velocity_forcing`, and prose. The rule: **symbols for math
variables, descriptive names for storage.** (Type `û` as `u\hat<tab>`, `φ̂` as `\varphi\hat<tab>`, `ω`
as `\omega<tab>`.)

**Naming — public API is user-facing, unambiguous, and precise.** Name a public type, function, or
argument for **what it means to the user**, not how it is built at the backend, and make each name
unambiguous (one reading) and precise (the exact thing, not an approximate cover word). The user is a
**physicist** — hence also a mathematician and computer scientist, but *not* a software engineer fluent
in startup idiom — so names speak physics, mathematics, and computational science, preferring the precise
meaningful word to a terse handle or an implementation term. Name the object the user reasons about, not
the machinery inside it: `SimulationDomain` (the discretized box the run lives on), never
`SpectralOperators` (its backend contents — the transform plans and wavenumber multipliers); and
`grid_points_per_axis` / `side_length` (each a single per-side scalar), never the ambiguous
`resolution` / `box` (is it the count or the `N³` grid? the side or the `L³` volume?). This is the
naming counterpart of the physical-meaning-first documentation rule.

**Docstrings vs comments.** Reserve plain `#` comments for non-intuitive *why* (the
destructive-transform copy, the rotational-form Lamb vector, the per-call tensor allocation for an
occasional diagnostic). A package-owned generic carries its docstring on `function f end`; an extended
Base / backend function on the bare imported name. Plain `#` comments stay Unicode (they are not
rendered).

## Documentation policy — physical-meaning first

The rulebook (`.gbg/policy/`) holds the documentation rules; what follows is only what is HT's own —
its examples, its physics, and the owner's rulings the rulebook does not carry. Where this text and a
rule disagree, the rule wins and this text is the one corrected (the owner, 2026-10-03). The rendered glossary
at `docs/src/notation.md` is the reader's copy of the notation.

**Module maps.** No Mori–Zwanzig framing or architecture rationale in a module docstring — those live in
`ARCHITECTURE.md`.

**Citations.** A citation of a named method may open the identity sentence ("the smooth spectral
filter of Hou & Li (2007) …"). A link target percent-encodes `()` and `<>`. Every `§References` entry
in `ARCHITECTURE.md` has a citing docstring.

**Type docstrings.** Name the plain positional constructor only where a reader might reasonably call
it — a small parameter record (`HouLi`, `FlowConditions`). Omit it for a type whose positional form
takes preallocated internals (`Simulation`, `ObservablesCache`, `IntegratorBuffers`,
`ResolvedGenerator`): advertising that form invites a caller to assemble machinery by hand, which the
derived constructor exists to prevent. The presence or absence is a *claim about who builds the
value*, not a template slot.

**Physical meaning first** (the rulebook's `leading_identity`, HT's examples). `dissipation` is the
reference: lead with ``\varepsilon = \nu\langle\lvert\boldsymbol{\omega}\rvert^2\rangle`` (the physical
dissipation rate), then the reduction that computes it. The integrating factor is the example with no
clean physical form: a spectral multiplier, said so briefly. Every diagnostic states the physical
quantity it measures before the numerical method.

**Cross-referencing.** Never link the docstring's own binding, its argument names, option / `Symbol`
tokens, or struct fields. A **family** of related built-ins is **one** catalogue destination, not five
(a glossary table is the exception — it maps each symbol to its own object). **At-home test** — if a
sentence would sit equally well in the *target's* own docstring, cut it and link.

**No dead references** extends to a thrown error message, a decision-log entry and a repo path (`src/…`,
`inspiration/…`): a cross-reference adds depth one hop away; it never carries a fact the reader needs.

**Template conventions.**

- An admonition title is **plain text** — Documenter renders neither code spans nor math there.
- The `# Arguments` list is led by "The arguments are:". A lead-in qualifier ("All keyword, all
  required:") appears only where it carries information beyond the entries themselves.
- An **`# Examples`** section appears where construction is non-obvious, not on every type — hence
  none on the types a run builds for the user, and one on `FixedDomain`, `Simulation`, `Tracers`,
  `FlowParameters`.
- A **formula gets a display block** when it is the thing the docstring defines, and stays inline
  when it is a fragment cited in passing.
- A return whose **shape** is not evident from the name (a named tuple) is stated. A reduction
  returning *the field's own* element type says so in prose rather than with an arrow; a mutator may
  carry **`-> arg`**, naming the argument it returns, and then needs no `Returns` sentence.

**Rewrite, don't patch.** When a docstring has taken three or more rounds of patches, rewrite it whole
rather than append again (`RULE.DOC.SHAPE` measures growth). Measured 2026-08-19: `VarianceRescaling`
reached 861 words with four scattered admonitions, `# Arguments` mid-docstring and a caveat after
`# Fields`; `Simulation`'s grid-mode bullet reached a 120-word run-on. Every individual edit was correct.

**API pages.** Group public objects under hand-written `## Header` sections via explicit `@docs` blocks
(never `@autodocs`, which cannot express a semantic group); keep an `f` / `f!` pair together with the
`!` home first; a `@docs` block stays homogeneous (all-types or all-functions, a supertype leading its
concretes). `checkdocs = :exports` guards a dropped export.

**Notation** (the glossary, `docs/src/notation.md`, is the single reference). The house rules: vectors
and tensors are bold italic ``\boldsymbol{u}``; the wavenumber set is kept distinct —
``\boldsymbol{\kappa}`` the vector, ``\kappa`` its magnitude, ``k`` the turbulent kinetic energy,
``\varkappa`` the scalar diffusivity; the passive scalar is ``\varphi``, **never ``\theta``**; the Leray
projection is ``\mathbb P``, a Mori–Zwanzig projection ``\mathcal P``; a conditional bar is ``\mid``.
The Reynolds number is set through ``\nu`` (``\mathrm{Re} = 1/\nu``), never a field —
``\mathrm{Re}_\lambda`` is measured. Long docstring signatures hand-wrap with a hanging indent under the
first argument.

**Bind each code object to its symbol on first mention** — write the correspondence explicitly so it is
never left implicit: `dissipation` (``\varepsilon``), `kinetic_energy` (``k``), `curl`
(``\nabla\times``), a field in spectral representation ``\hat f``.

**Correctness — HT's cases.** The normalizations to expand against the code: the ``1/N``, the
``2\varkappa``, the ``\tfrac{1}{2}`` in the energy, the Parseval / spectral factors. Two examples from
this codebase: the derivative-skewness "divergence" bug (a repeated index read as
``\nabla\cdot\boldsymbol{u} = 0``), and the coordinate-free skewness constant
``C = \tfrac{4}{7}\sqrt{15/2}`` (numerically verified, a competing value ruled out). The category
errors this physics invites: a **field** with its **representation** (say "field in spectral
representation", never "spectral field"); the rate ``\varepsilon``, a number, with a dissipation field;
the kinetic energy ``k`` with the spectrum ``E(\kappa)``; the integrating factor ``\mathcal E`` with
``\nu``; ``\mathbb P`` with ``\mathcal P``; a per-unit-wavenumber density ``E(\kappa)`` with an
energy; a dimensionally incomplete law (a bare ``\kappa^{-5/3}`` slope vs
``C_K\varepsilon^{2/3}\kappa^{-5/3}``).

**Prose.** No noun-stacks, `label:`-colon tags, or comma splices; lead a sentence with a capitalized
word ("The `dissipation` reduction…").

**Register.** A tunable may also be an *axis* or a post-hoc *choice*; keep a neutral tone on
`@testset` names too. **No invented aliases for API objects** (owner-ruled 2026-08-24): `Simulation`
may be called *the front door* only in its own description — its docstring and its own api-page/§4.7
sections, where the term is introduced — and every other surface names `Simulation` explicitly. The
same rule covers any future metaphor: an alias lives where it is defined, nowhere else. (The glossary
keeps its *front door* row: the decision log's history uses the term, and the row is where a reader
resolves it.)

**Order the work: code before docs.** When a round of findings mixes renames, signature changes and
prose, land the code first — the docs describe the code, so the reverse order writes every affected
docstring twice. (2026-08: ten renames landed first, and the doc phase then touched each surface once.)

**HT's checks on a doc edit**, beyond the rulebook's: quote the decisive `src/` line for a verified
claim; a diagnostic's docstring matches the quantity it claims to measure; a docstring or summary
naming only a *subset* of what the code now provides is stale even if literally true (a module
docstring naming one scheme family, a capability list missing a builder) — check it against the
current `export`s and method set. The enumeration of signature arguments exists because `domain` /
`buffers` once slipped past.

## Verification workflow

- Load: `julia --project -e 'using GBGHomogeneousTurbulence'`.
- Test: `julia --project -e 'using Pkg; Pkg.test()'` — keep it green. The suite includes three
  audits over the shared op model in `test/audit_ops.jl` (which owns the op lists, the cost model,
  and the shape-class decomposition with its reflective counter): `test/memory_audit.jl` and
  `test/compute_audit.jl` **measure** — a deliberate footprint or
  step-schedule change updates the frozen ledgers (and, on a structural `step!`/protocol change, the
  op lists — `AUDIT_PRINT=1` regenerates the compute cells for review) in the same commit, citing the
  decision — while `test/optimality_audit.jl` **bounds**: every cell is held against a physical
  floor, and residual distance must carry a named holder. Its register works in both directions, so
  closing a gap means **retiring its holder in the same commit**; a holder left behind fails the
  suite just as an unclaimed gap does. The memory audit ledgers the working set and the read-only
  frame (the `FixedDomain`) **separately**, joined by a completeness test requiring their sum to
  account for every field-scale array a live `Simulation` reaches — so new residency cannot hide by
  hanging off an unwalked owner (decision 36).
- Docs build: `julia --project=docs docs/make.jl` (`checkdocs = :exports` and the rulebook's build
  checks). `docs/Project.toml` carries the package as a `[sources]` path and the GBGCodingTools pin:
  there is no transient dev entry, and the file is never reverted after a build.
- The GPU checks (`test/device_hot_loop.jl`, `test/device_memory.jl`, `test/device_limits.jl`,
  `test/seed_backends.jl`) run only where a functional GPU is present, and otherwise record a visible
  skip, never a pass.
- Consult `Project.toml` for dependencies and versions; do not assume.

## Working agreements

- Reference clones under `inspiration/` (PF, SS, and TurTLE / GHOST / hit3d) are **study-only,
  gitignored** — never copied into the package, only properly cited.
- **`inspiration/OldCode` is not a reference clone and is not inspiration.** It is the previous
  generation of this work, kept only so the question *what was done before, and what came of it?* can
  be answered from the record rather than from memory. **Do not follow it.** The current direction of
  the GBG packages is to **replace it entirely**, because it was problematic — so its arrangements
  carry no authority, and "the old code did it this way" is never a reason to do anything. Read it
  **critically**: when it is consulted, the useful output is a diagnosis (what it did, why that
  failed, what replaced it), never a pattern to copy. It is study-only and gitignored like the rest,
  and it is **not** citable — a published method gets cited to its paper, not to this archive.

## Known weaknesses — self-guards

Documented tendencies of mine the user has caught; treat each as a **live risk**, not a resolved one, and
actively check for it.

- **Circular / self-referential justification.** I default to justifying a decision by the *existing state*
  or my *own prior decisions* — "it's already like that", "keeps it parallel with the current form", "for
  consistency / symmetry with what's there" — instead of arguing from first principles or the user's stated
  direction. **Legacy is not evidence of correctness:** if the existing arrangement were wrong, "keep it
  parallel" only propagates the error. When justifying a choice, lead with a first-principle reason or the
  user's preference; if the only reason is "that's how it is", it is not a reason — say so and find the real
  one, or flag that there isn't one. This is the decision-making sibling of invariant 3's "*for symmetry /
  for completeness / it's convenient* is never a valid justification" and of laundering a flagged smell as
  "by design" (`RULE.DOC.VERIFIED`). Instances (2026-07-14):
  justifying the `Tracers(domain, …)` argument order by "the `count` form is already domain-first" (the
  sound reason is the domain-derived-constructor convention the user endorsed); the `kinetic_energy` default
  "differ by design" laundering.
- **Asserting a shape instead of expanding it.** When mapping work onto a backend — a PF / SS request, a
  gap-register holder, a "this chain needs a new op" claim — I pattern-match over operation *names* and
  assert the algebraic shape, instead of writing the expression out and unifying it against the backend's
  **current** method set. Both failure directions are live: requesting an operation whose composition is
  already expressible (the 2026-07-19 shift-back∘average — expressible all along as the five-argument
  `convolve!` α/β form, verified in the clone and in use on a neighboring line), and proposing a consumer
  that is not an instance of the requested op (the phase-shift chain claimed for the two-operand combine —
  a kernel on *one* operand is not `ĝ⊙(α·a + β·b)`). The rule: **before raising a request or naming a gap
  holder, expand each candidate chain algebraically and check it against the existing exports** — `RULE.DOC.VERIFIED`'s
  "a plausible 'X is just Y' is false until the expansion matches", applied to code shapes and
  backend surfaces, not only docstrings. Instances (2026-07-19, both caught by PF's triage): the missed
  free win at `Generator.jl` 253–254; the item-7 phase-shift consumer misclaim.
- **Treating what is *in place* as evidence it should be so — dismissing a flagged cost instead of
  challenging it or asking.** When a finding surfaces a cost that is already *recorded* — a frozen audit
  delta, a decision-logged tradeoff, an existing buffer — I default to closing it as "deliberate /
  accepted / off-axis," treating the record as the justification. But **a frozen audit cell measures
  what *is*, not what *should be*:** a recorded cost with no *lower bound* held against it is an
  unexamined cost, not a minimal one. This is the audit-coverage sibling of the fusion-bound
  complacency — "achieved = bound" certified nothing because the bound was not the physical floor — and
  of invariant 3. The rule: **before dismissing a finding as acceptable, either produce the lower bound
  that proves it minimal, or ask the user** — never close it by pointing at the existing arrangement,
  and never let "it's already recorded / it was done to get things working" stand as a reason. Instance
  The sharpest form is **building the instrument out of the assumption it should test**: if a
  projection needs an assumption to reach the achieved number, that assumption is a *holder*, not a
  modelling input, and a bound that consumes it certifies nothing (decision 37 — the liveness
  projection declared the observation charts live across the step, so `achieved == bound` held by
  construction and hid two physical vectors). A bound that cannot fail is not a bound. Instances
  (2026-07-25): dismissing the Lagrangian tracer's full-field ``\boldsymbol u(t_n)`` copy — an ``N^3``
  resident buffer plus a per-step ``N^3`` copy serving an ``M\times3`` interpolation need — as "a
  consciously-accepted tradeoff already frozen in both audits," when the freeze *records* the cost with
  no bound challenging it and the ``N^3``-for-``M\times3`` spend violates the "minimal footprint trumps
  compute" invariant. The user: "Stop taking what is in place as an indication that it should be like
  that. Probably you should ask before you dismiss something."

- **Fixing the instance, not the class — and being unable to see it from the inside.** This one is
  different in kind from the others: the rule is *already written down* ("a flagged instance is a
  sample of a class — fix the class, not the line"), I know it, I quote it, and I break it anyway. In
  one measured round of `verify-fixes.js`, **eleven of thirteen deficiencies were `LINE-ONLY`** — the
  flagged site fixed, the class alive on surfaces the finding had *already named*. The lesson is
  therefore not another statement of the rule. It is that **stating it does not work and measuring it
  does**: the class-sweep claim has to be *checked by something that is not me*, which is what the
  verifier pair exists for. Three shapes recur, none visible from inside the edit:
  (a) **the sweep that skips its own surfaces** — every rename swept `src/` and `docs/` and stopped,
  leaving `CLAUDE.md` and `README.md` untouched for rounds, the latter holding the *worst* instance of
  the very claim being fixed; (b) **the fix that creates the defect it closes** — a gloss defining
  "register" asserted a corpus-wide usage whose flagship example the same pass had deleted two commits
  earlier, and a rewrite that purged the banned "the run stands at ``t_n``" reintroduced the identical
  construction three sentences later; (c) **the fix that contradicts itself** — a link sweep added the
  policy sentence "every Code entry naming a package object links" and left its own table disobeying
  it, because the regex required a cell to be exactly one backticked name. A class claimed swept but
  not re-measured is an instance fix wearing a class's name.
  Instances (2026-08-17): the eleven above, plus a scan I wrote that caught only the form I had first
  noticed (bare `` `code` `` beside math, not the linked `[`code`](@ref …)` form), certifying clean
  while three sites stood.

- **Writing the rule down instead of building the check — and the rule's presence then reading as
  compliance.** The generalisation of the entry above, and the one that explains why that entry
  keeps recurring despite being written. Over three days of cross-checking instruments against the
  sibling PF session, six defects were found across the two trees, and in **every one the correct
  behaviour was already written down in the same tree**: the class-sweep rule sat in the discipline
  section while eleven of thirteen fixes were `LINE-ONLY`; `hunt.js`'s "it must assert the RIGHT
  behaviour" sat three lines above code that accepted *any* failing test as proof; this file's
  doc-edit checklist then named `domain` as the argument an enumeration must not skip, while
  `ResolvedFields(domain; …)` left `domain` unbound and `argcov.jl` reported `0` and **could not have
  reported otherwise** — its parser discarded the last positional argument of every signature
  carrying a `;`. PF hit the mirror image the same day: its unbound argument was the *stencil width*,
  the example its own rulebook gives verbatim for that class.

  **The mechanism (PF's, and it is the useful part):** a rule is written by whoever has just fixed an
  instance, at the moment they are most confident the class is handled — which is precisely the
  moment nobody builds the check, because *the fix feels like the closure*. So the rule is written
  **instead of** enforcement, not merely alongside it. Afterwards the rule reads as evidence of
  compliance rather than of intent, and from inside the tree you read it and believe the tree obeys.
  That is why this class is invisible from inside and obvious from outside, and why it needed a
  second package to surface: neither session found more than two instances in its own tree alone.

  The rule: **when you write a rule down, name what would catch its next violation — and if the
  answer is "someone remembering this rule", it is not enforced.** A rule and its check belong in the
  same commit. And on the checks themselves, prefer a stated denominator to a
  bare verdict: "CLEAN over 98 bindings" is falsifiable where "CLEAN" is not.
  Instances (2026-08-25/27): the six above.

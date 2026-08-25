# CLAUDE.md — GBGIsotropicTurbulence

Julia package: a small, focused **pseudospectral direct numerical simulation (DNS) of homogeneous
isotropic turbulence** — one incompressible velocity field ``\boldsymbol u`` and one passive scalar
``\varphi`` on a triple-periodic box, each optionally forced, advanced by interchangeable
integrating-factor time-stepping, with Lagrangian particle tracking and field sampling along the
trajectories (accumulating statistics over those values is the caller's analysis, not this package's). **GPU is the primary target**: the time loop is in-place and allocation-free over
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
`docs/ARCHITECTURE.md` and this file; the umbrella module `src/GBGIsotropicTurbulence.jl` only points
there.

## Modules and wiring

Each concern is its own file (`docs/ARCHITECTURE.md` §4). **Physics** concerns take their names from
the **Mori–Zwanzig lens** — the *dynamics* (the generator / RHS) and its *observables* (the measured
functions of state); **realization / infrastructure** concerns are named by their job.

- `SimulationDomain` — the discretised periodic box a run lives on: the reusable, read-only frame
  (`FixedDomain` — grid, transform plans, spectral multipliers, dealiasing strategy, scratch allocators).
- `State` — the evolving fields a run advances (`ResolvedFields` — the velocity `û` and scalar `φ̂` in
  spectral representation, the single source of truth) and the random initial conditions. The
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
  (`IntegratorBuffers`).
- `Particles` — Lagrangian particle tracking: the trajectory state (`Tracers`) held apart from the
  pluggable trajectory integrator (`AbstractParticleIntegrator`: `EndpointHeun`, `AdamsBashforth`) and its per-scheme
  registers (`ParticleIntegratorBuffers`) — decision 50. *Particle* names anything true of the whole
  deferred ladder, *tracer* only the massless kind (decision 51).
- `SimulationRun` — the ergonomic run layer (`Simulation` + `run!` / `warmup!` / `advance!`).

Include order: `SimulationDomain → Observables → State → Cache → Forcing → Generator → Propagator →
Particles → SimulationRun` (with `Phenomenology`, the extraction-bound leaf, included first). Cross-module access
only through explicit `using ..Module: name` — never a bare `using`.

A **`Phenomenology`** submodule — the reference turbulence laws (model spectra, structure-function laws,
dimensionless-constant fits), each an author-year parametrization of one abstract law family per quantity
— is a dependency-light, **extraction-bound** leaf (scaffolded, with reference laws and oracle tests in place): it takes **no** `GBGPeriodicFields` /
`GBGStreamingStatistics` / dynamics dependency, is **not** re-exported by the umbrella, and is designed to
be cut into a standalone `GBGTurbulencePhenomenology` with no rewrite. Do not add such dependencies to it.
See `docs/ARCHITECTURE.md` §4.7 and decision 18.

## Core invariants — do not violate

1. **Thin physics, rich numerics + statistics.** This package owns only the physics — the equations,
   forcing, transport, run control. The numerics and statistics stay rich; the physics stays thin.
2. **Belongs-in-PF / SS → raise, don't reimplement.** A general, physics-free field operation (a fused
   reduction, a differential or tensor operator) belongs in PF; an online statistic (a density, a
   moment, a conditional expectation) in SS. When IT needs one, **raise it to the backend** — never
   reimplement field or statistics machinery here. A deferred backend feature is a *request*, not a
   local workaround.
3. **Deferred ≠ missing.** A recorded coverage gap or a deferred capability is a *decision*, not an
   omission; "for symmetry", "for completeness", or "it's convenient" is never a valid justification (a
   missing capability encodes a decision — the PF / SS discipline).
4. **GPU-primary, minimal footprint.** The hot loop (`step!`) is in-place and allocation-free over the
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

**Docstrings vs comments.** Prefer docstrings; reserve plain `#` comments for non-intuitive *why* (the
destructive-transform copy, the rotational-form Lamb vector, the per-call tensor allocation for an
occasional diagnostic). One docstring per operation, on the bare binding (`function f end` for
package-owned generics, the bare imported name for extended Base / backend functions). Plain `#`
comments stay Unicode (they are not rendered).

## Documentation policy — physical-meaning first

The organizing spec for every user-facing docstring and API page; the rendered glossary at
`docs/src/notation.md` is the reader's copy of the notation. Two audiences, one rule each: a **module
docstring is a map**; a **function or type docstring is a home**.

**Two-tier structure.**
- **Module docstring = map.** What the module is, its scope, its invariants — then a **linked one-liner per
  operation, and no formulas** (no Mori–Zwanzig framing or architecture rationale — those live in
  `ARCHITECTURE.md`). Every formula
  lives in the operation's own docstring.
- **Function docstring = home**, in this order: (1) a one-sentence identity in the user's terms; (2)
  when to use it, versus the alternatives; (3) each argument (positional and keyword) and its effect;
  (4) the caveats a user needs (memory, accuracy, stability), as a `!!! warning` / `!!! note` where
  load-bearing; (5) **the physical-meaning-first formula** — see below; (6) an inline citation for a
  **named / published** method — which may open the identity sentence when the citation *names* the
  method ("the smooth spectral filter of Hou & Li (2007) …"), the corpus-wide convention. **One link form on both surfaces** (owner-ruled 2026-08-24, adopting PF's convention): a citation carries its clickable DOI on the paper's *title* — `[*Title*](https://doi.org/…)` — identically in the `§References` bibliography and in every inline docstring copy, so the reader sees the paper's name at the point of use and the two surfaces cannot drift (`doi_crosscheck.py` verifies both the DOI, decoded, and the title). **And the inline copy is the FULL reference** (owner-ruled 2026-08-25, completing the PF parity): the linked title is followed by the journal, volume, and pages, verbatim-consistent with the `§References` entry, so a docstring's citation reads complete at the REPL — the title appears once, as the link, never doubled. A link target percent-encodes `()` and `<>`. **In-text author truncation** (PF's rule, adopted the same day): name up to three authors; four or more become `First et al.` — the full author list lives only in the `§References` entry. (The `Phenomenology` leaf is the one sanctioned exception to the title form: its self-contained `Reference` strings stay compact — author–year plus the labelled `[doi:10.…]` link, no title.) (verbatim-consistent with `ARCHITECTURE.md` §References — every such cite
  has a §References entry and every entry a citing docstring; the extraction-bound `Phenomenology` leaf is
  exempt, carrying its own self-contained `Reference` values), none for a classical one. **Exclude:** implementation internals (→ `#` comments) and architectural rationale
  (→ `ARCHITECTURE.md`).
- **Type docstring = home, constructor-first**, in this order: (1) a one-sentence identity in the
  user's terms; (2) the constructor and its arguments — how the user builds and uses the type (the
  primary read); (3) an example where the construction is non-obvious; (4) a demoted `# Fields` section —
  the plain positional constructor and the field explanations. The struct's fields are reference detail,
  not the opening; lead with the constructor the user calls. **Name the plain positional constructor
  only where a reader might reasonably call it** — a small parameter record (`HouLi`, `FlowConditions`,
  `Reference`, a `Phenomenology` law). Omit it for a type whose positional form takes preallocated
  internals (`Simulation`, `ObservablesCache`, `IntegratorBuffers`, `ResolvedGenerator`): advertising
  that form invites a caller to assemble machinery by hand, which the derived constructor exists to
  prevent. The presence or absence is thus a *claim about who builds the value*, not a template slot.

**Physical meaning first — even for spectral-representation operations.** A field is a real physical
object; spectral is only a *representation*. A docstring for an operation *computed* in spectral
representation must still **state what it does to the real physical quantity first — with the explicit
formula — then give the spectral form it uses.** `dissipation` is the reference: lead with
``\varepsilon = \nu\langle\lvert\boldsymbol\omega\rvert^2\rangle`` (the physical dissipation rate), then
the reduction that computes it. Give the physical formula **whenever a clean one exists**; where it
does not (the integrating factor is a spectral multiplier), say so briefly rather than forcing it. **Every diagnostic states the physical quantity
it measures before the numerical method** — the physics-first mirror of PF's rule.

**One concept, one home.** One docstring per operation, on the bare binding; a generic carries **one**
docstring, never one per method. Across an `f` / `f!` pair the in-place `!` form is the **home** (owns
the formula and the kernel, listed first); the allocating form is a thin `@ref`-linking wrapper with no
second copy of the formula and no notation that drifts across the pair (`\partial_i` vs
`\partial_{x_i}`).

**Cross-referencing — a link earns its place.** Backtick every code identifier; promote to `@ref` (or
`@extref` for an external / cross-package object) only where a reader would genuinely jump and there is
**one** clear destination. (1) Link a target **at most once per docstring** — its first genuine mention.
(2) **Never** link the docstring's own binding, its argument names, option / `Symbol` tokens, or struct
fields. (3) A **family** of related built-ins is **one** catalogue destination, not five (a glossary
table is the exception — it maps each symbol to its own object). (4) **At-home test** — if a sentence
would sit equally well in the *target's* own docstring, cut it and link. The storage-backend and element
types (`Array` / `CuArray` / `ROCArray`, `Float32` / `Float64`) and the `GBGPeriodicFields` types are the
deliberate `@extref` exception to "don't link `Base`": the GPU-backend and dependency story makes them
worth the jump.

**No dead references on the user-facing surface.** A rendered docstring — and a thrown error message —
must read **complete at the REPL**, where cross-links are dead: never cite an `ARCHITECTURE.md` section
number (`§4.5`), a decision-log entry, or a repo path (`src/…`, `inspiration/…`) there. A cross-reference
adds depth one hop away; it never carries a fact the reader needs. (Design rationale and section
citations stay in `#` comments and `ARCHITECTURE.md`.)

**Template conventions, stated so the split is checkable.** Several shapes vary across the corpus for
reasons that were real but unwritten; they are rules now, one per line so a later round appends a
line rather than a clause:

- An **admonition takes a custom title** when it carries one load-bearing claim a reader should be
  able to scan for, and stays a bare `!!! note` when it is a general aside. The title is **plain
  text** — Documenter renders neither code spans nor math there.
- A **caveat admonition is the last substantive block** of a docstring, before `# Fields` — in a
  function docstring as in a type's.
- A type gets a bulleted **`# Arguments`** section when its keywords are independent settings, and
  folds them into prose when they must be read together (one keyword conditioning what another
  *means*, or several jointly naming one object). Independence is the discriminator, not count.
- A **function** docstring documenting three or more arguments, or any keyword argument, uses the
  bulleted form led by "The arguments are:"; with fewer, the arguments are bound in running prose.
  Never mix the two within one docstring. (PF's numeric rule, adopted 2026-08-24 — the corpus
  already practiced it unwritten, which is exactly how a convention drifts.)
  An `# Arguments` lead-in qualifier ("All keyword, all required:") appears only where it carries
  information beyond the entries themselves; a bare "All keyword:" over entries that show their own
  defaults says nothing and is omitted.
- An **`# Examples`** section appears where construction is non-obvious, not on every type — hence
  none on the types a run builds for the user, and one on `FixedDomain`, `Simulation`, `Tracers`,
  `FlowParameters`.
- A **formula gets a display block** when it is the thing the docstring defines, and stays inline
  when it is a fragment cited in passing.
- A **`Returns x.` sentence** is required of any in-place mutator whose signature carries no `-> `
  arrow, and sits **before** any caveat admonition. A *pure* function needs none; the exception is a
  return whose **shape** is not evident from the name (a named tuple), where the shape is stated.
- A signature carries a **`-> Type` arrow** only where the return type is fixed by the signature; a
  reduction returning *the field's own* element type says so in prose instead. A **mutator** may
  instead carry **`-> arg`**, naming the argument it returns — the corpus-wide idiom — and then
  needs no `Returns` sentence; arrow and sentence never both appear.
- A **module map is identity → contents list → optional trailing remark**, in that order, with no
  essay before the list — deliberately tighter than PF's map rule, which asks for scope-and-invariants
  prose ahead of the list: IT's four-role maps stay list-first.

**Watch the shape, not only the sentence.** These rules are how a docstring is *checked*, but a
docstring can satisfy every one and still be unreadable, because a fix pass edits clauses and never
re-reads the whole. Measured 2026-08-19: `VarianceRescaling` reached 861 words with four scattered
admonitions, `# Arguments` mid-docstring and a caveat after `# Fields`; `Simulation`'s grid-mode
bullet reached a 120-word run-on with an ungrammatical clause. Every individual edit was correct.
**When a docstring has taken three or more rounds of patches, rewrite it whole rather than append
again** — and the build now measures this: `docs/make.jl`'s `lint_docstring_shape()` fails on a
docstring that *grew* since `docs/docstring_shape.csv` was last written, and on a structural
violation (`# Arguments` after a caveat, a caveat after `# Fields`). Rewrite, or re-baseline
deliberately with `DOCSTRING_SHAPE_BASELINE=1 julia --project=docs docs/make.jl` — the signature to watch is a long paragraph, an admonition count above two, or a section
out of the order above.

**API pages are logically grouped.** Group public objects under hand-written `## Header` sections via
explicit `@docs` blocks (never `@autodocs`, which cannot express a semantic group); each object appears
**once**; keep an `f` / `f!` pair together with the `!` home first; a `@docs` block stays homogeneous
(all-types or all-functions, a supertype leading its concretes). `checkdocs = :exports` guards a
dropped export.

**Notation** (glossary: `docs/src/notation.md`, the single reference — a docstring introduces a symbol
on first use and need not repeat the convention). The load-bearing house rules: **vectors and tensors
are bold italic ``\boldsymbol{u}`` — never upright ``\mathbf`` (build-enforced)**; the wavenumber set
is kept distinct — ``\boldsymbol{\kappa}`` the vector, ``\kappa`` its magnitude, ``k`` the turbulent
kinetic energy, ``\varkappa`` the scalar diffusivity; the passive scalar is ``\varphi``, **never
``\theta``**; a partial derivative is ``\partial_{x_i}`` (subscript the coordinate — **never the
bare-index ``\partial_i``, build-enforced**); the imaginary unit is upright ``\mathrm{i}``; the Leray
projection is ``\mathbb P``, a Mori–Zwanzig projection ``\mathcal P``. The Reynolds number is set
through ``\nu`` (``\mathrm{Re} = 1/\nu``), never a field — ``\mathrm{Re}_\lambda`` is measured.

**Bind each code object to its symbol on first mention** — write the correspondence explicitly so it is
never left implicit: `dissipation` ``\equiv \varepsilon``, `kinetic_energy` ``\equiv k``, `curl`
``\equiv \nabla\times``, a field in spectral representation ``\hat f``. In a *rendered* docstring make the
binding **one** LaTeX span — ``\texttt{dissipation} \equiv \varepsilon`` — never a `` `code` `` span
abutting a math span (silent-rendering rule (b) below).

**Silent-rendering micro-rules — markup KaTeX / Documenter render *wrong without failing the build*.**
(a) A code identifier never sits inside a ``…`` / ```math``` span (it renders as a product of italic
single letters — backtick it, or ``\texttt{}``-wrap it inside a formula). (b) A formula is one LaTeX
span — never split across a ``…`` span and an adjacent `` `code` `` span. (c) **Inline math stays on
ONE source line** — a wrapped continuation beginning with a CommonMark list / blockquote leader
(`- ` / `* ` / `> ` / `1.`) is parsed as a new list item and silently drops the span out of math mode
(`docs/make.jl`'s `lint_inline_math()` fails the build on it). (d) No horizontal scroll — hand-wrap a
long docstring signature with a hanging indent under the first argument; break a wide display formula
with `aligned` / `gathered` / `split` (neither a code block nor display math auto-wraps). (e) A backtick
span holds only **well-formed Julia** — a name, type, call, or expression; math that merely looks
code-ish (a half-open interval `[a, b)`, an inequality `κ ≥ 2`, a lone `≤` / `·` / `−` glyph) is LaTeX,
not backticks. (f) **TeX idiom** (adopted from PF 2026-08-06; the first three build-enforced): braced
group arguments — ``\tfrac{1}{2}``, ``\boldsymbol{u}``, never `\tfrac12` / `\boldsymbol u`; no
``\mathbb`` on a digit; the thin space ``\,`` reserved for the differential ``\,\mathrm dx``, never
between plain factors; no manual ``\;`` / ``\:`` spacing around relations; no ``\left``/``\right``
auto-sizing (size by hand with ``\bigl``/``\Bigl``; the ``\left\{ \dots \right.`` system idiom and
the arrow commands are exempt); a conditional bar is ``\mid`` (IT's own addition to the adopted set).

**Correctness is verified, not asserted.** Check every formula, normalization (the ``1/N``, the
``2\varkappa``, the ``\tfrac{1}{2}`` in the energy, Parseval / spectral factors), and every "X is just Y"
equivalence by expanding it against the code — a plausible claim is false until the expansion matches.
Two examples from this codebase: the derivative-skewness "divergence" bug (a repeated index read as
``\nabla\cdot\boldsymbol u = 0``), and the coordinate-free skewness constant
``C = \tfrac47\sqrt{15/2}`` (numerically verified, a competing value ruled out).

**Category/type errors are their own class** — distinct from a normalization slip and invisible to a
value-check: a sentence can be perfectly formatted and read true yet conflate two *kinds* of object.
Guard against conflating a **field** with its **representation** (the physical object vs its spectral
coefficients — say "field in spectral representation", never "spectral field"); a **diagnostic scalar**
with the **field** it reduces (the rate ``\varepsilon = \nu\langle\lvert\boldsymbol\omega\rvert^2\rangle``,
a number, vs a dissipation field; the kinetic energy ``k`` vs the spectrum ``E(\kappa)``); an **operator**
with its **parameter** (the integrating factor ``\mathcal E`` vs ``\nu``; the Leray projection ``\mathbb P``
vs a Mori–Zwanzig ``\mathcal P``); a **rate** with its **time-integral**; a per-unit-wavenumber **spectral
density** ``E(\kappa)`` with an **energy**; and a dimensionally-incomplete reference law (a bare
``\kappa^{-5/3}`` slope vs ``C_K\,\varepsilon^{2/3}\kappa^{-5/3}``). Type every object from the code and
expand it — the physics mirror of the sibling backends' type-error guard.

**Prose is grammatical.** Every sentence has a subject and a verb; no verbless fragments, noun-stacks,
`label:`-colon tags, or comma splices. Concise means few words, not missing verbs. A prose sentence
never opens with a lowercase code identifier — a bare `dissipation` at the start reads as a typo against
the capitalization, so lead with a capitalized word ("The `dissipation` reduction…") or reword (bulleted
`` `arg` `` entries and signatures are exempt).

**Neutral reference register.** A tunable is an *option* / *setting* / *axis* / post-hoc *choice*,
never a "knob"; keep a neutral tone across every authored surface — docstrings, `ARCHITECTURE.md`, the
doc pages, and `@testset` names. **No invented aliases for API objects** (owner-ruled 2026-08-24):
`Simulation` may be called *the front door* only in its own description — its docstring and its own
api-page/§4.7 sections, where the term is introduced — and every other surface names `Simulation`
explicitly. The same rule covers any future metaphor: an alias lives where it is defined, nowhere
else. (The glossary keeps its *front door* row: the decision log's history uses the term, and the
row is where a reader resolves it.)

## Doc-edit checklist — run all on every documentation change (most strictly on `ARCHITECTURE.md`)

The battery the `/check-docs` command (`.claude/commands/check-docs.md`) encodes; run it across
**every** surface (every `src/*.jl` docstring, `ARCHITECTURE.md`, every `docs/src` page). Run each as a
**positive** procedure — enumerate, then verify each item; a defect that is absent-by-omission (an
unbound symbol, a false-but-plausible formula) does not announce itself on a read-through. A flagged
instance is a *sample of a class* — fix the class, not the line.

**Order the work: code before docs.** When a round of findings mixes renames, signature changes and
prose, land the code first — the docs describe the code, so the reverse order writes every affected
docstring twice. (2026-08: ten renames landed first, and the doc phase then touched each surface once.)

1. **Correct** — every formula, normalization, conservation / adjoint relation, and quantifier
   (*exact / all / never*) true and precise, verified against `src/` (quote the decisive line) or by
   derivation; the diagnostic consistent with the physical quantity it claims to measure; and free of
   **category/type errors** (a field vs its representation, an operator vs its parameter, a rate vs its
   time-integral — type each object from the code).
2. **Self-contained** — every symbol bound to its meaning at first use (or in `notation.md`); **and
   every signature argument documented** — enumerated *from the signature* (positional + keyword), each
   its own entry, so an "obvious" `domain` or `dt` cannot be skipped (this is how `domain` / `buffers` once
   slipped past). A **term of art** naming a package concept is explained or `@ref`-linked, not left
   correct only to a reader who already knows the code — the **cold read** (the docstring parsed with
   the module source withheld) is the test.
3. **Notation** — one symbol per concept, one concept per symbol; the house glyphs (`\boldsymbol`, the
   `\boldsymbol{\kappa}` / `\kappa` / `k` / `\varkappa` set, `\varphi`, `\partial_{x_i}`, `\mathrm{i}`,
   `\mathbb P` / `\mathcal P`); standard notation; the naming convention (math variables symbolic,
   storage descriptive).
4. **Formatted (bidirectional)** — math is LaTeX never backticks; every code identifier backticked
   never bare; markdown tables top-level; and the *silent* failures — a code name never inside a math
   span, a formula never split across a math / `` `code` `` boundary, inline math on one source line
   (build-enforced), no `\mathbf` (build-enforced), no > 88-col signature or wide display block
   (horizontal scroll).
5. **Current & complete** — every claim matches the code's present state; no stale
   *future / deferred / none-exist*; and a docstring or summary that names only a *subset* of what the
   code now provides is stale even if literally true (a module docstring naming one scheme family, a
   capability list missing a builder). Check each still names everything added since it was written,
   against the current `export`s / method set.

Plus, **across variant pairs** (the `src/` docstrings, *relational*, not per-surface): each operation's
`f` / `f!` (getter / `set_…!`) share **one home** for the formula, the other a thin `@ref` wrapper,
with no notation that drifts across the pair.

## Verification workflow

- Load: `julia --project -e 'using GBGIsotropicTurbulence'`.
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
- Docs build: `julia --project=docs docs/make.jl` — `checkdocs = :exports` plus the two build lints
  (`lint_inline_math`, `lint_notation_variants`) must be clean. After a build, revert the transient
  dev entry with `git checkout -- docs/Project.toml` **alone** — never co-list `docs/Manifest.toml`,
  which aborts the checkout and lets the dev entry slip into a commit (it broke the Docs CI once). CI
  does its own `Pkg.develop`.
- Consult `Project.toml` for dependencies and versions; do not assume.

## Working agreements

- The API is not frozen; do not build backward-compatibility shims.
- **Commit ⇒ push, on `main`.** This is a private repo in active development, synced through GitHub;
  work is committed **directly on `main`** and **pushed in the same step**. End every commit message
  with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; never use `[skip ci]`.
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
  "by design" (see the doc policy's "Correctness is verified, not asserted"). Instances (2026-07-14):
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
  holder, expand each candidate chain algebraically and check it against the existing exports** — the doc
  policy's "a plausible 'X is just Y' is false until the expansion matches", applied to code shapes and
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
  it, because the regex required a cell to be exactly one backticked name. The rule: **after any class
  fix, enumerate the surfaces from the finding's own text — not from memory — and re-run the
  verifier; a class claimed swept but not re-measured is an instance fix wearing a class's name.**
  Instances (2026-08-17): the eleven above, plus a scan I wrote that caught only the form I had first
  noticed (bare `` `code` `` beside math, not the linked `[`code`](@ref …)` form), certifying clean
  while three sites stood.

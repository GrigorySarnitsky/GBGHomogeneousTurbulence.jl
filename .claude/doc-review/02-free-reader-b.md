# Free Reader B — fresh-eyed, no-checklist review

Hat: an expert physicist-programmer reading the rendered docs cover to cover, asking "would I
trust this DNS with my own research?" No assigned lens; findings below are genuine reactions from
the read, ranked most-severe first. Most of the document's individual formulas and cross-page
numeric claims (CFL constants, the `κ_max·η` derivation, the She–Lévêque/K62 exponents, the
`G ↔ C_ε` conversion, the Lundgren2002 floor, the `PhaseShift` band fraction, register counts,
etc.) were spot-checked by hand and found internally consistent — this document has clearly been
through many prior rounds of formula auditing. The findings below are the things that survived
that: usability, promise-vs-delivery gaps, and one outright non-runnable "runs as written" claim.

---

## Finding 1 — the one runnable-code claim in ARCHITECTURE.md is false as written

**Type:** other (documentation correctness) · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: architecture, §2 "Running a simulation" — the code block:
  ```
  run!(sim) do s
      accumulate_statistics!(my_stats, s)
      current_time(s) < t_end
  end
  ```
- Same section, immediately after: *"the example above runs as written — a forcing can be named
  operator-free (...) and `warmup!` detects stationarity."*

**Description:** The text explicitly asserts the whole preceding code block "runs as written," but
the block calls `accumulate_statistics!(my_stats, s)`, and neither `accumulate_statistics!` nor
`my_stats` is defined, imported, or explained anywhere in the snippet, the surrounding prose, or
the package's own API index (it is not a `GBGIsotropicTurbulence` export). Copy-pasting the example
throws `UndefVarError`. By contrast, the Home page's own quick-start snippet is genuinely
self-contained and runnable. This is the one place in the document where runnability is claimed as
a specific, falsifiable fact, and the fact is wrong.

---

## Finding 2 — the architecture's "comparison machine" has no public entry point

**Type:** api-gap · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: architecture, §3: *"Both disciplines are the same comparison machine — run a configuration
  against a reference and check chosen physical functionals ... within tolerance."*
- PAGE: phenomenology: *"the DNS measures, the laws predict, and the validation layer sets them
  side by side"* / *"The comparison lives consumer-side (the validation layer), which reads both."*
- PAGE: decisions (2026-08, user-directed, "A `Simulation` is a container..."): *"The `validate_spectrum`
  helper leaves the package altogether, to `test/validation.jl` as `compare_to_model`: comparing a
  run against a model spectrum ... is what a validation suite asks and a solver never does."*

**Description:** §3 frames "the comparison machine" as the architecture's organizing research
tool, and the Phenomenology page's own prose ("the validation layer... which reads both") reads as
though a shipped component performs this comparison. In fact the one function that did this
(`validate_spectrum`) was deliberately removed from the public API and now lives only inside the
internal test suite as `compare_to_model` — invisible to a downstream user, and absent from the
`GBGIsotropicTurbulence` API index and every `Phenomenology` page. A user who wants to do exactly
what §3 and the Phenomenology page describe as the point of the exercise has to reimplement the
comparison from `energy_spectrum` and `spectrum` themselves; nothing in the docs says so plainly.

---

## Finding 3 — no demonstrated validation numbers or performance data anywhere

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:** whole document; most concretely PAGE: architecture §6 ("GPU is the primary target...")
and PAGE: phenomenology / api-Scalings (`Li2008`, `Sreenivasan1995`, `Sreenivasan1998`).

**Description:** The package is presented as GPU-primary and performance-audited to an extreme
degree (the decision log's memory/compute/optimality audits run to thousands of words), and as
carrying a full literature-comparison apparatus (`Phenomenology`). Yet nowhere in the rendered docs
is there a single demonstrated result from an actual run of this code — no measured `C_K`, `Re_λ`,
or spectrum plotted against a model law, and no wall-clock/throughput number for any grid size on
any backend. For a physicist deciding whether to trust the solver, the docs argue exhaustively
about *how carefully* the code is built but show no evidence that a run of it reproduces known
turbulence statistics.

---

## Finding 4 — `kinetic_energy` and `scalar_variance` name both a setting and a measurement

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun: `Simulation(...; kinetic_energy = 1.5, ...)`, `scalar_variance = 1.0`
  keyword arguments — *"the initial, and when forced the held, kinetic energy $k$."*
- PAGE: api / Observables: `kinetic_energy(u)` / `kinetic_energy(û)`, `scalar_variance(φ)` — the
  measured reductions.

**Description:** The identical identifiers `kinetic_energy` and `scalar_variance` are used both as
`Simulation` keyword-argument names (a target/initial *setting*) and as exported `Observables`
function names (a *measurement*). Julia's scoping resolves this without a runtime collision, and
the symmetry (the keyword names the quantity the function measures) is arguably elegant — but a
reader skimming a code snippet with both uses nearby (as the Home page's quick start has) has to
stop and determine from context which role `kinetic_energy` plays at each site.

---

## Finding 5 — `valid_Reλ` is advisory-only, so `Lundgren2002` can silently return an unphysical sign

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / phenomenology / Phenomenology: `Reference` — *"the range discriminates only where a
  law states one, and it is advisory: a comparison that opts in reads it, nothing enforces it."*
- PAGE: api / phenomenology / StructureFunctions: `Lundgren2002` — *"The bracket vanishes at
  $\mathrm{Re}_\lambda \approx 34$ and turns positive below it — a third-order longitudinal
  structure function of the wrong sign... a comparison that honours `valid_Reλ` never evaluates it
  in the region where the sign flips."*

**Description:** Calling `structure_function(Lundgren2002(), r, fp; order = 3)` at `Re_λ` below
~34 returns a positive value implying an inverse energy flux — a physically nonsensical result —
with no warning or error, because `valid_Reλ` is deliberately unenforced everywhere in
`Phenomenology`. This sits oddly next to the rest of the package, which is otherwise generous with
construction-time guards and warnings for exactly this class of silent-wrongness risk (the
empty-band floor in `ConstantPower`/`VarianceController`, the under-resolved-scalar warning in
`Simulation`, the misdeclared-forcing `ArgumentError` in `ResolvedGenerator`). A physicist reaching
for this one law without having read its docstring's caveat admonition gets a wrong number, not a
loud failure.

---

## Finding 6 — the decision log's prose density works against it as documentation

**Type:** clarity · **Severity:** nit · **Confidence:** high

**Locations:** PAGE: decisions, throughout — e.g. the 2026-07 "The observation layer" entry and the
2026-07 "The memory audit" entry each run 300–500+ words as a single paragraph, multiply nested
parentheticals and em-dashes deep (three and four levels are common).

**Description:** Individually, the claims check out (verified several by hand). But several entries
required two or three passes to parse the actual claim being made, which is exactly the "a passage
you had to read three times" reaction this review is watching for. `ARCHITECTURE.md §11` reads more
like a commit-log audit trail for the tool's own author than documentation a new physicist-user
would consult; that may be a deliberate audience choice (`CLAUDE.md` frames it as read-before-
structural-change material), but as delivered it is a genuine readability cost.

---

## Finding 7 — inconsistent leading-semicolon style across `FixedDomain(...)` call examples

**Type:** format · **Severity:** nit · **Confidence:** low

**Locations:**
- PAGE: api / Forcing, `DeferredForcing` examples: `domain = FixedDomain(grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)` — no leading `;`.
- PAGE: api / SimulationDomain, api / SimulationRun, PAGE: observables_cache — every other
  `FixedDomain(...)` call example leads with `FixedDomain(; grid_points_per_axis = ..., ...)`.

**Description:** Not a functional bug — Julia does not require the semicolon at a call site even
for a keyword-only signature — but every other worked example in the document consistently opens
the call with `;` and this one Forcing-page example is the sole outlier, a small inconsistency a
copy-paste-driven reader would notice.

---

*Candidates weighed before ranking: ~20 (most were formula/cross-reference spot-checks that came
back consistent and are not reported as findings). No truncation — all findings judged worth
reporting are listed above.*

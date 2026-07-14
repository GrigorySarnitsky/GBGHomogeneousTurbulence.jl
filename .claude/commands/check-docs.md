---
description: Run the COMPLETE documentation-quality battery — every check across every doc surface, fix all findings, rebuild.
---

Run the **entire** documentation-quality battery. This is the full matrix of (every check) × (every
surface), run to completion in one invocation — not a single check, not a single file. Do not stop after
one check or one file, and do not ask which check to run. Cover every cell, fix every genuine finding in
one pass, rebuild, and report the matrix. `CLAUDE.md` (§Documentation policy, §Style, the doc-edit
checklist) holds the authoritative definitions; this command runs all of them.

## Surfaces (ALL of them)

1. `docs/ARCHITECTURE.md` — every section and §References.
2. Every docstring in `src/*.jl` — `SimulationDomain`, `State`, `Generator`, `Observables`, `Forcing`,
   `Propagator`, `Particles`, `SimulationRun`, `Phenomenology` (and its `Spectra` / `StructureFunctions` /
   `Scalings` submodules), and the umbrella `GBGIsotropicTurbulence.jl` (module **and** function
   docstrings; `#` comments are exempt — not rendered).
3. Every page in `docs/src/` — `index.md`, `notation.md`, `api.md`, and all `docs/src/api/*.md`
   (hand-written prose and `@docs` groupings; skip the `@autodocs` / `@example` / `@repl` / `@index`
   blocks themselves).

## Checks (ALL of them, on every surface)

Run each as a POSITIVE procedure — enumerate, then verify each item. A defect that is absent-by-omission
(an unbound symbol; a false-but-plausible formula; a missing argument) does not announce itself on a
read-through, so passive reading is not a check.

1. **Correct** — enumerate every formula, normalization constant (the `1/N`, `2ν`, `2ϰ`, the `½` in the
   energy, Parseval / spectral factors), conservation / adjoint relation, complexity claim, and quantifier
   (*exact / all / never / allocation-free*); verify EACH against the implementation in `src/` (read it,
   quote the decisive line) or by derivation. Confirm the **diagnostic is consistent with the physical
   quantity it claims to measure** (the estimator computes what the leading formula states). Flag false /
   imprecise / overclaim. For a nontrivial statement the sharpest method is to write it formally on scratch
   (types from the code) and expand it. **Also flag the category/type-error class** — invisible to a
   value-check (a sentence can be perfectly formatted and read true yet conflate two *kinds* of object): a
   **field** conflated with its **representation** (physical vs spectral — "field in spectral
   representation", not "spectral field"); a **diagnostic scalar** with the **field** it reduces (the
   dissipation *rate* `ε = ν⟨|ω|²⟩`, a number, vs a dissipation field; `k` vs the spectrum `E(κ)`); an
   **operator** with its **parameter** (the integrating factor vs `ν`; the Leray projection `ℙ` vs a
   Mori–Zwanzig `𝒫`); a **rate** vs its **time-integral**; a per-`κ` **spectral density** `E(κ)` vs a bulk
   **energy**; a dimensionally-incomplete reference law (a bare `κ^-5/3` slope vs `C_K ε^2/3 κ^-5/3`). Type
   every object from the code. Cross-check a load-bearing claim against `ARCHITECTURE.md` (its decision log
   and the physics) and against the enforcing test.
2. **Self-contained** — enumerate every symbol, sub / superscript, operator name, and bold / blackboard
   letter; cite the clause (on the page or in `notation.md`) that binds each; flag any unbound.
   (Universally standard math — `∇`, `Δ`, `∫`, `⟨·⟩`, `π`, the imaginary unit — needs no binding.) **And,
   separately, from each docstring's *signature*:** enumerate every argument (positional *and* keyword)
   and cite where the body documents it — an argument mentioned only *inside a formula* reads as
   bound-by-use and is `UNDOCUMENTED` (`ops` / `ws` once slipped this way). **And the same bar binds
   *terms of art*, not only symbols:** a noun naming a package concept (an *integrating factor*, a
   *de-alias kernel*, the *Lamb vector*, a *stage register*) must be explained on the page or `@ref`-linked
   — the **cold read** (parse the docstring with the module source withheld) is the test. Run this in the
   cold-reader lane.
3. **Notation — one symbol per concept, one concept per symbol** — flag a concept wearing two symbols; a
   glyph with two meanings in one section. Enforce the house set: vectors / tensors `\boldsymbol` (never
   `\mathbf`); the wavenumber clash kept distinct — `\boldsymbol{\kappa}` vector, `\kappa` magnitude, `k`
   kinetic energy, `\varkappa` scalar diffusivity; `\varphi` the scalar (never `\theta`); `\partial_{x_i}`
   (never `\partial_i`); upright `\mathrm{i}`; `\mathbb P` Leray, `\mathcal P` Mori–Zwanzig. And the code
   **naming convention** (math variables `u` / `ω` / `φ` / `û` / `φ̂`, storage slots descriptive) — a
   docstring signature or example that reintroduces `velocity` / `uh` for a math variable is stale.
4. **Formatted (bidirectional)** — math is LaTeX, never backticks (incl. ASCII-math like `Re = 1/nu` that
   carries no glyph); every code identifier / type / module name is backticked, never bare; check BOTH
   directions. Markdown tables top-level, never indented in a list. Also the *silent* failures (source
   looks right, page renders broken): a code name never *inside* a ``…`` span, a formula never split
   across a ``…`` / `` `code` `` boundary, inline math on one source line, no `\mathbf`, and no > 88-col
   signature or wide unbroken display block (horizontal scroll). Inline-math-on-one-line, `\partial_i`,
   and `\mathbf` are **build-enforced** (`docs/make.jl`'s `lint_inline_math()` / `lint_notation_variants()`
   error), so the rebuild below IS those guards; the **argument-coverage** sweep runs inside check 2.
5. **Current & complete** — every claim matches the code's present state; no stale
   *future / deferred / none-exist*; and a docstring or summary that names only a *subset* of what the
   code now provides is stale even if literally true (a module docstring naming one of two integrator or
   forcing families; a capability list missing a builder). Check each module / operation / summary still
   names everything added since it was written, against the current `export`s / method set.
6. **Cited** — context-standard author–year; ≤ 3 authors named, `First et al.` for 4+; inline references
   verbatim-consistent with the `ARCHITECTURE.md` §References entry. **Bidirectional:** every inline
   author–year cite in a `src/*.jl` docstring has a matching `§References` entry — a cite with no entry is
   a defect; an entry citing no docstring is stale. The extraction-bound `Phenomenology` leaf is
   **exempt**: each reference law carries its own self-contained `Reference` value, so its cites are *not*
   duplicated in `§References`. **Never cite an inaccessible source** (the private notes under
   `inspiration/` are working material, not citable).
7. **Consistent across variant pairs** (the `src/` docstrings — *relational*, not per-surface) — group
   each operation's generics (allocating `f` / in-place `f!`, physical / spectral, getter / `set_…!`) and
   confirm the defining math (formula, spectral kernel) lives in **one home**, every other variant a thin
   `@ref`-linking wrapper — no second copy of the formula, no notation that drifts across the pair
   (`\partial_i` vs `\partial_{x_i}`, `velocity` vs `u`). Checks 1–6 each run inside one string and cannot
   see this; run it in the family lane.

## Mechanism

- Fan out subagents across the surfaces in parallel — each runs checks 1–6 on its surface via the
  positive procedures above, reading `src/` as ground truth, and returns genuine findings with evidence
  and a proposed fix.
- Two **cross-cutting lanes** (their grouping is not per-surface, so the surface agents cannot run them):
  a **family lane** that enumerates each operation's `f` / `f!` (physical / spectral) generics and diffs
  their docstrings for one-home + notation (check 7); and a **cold-reader lane** — an agent handed each
  exported docstring's text *alone, without the module source*, reporting every term of art it cannot
  parse (check 2's audience half). **Substrate rule for the cold-reader lane:** feed it the reader's
  *actual* `?name` view — include the **module docstring** (`?Module`) and **every** method docstring of a
  generic, never one collapsed docstring; a substrate that skips the module docstring or shows one method
  of a multi-method generic over-flags things documented centrally or on a sibling method, so **verify
  every cold-reader finding against source before fixing**.
- Run the deterministic grep guards below, plus a bare-module-name scan and a glyph-vs-backtick scan
  (Unicode math *outside* a backtick span), a **code-in-math scan** (a 2+-letter lowercase run *inside* a
  ``…`` span that is neither a `\command` nor `\texttt`/`\mathrm`-wrapped — it renders as a letter-product),
  a **split-formula scan** (a ``…`` math span abutting a `` `code` `` span — the silent rule-(b) failure),
  and a deterministic **argument-coverage** backstop: a short Julia helper that splits each `"""…"""`,
  parses the signature's positional + keyword parameters, and flags any never mentioned as a backticked
  `` `arg` `` in the body (then triage).

```bash
grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs                              # tables top-level only — must be empty
grep -rnE '`[^`]*[≤≥≠∈∉∇Δ⟨⟩‖√×⋅][^`]*`' src/*.jl docs/src docs/*.md    # formula-in-backticks → should be ``LaTeX``
grep -rnE '\$[^$]*[\\_^{}][^$]*\$' docs                                # stray TeX $…$ → use ``…`` / ```math```
grep -rniE '\bknobs?\b' docs src                                       # neutral register — must be empty
grep -rnE '\\partial_[ijk]' src/*.jl docs/*.md docs/src                # bare-index ∂ → \partial_{x_i}; build-enforced, must be empty
grep -rnE '\\mathbf' src/*.jl docs/*.md docs/src                       # upright bold → \boldsymbol; build-enforced, must be empty
grep -rnwE 'uh|phih|velocity|vorticity' src/*.jl | grep -vE 'ws\.|sim\.|\.velocity|_forcing|_spectral|_physical|_field|_copy|_star|_start|_rate|_nonlinear|_plans|velocity_|vorticity_|`|the |physical |a velocity'  # stale math-variable names (triage: keep struct fields / function names / prose)
awk '/^"""/{d=!d;s=d;next} s&&/^[^ ]/{s=0} s&&/^    [A-Za-z_].*\(/&&length>88{print FILENAME":"FNR}' src/*.jl  # wide docstring signatures — FNR (per-file)
grep -rnE '§[0-9]|docs/src/|inspiration/|ARCHITECTURE\.md' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'  # dead ref on a user-facing docstring: a §-number / design-doc path (drop #-comment hits) — must be empty
grep -rnzE 'References?:[^"]*;' src/*.jl                                # crammed citation block (two citations joined by `;`) → one per bullet line
comm -23 <(grep -rhoE '\((19|20)[0-9]{2}' src/SimulationDomain.jl src/Propagator.jl src/Generator.jl src/Observables.jl src/Forcing.jl src/State.jl | grep -oE '(19|20)[0-9]{2}' | sort -u) <(sed -n '/^## References/,$p' docs/ARCHITECTURE.md | grep -oE '\((19|20)[0-9]{2}' | grep -oE '(19|20)[0-9]{2}' | sort -u)  # §4: a dynamics-side cite year with no §References entry (Phenomenology leaf exempt) — triage each
grep -rnE '\. `[a-z][a-z_]+!?`' src/*.jl docs/src docs/*.md | grep -vE ':[0-9]+:[[:space:]]*#'  # prose sentence opens with a lowercase code identifier (incl. an `f!` form) → capitalize the lead word or reword (triage: bullets / args / signatures exempt)
```

- Triage (drop false positives — universally standard math; the real Julia operators `×` / `⋅` / `≈`;
  pervasive shorthand `L²` / `N³` / `O(N²)`; `#`-comment hits; kwarg names correctly backticked; the
  `velocity`/`vorticity` inside a *storage field* or *function name* or *prose*), then fix EVERY genuine
  finding in one pass.
- Rebuild: `julia --project=docs docs/make.jl` (`checkdocs = :exports` + both lints + render) — must be
  clean; then `git checkout docs/Project.toml`.
- Commit + push on `main` (no `[skip ci]`; the docs site must redeploy).

## Report

Report the full matrix: which surfaces × checks were run, the findings (class and count) with fixes, and
what was verified clean — including the **family lane**'s one-home / notation audit of each `f` / `f!`
pair and the **cold-reader lane**'s pass over the exported docstrings. A flagged instance is a *sample of
a class* — fix the class, not the line. Done only when every cell is covered and the build is clean.

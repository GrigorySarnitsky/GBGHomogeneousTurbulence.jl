---
description: Run the COMPLETE documentation-quality battery — every check across every doc surface, fix all findings, rebuild.
---

Run the **entire** documentation-quality battery. This is the full matrix of (every check) × (every
surface), run to completion in one invocation — not a single check, not a single file. Do not stop after
one check or one file, and do not ask which check to run. Cover every cell, fix every genuine finding in
one pass, rebuild, and report the matrix. `CLAUDE.md` (§Documentation policy, §Style, the doc-edit
checklist) holds the authoritative definitions; this command runs all of them.

## Cost modes — cheap lanes by default; the fix is never economized

The scan/review lanes run on a **cheaper agent model by default** (the economy mode is the standard
one — Sonnet-class lanes; lane cost is the ONLY thing it reduces; the reviewer-model policy of
2026-08-01). Run the lanes at full strength only when the user explicitly asks for it (in any words —
"strong lanes", "full-price scan", "expensive lanes"). In EVERY mode the **fix phase is never
reduced**: the main thread — at its own (strongest) model, full effort — verifies every finding and
closes every one in the same run, as *fixed* or as *dismissed with a written reason*, including the
expensive judgment calls (cold-reader glosses, argument-coverage triage, the class sweeps the findings
demand). Deferring findings to a later session is NOT an outcome of any mode. All modes produce the
identical end state — zero open findings, clean build — and differ only in what the lanes cost.
(Ported from PF 2026-08-06, with its postmortem: an economy run once deferred its judgment tail as a
standing remainder — the failure mode this paragraph forbids.)

## Surfaces (ALL of them)

1. `docs/ARCHITECTURE.md` — every section and §References. (The decision log §11 is append-only
   HISTORY: an old entry naming a superseded API records what was decided then — only the
   current-state sections must match the code.)
2. Every docstring in `src/*.jl` — `SimulationDomain`, `State`, `Cache`, `Generator`, `Observables`,
   `Forcing`, `Propagator`, `Particles`, `SimulationRun`, `Phenomenology` (and its `Spectra` /
   `StructureFunctions` / `Scalings` submodules), and the umbrella `GBGIsotropicTurbulence.jl` (module
   **and** function docstrings; `#` comments are exempt — not rendered).
3. Every page in `docs/src/` — `index.md`, `notation.md`, `observables_cache.md`, `api.md`, and all
   `docs/src/api/*.md` (hand-written prose and `@docs` groupings; skip the `@autodocs` / `@example` /
   `@repl` / `@index` blocks themselves). The gitignored `docs/src/architecture.md` is a regenerated
   *copy* — exclude it (edit `docs/ARCHITECTURE.md`, not the copy).
4. **The BUILT HTML** — `docs/build/api/*/index.html`, after `julia --project=docs docs/make.jl`.
   This is a surface in its own right, not a rendering of surface 3: what each `@docs` block actually
   collected, whether every export landed on exactly one page, and whether a section's hand-written
   blurb still matches its block's contents are visible only here (ported from PF, where two defect
   classes lived exactly in this gap).

## Checks (ALL of them, on every surface)

Run each as a POSITIVE procedure — enumerate, then verify each item. A defect that is absent-by-omission
(an unbound symbol, a false-but-plausible formula) does not announce itself on a read-through, so passive
reading is not a check.

1. **Correct** — enumerate every formula, normalization (the `1/N`, the ``2\varkappa``, the ``\tfrac{1}{2}``
   in the energy, Parseval / spectral factors), conservation / adjoint relation, and quantifier
   (*exact / all / never*) true and precise, verified against `src/` (quote the decisive line) or by
   derivation; the diagnostic consistent with the physical quantity it claims to measure; and free of
   **category/type errors** (a field vs its representation, an operator vs its parameter, a rate vs its
   time-integral, a diagnostic scalar vs the field it reduces, a per-``\kappa`` density vs an energy —
   type each object from the code).
2. **Self-contained** — every symbol bound to its meaning at first use (or in `notation.md`); **and
   every signature argument documented** — enumerated *from the signature* (positional + keyword), each
   its own entry, so an "obvious" `domain` or `dt` cannot be skipped. A **term of art** naming a package
   concept (a *boundary*, a *deposit*, a *stamp*, an *epoch*, a *slot*, an *observation*, an
   *integrating factor*) is explained or `@ref`-linked, not left correct only to a reader who already
   knows the code — the **cold read** (the docstring parsed with the module source withheld) is the
   test. Run this in the cold-reader lane.
3. **Notation** — one symbol per concept, one concept per symbol; the house glyphs (`\boldsymbol`, the
   `\boldsymbol{\kappa}` / `\kappa` / `k` / `\varkappa` set, `\varphi`, `\partial_{x_i}`, `\mathrm{i}`,
   `\mathbb P` / `\mathcal P`); standard notation; the naming convention (math variables symbolic,
   storage descriptive).
4. **Formatted (bidirectional)** — math is LaTeX never backticks; every code identifier backticked
   never bare; markdown tables top-level; and the *silent* failures — a code name never inside a math
   span, a formula never split across a math / `` `code` `` boundary, inline math on one source line
   (build-enforced), no `\mathbf` (build-enforced), no > 88-col signature or wide display block. **And
   the TeX idiom set** (adopted 2026-08-06, every scan empty at adoption): braced group arguments
   (``\tfrac{1}{2}``, ``\boldsymbol{u}`` — never `\tfrac12`, `\boldsymbol u`); the thin space ``\,``
   reserved for the differential (``\,\mathrm d\kappa``) — never between plain factors; no manual
   ``\;`` / ``\:`` spacing around relations or between factors; no ``\left``/``\right`` auto-sizing
   (an Inner atom that adds a spurious gap — size by hand with ``\bigl``/``\Bigl``; the system
   ``\left\{ \dots \right.`` and the arrow commands are exempt); no ``\mathbb`` on a digit; a
   conditional bar is ``\mid``, never a spaced `|`.
5. **Current & complete** — every claim matches the code's present state; no stale
   *future / deferred / none-exist*; and a docstring or summary that names only a *subset* of what the
   code now provides is stale even if literally true. Check each still names everything added since it
   was written, against the current `export`s / method set.
6. **Cited** — context-standard author–year; ≤ 3 authors named, `First et al.` for 4+; inline
   references verbatim-consistent with the `ARCHITECTURE.md` §References entry (the `Phenomenology`
   leaf is exempt, carrying its own self-contained `Reference` values); never an inaccessible source.
7. **Consistent across variant pairs** (the `src/` docstrings — *relational*, not per-surface): each
   operation's `f` / `f!` (getter / `set_…!`) share **one home** for the formula, the other a thin
   `@ref` wrapper, with no notation that drifts across the pair. Run it in the family lane.

## Mechanism

- Fan out subagents across the surfaces in parallel, **on the cheaper (economy) lane model by
  default** (see Cost modes) — each runs checks 1–6 on its surface via the positive procedures,
  reading `src/` as ground truth, and returns genuine findings with evidence and a proposed fix.
- Two **cross-cutting lanes** (their grouping is not per-surface, so the surface agents cannot run
  them): the **family lane** (check 7) and the **cold-reader lane** (check 2's audience half).
  **Substrate rule for the cold-reader lane:** feed it the reader's *actual* `?name` view — include
  the **module docstring** (`?Module`) and **every** method docstring of a generic, never one
  collapsed docstring; a substrate that skips the module docstring or shows one method of a
  multi-method generic over-flags things documented centrally or on a sibling method, so **verify
  every cold-reader finding against source before fixing**.
- Run the deterministic scans below. The block has two tiers: **must-be-empty** scans and **triage**
  heuristics whose hits mix real signal with false positives.
  **NEVER pipe a triage scan through `head`/`tail`.** Adding a limit to keep the output readable is
  how a class gets half-swept and reported closed (PF, 2026-08-04: a scan run with `| head -5` showed
  5, and there were 31). Count first (`| wc -l`), then read the whole list.

```bash
DOCS_MD="docs/ARCHITECTURE.md docs/src/notation.md docs/src/index.md docs/src/api.md \
         docs/src/observables_cache.md docs/src/api/*.md docs/src/api/phenomenology/*.md"

# ---- must come back EMPTY ----
grep -rnE '^[[:space:]]+\|[-:| ]+\|' docs                              # tables top-level only
grep -rniE '\b(knobs?|tweaks?)\b' docs src                             # neutral register
grep -rnE '\\partial_[ijk]' src/*.jl $DOCS_MD                          # bare-index ∂ → \partial_{x_i}; build-enforced
grep -rnE '\\mathbf' src/*.jl $DOCS_MD                                 # upright bold → \boldsymbol; build-enforced
grep -rnP '\\\\,(?!\\\\mathrm[ {]d)' src/*.jl; grep -rnP '\\,(?!\\mathrm[ {]d)' $DOCS_MD  # gratuitous thin space → keep only the differential \,\mathrm d; else a plain space (never delete: \varepsilon\,r → \varepsilon r, not \varepsilonr)
grep -rnP '\\\\[dt]?frac\s*[^{\s\\\\]' src/*.jl; grep -rnP '\\[dt]?frac\s*[^{\s]' $DOCS_MD  # unbraced fraction numerator → \tfrac{1}{2} (catches \tfrac12 AND \tfrac N2; build-enforced)
grep -rnP '\\\\boldsymbol(?!\{)' src/*.jl; grep -rnP '\\boldsymbol(?!\{)' $DOCS_MD  # unbraced \boldsymbol → \boldsymbol{u} (catches the space, digit, and \boldsymbol\omega forms; build-enforced)
grep -rnP '\\\\!\\\\!' src/*.jl; grep -rnP '\\!\\!' $DOCS_MD           # \!\! double negative thin → juxtapose
grep -rnP '\\\\mathbb\s*\{?\s*[0-9]' src/*.jl; grep -rnP '\\mathbb\s*\{?\s*[0-9]' $DOCS_MD  # \mathbb on a digit falls back to a plain glyph → \mathbf{1}
grep -rnP '\\\\(left|right)(?![a-zA-Z])' src/*.jl; grep -rnP '\\(left|right)(?![a-zA-Z])' $DOCS_MD  # \left/\right auto-sizing → \bigl/\Bigl by hand (the \left\{ … \right. system idiom and \leftarrow/\rightarrow are exempt — none in this corpus today)

# ---- TRIAGE (real signal mixed with false positives — COUNT first with wc -l, then read ALL) ----
grep -rnE '`[^`]*[≤≥≠∈∉∇Δ⟨⟩‖√×⋅][^`]*`' src/*.jl docs/src docs/*.md    # formula-in-backticks → ``LaTeX`` (FP: real Julia operators ×/⋅/≈)
grep -rnE '\$[^$]*[\\_^{}][^$]*\$' docs                                # stray TeX $…$ → use ``…`` / ```math```
grep -rnP '\\\\[;:](?![a-zA-Z])' src/*.jl; grep -rnP '\\[;:](?![a-zA-Z])' $DOCS_MD  # manual \;/\: spacing → let TeX space the operator (FP: a \; separating args after a comma)
grep -rnoP '``[^`]+``' src/*.jl $DOCS_MD | perl -ne 'if (/^(.*?:\d+):(.*)$/) { my ($loc,$span)=($1,$2); my $s=$span; $s =~ s/\\\\?[a-zA-Z]+//g; $s =~ s/_\{[a-z]+\}//g; print "$loc:$span\n" if $s =~ /[a-z]{2,}/; }'  # code-in-math: a bare multi-letter run INSIDE a math span renders as a letter-product → \mathrm{…}/\texttt{…}. The filter tests the span only (a naive grep of the full line matches the FILE PATH and drowns the scan — the 2026-08-06 lesson); FPs: \texttt{…}/\text{…} braced arguments, #-comment lines
grep -rnwE 'uh|phih|velocity|vorticity' src/*.jl | grep -vE 'ws\.|sim\.|\.velocity|_forcing|_spectral|_physical|_field|_copy|_star|_start|_rate|_nonlinear|_plans|velocity_|vorticity_|`|the |physical |a velocity'  # stale math-variable names (triage: struct fields / function names / prose are fine)
awk '/^"""/{d=!d;s=d;next} s&&/^[^ ]/{s=0} s&&/^    [A-Za-z_].*\(/&&length>88{print FILENAME":"FNR}' src/*.jl  # wide docstring signatures — FNR (per-file)
grep -rnE '§[0-9]|docs/src/|inspiration/|ARCHITECTURE\.md' src/*.jl | grep -vE ':[0-9]+:[[:space:]]*#'  # dead ref on a user-facing docstring — must read complete at the REPL (drop #-comment hits)
grep -rnzE 'References?:[^"]*;' src/*.jl                                # crammed citation block → one per bullet line
grep -rnE '\. (`[a-z]|``)' src/*.jl docs/src docs/*.md | grep -vE ':[0-9]+:[[:space:]]*#'  # prose sentence opens with a lowercase identifier or a formula → reword with a capitalized lead (bullets/args/signatures exempt)
```

Two deterministic backstops that are not one-line greps:

```bash
# DOI / citation cross-check — every DOI cited in a src docstring must appear (verbatim) in
# ARCHITECTURE.md §References (the Phenomenology leaf is exempt: its Reference values are
# self-contained by design and are checked for well-formedness instead).
python3 - <<'PY'
import re, glob
arch = open('docs/ARCHITECTURE.md').read()
for f in glob.glob('src/*.jl'):
    exempt = 'Phenomenology' in f
    for m in re.findall(r'doi\.org/[^\s\)\]"`]+', open(f).read()):
        d = m.rstrip('.,);')
        if not exempt and d not in arch:
            print('DOI in a docstring but not in ARCHITECTURE §References:', f, d)
PY

# Argument coverage — from each docstring SIGNATURE, every positional + keyword parameter must be
# mentioned as a backticked `arg` in the body (an arg named only inside a formula reads as
# bound-by-use). Triage the hits: a thin wrapper that @ref-links its home may name a math variable
# in a ``…`` span; internal `_helpers` are looser.
julia --startup-file=no -e '
for file in filter(f->endswith(f,".jl"), readdir("src"; join=true))
  s = read(file, String)
  for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, s)
    body = m.captures[1]; sig = strip(first(split(body, "\n")))
    (occursin("(", sig) && occursin(")", sig)) || continue
    o = findfirst("(", sig).start; c = findlast(")", sig).start
    inside = sig[nextind(sig, o):prevind(sig, c)]   # prevind, NOT c-1: û/φ̂/ω are multibyte, and a
                                                    # StringIndexError aborts the sweep at the FIRST
                                                    # file while the run still looks complete
    for raw in split(inside, ",")
      p = strip(split(split(raw, "::")[1], "=")[1]); p = strip(split(p, ";")[end])
      occursin(r"^[A-Za-zα-ωΑ-Ω][A-Za-z0-9_!α-ωΑ-Ω̂]*$", p) || continue
      # A mention counts in either form: `name` alone, or `name = value` (four docstrings document a
      # keyword as "pass `scalar = true` to …", which names the argument and its effect perfectly
      # well). Requiring the bare span would push prose around to satisfy the regex.
      mentioned = occursin(Regex("`\\Q"*p*"\\E`"), body) ||
                  occursin(Regex("`\\Q"*p*"\\E\\s*="), body)
      mentioned || println(file, ": ", sig, "  UNDOCUMENTED `", p, "`")
    end
  end
end'
```

Three scans added 2026-08-17, each from a defect class a read-through found and this battery did not.
They live in `.claude/commands/check-docs/` rather than inline, because each carries a real subtlety
that a one-line grep gets wrong:

```bash
python3 .claude/commands/check-docs/abutting_spans.py    # (a) `code` next to ``math``
julia --project --startup-file=no .claude/commands/check-docs/xlink.jl   # (b) unlinked cross-module names
python3 .claude/commands/check-docs/doi_crosscheck.py    # (c) docstring DOIs vs §References
```

**(a) A code span abutting a math span.** The house rule is that a binding is ONE LaTeX span
(``\texttt{dissipation} \equiv \varepsilon``); a `` `code` `` span next to a ``` ``math`` ``` span renders
as two disjoint runs. The build cannot see it. TRIAGE: an argument name followed by the symbol it
denotes, or a formula split across the boundary, is the true hit; plain adjacency of two unrelated
things (a grid size next to a strategy name) is not.

**(b) A cross-module first mention, unlinked.** An `@ref` to another module does not resolve
unqualified, so the author downgrades the link rather than qualifying it — and a broken link never
reaches the build, it silently becomes a MISSING one. This is why the class is invisible: nothing
fails. Measured at 56 sites on first run. `APPLY=1` rewrites; the default is a dry run. Note the
scope: it flags a name whose DEFINING module differs from the docstring's, at its FIRST mention,
never linked anywhere in that docstring — not every backticked identifier, since the policy caps a
target at one link per docstring.

**(c) The DOI cross-check, format-aware.** `ARCHITECTURE.md` uses autolinks `<…>`, which cannot
contain `>`; a docstring uses `[text](…)`, which cannot contain unescaped parens. An AMS DOI contains
all three, so the same identifier is percent-encoded DIFFERENTLY on the two surfaces and the sides
must be compared DECODED. The earlier inline regex truncated at the first paren and would report
false mismatches in both directions.

```bash
# ---- SURFACE 4: the built API pages. Run AFTER `julia --project=docs docs/make.jl`. ----
# Buckets every rendered docstring by page and reports the two mechanical questions; the third
# (blurb vs contents) is a read, not a grep — do it from this script's own output.
python3 - <<'PYEOF'
import re, html, glob, os, collections
where = collections.defaultdict(list)
for page in sorted(glob.glob('docs/build/api/**/index.html', recursive=True)):
    mod = os.path.relpath(os.path.dirname(page), 'docs/build/api'); s = open(page).read()
    names = [html.unescape(m.group(1)).split('-')[0]
             for m in re.finditer(r'<summary id="([^"]+)"><a class="docstring-binding"', s)]
    for n in names: where[n].append(mod)
    print(f"{mod:28s} rendered={len(set(names))}")
dups = {n: p for n, p in where.items() if len(set(p)) > 1}             # question 1: once and only once
print("DUPLICATES:", dups if dups else "none")
print("rendered-name count:", len({n.split('.')[-1] for n in where}))
PYEOF
# question 2 — every umbrella export has a home on some api page: diff the rendered names against
julia --project -e 'using GBGIsotropicTurbulence;
  println(join(sort(String.(names(GBGIsotropicTurbulence))), "\n"))' | sort > /tmp/exports.txt
# compare /tmp/exports.txt against the rendered names above; checkdocs=:exports guards the docstring
# EXISTING, this guards it LANDING on a page. Question 3 — each api page/section blurb (the
# hand-written ## prose) still matches what its @docs block holds: read them against the output.
```

- Triage (drop false positives — universally standard math; the real Julia operators `×` / `⋅` / `≈`;
  pervasive shorthand `L²` / `N³` / `O(N²)`; `#`-comment hits; kwarg names correctly backticked; the
  `velocity`/`vorticity` inside a *storage field* or *function name* or *prose*), then fix EVERY
  genuine finding in one pass — and **fix the class, not the line** (a flagged instance is a sample
  of a sweepable class).
- Rebuild: `julia --project=docs docs/make.jl` (`checkdocs = :exports` plus the two build lints) —
  **verify by EXIT CODE, never by grepping the output** (a lint failure prints `ERROR: LoadError:`,
  which does not match a `^┌ Error` pattern; PF let three consecutive false "docs clean" reports
  stand on exactly that mismatch). Use
  `julia --project=docs docs/make.jl > /tmp/build.log 2>&1; echo $?` and require `0`. Then revert the
  transient dev entry with `git checkout -- docs/Project.toml` **alone** — never co-list
  `docs/Manifest.toml`.
- Commit + push on `main` (no `[skip ci]`; the docs site must redeploy).

## Report

Report the full matrix: which surfaces × checks were run, the findings (class and count) with fixes,
and what was verified clean — including the **family lane**'s one-home / notation audit of each
`f` / `f!` pair, the **cold-reader lane**'s pass over the exported docstrings, and **surface 4**'s
placement audit of the built API pages (nothing rendered twice, every export landed on a page, every
blurb matching its block). A flagged instance is a *sample of a class* — fix the class, not the line.
Done only when every cell is covered, every finding is closed (fixed, or dismissed with its reason),
and the build is clean — in ANY cost mode.

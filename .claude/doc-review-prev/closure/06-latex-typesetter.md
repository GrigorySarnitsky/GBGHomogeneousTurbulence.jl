# Closure audit — Hat 06: LaTeX / mathematical-typesetting reviewer

## Finding 1 — restated governing equations switch derivative notation mid-corpus

**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:231-238` now writes `\partial_t \boldsymbol{u}` and
`\partial_t \varphi` (checked via `sed -n '220,245p'`), matching `docs/src/index.md:62,69`,
`docs/ARCHITECTURE.md:242`, and `src/Generator.jl:294,380`. A corpus-wide grep for
`frac{\partial` across `src/*.jl`, `docs/src/*.md`, `docs/ARCHITECTURE.md`,
`src/phenomenology/*.jl` returns no hits — the spelled-out fraction form is gone entirely.

---

## Finding 2 — skewness constant loses its subscript inside its own defining formula

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:321` and `:902` both now read
`3C_S\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}` with
`C_S = \tfrac{4}{7}\sqrt{15/2}` — subscripted at first introduction, matching the canonical
`Observables.jl` home docstring's `3C_S`. Grep for `3C\b` (unsubscripted) in ARCHITECTURE.md
returns nothing.

---

## Finding 3 — mixed `\tfrac`/`\frac` sizes inside one display formula

**VERDICT: ABSENT**

Evidence: `src/phenomenology/StructureFunctions.jl:179` (the `Lundgren2002` formula) now reads
`-\Bigl(\tfrac{4}{5} - \tfrac{8.45}{\mathrm{Re}_\lambda^{2/3}}\Bigr)\varepsilon r` — both
fractions use `\tfrac`, no size mismatch remains.

---

## Finding 4 — differential command inconsistently braced

**VERDICT: ABSENT**

Evidence: corpus-wide grep `\\mathrm d[^{a-zA-Z]` (unbraced form) across `src/*.jl`,
`src/phenomenology/*.jl`, `docs/src/*.md`, `docs/ARCHITECTURE.md` returns zero matches. Every
remaining differential (`src/Observables.jl:275,300,315`, `src/Phenomenology.jl:213`,
`docs/src/notation.md:18,72,84`, `docs/ARCHITECTURE.md:619`, `docs/src/observables_cache.md:240`)
now uses the braced `\mathrm{d}` spelling uniformly.

---

## Finding 5 — `\kappa^4` braced in one place, unbraced everywhere else in the same file

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:13,148,149,263,328` — grep for `kappa\^4` (unbraced) and
`kappa\^{4}`/`sigma = 4` shows all five occurrences of the exponent now render as `\kappa^{4}`
(braced), including the `\sigma = 4` line at 263 that was previously the sole braced outlier.

---

## Finding 6 — Home page's scalar equation skips ϰ that every other restatement uses

**VERDICT: ABSENT**

Evidence: `docs/src/index.md:69` now reads
`\partial_t \varphi = -\nabla\cdot(\boldsymbol{u} \varphi) + \varkappa\nabla^{2}\varphi + f_\varphi`
— the scalar diffusivity is written with `\varkappa`, matching `docs/src/observables_cache.md:238`
and the glossary convention; the following prose line still defines
`\varkappa = \nu/\mathrm{Sc}` for the reader, but the raw `ν/Sc` no longer appears inside the
formula itself.

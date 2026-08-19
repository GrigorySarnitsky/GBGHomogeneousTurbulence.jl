# Closure — 06-latex-typesetter

## Finding 1 — Nested delimiters left unsized where the corpus's own convention sizes them

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:152` now reads
``f_\eta(\kappa\eta) = \exp\!\Bigl(-\beta\bigl\{\bigl[(\kappa\eta)^4 + c_\eta^4\bigr]^{1/4} - c_\eta\bigr\}\Bigr)``
— all three inner delimiter levels are now hand-sized (`\Bigl(` outer, `\bigl\{` middle, `\bigl[`
inner), where the finding quoted an unsized `\{`/`[`/`(` nest. Searched the whole corpus
(`rg --glob '!.claude/**' '\bigl\\\{|\Bigl\\\{|\bigl\[|\Bigl\['` across `src/`, `docs/src/`,
`docs/ARCHITECTURE.md`) for the same unsized-nesting class elsewhere: only this line and the
already-correct `StructureFunctions.jl:90` (`SheLeveque1994`) match, and both are properly tiered. A
follow-up grep for any remaining literal `{[…(…)…]…}` nest without a `\bigl`/`\Bigl` guard returned
no hits. No surviving instance of the class.

---

## Finding 2 — Duplicate formula disagrees on a stray space before its terminal period

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:252` now reads
`\partial_t\boldsymbol{u} = \mathbb{P} (\boldsymbol{u}\times\boldsymbol{\omega}) + \nu\nabla^{2}\boldsymbol{u} + \boldsymbol{f}.`
(confirmed byte-exact with `cat -A`, no trailing space before the closing `.`), matching
`src/Generator.jl:321`'s `... + \boldsymbol{f}.` exactly. The generated build copy
`docs/src/architecture.md:252` is identical (regenerated from the same source). The two copies of
the formula are now source-identical; the stray space is gone.

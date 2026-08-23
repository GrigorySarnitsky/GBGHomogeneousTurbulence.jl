# Closure — Hat 06: LaTeX / Mathematical-Typesetting Reviewer

## Finding 1 — bare `|\kappa|^2` breaks the house `\lvert\boldsymbol{\kappa}\rvert^2` convention
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:1445` and `:1449` (decision 38's passage, the location the finding
names) now both read `\lvert\boldsymbol{\kappa}\rvert^{2}` in full house form — no bare pipes, no
non-bold `\kappa`. `docs/src/architecture.md` lines 1440–1450 are byte-identical to
`docs/ARCHITECTURE.md` (diff empty), so the "byte-identical copy" the finding cites is fixed in both
places at once. Corpus-wide sweep `grep -rn -E '\|\\?kappa\|' src docs/src docs/ARCHITECTURE.md` and
`grep -rn 'lvert\\kappa\\rvert'` (non-bold inside the delimiters) both return empty — no bare-pipe or
non-bold-kappa regression anywhere else in the corpus.

## Finding 2 — `\mathcal F` is the corpus's only unbraced `\mathcal` argument
**VERDICT: PRESENT**

Evidence: `docs/src/notation.md:60` still reads `` ``\mathcal F``, ``\mathcal F^{-1}`` | forward /
inverse real transform `` — unbraced, unchanged from the finding. Corpus sweep
`grep -rn -E '\\mathcal [A-Za-z]' src docs/src docs/ARCHITECTURE.md` returns only this one line,
confirming it remains the sole unbraced `\mathcal` invocation against the corpus's otherwise-universal
`\mathcal{<letter>}` bracing.

## Finding 3 — von Kármán roll-off formula set at two different delimiter sizes across its two docstrings
**VERDICT: PRESENT**

Evidence: `src/phenomenology/Spectra.jl:176` (`VonKarmanLarge`) still uses
`` \Bigl(\frac{(\kappa\ell)^2}{(\kappa\ell)^2+c_L}\Bigr)^{17/6} ``; `src/phenomenology/Spectra.jl:359`
(`VonKarman1948`) still uses `` \bigl((\kappa\ell)^{2}/((\kappa\ell)^{2}+c_L)\bigr)^{17/6} `` — same
formula (variable renamed `L`→`ℓ` in the interim, defect unchanged), same enclosing parenthesis,
still `\Bigl`/`\Bigr` in one docstring and `\bigl`/`\bigr` in the other.

## Finding 4 — kerning idiom `\exp\!\bigl(…\bigr)` around a function name (advisory only, not a defect)
**VERDICT: NOT-A-DEFECT**

Evidence: matches the finding's own framing — filed as "advisory only, not filed as a defect." Current
sweep (`grep -rn 'exp\\!\\bigl'` / `exp\!\bigl` across `src/State.jl:75,78,156,159`,
`src/SimulationDomain.jl:76`, `src/Generator.jl:412`, `docs/src/notation.md:63`,
`docs/ARCHITECTURE.md:269`) confirms the `\!` kern before `\bigl(` remains applied uniformly
corpus-wide — the pattern the finding recorded as a checked non-issue still holds, no regression.

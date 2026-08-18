# Closure audit: hat 06-latex-typesetter

## Finding 1 — `C_{OC}` bare italic letter-product
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Spectra.jl:386` now reads `C_{\mathrm{OC}}` (upright label), and the
docstring prose (`C_OC` code-form) is unaffected. `grep -rn "C_{OC}"` across `src/`, `docs/src/`,
`docs/ARCHITECTURE.md` returns no hits — no bare-italic occurrence remains.

## Finding 2 — Big-O styled two ways (`\mathcal O` vs plain `O`) for the tracer predictor error term
**VERDICT: PRESENT**
Evidence: `docs/src/observables_cache.md:368` still `\mathcal O(\Delta t^{2})`; `docs/ARCHITECTURE.md:415`
still plain `O(\Delta t^2)` for the same tracer-predictor claim (also :1093, :1538 plain `O`). The two
glyphs for the identical concept still coexist across the two pages.

## Finding 3 — Word-subscript labels mix `\text{}` and `\mathrm{}`
**VERDICT: ABSENT**
Evidence: `notation.md:108` now `\varepsilon_{\mathrm{target}}` (was `\text{target}`);
`grep -rn "\\\\text{" src/ docs/src docs/ARCHITECTURE.md` returns zero hits corpus-wide — every
word-subscript label unified on `\mathrm{}`.

## Finding 4 — `2√2/3` stacked-fraction vs bare-slash inconsistency in `SimulationDomain.jl`
**VERDICT: ABSENT**
Evidence: `src/SimulationDomain.jl:125,361` (the two flagged bare-slash sites) now read
`\tfrac{2\sqrt{2}}{3}\kappa_{\mathrm{Ny}}`, matching the other four occurrences.
`grep -rn "2\\\\sqrt{2}/3"` across `src/`, `docs/src/`, `docs/ARCHITECTURE.md` returns nothing.

## Finding 5 — `\theta` reused for OU coefficient against the house `φ`-not-`θ` rule
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:383-384` (`StochasticOU` docstring) now uses `\alpha` for the transition
coefficient (`\hat f \leftarrow \alpha \hat f + …`, `\alpha = \exp(-\Delta t/T_L)`). The only
remaining `\theta` in the corpus are the two house-rule statements themselves
(`notation.md:31`, `ARCHITECTURE.md:771`: "never `\theta`") — not a reuse.

## Finding 6 — `\exp\!\big(…\big)` non-directional vs directional `\bigl/\bigr` elsewhere
**VERDICT: PARTIAL**
Evidence: all `src/*.jl` sites cited by the finding are fixed — `src/Generator.jl:405`,
`src/State.jl:75,78,149,152`, `src/SimulationDomain.jl:73` now use `\exp\!\bigl(…\bigr)`. But the
identical integrating-factor formula in the docs surfaces was left unconverted:
`docs/src/notation.md:62`, `docs/src/observables_cache.md:263`, `docs/ARCHITECTURE.md:260`
(mirrored `docs/src/architecture.md:260`) still read `\exp\!\big(…\big)`.
Surviving class: the `\big`-vs-`\bigl/\bigr` inconsistency for this exact ``\mathcal E(\boldsymbol\kappa)``
formula, on the three/four non-`src/` pages.

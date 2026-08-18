# Closure audit — hat 06-latex-typesetter

## Finding 1 — `C_{OC}` bare italic letter-product, not upright label
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Spectra.jl:384` now reads `C_{\mathrm{OC}}` in the display formula. Only
remaining bare `C_OC` tokens are the Julia field/keyword name (`C_OC = 0.67`, struct field, prose
backtick-code references), which is correct — that's the identifier, not the math subscript. `grep -rn
'C_{OC}'` across `src/`, `docs/src/`, `docs/ARCHITECTURE.md`, and `docs/build/` returns zero bare
occurrences; the rendered build's `Spectra/index.html` shows `C_{\mathrm{OC}}` in the math-container span.

## Finding 2 — Big-O styled two ways (`\mathcal O` vs plain `O`)
**VERDICT: ABSENT**
Evidence: `grep -rn '[^a-zA-Z\{]O(\Delta'` (bare italic `O`) across `docs/ARCHITECTURE.md`,
`docs/src/*.md`, `src/**/*.jl` returns nothing. All six live occurrences
(`observables_cache.md:373`, `ARCHITECTURE.md:416,1097,1542`, plus two more found) now read
`\mathcal{O}(\Delta t^{...})` — consistent glyph and consistent braced-argument TeX idiom throughout.

## Finding 3 — Word-subscripts mix `\text{}` and `\mathrm{}`
**VERDICT: ABSENT**
Evidence: `grep -rn '\\text{'` across `docs/ARCHITECTURE.md`, `docs/src/*.md`, `src/**/*.jl` returns zero
hits corpus-wide. `notation.md:108` now reads `\varepsilon_{\mathrm{target}}` (was `\text{target}`),
matching the file's own `C_{\mathrm{CFL}}` / `y_{\mathrm{s}}` convention; the `ARCHITECTURE.md`
`S_{\text{fine}}`/`S_{\text{coarse}}` and `(D,\tau,\text{rate})` instances no longer exist as `\text{}`.

## Finding 4 — `2√2/3 · κ_Ny` stacked-fraction vs bare-slash inconsistency in `SimulationDomain.jl`
**VERDICT: ABSENT**
Evidence: `src/SimulationDomain.jl` lines 47, 107, 112, 119, 125, 283, 361 all now use
`\tfrac{2\sqrt{2}}{3}` (line 283's compact enumerated-list slash form `2/3`/`1` remains, matching the
finding's own noted defensible exception). No bare `2\sqrt{2}/3` slash form remains in the file
(`grep -n '2\\sqrt{2}/3' src/SimulationDomain.jl` returns nothing outside the `\tfrac{}{}` wrapper).

## Finding 5 — `\theta` reused for OU coefficient against the house `φ`-never-`θ` rule
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:399-401` (the `StochasticOU` docstring formula) now uses `\alpha` for the
autocorrelation coefficient (`\hat f \leftarrow \alpha \hat f + ...`, `\alpha = \exp(-\Delta t/T_L)`).
`grep -rn '\\theta'` across `src/`, `docs/src/`, `docs/ARCHITECTURE.md` returns only the house-rule
statements themselves (`notation.md:31`, `ARCHITECTURE.md:774`, `architecture.md:774`) naming `\theta`
as the forbidden glyph — no live docstring uses it for a non-scalar quantity.

## Finding 6 — `\exp\!\big(...\big)` non-directional vs corpus's directional `\bigl/\bigr` elsewhere
**VERDICT: ABSENT**
Evidence: All six flagged sites (`src/Generator.jl:402`, `src/State.jl:75,78,149,152`,
`src/SimulationDomain.jl:73`) now use `\exp\!\bigl(...\bigr)`. `grep -rn '\\big(\|\\big)\|\\big\['`
across `src/**/*.jl`, `docs/src/*.md`, `docs/ARCHITECTURE.md` returns zero occurrences of the
non-directional form anywhere in the corpus — confirmed in the rendered `docs/build/api/State/`
page as well (`\bigl(-\lvert\boldsymbol{\kappa}\rvert^{2}/\kappa_p^{2}\bigr)`).

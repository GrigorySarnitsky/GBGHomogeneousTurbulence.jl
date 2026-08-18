# Closure audit — hat 06-latex-typesetter

## Finding 1 — `C_{OC}` renders as a bare italic letter-product
**VERDICT: ABSENT**
Evidence: `src/phenomenology/Spectra.jl:385` now reads `C_{\mathrm{OC}}` (checked via
`grep -n "C_{OC}\|C_{\\\\mathrm{OC}}\|C_OC"` — only the plain-code `C_OC` field/kwarg names remain,
which are code identifiers not math). Rendered build
(`docs/build/api/phenomenology/Spectra/index.html`) confirms `C_{\mathrm{OC}}` in the displayed
formula. `grep -rn "C_{OC}\b" src docs` returns nothing — no surviving bare occurrence anywhere.

## Finding 2 — Big-O styled two ways (`\mathcal O` vs plain `O`)
**VERDICT: ABSENT**
Evidence: all four cited sites now use `\mathcal{O}`: `docs/src/observables_cache.md:373`,
`docs/ARCHITECTURE.md:416,1097,1542` all read `\mathcal{O}(\Delta t^{...})`. Corpus-wide search
(`grep -rnE '\\, ?O\(|[^a-zA-Z\}]O\([Nh]'` and a plain-`O(\Delta` grep) over `src`, `docs/src`,
`docs/ARCHITECTURE.md` finds no remaining bare-italic `O(...)` asymptotic-order usage; the one hit
(`src/SimulationDomain.jl:262`) is a `#` comment ("`O(N)` vectors"), which per house rule is never
rendered/LaTeX and outside the class.

## Finding 3 — Word-subscript labels mix `\text{}` and `\mathrm{}`
**VERDICT: ABSENT**
Evidence: all three cited sites converted to `\mathrm{}`: `docs/src/notation.md:108`
(`\varepsilon_{\mathrm{target}}`), `docs/ARCHITECTURE.md:711` (`S_{\mathrm{fine}}`,
`S_{\mathrm{coarse}}`), `docs/ARCHITECTURE.md:1460` (`\mathrm{rate}`). `grep -rn "\\text{"` across
`src`, `docs/src`, `docs/ARCHITECTURE.md` returns zero hits — no `\text{}` word-subscript survives
anywhere in the corpus.

## Finding 4 — Same coefficient typeset as stacked fraction vs bare slash within one file
**VERDICT: ABSENT**
Evidence: `src/SimulationDomain.jl` lines 47,107,112,119,125,283,361 all now use
`\tfrac{2\sqrt{2}}{3}` (checked directly); line 125/361, previously bare-slash, now match the
stacked-fraction convention. Line 133 is a `#` comment (not rendered). Corpus-wide
`grep -rn "2\\sqrt{2}/3"` across `src`, `docs/src`, `docs/ARCHITECTURE.md` returns nothing — no
bare-slash survivor of this constant anywhere.

## Finding 5 — `θ` reused for OU coefficient against the house `φ`-never-`θ` rule
**VERDICT: ABSENT**
Evidence: `src/Forcing.jl:401-403` (the `StochasticOU` docstring) now uses `\alpha` for the
autocorrelation coefficient — `\hat f \leftarrow \alpha \hat f + ... \alpha = \exp(-\Delta t/T_L)` —
no `\theta` remains. Corpus-wide `grep -rn "\\theta"` over `src`, `docs/src`,
`docs/ARCHITECTURE.md` returns only the house-rule statements themselves (`notation.md:31`,
`ARCHITECTURE.md:774`, both "never `\theta`"), no live misuse.

## Finding 6 — `\exp\!\big(...\big)` non-directional vs directional `\bigl/\bigr` elsewhere
**VERDICT: ABSENT**
Evidence: every cited site now uses directional forms:
`src/Generator.jl:402`, `src/State.jl:75,78,149,152`, `src/SimulationDomain.jl:73`,
`docs/src/notation.md:62`, `docs/src/observables_cache.md:265` all read `\exp\!\bigl(...\bigr)`.
Corpus-wide `grep -rn "\\big(\|\\big)"` across `src`, `docs/src`, `docs/ARCHITECTURE.md` returns
zero hits — no bare non-directional `\big(`/`\big)` survives anywhere.

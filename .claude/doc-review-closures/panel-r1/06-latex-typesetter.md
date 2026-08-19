# Closure: 06-latex-typesetter

## Finding 1 — bold `\boldsymbol{h}` at home vs bare `h` in decision log

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:1461` now reads `\hat{\boldsymbol{u}} \leftarrow \mathcal{E}(\hat{\boldsymbol{u}} + B_i \boldsymbol{h})` — the accumulator is bold, matching its home docstring `src/Propagator.jl:222-230` which is unchanged (`\boldsymbol{h}` throughout, e.g. line 225 `\boldsymbol{h} \leftarrow A_i \boldsymbol{h} + ...`). Grepped `docs/ARCHITECTURE.md` for `B_i h` / bare-`h` variants of this update — none found; only the bold form appears.

## Finding 2 — display formulas laid out as if multi-line but no alignment environment

**VERDICT: ABSENT**

Evidence: `src/Observables.jl:78-83` (the `dissipation` docstring) now reads `\begin{aligned}\n\varepsilon &= \nu \langle...\rangle \\\\\n &= 2\nu\langle S_{ij}S_{ij}\rangle,\n\end{aligned}` — properly wrapped with `&` alignment and `\\` line breaks. `src/Observables.jl:101-107` (vorticity-identity block) likewise now wrapped in `\begin{aligned}...\end{aligned}`. Both originally-flagged sites are fixed, matching the file's own established idiom (`derivative_skewness`, `integral_scale`) cited in the finding.

Surviving-class check: swept every ` ```math ` block across `src/*.jl`, `docs/src/*.md`, `docs/ARCHITECTURE.md` for blocks with more than one non-empty content line lacking `aligned`/`gathered`/`split`. Three additional multi-line blocks found (`src/Forcing.jl:428-431`, `docs/src/observables_cache.md:237-240`, `docs/src/index.md:63-66`) but each is a *single* equation (one relation) whose source is merely line-wrapped for readability — not a case of two stacked relations faking visual alignment via manual indentation, the specific anti-pattern this finding described. A second, stricter scan for blocks containing more than one line beginning with a bare `=`/`&=` relation (the actual "meant-to-be-aligned-but-isn't" shape) returned nothing beyond the two now-fixed sites. No surviving instances of the class found.

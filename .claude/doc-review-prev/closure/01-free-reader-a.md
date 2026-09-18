# Closure — 01-free-reader-a

## Finding 1 — scalar called θ on Architecture page
**Verdict:** ABSENT
**Evidence:** `docs/ARCHITECTURE.md:489` and `:948` both now read `\langle\varphi^2\rangle` ("must settle too" / "must flatten too"). Corpus-wide grep `rg '\\theta|θ' src/*.jl docs/` (excluding `.claude/`) returns zero hits — no stray θ anywhere, only the two "never θ" rule statements (ARCHITECTURE.md:838, notation.md:32).

## Finding 2 — Rogallo dated 1984 in one docstring
**Verdict:** ABSENT
**Evidence:** `src/SimulationDomain.jl:114` docstring now reads "Rogallo (1981)". Grep for `1984` across `src/*.jl docs/` finds only unrelated Nosé/Berendsen thermostat citations (Forcing.jl:567,569; decisions.md:1245,1257). No Rogallo 1984 anywhere.

## Finding 3 — skewness "≈ −0.05" instead of "≈ −0.5" in decision-log parenthetical
**Verdict:** ABSENT
**Evidence:** `docs/src/decisions.md:49` and `docs/ARCHITECTURE.md:947` (identical text, mirrored) now both read "(``S`` runs from ``0`` toward ``\approx -0.5``)" — matching the value given elsewhere (SimulationRun.jl:822, Observables.jl). Grep `rg '\-0\.05' docs/ src/*.jl` returns nothing.

## Finding 4 — `add_forcing_source!` still charges VarianceController three readbacks per stage
**Verdict:** ABSENT
**Evidence:** `src/Forcing.jl:261-264` docstring now reads "Measuring the state costs one blocking device-to-host transfer **at every stage** — a single fused multi-weight reduction answers `VarianceController`'s three weighted sums together, `ConstantPower` reads its band ... the same fused way, and `Linear` pays none." This matches the decision-log fusion (decisions.md ~1168, "one traversal and one readback"). The "three blocking readbacks" text remaining at decisions.md:507/ARCHITECTURE.md:1405 is unrelated — it describes the historical *default-configuration step total* (pre-decision-58), not VarianceController's per-stage cost, and is explicitly framed as superseded in the surrounding text.

## Finding 5 — Home page "build order" list puts Phenomenology last; API overview / Architecture say it leads
**Verdict:** ABSENT
**Evidence:** `docs/src/index.md` Components list still shows Phenomenology last (unchanged order), but the entry now explicitly states: "In the actual include order this dependency-light leaf comes *first*; it is listed last here because a reader meets it last." (index.md ~123-125). This matches `src/GBGIsotropicTurbulence.jl` include order (`Phenomenology.jl` included first, line 60) and matches api.md:6 ("leads the include order") and ARCHITECTURE.md:584 ("`Phenomenology` (§4.8) leads this order"). The apparent cross-page contradiction is resolved by the added clarifying sentence — no page states the opposite fact anymore.

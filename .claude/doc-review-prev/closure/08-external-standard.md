# Closure — Hat 08: Senior DNS Referee (external required-content standard)

## Finding 1 — The default viscosity-setting law is calibrated at one Re_λ, with no stated validity range
**Verdict:** REGRESSED
**Evidence:** `src/phenomenology/Scalings.jl:121` now sets `const _LI2008 = Reference(...; valid_Reλ = (100.0, Inf))` — a floor was added, unlike `Sreenivasan1998`/`Sreenivasan1995` which also now carry `valid_Reλ = (50.0, Inf)` (lines 50, 88). But `Li2008`'s own docstring (lines ~136-139) still asserts "its `Reference` records no validity floor because none has been measured" — directly contradicting the const two lines above it. Confirmed rendered as-is in `docs/build/api/phenomenology/Scalings/index.html`. The new defect is the self-contradiction, not the original absence.

## Finding 2 — No stability bound is stated for source-routed (explicit-stage) forcing terms
**Verdict:** PRESENT
**Evidence:** Searched `src/Forcing.jl` (`VarianceController` docstring, `gain`, `turnover_time` sections, lines 540-595) and `src/SimulationRun.jl` (`cfl_timestep`, `advance!`, `ARCHITECTURE.md` §"temporal-accuracy step control" at line ~702) — no mention anywhere of a forcing-magnitude/gain timestep restriction independent of the advective CFL. `recommended_cfl` and `cfl_timestep` remain purely advective+diffusive-decay+`max_dt`.

## Finding 3 — No averaging-window or ensemble-size statement for any quoted diagnostic
**Verdict:** PRESENT
**Evidence:** Searched `energy_spectrum`, `derivative_skewness`, `dissipation` docstrings in `src/Observables.jl` and `test/validation.jl`'s `compare_to_model` (moved out of `src/` per decision 49, still purely instantaneous, no averaging discussion). Grepped "turnovers|time-averaged|statistically meaningful|ensemble" across `src/`, `docs/src/` — the only turnovers hits are `StationarityCriterion`'s warm-up gate, a different concept (transient detection, not post-warm-up averaging window for a law comparison).

## Finding 4 — Scope of the scalar-resolution warning across grid/explicit viscosity modes is unstated
**Verdict:** ABSENT
**Evidence:** `src/SimulationRun.jl:168-171` docstring now states explicitly: "The constructor **warns** when the run's κ_max η_B falls below the 1.5 well-resolved floor — in **either** viscosity mode, since the check reads the resolved ν however it was obtained." Code at lines 367-379 confirms: the `if scalar ... κ_max_η_B < 1.5` check sits after the shared `ν` resolution (both grid and explicit branches), unconditional on mode.

## Finding 5 — No user-facing recipe to check a run's own numerical conservation
**Verdict:** PRESENT
**Evidence:** `docs/ARCHITECTURE.md:717-730`, the ν=0 truncated-Euler experiment, still reads "It is not a turbulence run" and is framed entirely as a scheme/dealiasing oracle for the internal test suite; no minimal user-runnable check (a short unforced/very-low-ν segment with energy logged) is documented anywhere in `docs/src/` or `src/`.

## Finding 6 — Rogallo citation year contradicts itself (1984 vs 1981) for the identical report
**Verdict:** ABSENT
**Evidence:** Grepped "Rogallo" across `src/`, `docs/src/`, `docs/ARCHITECTURE.md`: every citation now reads 1981 — `src/SimulationDomain.jl:114` ("Rogallo (1981)"), `docs/ARCHITECTURE.md:2110`/`docs/src/decisions.md:1212` (References list), `docs/ARCHITECTURE.md:1144`/`docs/src/decisions.md:246` (decision 27). No remaining 1984 instance found anywhere in the corpus.

## Finding 7 — No initialization-transient marker for a decaying (unforced) run
**Verdict:** PRESENT
**Evidence:** `src/SimulationRun.jl:800-805`, `StationarityCriterion` docstring, still only says "A freely decaying run (`NoForcing()`) has no stationary state to detect ... give a decaying run a fixed-length loop instead, which is a three-line callback (see `run!`)" — no mention of reusing the skewness-plateau gate by hand as a transient-end marker, in this docstring, `run!`'s docstring/examples, or `docs/src/decisions.md`/`ARCHITECTURE.md`.

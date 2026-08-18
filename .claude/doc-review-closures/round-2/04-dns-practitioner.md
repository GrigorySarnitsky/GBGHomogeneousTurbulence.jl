# Closure audit — 04-dns-practitioner (DNS practitioner / GPU performance hat)

## Finding 1 — "Float64 is the production precision" framing tension

**VERDICT: ABSENT**

**Evidence:** `docs/ARCHITECTURE.md` §6 (lines 586–599) no longer contains the phrase "production
precision" or "development and desktop precision." The text now reads symmetrically: "`Float32`
buys twice the grid per byte and roughly twice the throughput on a consumer GPU; `Float64` buys
the accuracy margin a long integration or a sensitive diagnostic may need. Which one a run wants
is a fitness question, settled by test rather than by a house default." `grep -rn "production
precision" docs/ src/` returns nothing; confirmed absent in the rendered build
(`docs/build/architecture/index.html` — 0 occurrences). `Simulation`'s `element_type = Float64`
front-door default (`src/SimulationRun.jl:140`) is stated plainly with no normative label
attached, so the specific contradiction the finding quoted no longer exists.

---

## Finding 2 — §2.3 transform-count table's scheme scope stated only once, before the table

**VERDICT: ABSENT**

**Evidence:** `docs/src/observables_cache.md:293–294`, immediately above the table (line 298),
now reads: "Counts are per step of a three-stage scheme (`IFLowStorageRK3`); a scheme with a
different stage count scales them by its own." This is exactly the resolution hint the finding
suggested (repeat the scheme-scope qualifier at the table). Confirmed present in the rendered
build (`docs/build/observables_cache/index.html` contains both "Counts are per step" and
"three-stage scheme").

---

## Finding 3 — `IFLowStorageRK3`'s "two field registers" headline vs three-array `IntegratorBuffers`

**VERDICT: REGRESSED**

**Evidence:** The disclaiming parenthetical was rewritten (`src/Propagator.jl:240–245`) to read:
"The `IntegratorBuffers` a run allocates holds more than that count — `nonlinear` is the
dealiasing seam's assembly register and `velocity_star_spectral` the projection's — because the
count measures the scheme, not the solver it is embedded in." This now correctly disclaims the
count (addressing the original nit), but mislabels `velocity_star_spectral`: every other mention
of this register in the same file calls it the **predictor**, never "the projection's" —
`IntegratorBuffers` Fields (`Propagator.jl:93`): "the substage velocity predictor `û*`";
`Propagator.jl:98`: "predictor state `φ̂*`"; `Propagator.jl:345,384,386,399`: "the predictor."
`velocity_star_spectral` is the exponential-integrating-factor-updated substage state used as
*input* to `velocity_rhs!`; the Leray projection `ℙ` is applied *inside* `velocity_rhs!`, writing
into `nonlinear`/`stage2`, not into `velocity_star_spectral`. `grep -n "projection"
src/Propagator.jl` shows the term "the projection's" used nowhere else for this register (the
other two hits are the unrelated "post-step forcing projections," e.g. `BandRescaling`).

**Surviving class:** the mislabeling is confined to this one sentence (`Propagator.jl:244`); no
other file repeats "the projection's" for `velocity_star_spectral`. The class at risk — a
register's established name drifting inside a single explanatory aside — is not observed
elsewhere in this docstring or `IntegratorBuffers`'s own Fields section, which stays consistent
with "predictor."

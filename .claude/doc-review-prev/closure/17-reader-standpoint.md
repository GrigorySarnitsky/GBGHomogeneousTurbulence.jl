# Closure — hat 17: reader-standpoint (silent wrong-number hazards)

9 findings adjudicated against the current corpus (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`,
`docs/build/`), blind to any prior closure round.

---

## Finding 1 — `Li2008` validity range

**VERDICT: REGRESSED**

`src/phenomenology/Scalings.jl:120-121` now sets `const _LI2008 = Reference(...; valid_Reλ =
(100.0, Inf))` — a validity floor of 100 IS recorded. But the docstring immediately below
(lines 121-123) still reads: "its `Reference` records no validity floor because none has been
measured; the grid-mode ``\nu`` solve that consumes the law inherits the same standing." This is
now a direct false statement contradicted by the code two lines above it, and it renders verbatim
in the built docs (`docs/build/api/phenomenology/Scalings/index.html`: "records no validity floor
because none has been measured"). The underlying gap (no floor) was closed in code; the prose
was not updated to match, producing a new falsehood at the same site.

---

## Finding 2 — Grid-mode viscosity calibration invalidated by a mismatched forcing target/band

**VERDICT: PRESENT**

`src/SimulationRun.jl`'s `Simulation` docstring ("Setting the Reynolds number") still only states
the precondition in prose ("the choice is self-consistent only if the run holds `k` near
`kinetic_energy`"; "a forcing moved higher invalidates it"). Read through the full constructor body
(`src/SimulationRun.jl` ~275-400): no comparison of `velocity_forcing`'s `target`/`lowest_shell`/
`highest_shell` against `kinetic_energy` or the assumed 1-2 band exists anywhere in
`Simulation(domain::FixedDomain; ...)`. A `VarianceController(d; target = 0.5)` or a forcing with a
moved band still builds silently.

---

## Finding 3 — `initial_spectrum` uses a stationary-forced ε estimate even in decaying mode

**VERDICT: ABSENT**

`src/SimulationRun.jl`, the `initial_spectrum` argument bullet, now carries the exact caveat this
finding asked for: "Note the ε half: it is the *stationary forced* estimate, so on a decaying run —
where the explicit-``\nu`` advice above exists precisely because that balance does not hold — the
model's dissipation-range placement inherits the same mismatch." This is an explicit at-site caveat
naming the precise combination (decaying run + `initial_spectrum`) the finding flagged, so the
"nothing... flags this" claim no longer holds. Searched: `rg "initial_spectrum" src/SimulationRun.jl`
and read the full bullet.

---

## Finding 4 — `envelope_wavenumber` vs the dealias cutoff, unlike a forcing band

**VERDICT: PARTIAL**

`src/SimulationRun.jl`'s `Simulation` docstring, `envelope_wavenumber` bullet, now carries an
explicit at-site caveat: "Keep ``\kappa_p`` well below the dealias cutoff: a value near or above it
concentrates the pre-rescale seed in shells the mask holds empty, and no guard checks this — unlike
a forcing band, which warns." (`src/State.jl` also gained a *different*, narrower guard: a thrown
`ArgumentError` when the seed is annihilated *entirely*, `current_energy > 0 || throw(...)` at
`src/State.jl` ~152 — but that only catches total annihilation, not the concentration case the
caveat itself admits is unguarded.) The finding's third named location,
`random_solenoidal_velocity_spectral!`'s own docstring in `src/State.jl` (lines ~68-105), still has
no mention of the dealias-cutoff relationship at all — same silence as before. Surviving class:
`src/State.jl`'s `random_solenoidal_velocity_spectral!` docstring (and its scalar twin
`random_scalar_spectral!`, same file, same pattern) carry no caveat, only the front door
(`Simulation`) does.

surviving_class: `src/State.jl` `random_solenoidal_velocity_spectral!` and `random_scalar_spectral!` docstrings — no caveat or guard against `envelope_wavenumber` near/above the dealias cutoff (only total-annihilation is caught, by a thrown error unrelated to the concentration hazard).

---

## Finding 5 — Near-empty-band forcing floor: no threshold, no runtime signal

**VERDICT: PRESENT**

`src/Forcing.jl` now documents the floor's *character* qualitatively — `ConstantPower`'s note
(~line 509-516): "Below a machine-roundoff floor on the band's observable — measured relative to
the whole field's... the amplitude is set to zero" — but not the actual numeric threshold
(`_band_is_empty`, line 95-96: `10 * eps(one(band_value)) * whole_value`, never quoted in either
docstring). More importantly, the finding's second and sharper claim survives fully: nothing emits a
warning, log message, or observable flag when the clamp fires mid-run. `project_forcing!` for
`VarianceRescaling` (line 418: `_band_is_empty(...) && return field`) and the `VarianceController`
rate solve (line 668-669: `_band_is_empty(band, whole) ? 0.0 : ...`) both silently no-op with no
signal.

---

## Finding 6 — Overriding `Pope2000`'s `c_L`/`c_η` silently breaks the normalization

**VERDICT: ABSENT**

`src/phenomenology/Spectra.jl`, the `Pope2000` docstring, now states exactly this: "Override any
coefficient to re-fit — but the two kinds of coefficient differ: the shape exponents `p₀` and `β`
are free axes, while `c_L` and `c_η` are the values *derived from* the energy and dissipation
normalizations, so hand-setting either breaks the stated ``\int E = k`` / dissipation identities
silently." This is the explicit at-site caveat, naming the exact distinction (shape exponents vs.
normalization constants) the finding said was missing. Read the full `Pope2000` docstring
(lines 350-364).

---

## Finding 7 — `AdamsBashforth(order = N)` for `N > 8`: enforcement unspecified

**VERDICT: ABSENT**

`src/Particles.jl`: the constructor now throws — `order <= 8 || throw(ArgumentError(...))`
(lines ~348-354) — and the docstring's `# Arguments` section states it: "Orders above `8` are
refused with an `ArgumentError`: past it the four-point Gauss–Legendre rule that integrates the
interpolation weights stops being exact, and the refusal is loud because the alternative is
silently wrong weights." Both the code and the docstring now resolve the finding's three-way
ambiguity (error vs. clamp vs. silent) in favor of a thrown error.

---

## Finding 8 — Hand-built `ObservablesCache` with insufficient `history_depth` for `AdamsBashforth`

**VERDICT: ABSENT**

`src/Particles.jl`, `allocate_buffers(::AdamsBashforth{K}, tracers, cache)` (lines ~389-396): `length
(cache.particle_velocity_history) >= K - 1 || throw(ArgumentError("this cache carries $(...) past
sample(s), but AdamsBashforth(order = $K) integrates over $(K - 1); build the cache with
history_depth = $K"))`. A mismatched hand-assembled cache now throws with the exact remedy at
construction of the particle buffers, rather than silently under-reading history or reading
uninitialized slots.

---

## Finding 9 — `VarianceController`'s default `turnover_time` tied to the grid-mode ε estimate

**VERDICT: ABSENT**

`src/Forcing.jl`, `VarianceController`'s `turnover_time` argument bullet, now reads: "Left at
`nothing` it is computed for you from that formula, with ``\varepsilon_\infty`` the stationary
estimate for this box — the same estimate the grid-mode viscosity solve uses, so a run that sets
``\nu`` explicitly against a very different regime should pass its own value." This is the explicit
at-site caveat the finding asked for — it names the exact failure mode (explicit-``\nu`` mode,
mismatched regime) and the remedy (pass `turnover_time` yourself).

---

## Summary

| # | Verdict |
|---|---------|
| 1 | REGRESSED |
| 2 | PRESENT |
| 3 | ABSENT |
| 4 | PARTIAL |
| 5 | PRESENT |
| 6 | ABSENT |
| 7 | ABSENT |
| 8 | ABSENT |
| 9 | ABSENT |

# Closure audit — hat 11: conjunction-coverage

## Finding 1 — `add_forcing_source!`'s per-stage readback count stale for `VarianceController`

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:261-264` now reads "Measuring the state costs one blocking device-to-host
transfer at every stage — a single fused multi-weight reduction answers `VarianceController`'s three
weighted sums together, `ConstantPower` reads its band … the same fused way, and `Linear` pays
none." The flagged "three per stage for `VarianceController`" text is gone; the docstring now
matches the one-fused-reduction-per-stage implementation the decision log describes. Grep for
"three per stage" / "blocking device-to-host" in `src/Forcing.jl` confirms no stale count remains.

---

## Finding 2 — ν = 0 truncated-Euler oracle silently incompatible with `IFRK2`

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:721-723` now reads "a conservation and order-of-accuracy test on
`IFLowStorageRK3` (the drift must scale with the scheme's order; at ν = 0 `IFRK2` is excluded — its
stability rests entirely on viscous damping, which the oracle removes, so it would measure an
instability, not an order)". The oracle is now explicitly scoped to `IFLowStorageRK3` and `IFRK2`'s
exclusion is stated with the same reasoning as its own docstring's stability caveat — no silent gap.

---

## Finding 3 — Cubic-invariant aliasing residual priced for one dealiasing strategy only

**VERDICT: PRESENT**

Evidence: `src/Observables.jl:43` (module docstring, unchanged) still states "the cubic skewness
carries the slight residual its own docstring prices." But `src/Observables.jl:314-319`
(`derivative_skewness`) now explicitly says, for `HouLi`: "leaves a residual of its own shape that
**no bound here prices**" — a direct, currently-quoted self-contradiction of the module docstring's
promise. `PhaseShift` now gets a qualitative treatment ("the same kind of residual over its larger
retained band") but no quantified bound either. A user on `HouLi` still has no stated residual bound,
exactly the harm the finding described — now made explicit rather than silent, but not resolved.

---

## Finding 4 — `max_dt`'s diffusive-decay-time bound doesn't name which diffusivity it uses

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:205-208` now reads "the longest mode's diffusive-decay time
`1/(Dκ_min²)` — with `D` the **larger** of the run's diffusivities (`ν`, and `ϰ = ν/Sc` when a
scalar rides), since the faster-diffusing field decays first". Matches the code at
`src/SimulationRun.jl:525-526` (`diffusivity = max(viscosity, viscosity/schmidt)` when scalar
present). The ambiguity is resolved and the choice is justified.

---

## Finding 5 — `EndpointHeun`'s interpolation/time-error crossover not given for `AdamsBashforth`

**VERDICT: PRESENT**

Evidence: `src/Particles.jl:196-208` (`EndpointHeun`) still carries the concrete crossover numbers
("interpolation dominates at N = 16-32 and the time error dominates from N ≈ 64 on … at N = 128,
floor 1e-5 against time error 6e-5"). `src/Particles.jl:291-341` (`AdamsBashforth`) gives only the
generic Grönwall-floor argument and its own measured time order ("about third order … fifty times
smaller"), with no analogous crossover-N estimate. Grep for "N ≈ 64", "N = 128", "crossover" outside
`EndpointHeun`'s docstring returns nothing.

---

## Finding 6 — `AdamsBashforth`'s measured practical order reported for `order = 4` only

**VERDICT: PRESENT**

Evidence: `src/Particles.jl:310-323` gives the qualitative bootstrap-degradation mechanism generically
but the only quantified figures ("about third order rather than fourth", "fifty times smaller") are
for the default `order = 4`; the `order` keyword entry (`src/Particles.jl:318-323`) states the `1`-`8`
range and the refusal above `8` but no order-specific practical-order numbers. Grep for "order = 6",
"order = 8", "sixth order", "eighth order" in `src/Particles.jl` and `docs/ARCHITECTURE.md` returns
nothing.

---

## Finding 7 — "Read-only" caching caveat inconsistently placed across the four cache accessors

**VERDICT: ABSENT**

Evidence: `src/Cache.jl:258` (`particle_velocities`) now carries its own local caveat: "Treat the
returned array as read-only — it is the tracer set's own storage, and the tracer advance writes into
it mid-iteration." `velocity_physical` (line 204), `vorticity_physical` (line 218, by reference to
`velocity_physical`'s contract), and `scalar_physical` (line 234, likewise) all state or reference the
same caveat. All four accessors now carry it, either locally or by explicit cross-reference.

---

## Finding 8 — `VarianceController`'s `gain = 0` drift measurement not qualified by element type

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:556-558` now reads "discrete integration bias accumulates uncorrected (about
1% of k per 1000 steps, measured at 24³ in `Float64`; a `Float32` run's roundoff bias is larger and
unmeasured)". The element type of the measured figure is now stated, and the `Float32` case is
explicitly flagged as larger-but-unmeasured rather than left unaddressed.

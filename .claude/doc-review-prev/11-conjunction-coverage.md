# Configuration-coverage audit — caveat × option-space pairs

Hat: **conjunction-coverage**. Method: enumerated every caveat/admonition/stated guarantee on the
API + design-doc pages, then checked it against the option axes it is reachable under (dealiasing
strategy, scheme, forcing, scalar on/off, element type, particle scheme, interpolation scheme,
adaptive/fixed timestep), naming the covered set and the reachable-but-silent set.

---

## Finding 1 — `add_forcing_source!`'s per-stage readback count is stale for `VarianceController`

**Type:** contradiction · **Severity:** blocker · **Confidence:** high

**Locations:**
- PAGE: api / Forcing, `add_forcing_source!` docstring: *"Each reduction costs one blocking
  device-to-host transfer, at every stage — three per stage for `VarianceController`, one for
  `ConstantPower`, where `Linear` pays none."*
- PAGE: architecture, decision log, the 2026-08-23 PF-request entry: *"The multi-weight fused
  reduction … `weighted_inner(f, (w_1, …, w_n))` answers `n` weighted sums from one traversal and
  one readback … Wired at every same-field multi-reduction site: `VarianceController` (three
  weights per stage — the unit, the band, `|κ|²`) … The synchronization ledger re-froze: the
  default row fell 10 → 4 crossings (**one fused reduction per stage** plus the Δt choice)."*

**Contradicts:** the `add_forcing_source!` caveat's own quantified claim ("three per stage") against
the decision log's stated current implementation (one fused reduction, one readback, per stage),
axis: number of host-device synchronizations `VarianceController` costs per Runge–Kutta stage.

**Description:** The docstring's cost table is exactly the kind of quantified, per-forcing
guarantee this hat is built to check — and for `VarianceController` (the *default* velocity
forcing every `Simulation()` call reaches) it is now wrong. The three separate weighted reductions
(unit, band, `|κ|²`) it once cost were fused into one `weighted_inner` call with one host readback,
per the compute/synchronization ledger's own re-freeze. The docstring was never updated to match,
so a reader sizing a GPU run's synchronization budget from this docstring overcounts the default
forcing's cost by 3×. `ConstantPower`'s "one" and `Linear`'s "none" remain correct (neither needed
multi-weight fusion), so only the `VarianceController` entry drifted.

---

## Finding 2 — The ν = 0 truncated-Euler conservation oracle is silently incompatible with `IFRK2`

**Type:** contradiction · **Severity:** major · **Confidence:** medium-high

**Locations:**
- PAGE: architecture §7: *"a per-scheme conservation and order-of-accuracy test (the drift must
  scale with the scheme's order) … measured energy drift isolates the time scheme alone"* — stated
  with no scheme restriction, over "each scheme" generically.
- PAGE: api / Propagator, `IFRK2`: *"Unstable on the imaginary axis without viscous damping … it is
  stable only where the viscous damping of the integrating factor dominates."*

**Contradicts:** §7's implicit claim that the ν = 0 oracle is a *per-scheme* test (reachable under
either scheme choice) against `IFRK2`'s own docstring, which states its stability region is empty
whenever the diffusive term (which the oracle sets to exactly zero) is absent.

**Description:** At ν = 0 the integrating factor degenerates to the identity (stated explicitly in
§7), so `IFRK2` has literally no viscous damping to lean on — its own docstring's stability
condition ("stable only where the viscous damping … dominates") is then never satisfied for any
excited mode. Under `IFRK2` the oracle's diagnostic (measured energy drift scaling with the
scheme's order) would instead show the scheme's unconditional imaginary-axis instability, not a
clean order-of-accuracy signal. Neither the §7 description of the oracle nor `IFRK2`'s own caveat
says the oracle needs `IFLowStorageRK3`; a reader who reaches for the deferred ν = 0 experiment
under the (also reachable, and cheaper) `IFRK2` gets a silently invalid result.

---

## Finding 3 — The cubic-invariant aliasing residual is priced for one dealiasing strategy only

**Type:** api-gap · **Severity:** major · **Confidence:** high

**Locations:**
- PAGE: api / Observables, module docstring: *"the cubic skewness carries the slight residual its
  own docstring prices"* — a forward pointer implying full pricing lives in the function's own doc.
- PAGE: api / Observables, `derivative_skewness`: *"its grid mean carries a small residual aliasing
  on a `2/3`-truncated field — negligible for a well-resolved run, but … not exactly alias-free."*

**Contradicts:** the module docstring's promise ("its own docstring prices [the residual]") against
what the function docstring actually prices — only the `TwoThirds` case — leaving `HouLi` and
`PhaseShift` unpriced despite `derivative_skewness(û, domain)` being callable under all three.

**Description:** For the *quadratic* reductions (`kinetic_energy` et al.) the module and function
docstrings give an explicit three-way breakdown across `TwoThirds`, `PhaseShift`, and `HouLi`
("alias-free in practice, not exactly" for `HouLi`). For the cubic `derivative_skewness`, only the
`TwoThirds` case is quantified. `PhaseShift` is also a hard truncation (wider band), so the same
kind of residual plausibly extends — but `HouLi` tapers rather than truncates, and whether a smooth
taper leaves a comparable, larger, or qualitatively different cubic-invariant residual is not
stated and is not an obvious extension of the 2/3-rule argument. A user running the (fully
supported) `HouLi` strategy and gating `warmup!` on the skewness plateau has no stated bound on
this residual for their configuration.

---

## Finding 4 — `max_dt`'s diffusive-decay-time bound does not name which diffusivity it uses

**Type:** api-gap · **Severity:** major · **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `Simulation`, the `max_dt` keyword: *"the longest mode's diffusive-decay
  time `1/(Dκ_min²)`, built from the run's own diffusivity and box."*
- Same page, `schmidt` keyword: *"the scalar diffusivity `ϰ = ν/Sc`"* — a run with `scalar = true`
  and `schmidt ≠ 1` carries **two** diffusivities, not one.

**Description:** The adaptive-step ceiling's third bound is stated with a single symbol `D` and
"the run's own diffusivity" (singular). For a scalar-free run this is unambiguous (`D = ν`), but a
scalar-carrying run with `schmidt ≠ 1` has two candidate diffusivities, and the smaller one (`ϰ`
when `Sc > 1`) is the one whose decay time is longer and therefore binding for "avoiding a step that
makes the clock advance by a number that means nothing." The docstring never says whether the bound
takes the min over both fields' diffusivities or only ν, so a user with a high-Schmidt-adjacent
scalar (reachable and explicitly discussed two paragraphs earlier in the same docstring) cannot
tell from this caveat alone whether the ceiling protects the scalar's decay too.

---

## Finding 5 — `EndpointHeun`'s interpolation/time-error crossover is not given for `AdamsBashforth`

**Type:** api-gap · **Severity:** minor-major · **Confidence:** medium

**Locations:**
- PAGE: api / Particles, `EndpointHeun`: *"this scheme's error falls as `Δx²` while a degree-`d`
  interpolant's trajectory floor falls as `Δx^{d+1}` … the two cross over … at `N ≈ 64` on"* (concrete
  numbers given).
- PAGE: api / Particles, `AdamsBashforth`: gives the Grönwall floor argument generically (*"The
  interpolant sets a floor no timestep can cross"*) but no analogous crossover-resolution estimate,
  despite reporting its own measured order (*"about third order"*) two paragraphs earlier.

**Description:** `EndpointHeun`'s crossover analysis is scheme-specific: it is derived from that
scheme's second-order time convergence against the interpolant's `Δx^{d+1}` floor. `AdamsBashforth`
converges faster in time (measured ≈3rd order against `EndpointHeun`'s 2nd), which — by the same
argument the `EndpointHeun` docstring makes — should push the interpolation-dominates crossover to
*coarser* resolution than `N ≈ 64`, i.e. `CatmullRom` would limit `AdamsBashforth` trajectories over
a wider practical range than it limits `EndpointHeun` ones. `interpolation_scheme` is one option axis
reachable under either `trajectory_scheme`; the numeric guidance for choosing it is given for only
one of the two.

---

## Finding 6 — `AdamsBashforth`'s measured practical order is reported for `order = 4` only

**Type:** api-gap · **Severity:** minor · **Confidence:** medium

**Locations:**
- PAGE: api / Particles, `AdamsBashforth`: *"over a fixed window `order = 4` converges at about
  third order rather than fourth … an error some fifty times smaller at equal step count"* — measured
  only at the default.
- Same docstring, `order` keyword: *"Capped at `8` … the cap is far above any useful order"* — `order`
  is user-settable across `1`–`8`.

**Description:** The bootstrap-degrades-the-achieved-order mechanism is explained qualitatively for
any `order` (fixed-order `EndpointHeun` startup costs a fixed error budget, more costly relative to a
shorter multistep window), but the only quantified number ("about third order", "fifty times
smaller") is for the shipped default. A user choosing `order = 6` or `order = 8` — both reachable,
neither refused — has no stated expectation for what practical order or error reduction that buys,
only the generic mechanism.

---

## Finding 7 — The "read-only" caching caveat is inconsistently placed across the four cache accessors

**Type:** format · **Severity:** nit · **Confidence:** medium

**Locations:**
- PAGE: api / Cache, `velocity_physical`: *"Treat the returned field as read-only …"*
- PAGE: api / Cache, `vorticity_physical`: *"… read-only …"*
- PAGE: api / Cache, `particle_velocities`: no read-only statement in this docstring; the same
  caveat instead appears only on PAGE: api / Particles, `Tracers`, field `particle_velocities`
  (*"treat it as read-only, since the tracer advance writes here mid-iteration"*).

**Description:** Three of the four field-slot accessors restate the read-only caveat locally;
`particle_velocities` (`Cache` module) is missing it, and a reader who reaches `Cache.particle_velocities`
directly (rather than via `Tracers`) sees no local warning that the returned array is mid-iteration
scratch between deposits. Minor because the fact is documented somewhere, but the per-accessor
coverage is not uniform across an otherwise parallel set of four.

---

## Finding 8 — `VarianceController`'s `gain = 0` drift measurement is not qualified by element type

**Type:** api-gap · **Severity:** minor · **Confidence:** low-medium

**Locations:**
- PAGE: api / Forcing, `VarianceController`: *"discrete integration bias accumulates uncorrected
  (about 1% of `k` per 1000 steps, measured at `24³`)"* — no element type stated.
- PAGE: architecture §6: *"Precision and the memory-footprint/accuracy trade-off are objects of
  study … `Float32` buys twice the grid per byte and roughly twice the throughput"* — precision is
  explicitly a first-class, studied axis elsewhere.

**Description:** The `gain = 0` neutral-equilibrium drift is a round-off/discretization-bias effect,
which is exactly the kind of number that should differ materially between `Float32` and `Float64`
(the package's own two supported, equally-first-class element types). The one measured figure
carries no element-type label, so a `Float32` run — the GPU-primary target this package optimizes
for — has no stated expectation for how much faster (or slower) this drift accumulates than the
figure quoted.

---

## Notes on candidates considered but not reported

- The Simulation docstring's grid-mode ν-calibration caveat ("a forcing moved higher invalidates
  it") already covers the reachable case of moving a forcing's shells — re-checked directly against
  the rendered text and found present, not a gap.
- `HouLi`'s and `PhaseShift`'s Nyquist-attenuation caveats are each self-contained and explicitly
  reasoned to not apply to the shipped configuration — not gaps.
- Whether `Linear` forcing (fixed-rate, user-tuned) is silently excluded from `StationarityCriterion`'s
  "no stationary state to detect" warning was considered; `Linear` is a legitimate stationary-turbulence
  generator in the cited literature (Lundgren 2003), so its absence from that warning is correct, not
  a gap.
- The `FlowConditions` "one instance per forced field" constraint was checked against all five shipped
  forcings; none of them is actually stateful, so the constraint is currently vacuous but not wrong —
  not reported as a gap.

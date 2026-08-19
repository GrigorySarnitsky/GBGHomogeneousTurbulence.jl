# Closure — Hat 08 (Dimensional analysis & normalization)

## Finding 1 — Seeded model spectrum's large scale: `Simulation` promises `1/envelope_wavenumber`, `large_scale_length` overrides it

**VERDICT: PRESENT**

Evidence: `src/SimulationRun.jl` line 158–160 (the `envelope_wavenumber` bullet), rendered
identically in `docs/build/api/SimulationRun/index.html`: "it also sets the integral scale
`initial_spectrum` is evaluated at" — an unconditional claim. `src/phenomenology/Spectra.jl`
lines 99–106 (`large_scale_length`) still documents that `PopeLargeScale` (used by the flagship
`Pope2000` preset) overrides with ``L_0 = k^{3/2}/\varepsilon``, "3.7 times smaller" at
``C_\varepsilon = 0.5``. `SimulationRun.jl` contains no mention of "Pope" or "override" anywhere
(`grep -n "Pope\|override" src/SimulationRun.jl` returns nothing), so the front-door promise is
still unqualified against the one preset that breaks it.

---

## Finding 2 — `ε_target` bound to "energy-injection rate" but also carries a scalar-variance rate

**VERDICT: PARTIAL**

Evidence: `docs/src/notation.md` line 109 now reads "the injection rate a `ConstantPower` holds:
energy for the velocity, scalar variance for the scalar" — the glossary's dimensional binding is
fixed. `src/Forcing.jl` `ConstantPower` docstring (lines 381–386) likewise now distinguishes
``\varepsilon`` (velocity) from ``\varepsilon_\varphi`` (scalar) explicitly.

surviving_class: the same file's own `# Arguments` entry, line 400, still reads "`injection_rate` —
the energy-injection rate to hold" unqualified (self-contradicting the paragraph six lines above
it); the module docstring (`Forcing.jl` line 20, "The interchangeable energy-injection
strategies") and `AbstractForcing`'s docstring (line 61, "Supertype of the energy-injection
strategies") still name the whole family "energy-injection" although one implementation serves
scalar variance too.

---

## Finding 3 — "Two registers per field" names two different sets on two pages

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md` §4.5 (lines 385–389) now states its counting convention
explicitly — "three spectral registers per field against the low-storage scheme's two, counting
the same way on both sides: the scheme's own registers plus the dealiasing seam's assembly
register" — which reproduces `allocate_buffers`' actual totals (`src/Propagator.jl` lines
157–158: `IFLowStorageRK3` → `stage1`+`nonlinear` = 2; `IFRK2` → `stage1`+`stage2`+
`velocity_predictor_spectral` = 3). `IFLowStorageRK3`'s own docstring (lines 244–249) now
explicitly separates Williamson's classical 2N count ("the state's own array plus one accumulator
(`stage1`)") from the `IntegratorBuffers` total and warns "the count measures the scheme, not the
solver it is embedded in" — the collision is flagged, not silent, and the numbers reconcile.

---

## Finding 4 — `max_wavenumber` calls κ_max "the highest wavenumber magnitude that `domain` actually evolves" — false for `HouLi`

**VERDICT: PARTIAL**

Evidence: `src/SimulationDomain.jl` lines 281–283 now reads "the highest wavenumber magnitude the
run treats as resolved signal, and for a truncating strategy the highest it evolves at all (under
`HouLi` the modes above it are damped rather than removed)" — the docstring itself is fixed,
matching the finding's own resolution hint almost verbatim.

surviving_class: `docs/src/api/SimulationDomain.md` line 30 still reads "The dealiasing cutoff it
sets — the highest wavenumber the domain evolves" (unconditional, no `HouLi` caveat), rendered
verbatim in `docs/build/api/SimulationDomain/index.html`. `docs/src/api.md` line 13 likewise
still calls `max_wavenumber` "the highest wavenumber magnitude the run evolves."

---

## Finding 5 — `Sreenivasan1995`'s default C_K = 1.5 is not Sreenivasan's own value

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Scalings.jl` lines 100–102 now reads "The default ``C_K = 1.5 \pm
0.1`` used here is the consensus value as quoted by Sagaut & Cambon (2018), **not a figure read
off the 1995 paper**, with no significant Reynolds-number trend" — the misattribution the finding
flagged (reading as Sreenivasan's own finding) is explicitly disclaimed.

---

## Finding 6 — `initial_spectrum` "evaluated at the run's state" at t = 0, where ε and η do not yet exist

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl` lines 163–167 now states exactly which assumed values are used:
"``\varepsilon`` from the `Li2008` stationary-dissipation law at the requested `kinetic_energy` and
box side, ``u'`` from that same energy, ``\nu`` as resolved above, and the integral scale as
`1/envelope_wavenumber`." This answers the finding's open question ("Which ε the seeder uses…is
not stated anywhere on the page") directly; ``\eta`` follows from the now-stated ``\nu,\varepsilon``
via `kolmogorov_length`, needing no separate statement.

---

## Finding 7 — "Carrying the ½ only for the vector" attributes an energy-vs-variance convention to tensor rank

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl` `BandRescaling` docstring, lines 230–237: "the field's ``L^{2}``
observable — the ``\tfrac{1}{2}`` belongs to the kinetic energy's own definition, not to the field
being a vector" — states exactly the correction the finding's description called for.

---

## Finding 8 — The notation glossary writes κ_max in two algebraic shapes and omits `HouLi`

**VERDICT: PRESENT**

Evidence: `docs/src/notation.md` line 99 is unchanged from the finding's quote — still
``\tfrac{2}{3}\cdot\tfrac{N}{2}\cdot\tfrac{2\pi}{L}`` for `TwoThirds` against
``\tfrac{\sqrt{2}}{3}N\cdot\tfrac{2\pi}{L}`` for `PhaseShift` (different algebraic shapes, one
with ``N/2`` factored out and one without), and still names no `HouLi` value at all — while
`src/SimulationDomain.jl`'s `max_wavenumber` docstring uses the uniform ``f\frac{N}{2}\frac{2\pi}{L}``
form with all three strategies' `f` given, including `HouLi`'s `1`.

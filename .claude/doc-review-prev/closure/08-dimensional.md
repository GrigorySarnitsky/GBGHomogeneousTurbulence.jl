# Closure — Hat 08 (Dimensional analysis & normalization)

Adjudicated against the current corpus only (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`). No prior
closure round, fix-pass report, or other hat file was read.

## Finding 1 — assumed-state ε (Li2008) vs assumed L₁₁ (1/envelope_wavenumber) mismatch

**PRESENT**. `src/SimulationRun.jl:173` still reads "...and the integral scale as
`1/envelope_wavenumber`", verbatim as quoted, with no note that this is a nominal length rather than
`L₁₁`, and no cross-derivation against `Li2008`'s own `L/L₁₁ ≈ 5`. `Li2008`'s docstring
(`src/phenomenology/Scalings.jl:140-145`) does caveat its own `G`-vs-`C_ε` discrepancy, but that
caveat is never connected to the `envelope_wavenumber`-as-`integral_scale` construction the finding
targets — `FlowParameters(...; integral_scale = inv(envelope_wavenumber), ...)` at
`src/SimulationRun.jl:285` still uses the default `κ_p = 2 ⇒ L₁₁ = 0.5`, unreconciled with the
`ε`-implied `L₁₁ ≈ L/5 ≈ 1.26`.

## Finding 2 — E(κ) half-energy vs E_φ(κ) full-variance asymmetry, no notation.md row

**PRESENT**. `docs/src/notation.md` has an `E(\kappa)` row (line 73) but no `E_\varphi(\kappa)` row
anywhere in the file (grep for `Ny}`, `varphi`-spectrum patterns returns nothing). `ScalarSpectrum`'s
docstring (`src/phenomenology/Spectra.jl:401-403`) still reads "the density in wavenumber of the
scalar variance ⟨φ²⟩", unchanged, so the ×2 convention asymmetry the finding flags remains unpinned
on the one page that is "the single reference."

## Finding 3 — IFRK2's CFL dealiasing scaling applied to a relation the same docstring calls degenerate

**PRESENT**. `src/Propagator.jl`'s `recommended_cfl` docstring still states, two paragraphs apart,
that `IFRK2`'s `0.25` is "an empirical margin, not a computed limit" (because `y_s = 0` makes the
`C_CFL = y_s/(κ_maxΔx)` relation degenerate for it), then applies the same dealiasing scaling
`C_CFL ∝ 1/κ_max` to both schemes with no statement that, for `IFRK2`, the scaling is a
heuristic riding on the empirical number rather than inherited from the derived relation. The
`_base_cfl`/`recommended_cfl` code (lines ~569-577) confirms both schemes get the identical
`(2//3)/f` multiplier.

## Finding 4 — `envelope_wavenumber`: "no effect" (State.jl) vs "sets the integral scale" (SimulationRun.jl)

**PRESENT**. Both quotes still stand unqualified: `src/State.jl:79` — "The `envelope_wavenumber`
setting has no effect in the `initial_spectrum` branch below" (verbatim, both
`random_solenoidal_velocity_spectral!` and `random_scalar_spectral!` copies at lines 79 and 160) —
and `src/SimulationRun.jl:166` — "it also sets the integral scale in the assumed state
`initial_spectrum` reads." Neither has been qualified with the front-door/seeder distinction the
resolution hint proposed.

## Finding 5 — `PhaseShift` scratch cost: "one spectral buffer per term" vs the actual register set

**PRESENT**. `src/SimulationDomain.jl`'s `PhaseShift` docstring still says "the displaced-evaluation
scratch (a field-scale spectral-representation buffer per phase-shifted term)" (unchanged). The
actual generator registers (`src/Generator.jl:111-119`) hold, per velocity term alone,
`velocity_shifted` (spectral) **and** `u_shifted` / `omega_shifted` (both explicitly "recovered on
the displaced grid" — physical representation), plus `scalar_shifted` (spectral) / `phi_shifted`
(physical) for the scalar term — understating both count and representation exactly as the finding
describes. Decision-log text at `docs/ARCHITECTURE.md:1606-1610` still names `u_shifted` /
`ω_shifted` the same way.

## Finding 6 — module docstring "distribution over wavenumber" vs the per-shell-energy discipline

**PRESENT**. `src/Observables.jl:27-28` still reads "...the energy spectrum reduces to a
distribution over wavenumber..." verbatim. `energy_spectrum`'s own docstring (lines 285-320) still
insists on the per-shell energy `E_n` vs the density `E(κ)` distinction. Grep for "distribution over
wavenumber" / "energy spectrum reduces" across `src/` and `docs/` returns only this one module-map
sentence — no other surviving instance of the same phrase, but the flagged sentence itself is
unswept.

## Finding 7 — notation.md ("the single reference") omits `κ_Ny` and `κ_p`, both defined inline repeatedly

**PRESENT**. `docs/src/notation.md` has no `\kappa_{\mathrm{Ny}}` row and no `\kappa_p` row (only
`\kappa_{\max}` at line 100). `κ_Ny = (N/2)(2π/L)` is still spelled out verbatim in
`src/SimulationDomain.jl` at lines 64, 77, and 113 (`TwoThirds`, `HouLi`, `PhaseShift` respectively) —
still three inline restatements of the same definition, exactly the repetition the page's "single
reference, no repeat" convention (its own opening line) exists to prevent.

## Finding 8 — `DissipationFactor` bottleneck note's γ<0 vs the cited fits' positive exponent

**PRESENT**. `src/phenomenology/Spectra.jl:76` still reads "...`A(κη)^γ exp(−βκη)` with `γ < 0`..." in
the bottleneck-deferral admonition, unchanged. `ExponentialDissipation`'s docstring two structs later
still cites Chen et al. 1993 (`β ≈ 7.1`) alongside Khurshid et al. 2018 (`β ≈ 6.7`) for the pure
exponential far-dissipation form — the same family the finding says carries a positive power-law
prefactor exponent in the cited literature. No re-derivation or sign clarification has been added.

## Finding 9 — grid-mode `HouLi` caveat did not say which way the resolution estimate errs

**ABSENT**. `src/SimulationRun.jl:117-121` now reads, immediately after the "approximate for `HouLi`"
sentence: "The gap is not cosmetic: f = 1 puts η ≈ 0.64 Δx at `κ_max_η = 2` (against 0.96 Δx for
2/3), and since ν ∝ f^(−4/3), `HouLi` is handed a Re_λ about 31% higher on the same grid at the same
nominal criterion — raise `κ_max_η` when comparing across strategies." This states exactly the
missing sign: grid mode over-credits `HouLi`'s effective resolution and hands it a smaller ν / higher
Re_λ than the criterion intends — precisely the clause the finding's resolution hint asked for.

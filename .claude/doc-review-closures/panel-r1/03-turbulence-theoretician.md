# Closure — Hat 03 — Turbulence theoretician

## Finding 1 — cache page "blocked reuse" contradiction (ω leaving vs staying)
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md` §1.2 (line 108-111) and §1.4 (line 202-206) now both read
in past/landed tense, consistent with §2.3/§2.4 and `docs/ARCHITECTURE.md` decision 41: "§2.3's
in-place reuse does not [remove ω], which is why it left ``\boldsymbol{\omega}`` in the cache."
Grepped `docs/src/*.md` and `docs/ARCHITECTURE.md` for "removes it", "keeps ... in the cache today",
"lands the reuse", "will take it out" — zero hits. No stale pre-landing phrasing remains anywhere.

## Finding 2 — ModelSpectrum evaluates Pope's roll-off at L₁₁ with Pope's c_L
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:107` — generic `large_scale_length` defaults to `fp.integral_scale`
(L₁₁) for `LargeScaleFactor`, but line 141-142 overrides it for `PopeLargeScale` specifically:
`(3 * fp.rms_velocity^2 / 2)^(3//2) / fp.dissipation` = ``k^{3/2}/\varepsilon``, with a docstring
(lines 94-103) stating exactly the finding's own math ("smaller by a factor of order three ... leaves
the model spectrum holding well under half the kinetic energy"). Fixed as the resolution_hint proposed.

## Finding 3 — validation differences per-shell energy against a spectral density
**VERDICT: ABSENT**

Evidence: `test/validation.jl` lines 60-109 — `compare_to_model` now computes
`Δκ = 2π / sim.domain.grid.domain_size[1]` and multiplies the model density by it
(`spectrum(model, κ[i], fp) * Δκ`) before comparing to the measured per-shell `E_n`; a dedicated test
pins a non-2π box (`Δκ ≈ 0.5`, "not 1: the factor is live here"). `docs/ARCHITECTURE.md` decision 19
(lines 941-945) states the conversion explicitly. Both locations cited in the finding are fixed.

## Finding 4 — ConstantPower's keyword described as holding the dissipation rate
**VERDICT: PARTIAL**

Evidence: `src/Forcing.jl` `# Arguments` entry (lines 386-387) is fixed, matching the resolution hint
verbatim: "the energy-injection rate to hold: the value ``\varepsilon`` relaxes to in the stationary
mean, not an instantaneous dissipation the forcing measures or clamps." But the docstring's own body
prose immediately above (lines 367-368) still reads "so `injection_rate` is a number: the **value**
of the dissipation rate to hold" — the identical conflation, now self-contradicting the fixed
Arguments entry three lines below it, in the same docstring.

**surviving_class**: `src/Forcing.jl:367-368` (the `ConstantPower` docstring body, immediately
preceding the fixed Arguments entry) still calls `injection_rate` "the value of the dissipation rate
to hold."

## Finding 5 — FlowParameters example states violate the plateau C_ε ≈ 0.5
**VERDICT: PARTIAL**

Evidence: `src/Phenomenology.jl:105,108` fixed — `dissipation = 1.0, rms_velocity = 1.0,
integral_scale = 0.5` gives `C_ε = εL₁₁/u'³ = 0.5`, on the plateau. But `docs/src/phenomenology.md:20`
is untouched: `FlowParameters(viscosity = 1e-3, dissipation = 0.1, rms_velocity = 1.0,
integral_scale = 1.0)` gives `C_ε = 0.1`, still five times below the plateau at `Re_λ ≈ 387` — inside
the plateau's asserted regime, exactly the finding's original complaint.

**surviving_class**: `docs/src/phenomenology.md:20` — the module-page example, unfixed.

## Finding 6 — flagship explicit-viscosity example under-resolved (κ_max η < 1.5)
**VERDICT: PARTIAL**

Evidence: `src/SimulationRun.jl:182` fixed — `viscosity = 1e-2` with `injection_rate = 0.1` at 128³
gives `η ≈ 0.0563`, `κ_max η ≈ 2.40`, above the 1.5 well-resolved threshold. But
`docs/ARCHITECTURE.md:53` (= `docs/src/architecture.md:53`, identical file) is untouched:
`Simulation(grid_points_per_axis = 128, viscosity = 5e-3; velocity_forcing =
ConstantPower(injection_rate = 0.1), ...)` still gives `η ≈ 0.0334`, `κ_max η ≈ 1.43` — below the
package's own `κ_max_η ≥ 1.5` well-resolved bar (`src/SimulationRun.jl:137`).

**surviving_class**: `docs/ARCHITECTURE.md:53` / `docs/src/architecture.md:53` — the architecture
page's headline example, unfixed.

## Finding 7 — envelope_wavenumber means two different large scales in its two modes
**VERDICT: ABSENT**

Evidence: `src/State.jl:82` (and the scalar twin at line 162) now states explicitly: "`envelope_wavenumber`
has no effect in the `spectrum` branch below, which carries its own large scale and will not generally
peak there — the two modes do not seed the same large scale at the same nominal setting." This is the
operation's home docstring; the caveat the finding requested is stated at the point of truth.

## Finding 8 — Li2008's G transferred to grid mode with no forcing-band caveat
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:106-109` — grid-mode docstring now states: "a value that assumes
forcing confined to the same low-wavenumber band as the calibrating runs, since ``G`` is
``C_\varepsilon`` rescaled by ``L_{11}/L`` ... a forcing moved to higher shells invalidates the
estimate and with it the ``\nu`` grid mode chooses." Matches the resolution hint's requested caveat
verbatim in substance.

## Finding 9 — StationarityCriterion recommended for runs with no stationary state
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:554-558` — "Use it before measurement on any freshly seeded **forced**
run. A freely decaying run (`NoForcing()`) has no stationary state to detect — its ``\varepsilon``
never plateaus — so the criterion can only run to `max_turnovers` and warn; give a decaying run a
fixed budget instead." Scoped to forced runs exactly as the resolution hint requested.

## Finding 10 — deposit_sample! required but undocumented
**VERDICT: ABSENT**

Evidence: `src/GBGIsotropicTurbulence.jl:99,178` — `deposit_sample!` now exported; `src/Cache.jl:262-278`
carries its own docstring; `docs/src/api/Cache.md:17` lists it in a `@docs` block. No longer an
undocumented mandatory call.

## Finding 11 — ScalingLaw family advertises the derivative skewness
**VERDICT: ABSENT**

Evidence: `src/phenomenology/Scalings.jl:28-30` — the `ScalingLaw` supertype docstring now illustrates
with "the normalized dissipation ``C_\varepsilon``, the Kolmogorov constant ``C_K``, and the
box-normalized dissipation group ``G``" — the derivative skewness is gone from the list, matching only
the built laws. `docs/ARCHITECTURE.md:520` still correctly marks the skewness as a forward-looking
addition, no longer contradicted.

## Finding 12 — ConstantPower's rate has an unguarded singular limit
**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:377-382` — a `!!! note "An empty band is left alone, not driven infinitely
hard"` now states the guard explicitly: "Below a small floor on ``E_{\mathrm{band}}`` the rate is set
to zero instead." The code implements it: `src/Forcing.jl` `set_forcing_rate!` —
`amplitude = band_observable > 1e-12 ? forcing.injection_rate / (2 * band_observable) : 0.0`. Matches
the `BandRescaling`-style caveat the resolution hint requested.

# Closure audit — hat 03: turbulence theoretician

## 1. `SaffmanDissipation` — unpublished coefficient, not overridable
**VERDICT: PRESENT**
`src/phenomenology/Spectra.jl:262-275`: `struct SaffmanDissipation <: DissipationFactor end` — still
zero fields, so `SaffmanDissipation()` cannot be given a coefficient; `dissipation_factor` still hard-codes
`exp(-2*κη^2)`. Docstring still states the published coefficient is 2.6–3.3 and "is simplified downward to
`2` here". `docs/src/phenomenology.md:14` still claims "any coefficient can be overridden to re-fit" for
every preset. Same class confirmed alive in `Lundgren2002` (`src/phenomenology/StructureFunctions.jl:198-202`,
hard-coded `8.45`, zero-field struct).
**surviving_class**: `Lundgren2002`'s hard-coded `8.45` (StructureFunctions.jl:179-202) — identical
unoverridable-coefficient pattern.

## 2. `ExponentialDissipation` enrolled among "inertial-normalized cutoffs"
**VERDICT: PRESENT**
`src/phenomenology/Spectra.jl:68-69`: `DissipationFactor`'s note still reads "These factors are
inertial-normalized cutoffs" verbatim. `ExponentialDissipation`'s docstring (lines 230-256) still gives no
restriction against composing it into a `ModelSpectrum`, and `ModelSpectrum`'s own docstring (line 289)
still invites "Build one directly to mix roll-off forms". `dissipation_factor(::ExponentialDissipation, κη)
= exp(-f.β*κη)` unchanged — no offset, so at `β≈6.7` it is still 0.51 at `κη=0.1`.

## 3. `Simulation`'s `G`–`C_ε` relation vs `Li2008`'s exact identity
**VERDICT: ABSENT**
`src/SimulationRun.jl:107-109` now reads "since `G` carries `C_ε^{-2/3}` and the ratio `L₁₁/L`" — the
inverse-2/3 dependence, matching `Li2008`'s identity. No "rescaled by" / linear-proportionality phrasing
found (`rg "rescaled by" src/SimulationRun.jl` empty). Rendered `docs/build/api/SimulationRun/index.html`
confirms the same wording is what ships.

## 4. `L₁₁` vs `k^{3/2}/ε` factor and "well under half"
**VERDICT: ABSENT**
`src/phenomenology/Spectra.jl:100-106` (`large_scale_length`) now gives the correct numbers: "at
`C_ε=0.5` the length is 3.7 times smaller and the spectrum integrates to `0.42k`, and at Pope's
high-Reynolds-number `L₁₁=0.43L₀` it is 2.3 times smaller and integrates to `0.57k`". `rg "order three|well
under half"` over `src/` and `docs/src/` returns nothing. Rendered build
(`docs/build/api/phenomenology/Spectra/index.html`) contains `0.42k` and `0.57k`, not the old numbers.

## 5. Scalar's held observable called *energy* (`E_band`, `injection_rate`)
**VERDICT: PARTIAL**
`BandRescaling`'s docstring (`src/Forcing.jl:230-236`) now correctly separates kinetic energy (velocity)
from scalar variance and explicitly states "the `½` belongs to the kinetic energy's own definition, not to
the field being a vector" — the quoted contradiction there is gone. `ConstantPower`'s empty-band note
(lines 391-396) now also correctly types it: "its energy for the velocity, its variance for the scalar".
But the `# Arguments` entry at `src/Forcing.jl:400` is unchanged: `` `injection_rate` — the
energy-injection rate to hold: the value ``\varepsilon`` relaxes to…`` — still typed as an energy-injection
rate with no scalar (`ε_φ`, variance-destruction) qualification, the exact defect the finding named.
**surviving_class**: `src/Forcing.jl:400` (`ConstantPower` Arguments entry for `injection_rate`).

## 6. Scalar right-hand side written as a bold (vector) symbol
**VERDICT: PRESENT**
`docs/src/notation.md:65` now disambiguates the table entry (`\widehat{N}` generic, `\widehat{\boldsymbol
N}` for velocity only) — but the actual formula displays are unchanged: `src/Propagator.jl:225-236`
(`IFLowStorageRK3`) still reads "and `\widehat{\boldsymbol{N}}` each field's right-hand side" (explicitly
covering the scalar) while writing `\boldsymbol{h} \leftarrow A_i\boldsymbol{h} +
\Delta t\widehat{\boldsymbol{N}}(\hat q)` — bold `N̂`/`ĥ` against non-bold `q̂`. Same pattern repeats in
`IFRK2` at lines 338-350 ("`\widehat{\boldsymbol{N}}` each field's right-hand side" then bold `N̂₁`, `N̂₂`
against non-bold `q̂`).
**surviving_class**: identical construction in `IFRK2`'s docstring (`src/Propagator.jl:338-350`).

## 7. `Li2008` attributes reference law to a database paper
**VERDICT: ABSENT**
`src/phenomenology/Scalings.jl:132-134`: the docstring now explicitly reads "The value is this package's
own reduction of the Johns Hopkins Turbulence Database (JHTDB) forced-isotropic dataset … and consistent
with higher-Reynolds-number periodic-box DNS" — no longer implies Li et al. published `G≈0.9` themselves;
the self-fit is now stated outright, one of the finding's two acceptable resolutions.

## 8. "Stamp" retired by decision 53/54 yet used in `ObservablesCache`'s own docstring
**VERDICT: ABSENT**
`rg -i "stamp" src/ docs/src/ docs/ARCHITECTURE.md` (excluding `.claude/`) returns zero hits in `src/Cache.jl`
or `docs/src/notation.md`; the only remaining occurrences are in `docs/ARCHITECTURE.md`'s decision-log entry
53 itself, which historically quotes the retired word ("this entry records that the older entries
originally said 'stamp'") — the intended historical record, not live vocabulary. The class is fully swept.

## 9. "IFRK2's two predictor registers" — only one predictor exists
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md:774-776` (§9 invariant 4) now reads "an `IFLowStorageRK3` run carries neither of the
two registers `IFRK2` adds — its corrector stage and its velocity predictor" — matches the finding's own
`resolution_hint` almost verbatim and is accurate against `src/Propagator.jl:158`
(`IFRK2` allocates `stage1`, `stage2`, and `velocity_predictor_spectral`).

## 10. `VonKarman1948`'s default `c_L = 1.0` presented as a published fit
**VERDICT: ABSENT**
`src/phenomenology/Spectra.jl:358-360`: the docstring now explicitly states `c_L` "is a shape parameter of
this form rather than a normalization — unlike `PopeLargeScale`'s `c_L`, no energy condition determines
it, and the default `1.0` is the conventional choice" — no longer presented as von Kármán's own published
fit.

## 11. Sreenivasan-named preset's default credited to a different source
**VERDICT: ABSENT**
`src/phenomenology/Scalings.jl:100-102`: the docstring now explicitly discloses "The default `C_K = 1.5 ±
0.1` used here is the consensus value as quoted by Sagaut & Cambon (2018), **not a figure read off the
1995 paper**" — the finding's second acceptable resolution ("the default is not the named paper's") is now
stated outright rather than left implicit/contradictory.

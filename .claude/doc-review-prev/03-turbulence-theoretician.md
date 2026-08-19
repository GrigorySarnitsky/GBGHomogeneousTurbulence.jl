# Doc-review panel — hat 03: TURBULENCE THEORETICIAN

Substrate: the consolidated rendered site (`manuscript-full.md`). Collect-only; no edits applied.

**Verified clean** (expanded against theory, no defect found — recorded so a later round need not
re-derive): the Betchov skewness constant `C_S = (4/7)√(15/2) ≈ 1.5649` (from
`⟨tr S³⟩ = (105/8)⟨(∂₁u₁)³⟩` and `⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩`, signs included, and `tr S³ = 3 det S`
for a traceless symmetric tensor); `ε = ν⟨|ω|²⟩ = 2ν⟨S:S⟩` and its "differ by a divergence" caveat;
the Dirichlet route `⟨|ω|²⟩ = ⟨û,|κ|²û⟩` and its solenoidal condition; `ε_φ = 2ϰ⟨|∇φ|²⟩` as the
full-variance rate and the resulting Yaglom `-2/3 ε_φ r`; `L₁₁ = (3π/4)∫(E/κ)/∫E`, `L₂₂ = L₁₁/2`,
`L_E = (π/2)∫(E/κ)/∫E = (2/3)L₁₁`; `λ`, `η`, `τ_η`, `Re_λ = u'²√(15/(νε))`; `G = (3/2)C_ε^{-2/3}` and
the `L/L₁₁ ≈ 5 ⇒ G ≈ 0.81` arithmetic; `ε = (k/G)^{3/2}/L`; `Re_λ ~ N^{2/3}`; `κ_max η = fπη/Δx` and
`κ_max_η = 2 ⇒ Δx ≈ η` at `f = 2/3`; the PhaseShift band `√2N/3 = (2√2/3)κ_Ny ≈ 0.94 κ_Ny`, `≈2.8×`
the modes, and the odd-axis/two-axis image argument; the alias-free condition `2κ_max < N`; RKW3
coefficients `A,B,d` and abscissae `c = (0,1/3,3/4)`; `y_s = √3 ⇒ C_CFL ≲ 0.83`; `|R(iy)|² = 1+y⁴/4`;
`ζ_p` for K62 and She–Lévêque; Lundgren's zero at `Re_λ ≈ 34` and the ~50 % coefficient loss at 100;
`C₂ ≈ 2.0` consistent with `C_K = 1.5`; the Gaussian-envelope peak at `κ_p/√2`; `√E(κ)/κ` mode
scaling; the ConstantPower rate `A = injection_rate/(2E_band)`; the transform ledgers (18/9, 21/18,
2× for PhaseShift).

---

## 1. `SaffmanDissipation` carries a published attribution but a deliberately unpublished coefficient, and cannot be overridden
- **type**: citation / physics
- **severity**: major
- **confidence**: high
- **locations**:
  - PAGE `api / phenomenology / Spectra`, `SaffmanDissipation`: signature `SaffmanDissipation()`;
    "whose coefficient varies with the derivative skewness $S$ — about $2.6$ to $3.3$ … and is
    simplified downward to $2$ here"; "retains more near-cutoff energy than a measured spectrum shows".
  - PAGE `phenomenology` (overview): "the published fit is the default, and any coefficient can be
    overridden to re-fit".
- **contradicts**: PAGE `phenomenology`, "any coefficient can be overridden to re-fit" — axis: whether a
  preset's fitted coefficient is (a) the published value and (b) user-overridable.
- **description**: The preset is named for Saffman and reports his provenance, yet its cutoff
  coefficient is neither his (2.6–3.3) nor any published value, and the zero-field constructor gives no
  way to restore one. In a library whose stated purpose is validating a run against the literature, a
  reference curve that is admittedly softer than measurement will report a spurious near-cutoff
  discrepancy that a user cannot dial away. Same class: `Lundgren2002`'s hard-coded `8.45`.
- **resolution_hint**: `SaffmanDissipation(; coefficient = 2.6)` (published default), and make
  Lundgren's coefficient a field.

## 2. `ExponentialDissipation` is a far-dissipation asymptote enrolled among "inertial-normalized cutoffs"
- **type**: physics
- **severity**: major
- **confidence**: medium
- **locations**:
  - PAGE `api / phenomenology / Spectra`, `DissipationFactor`: "These factors are inertial-normalized
    cutoffs"; "with $f_\eta \to 1$ as $\kappa\eta \to 0$".
  - Same page, `ExponentialDissipation`: "It is the far-dissipation form ($\kappa\eta \gg 1$), where
    DNS resolving that range fit $\beta \approx 6.7$"; "the factor tends to `1` in the inertial range".
- **contradicts**: `DissipationFactor`, "inertial-normalized cutoffs" — axis: whether the factor is ≈1
  across the inertial range or only in the limit.
- **description**: `exp(-βκη)` has no `c_η`-style offset, so at `β ≈ 6.7` it is 0.51 at `κη = 0.1` and
  0.07 at `κη = 0.4` — precisely where `PopeDissipation` is still ≈1. Composed into a `ModelSpectrum`
  (which the module invites: "Build one directly to mix roll-off forms") it multiplies the whole
  inertial range by a large exponential, so the composite is not a `κ^{-5/3}` law with a cutoff. The
  limit statement is true and the practical claim is not.
- **resolution_hint**: State the restriction (valid only as a far-range asymptote / not composable with
  an inertial core), or give it an offset form.

## 3. `Simulation` states the `G`–`C_ε` relation as a linear rescale; the `Scalings` page gives the exact inverse-2/3 identity
- **type**: contradiction
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE `api / SimulationRun`, `Simulation`, Grid mode: "since $G$ is $C_\varepsilon$ rescaled by
    $L_{11}/L$".
  - PAGE `api / phenomenology / Scalings`, `Li2008`: "Formed on a common length the two are exactly
    related by $G = \tfrac{3}{2} C_\varepsilon^{-2/3}$".
- **contradicts**: `Li2008` as quoted — axis: the functional form relating the two dimensionless groups.
- **description**: `G = (3/2)(L₁₁/L)^{2/3} C_ε^{-2/3}` — the dependence on `C_ε` is *inverse* and to the
  2/3 power, and the length ratio also enters to the 2/3 power. "`G` is `C_ε` rescaled by `L₁₁/L`" reads
  as a linear proportionality in both, and gets the direction of the `C_ε` dependence wrong (a larger
  `C_ε` gives a *smaller* `G`). The `Li2008` page even warns against substituting the two directly.
- **resolution_hint**: "since `G` is fixed by `C_ε` and the ratio `L₁₁/L` together (both to the 2/3
  power)".

## 4. The `L₁₁` vs `k^{3/2}/ε` factor and the "well under half" consequence disagree with Pope's own ratio
- **type**: physics
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE `api / phenomenology / Spectra`, `large_scale_length`: "feeding the same coefficient $L_{11}$
    instead — smaller by a factor of order three — leaves the model spectrum holding well under half the
    kinetic energy".
- **description**: Pope's own high-Reynolds-number result is `L₁₁ = 0.43 L₀` — a factor 2.3, not "of
  order three". Since `∫E dκ ∝ L^{2/3}` at fixed `C_K, ε`, substituting `L₁₁` leaves
  `0.43^{2/3} ≈ 0.57` of the energy — a bit *over* half, not "well under". The number quoted is only
  reached if the ratio really is ≈3.5, which is the package's box value rather than Pope's model value.
- **resolution_hint**: Quote Pope's `L₁₁ ≈ 0.43 k^{3/2}/ε` and say "roughly 40 % of the energy lost"
  (`1 − 0.57`), or state which ratio is meant.

## 5. For the scalar, `E_band` and `injection_rate` are called *energy* where the quantity is a variance
- **type**: dimensional / category
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE `api / Forcing`, `ConstantPower`: "The rate $A$ diverges as the band's own energy goes to zero,
    which is reachable — a scalar seeded with nothing in the forced shells".
  - Same docstring, Arguments: "`injection_rate` — the energy-injection rate to hold".
  - Same page, `BandRescaling`: "the field's $L^{2}$ observable, carrying the $\tfrac{1}{2}$ only for
    the vector".
- **description**: One implementation serves both fields, and the docstrings say so correctly elsewhere
  ("the rate $\varepsilon$ for the velocity … and $\varepsilon_\varphi$ for the scalar"). But the
  empty-band caveat and the `injection_rate` gloss both type the held quantity as an *energy*, which for
  the scalar is `⟨φ²⟩` — a variance — and the injected rate is `ε_φ`, a variance-destruction rate. The
  symbol `E_band` compounds it: `E` is glossed on the notation page as an energy/spectral density.
- **resolution_hint**: "the band's own held observable" / "the injection rate to hold (`ε` for the
  velocity, `ε_φ` for the scalar)".

## 6. The scalar's right-hand side is written as a bold (vector) symbol
- **type**: typesetting / category
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE `notation`, Spectral representation and operators: "$\widehat{\boldsymbol{N}}$ | a field's
    assembled explicit right-hand side … | velocity_rhs!, scalar_rhs!".
  - PAGE `api / Propagator`, `IFLowStorageRK3`: "$\boldsymbol{h} \leftarrow A_i \boldsymbol{h} +
    \Delta t \widehat{\boldsymbol{N}}(\hat q)$" — with the state written non-bold as `\hat q`.
- **description**: The house rule reserves bold italic for vectors and tensors. `scalar_rhs!` assembles
  a *scalar* field, and the low-storage formula is written generically over `q̂` (non-bold) while its own
  increment and right-hand side are bold — so within one display the same generic field is both bold and
  not. A reader types `N̂` as a vector and then meets it as the scalar's tendency.
- **resolution_hint**: Use non-bold `\widehat N` for the generic/scalar right-hand side (and `\hat h`),
  reserving the bold form for the velocity instance.

## 7. `Li2008` attributes a reference law to a database paper
- **type**: citation
- **severity**: minor
- **confidence**: medium
- **locations**:
  - PAGE `api / phenomenology / Scalings`, `Li2008`: "nearly Reynolds-number-independent from the Johns
    Hopkins Turbulence Database (JHTDB) forced-isotropic dataset".
  - PAGE `phenomenology`: "the paper is the author-year type (`Pope2000`)"; "our own fits sit beside the
    literature on equal footing".
- **description**: Li et al. (2008) is the JHTDB database paper; it does not publish a box-normalized
  dissipation group. The value `G ≈ 0.9` is the package's own reduction of that dataset, so the
  author-year handle asserts a provenance the source does not carry — exactly the case the module says
  it handles by letting our own fits stand as our own. This matters because the run layer's default `ν`
  rests on it.
- **resolution_hint**: Keep the name if the `Reference` string says "fitted here to the Li et al. (2008)
  JHTDB dataset"; otherwise name it as an own fit.

## 8. "Stamp" is retired by decision 54 yet is the ObservablesCache docstring's own vocabulary
- **type**: contradiction
- **severity**: minor
- **confidence**: high
- **locations**:
  - PAGE `architecture`, §11: "**'Stamp' is retired; a slot carries an epoch** … The `*_stamp` fields
    become `*_epoch`, and the verb goes with the noun — a deposit fills a slot and sets its epoch rather
    than 'stamping' it."
  - PAGE `api / Cache`, `ObservablesCache` Fields: "each slot carries a stamp, the counter's value at the
    moment that slot was filled"; "`velocity_epoch`, … — each slot's stamp"; "the particle velocities'
    two stamps".
  - Same page, `deposit_sample!`: "this call stamps both from the cache's current counters".
- **contradicts**: the §11 entry as quoted — axis: the retired noun/verb.
- **description**: The decision that renamed the fields also retired the word and its verb; the type's
  own docstring reintroduces both four times, including in the sentence that defines the concept. A
  reader meets "stamp" as the primary noun exactly where the glossary says "epoch".
- **resolution_hint**: Sweep `stamp` → `epoch` on the `Cache` surface; check the `Vocabulary` entry on
  the notation page too, which also says "the value of that counter stamped on it".

## 9. "IFRK2's two predictor registers" names one register that exists
- **type**: contradiction
- **severity**: nit
- **confidence**: medium
- **locations**:
  - PAGE `architecture`, §9 invariants: "an `IFLowStorageRK3` run does not carry `IFRK2`'s two predictor
    registers".
  - PAGE `api / Propagator`, `allocate_buffers`: "`IFRK2` allocates `stage1`, `stage2`, and
    `velocity_predictor_spectral`".
- **description**: `IFRK2` carries exactly one predictor register; the second register `IFLowStorageRK3`
  lacks is `stage2`, a corrector stage. The invariant's phrasing invites a reader to look for two
  predictors and find one.
- **resolution_hint**: "does not carry `IFRK2`'s second stage and predictor registers".

## 10. `VonKarman1948`'s default `c_L = 1.0` is presented as a published fit
- **type**: physics
- **severity**: minor
- **confidence**: low
- **locations**:
  - PAGE `api / phenomenology / Spectra`, `VonKarman1948`: signature `VonKarman1948(; C_K = 1.5,
    c_L = 1.0)`; "`c_L` fixes the peak scale".
  - PAGE `phenomenology`: "the published fit is the default".
- **description**: Unlike `PopeLargeScale`, whose `c_L = 6.78` is stated to come from the energy
  normalization, `VonKarmanLarge`'s `c_L = 1.0` looks like a placeholder: with the length taken as
  `L₁₁` the composed spectrum then peaks at `κL₁₁ ≈ 1.55`, whereas the classical von Kármán form with
  its own `κ_e`–`L₁₁` relation peaks nearer `κL₁₁ ≈ 1.2`. Nothing ties `c_L = 1` to von Kármán (1948),
  and no normalization condition is stated for it as one is for Pope's.
- **resolution_hint**: Either state the condition `c_L` satisfies (peak location or energy
  normalization) or mark it explicitly as a convenience value, not the published fit.

## 11. A Sreenivasan-named preset takes its default from a different source
- **type**: citation
- **severity**: nit
- **confidence**: medium
- **locations**:
  - PAGE `api / phenomenology / Scalings`, `Sreenivasan1995`: "a reliable estimate being $C_K = 1.5 \pm
    0.1$ (the default; Sagaut & Cambon 2018)".
  - PAGE `api / phenomenology / Phenomenology`, `provenance`: "it is the single source of the law's
    attribution".
- **description**: The preset's `provenance` will report Sreenivasan (1995) while its default value is
  credited in the same sentence to Sagaut & Cambon (2018). Either the two agree (in which case say so —
  Sreenivasan's 1-D 0.5 maps to a 3-D 1.5) or the default is not the named paper's, and `provenance`
  stops being the single source of attribution.
- **resolution_hint**: "Sreenivasan's one-dimensional 0.5 ± 0.05 corresponds to the three-dimensional
  1.5 (×55/18), the value Sagaut & Cambon also tabulate."

# Dimensional-analysis & normalization hat — findings (2026-08-24 round)

Substrate: `manuscript-full.md` (the full rendered site). Method: every stated formula,
normalization factor, and dimensionless constant was expanded and checked, and every factor that
appears on two or more pages was compared across those pages.

## Verified clean (the load-bearing factors — no finding)

These were each checked by expansion AND for cross-page identity; all pass:

- k = ½⟨|u|²⟩ (architecture §4.3, notation, `kinetic_energy`, `VarianceRescaling`) — the ½ identical everywhere.
- ε = ν⟨|ω|²⟩ = 2ν⟨S_ij S_ij⟩ (dilatation-difference claim expands correctly; Parseval route |κ×û|² identity correct).
- ε_φ = 2ϰ⟨|∇φ|²⟩ — the 2ϰ identical in architecture §4.3, notation, `scalar_dissipation`, `FlowParameters`, Yaglom, Obukhov–Corrsin. The Yaglom −(2/3)ε_φ r conversion from the classical −(4/3)·(half-variance rate) is exactly right; the C_OC = 0.67 claim of convention invariance is correct (both E_φ and ε_φ double together, so C_OC cancels — unlike Yaglom's one-sided coefficient).
- E(κ) density with Δκ = 2π/L, k = ΣE(κ_n)Δκ — identical in notation, `energy_spectrum`, decision log.
- L11 = (3π/4)∫(E/κ)/∫E, L22 = L11/2, L_E = (π/2)(…) = (2/3)L11 = (1/3)(L11+2L22) — internally exact.
- η = (ν³/ε)^{1/4}, τ_η = (ν/ε)^{1/2}, λ = √(15νu'²/ε), Re_λ = u'λ/ν = u'²√(15/(νε)), u' = √(2k/3) — identical in notation and the Phenomenology helpers.
- ℰ = exp((A − D|κ|²)τ), coefficient = −Dτ, offset_scale = τ — sign and |κ|² factor identical in §4.2, notation, cache-design §2.2, the factor verbs.
- CFL: Δt = C·Δx/max|u|; κ_maxΔx = fπ; RK3 y_s = √3 ⇒ C ≲ 0.83 (3√3/2π = 0.827 ✓) taken 0.5; IFHeun |R(iy)|² = 1 + y⁴/4 ✓.
- Phase-shift cutoff: (√2/3)N·(2π/L) = (2√2/3)κ_Ny ≈ 0.94κ_Ny, √2 wider than 2/3-rule, (√2)³ ≈ 2.8× modes — the SAME number at all six sites (decisions 27/§7, PhaseShift, DealiasingStrategy, max_wavenumber f = 2√2/3, truncate_to_band!, kinetic_energy's √2N/3).
- Alias-free condition 2κ_max < N (fundamental units): correct criterion; correctly marginal for HouLi's κ_max = N/2.
- Betchov constant: C_S = (4/7)√(15/2) ≈ 1.5649 from ⟨trS³⟩ = (105/8)⟨(∂₁u₁)³⟩ and ⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩ — expansion closes exactly; trS³ = 3detS ✓ (traceless Cayley–Hamilton).
- Transform table (18/9, 21/18, 36/18, 42/36 per RK3 step) consistent with per-evaluation (6,3) velocity / (1,3) scalar and PhaseShift ×2; consistent with decision 45's 51→42 (RK3) and 34→28 (RK2).
- Viscosity derivation: ε = (k/G)^{3/2}/L inverts G = k/(Lε)^{2/3} ✓; κ_maxη = fπη/Δx ⇒ η ≈ 0.96Δx (2/3) / 0.64Δx (HouLi) at κ_max_η = 2 ✓; ν ∝ f^{−4/3} ⇒ 31% Re_λ gap ✓; Re_λ ~ N^{2/3} ✓; G = (3/2)C_ε^{−2/3} and the 0.81-vs-0.9 cross-check at L/L11 ≈ 5 ✓.
- Pope/von Kármán/Pao: p₀ = 2 ⇒ κ² (Saffman-type), VonKarmanLarge 17/6 ⇒ κ⁴ ✓; ℓ₀-vs-L11 numbers (3.7×, 0.42k; 2.3×, 0.57k via ∫E ∝ ℓ^{2/3}) ✓.
- K62 ζ_p = p/3 − (μ/18)p(p−3), She–Lévêque ζ_p = p/9 + 2[1−(2/3)^{p/3}], both ζ₃ = 1 ✓; Lundgren zero at (8.45/0.8)^{3/2} ≈ 34 ✓.
- Envelope seeding: amplitude envelope exp(−κ²/κ_p²) ⇒ shell spectrum ∝ κ²exp(−2κ²/κ_p²), peak κ_p/√2 — identical at all four sites; √E/κ mode scaling ⇒ shell sum ∝ E ✓.
- ConstantPower A = P/(2E_band) (injection 2AE_band ✓ both fields); VarianceController A = [ε − G(k−k∞)/t_ℓ]/(2k_f) ⇒ dk/dt = −G(k−k∞)/t_ℓ ✓; sync counts 1+3×3 = 10 → 3+1 = 4 ✓.
- Memory numbers: 384 MiB = 3·256³·8 B ✓, 768 = 2×, 2.3 GiB = 6 fields ✓, 24/12 bytes per pointwise op ✓, 322.5 MiB → 2.52 GiB (×8 at 512³) ✓.
- AB order cap 8 ↔ 4-point Gauss–Legendre exact to degree 7 ✓; Heun/AB floor-vs-time-error rates (Δx^{d+1} vs Δx², Δx³) ✓.

## Findings

### 1. Notation page: the τ disambiguation points "below" but the integrating-factor row is above
- type: organization | severity: minor | confidence: high
- location: PAGE notation, "Derived scales" table, τ row: "in the integrating factor's row below, τ is a Runge–Kutta stage substep"
- The ℰ(κ) row that binds the substep sense of τ sits in the "Spectral representation and operators" table, which precedes "Derived scales" on the page. A reader sent "below" hunts in the Numerics/Forcing/Vocabulary tables and finds nothing. Wrong-direction pointer; the glyph-clash note itself is correct.
- hint: "row above", or name the table.

### 2. t_ℓ formula unparenthesized in the VarianceController docstring, parenthesized in the glossary
- type: typesetting | severity: nit | confidence: medium
- locations: PAGE api/Forcing, `VarianceController` `turnover_time` entry: "$t_\ell = 2k_\infty/3\varepsilon_\infty$"; PAGE notation, t_ℓ row: "$2k/(3\varepsilon)$"
- contradicts: the notation page's parenthesized form of the same formula — the axis is inline-division grouping.
- The docstring's slash form parses ambiguously (2k∞/3 times ε∞ vs 2k∞/(3ε∞)); the glossary's parenthesized form is unambiguous. Same quantity, two renderings; the ambiguous one is on the surface where a user copies the formula.

### 3. κ_min appears in the adaptive-step formula but is bound nowhere
- type: clarity | severity: minor | confidence: medium
- location: PAGE api/SimulationRun, `Simulation` `max_dt` entry: "the longest mode's diffusive-decay time $1/(D\kappa_{\min}^{2})$"
- The notation page has κ_Ny, κ_p, κ_max rows but no κ_min; the docstring does not define it either (presumably 2π/L, the fundamental). `advance!` cites the same bound by reference. Every other wavenumber symbol in the corpus is bound; this one is not. Dimensionally the formula is right.

### 4. Skewness aliasing: module summary says PhaseShift is "priced", the docstring says treat it as "not alias-controlled"
- type: contradiction | severity: minor | confidence: low
- locations: PAGE api/Observables, module docstring: "priced for the sharp truncations, unpriced for `HouLi`'s taper"; `derivative_skewness` docstring: "on either, treat the skewness as an indicator, not an alias-controlled measurement"
- contradicts: the module map's per-strategy summary — the axis is which strategies' cubic-aliasing residual is quantified.
- The module docstring groups PhaseShift with TwoThirds as "priced" (sharp truncations); the function docstring's closing "on either" groups PhaseShift with HouLi as an unquantified indicator. The two classifications of PhaseShift's standing do not read the same way, though a careful parse ("same kind of residual, larger band") can reconcile them.

### 5. PhaseShift "that top third of wavenumbers" overstates the recovered band
- type: physics | severity: nit | confidence: low
- location: PAGE api/SimulationDomain, `PhaseShift`: "Use it when that top third of wavenumbers is worth the price"
- The band the 2/3 rule discards is (2/3 → 1)κ_Ny; PhaseShift recovers only (2/3 → 0.943)κ_Ny — about 83% of that third, never the Nyquist-adjacent part. The precise numbers on the same page are all correct; only this framing sentence rounds the recovered band up to the whole third.

### 6. "Lateral" vs "transverse" for the same L22 relation
- type: contradiction | severity: nit | confidence: medium
- locations: PAGE notation, L11 row: "(the lateral is $L_{22} = L_{11}/2$)"; PAGE api/Observables, `integral_scale`: "The transverse integral scale is $L_{22} = L_{11}/2$"
- contradicts: one-symbol-one-concept discipline — the axis is the name of the L22 scale (value and formula agree exactly).
- Both words are standard in the literature, but the corpus's own convention is one term per concept; a cold reader may wonder whether lateral and transverse name two different scales that happen to share the value.

## Denominator
Candidates weighed before the cap: 13 (the 6 above plus 7 dismissed on verification —
the episode-ledger "half again" ratio (historical log entry, unverifiable), the 322.5 MiB frame
figure (layout-dependent, unverifiable), the G glyph double duty (explicitly flagged as deliberate
in the glossary), the Yaglom sign convention (correct as written), the C_OC convention pairing
(correct), the Home-page "CFL speed bound" wording (consistent across pages), and the ⟨φ²⟩
"variance for mean-zero φ" phrasing (qualified in place)). No truncation.

# Hat 08 — Dimensional analysis & normalization

Mechanical verification of every formula, factor, and normalization across the rendered site, and
of whether two pages state the same factor the same way.

**Verified clean (no finding):** the ½ in `kinetic_energy` and its absence in `scalar_variance`
(and `BandRescaling`'s explicit "½ only for the vector"); `ε = ν⟨|ω|²⟩ = 2ν⟨S_ijS_ij⟩`;
`ε_φ = 2ϰ⟨|∇φ|²⟩` (all four statements identical); the Dirichlet-form routes
`⟨|ω|²⟩ = ⟨û,|κ|²û⟩` and `⟨|∇φ|²⟩ = ⟨φ,|κ|²φ⟩`; the integrating-factor exponent
`exp((A − D|κ|²)τ)` and its parameter form `coefficient = −Dτ, offset_scale = τ` (five statements,
all consistent, sign correct); the RK3 coefficients (Σd = 1, c cumulative from d, all check);
IFRK2's `|R(iy)|² = 1 + y⁴/4`; the skewness constant `C_S = (4/7)√(15/2) ≈ 1.5649` — verified
against **both** stated isotropy relations `⟨trS³⟩ = (105/8)⟨(∂₁u₁)³⟩` and `⟨S:S⟩ = (15/2)⟨(∂₁u₁)²⟩`,
which are themselves consistent with Betchov's `⟨SSS⟩ = −(3/4)⟨ωωS⟩` and `⟨ωωS⟩ = −(35/2)⟨(∂₁u₁)³⟩`;
`L₁₁ = (3π/4)∫(E/κ)/∫E`, `L_E = (π/2)(…) = (2/3)L₁₁ = (1/3)(L₁₁+2L₂₂)` — derived independently from
`R_ii(r) = 2∫E sin(κr)/(κr) dκ`, exact; the phase-shift cutoff `(√2/3)N·2π/L = (2√2/3)κ_Ny ≈ 0.94 κ_Ny`,
`√2` wider than 2/3, `2.8×` the modes — identical in all six places it appears; `κ_max = f(N/2)(2π/L)`
with `f ∈ {2/3, 1, 2√2/3}` and `κ_maxΔx = fπ`; `κ_maxη = 2 ⇒ Δx ≈ η` and `Re_λ ~ N^{2/3}`
(both re-derived); the alias condition `2κ_max < N`; HouLi `strength = −log(eps)` ≈ 36 / 16;
Yaglom's `−(2/3)ε_φ r` (the half-vs-full-variance conversion is **correct** — re-derived from the
Kármán–Howarth–Monin analogue); `ζ_p` for K62 and She–Lévêque (both give ζ₃ = 1); Pope/von Kármán/Pao
roll-offs and their low-κ slopes σ = 2 / σ = 4; `C₂ = 2.0` ↔ `C_K = 1.5` (mutually consistent via
C₁ = (18/55)C_K, C₂ = 4.02 C₁); Obukhov–Corrsin's dimensions; every memory figure
(384 / 768 / 322.5 MiB, 2.3 GiB, 6 = 4 spectral + 2 physical, 10 before) and every transform cell
(18/9, 21/18, 36/18, 42/36, and 51 → 42, 34 → 28).

---

## 1. `Li2008`: the three numbers the docstring supplies do not satisfy the identity it supplies

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations**

- PAGE: api / phenomenology / Scalings, `Li2008`:
  > "exactly related by $G = \tfrac{3}{2} C_\varepsilon^{-2/3}$ … ($L/L_{11} \approx 5$)"
- Same docstring, two lines earlier:
  > "$G = \frac{k}{(L\varepsilon)^{2/3}} \approx 0.9$" and "$C_\varepsilon \approx 0.5$"

**Description**

`G ∝ L^{-2/3}`, so converting the integral-scale group to the box-side group gives
`G(L) = (3/2)·C_ε^{-2/3}·(L₁₁/L)^{2/3}`. With the docstring's own `C_ε = 0.5` and `L/L₁₁ = 5`
this yields `G = 1.5 × 1.5874 × 0.3420 = 0.814`, not the quoted `0.9` (10 % off). Consistency
would need `L/L₁₁ ≈ 4.3`. The passage is offered precisely to let a reader check the two groups
against each other, so the numbers should close.

**resolution_hint:** either quote `L/L₁₁ ≈ 4.3`, or say the conversion is order-of-magnitude only.

---

## 2. The advective-CFL derivation: the √3 component-vs-speed gap is not absorbed by 0.83 → 0.5

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations**

- PAGE: api / Propagator, `recommended_cfl`:
  > "$y_{\mathrm{s}} = \sqrt{3}$ gives $C \lesssim 0.83$, taken conservatively as $0.5$"
- Same docstring:
  > "within a factor $\sqrt{3}$ of $\sup\lvert\boldsymbol{u}\rvert$); that gap is absorbed by the conservative factor below"

**Description**

`C ≲ 0.83` is `y_s/(κ_maxΔx) = √3/(2π/3)` computed with `sup|u|`, i.e. with **no** allowance for the
√3 gap. Carrying the gap requires `C ≤ 0.83/√3 = 0.478`. The stated drop to `0.5` is a factor
1.66 < √3 = 1.732, so the conservative factor alone does **not** absorb it; only the second reason
given (the loose eigenvalue bound) does. As written the arithmetic invites the reader to check it
and it fails by 4.6 %.

**resolution_hint:** attribute the margin to the loose spectral-radius bound alone, or quote 0.48.

---

## 3. "Caching costs nothing on any axis" versus the recorded +1 pass per iteration

- **type:** performance
- **severity:** minor
- **confidence:** medium

**Locations**

- PAGE: api / Propagator, `deposit!`:
  > "so an iteration's transform and pass counts are unchanged by caching"
- PAGE: observables_cache, §1.4:
  > "It costs nothing, on any of the three axes."
- PAGE: architecture, §11 decision (2026-08, deposit-driven cache):
  > "+1 physical-vector pass in every cell; a hand-fixed-$\Delta t$ iteration still pays it"

**contradicts:** the traffic (pass) count per iteration.

**Description**

The architecture records that widening the audited model to the iteration surfaces a once-per-iteration
maximum-speed pass in **every** cell, held by a named `UNIFORM DEPOSIT SCHEDULE` holder, and that a
fixed-Δt run pays it without needing it. The cache page and `deposit!` both assert the pass count is
unchanged and the design costs nothing on any axis, exempting only one extra closing deposit *per run*.

**resolution_hint:** name the max-speed pass as the per-iteration exception on the cache page.

---

## 4. `C` is bound to two different constants — the CFL ceiling and the skewness isotropy constant

- **type:** typesetting
- **severity:** minor
- **confidence:** high

**Locations**

- PAGE: architecture, §4.3:
  > "$3C\langle\det\boldsymbol{S}\rangle/\langle\boldsymbol{S}:\boldsymbol{S}\rangle^{3/2}$ with the exact isotropy constant $C_S$"
- PAGE: notation, Numerics table:
  > "$C$ | advective-CFL ceiling … (the derivative-skewness isotropy constant wears the subscripted $C_S$)"

**contradicts:** which quantity the bare glyph `C` denotes.

**Description**

The glossary explicitly reserves the bare `C` for the CFL ceiling and states that the skewness constant
is the subscripted `C_S`. §4.3 (a current-state section) and decision 17 both write the skewness formula
with a bare `3C⟨det S⟩/…` and then name the constant `C_S` in the very same sentence — one symbol for two
concepts, and the formula's own symbol not the one that is defined. The `derivative_skewness` docstring
gets it right (`C_S` throughout).

**resolution_hint:** write `3C_S⟨det S⟩/…` in §4.3 and decision 17.

---

## 5. `peak_wavenumber` is documented as not being the peak, and is separately reused as `1/L₁₁`

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations**

- PAGE: api / State, `random_solenoidal_velocity!`:
  > "peaks at $\kappa_p/\sqrt{2}$, not at $\kappa_p$ itself"
- PAGE: api / SimulationRun, `Simulation`:
  > "its integral scale set to `1/peak_wavenumber`"

**Description**

The keyword named `peak_wavenumber` is, by the docs' own statement, a √2 factor away from the spectral
peak it names; the same number is then used unchanged as the model spectrum's integral scale `L₁₁ = 1/κ_p`
when `initial_spectrum` is passed. So one option carries two distinct meanings differing by √2, and neither
is the peak. A physicist reading "peak wavenumber = 2" will place the peak at κ = 2; the default puts it
at 1.41.

**resolution_hint:** rename to `envelope_wavenumber` (it is a Gaussian width, not a peak), or state the
√2 in the keyword table too.

---

## 6. `max_wavenumber`: "the modes above it are zeroed each step" is false for `HouLi`

- **type:** physics
- **severity:** nit
- **confidence:** high

**Locations**

- PAGE: api / SimulationDomain, `max_wavenumber`:
  > "It is the cutoff the dealiasing sets … the modes above it are zeroed each step."
- PAGE: api / SimulationDomain, `HouLi`:
  > "only damps aliasing rather than removing it exactly — a stabilization"

**contradicts:** whether super-cutoff modes are set to zero or attenuated.

**Description**

For `HouLi` the retained-Nyquist fraction is `f = 1`, so `κ_max = κ_Ny`; the cube's corner modes out to
`√3 κ_Ny` are *damped* by `exp(−strength(κ/κ_Ny)^order)`, not zeroed, and the Nyquist mode itself survives
at `e^{−strength} ≈ eps`. The absolute quantifier "zeroed" holds only for the two sharp strategies. Both
`HouLi` and `dealias!` state the weaker, correct claim.

**resolution_hint:** "zeroed (or, for `HouLi`, damped to machine epsilon)".

---

## 7. `E(κ)` is one glyph for two dimensionally distinct quantities

- **type:** dimensional
- **severity:** minor
- **confidence:** medium

**Locations**

- PAGE: notation, Diagnostics table:
  > "as measured, the energy in each wavenumber-magnitude shell … as a Phenomenology model, the spectral density per unit wavenumber"
- PAGE: api / SimulationRun, `validate_spectrum`:
  > "the density is multiplied by the shell width $\Delta\kappa = 2\pi/L$ before comparison"

**Description**

The measured `E(κ)` has the dimension of an energy (L²T⁻²) and the model `E(κ)` that of a density
(L³T⁻²); they differ by a length. The glossary — whose own rule is one symbol per concept — binds both
to `E(κ)` and only annotates the difference. Every reference formula (`C_Kε^{2/3}κ^{-5/3}`,
`∫E/κ dκ`, `k = ∫E dκ`) is written for the density; every measured statement (`k = Σ_κ E(κ)`,
the `energy_spectrum` return) for the per-shell energy. This is exactly the "spectral density versus
energy" category error the doc policy names, made survivable only by a footnote.

**resolution_hint:** distinguish the measured one (e.g. `Ê_shell(κ)` or `E_n`) in the glossary row.

---

## 8. Pointwise-kernel cost: ten flops paired with twenty-four bytes describes two different kernels

- **type:** performance
- **severity:** nit
- **confidence:** medium

**Locations**

- PAGE: observables_cache, §1.1:
  > "a pointwise multiplication … costs about ten arithmetic operations per point against twenty-four bytes moved"
- PAGE: observables_cache, §2.3:
  > "a pointwise multiplication of order ten"

**Description**

24 bytes is a scalar pointwise multiply in double precision (2 reads + 1 write), which costs **one**
flop, not ten. Ten flops is the count for a three-component kernel (a cross product is ≈ 9–15 flops),
which moves 72 bytes. The pair as written overstates the arithmetic by 10×. The conclusion drawn
(bandwidth-bound) survives either way — the overstatement is conservative — but the figure itself is
wrong for the operation named.

**resolution_hint:** either "one flop against twenty-four bytes", or name the vector kernel and use 72 bytes.

---

## 9. `2.51 GiB` should be `2.52 GiB`

- **type:** dimensional
- **severity:** nit
- **confidence:** high

**Locations**

- PAGE: architecture, §11 decision 36 (frame ledger):
  > "322.5 MiB at $256^{3}$ in double precision … and 2.51 GiB at $512^{3}$"

**Description**

The frame scales as `N³`, so `512³` is 8× `256³`: `322.5 MiB × 8 = 2580 MiB = 2.5195 GiB`, which rounds
to `2.52`, not `2.51`. A truncation rather than a rounding. Trivial in itself, but the frame ledger's
whole point is that its numbers are audited.

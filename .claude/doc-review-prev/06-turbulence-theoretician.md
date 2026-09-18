# Turbulence theoretician — rendered-docs review (2026-08-23)

Hat: turbulence-theoretician. Substrate: `manuscript-full.md` (the whole rendered site incl. design docs). Verified-clean before flagging: the Betchov skewness constant C_S = (4/7)√(15/2) and its 105/8, 15/2 expansion; the L11 / L_E = (2/3)L11 spectral integrals; Yaglom's −(2/3)ε_φ r under the full-variance convention; the Obukhov–Corrsin constant's convention-invariance; Li2008's G = (3/2)C_ε^{−2/3} and the 0.81-vs-0.9 cross-check; the Pope/von Kármán/Pao roll-off forms and the ℓ₀-vs-L11 0.42k/0.57k numbers; the CFL calibration 0.83→0.5 with y_s = √3; the controller's dk/dt = −G(k−k∞)/t_ℓ balance and ConstantPower's A = P/(2E_band); the mask/PhaseShift transform table (18/9, 21/18, ×2); the HouLi 31% Re_λ and Re_λ ∼ N^{2/3} scalings; the epoch arithmetic (1+2+1 = 4); the 2/3-rule alias-free condition 2κ_max < N. Candidates considered before the cap: 20.

---

## 1. Architecture §4.1 states the default dealiasing as "the sharp 3/4 rule" — everywhere else it is the 2/3 rule
- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE architecture, §4.1 (SimulationDomain bullet): "the dealias kernel of the run's chosen strategy (the sharp $3/4$ rule by default)"
  - PAGE Home, "What it solves": "dealiased by the default $2/3$ rule"
- **contradicts**: also architecture §4.2 "dealiased by the $2/3$ rule", §7 "the rotational form + spherical $2/3$ stays the lean default", and api/SimulationRun `dealiasing = TwoThirds()`. Axis: which fraction the default sharp truncation keeps.
- **description**: No "3/4 rule" exists anywhere in the package or the literature cited; the default is `TwoThirds` on every other surface, including the constructor signature. A reader of the spec's own module section is told the wrong default cutoff. Presumably a typo (digits of 2/3 scrambled), but it is a wrong physical statement about which modes are retained.
- **resolution_hint**: change to "the sharp $2/3$ rule by default".

## 2. The scalar appears as ⟨θ²⟩ in architecture §4.7 — the document's own invariant §9 says "never θ"
- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE architecture, §4.7 (StationarityCriterion bullet): "When the scalar is forced, $\langle\theta^2\rangle$ must settle too"
  - PAGE architecture, §9: "The scalar is denoted $\varphi$, never $\theta$ — in code, mathematics, and prose."
- **contradicts**: the decision-log warm-up entry states the identical fact with the house glyph: "When the scalar is forced, $\langle\varphi^2\rangle$ must flatten too". Axis: the symbol for the passive scalar.
- **description**: One quantity, two symbols two sections apart, with the deviant one violating an invariant stated in the same document. A cold reader could take θ for a second scalar (e.g. temperature) distinct from φ.

## 3. Stale synchronization counts: `add_forcing_source!` claims "three per stage" for the controller, and `VarianceRescaling` "two under :total" — the fused multi-weight reduction already collapsed both
- **type**: contradiction · **severity**: major · **confidence**: high
- **locations**:
  - PAGE api/Forcing, `add_forcing_source!`: "three per stage for `VarianceController`, one for `ConstantPower`"
  - PAGE decisions, the 2026-08-23 PF-delivery entry: "the default row fell 10 → 4 crossings (one fused reduction per stage plus the $\Delta t$ choice)"
- **contradicts**: same entry: "Wired at every same-field multi-reduction site: `VarianceController` (three weights per stage — …), `VarianceRescaling`'s `:total` pair". Second instance: api/Forcing `VarianceRescaling`: "each step blocks on a device-to-host transfer — two under `:total`". Axis: the per-stage / per-step blocking-readback count of the shipped code.
- **description**: After the multi-weight `weighted_inner` wiring, the controller pays one fused readback per stage (not three) and the `:total` rescale's pair is one traversal and one readback (not two). Both docstrings still quote the pre-fusion counts as present-tense costs — a "current & complete" failure on a user-facing cost claim that steers forcing choice.

## 4. Decision log: "$S$ runs from $0$ toward $\approx -0.05$" — an order-of-magnitude-wrong skewness value
- **type**: physics · **severity**: major · **confidence**: high
- **locations**:
  - PAGE decisions, the (2026-07) warm-up entry: "against the $\lvert S\rvert \approx 0.5$ of a developed cascade ($S$ runs from $0$ toward $\approx -0.05$)"
- **contradicts**: the same sentence's "$\lvert S\rvert \approx 0.5$", and `derivative_skewness` / `StationarityCriterion` ("only a developed cascade reaches $S \approx -0.5$"). Axis: the developed-cascade value of the derivative skewness.
- **description**: The parenthetical says the skewness develops toward −0.05; the established value (asserted three words earlier and on every other surface) is −0.5. This is a numeric error, not a superseded API, so append-only history does not shield it: a reader calibrating `skew_floor` against this entry would set a gate an order of magnitude too loose.

## 5. `PhaseShift` cites "Rogallo (1984)" for NASA TM-81315 — every other surface (and the memorandum itself) says 1981
- **type**: citation · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE api/SimulationDomain, `PhaseShift`: "the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315"
  - PAGE decisions, §References: "Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315."
- **contradicts**: also decision 27's inline "(… Patterson & Orszag 1971, Rogallo 1981)". Axis: the year of the same report.
- **description**: TM-81315 is the 1981 memorandum; the docstring's 1984 is wrong and disagrees with the package's own bibliography. An author-year handle is load-bearing in this corpus (the `Phenomenology` naming scheme), so a wrong year is worth fixing even on a DNS-side surface.

## 6. Divergence "damped only by $\exp(+\nu\kappa^{2}\Delta t)$" — the viscous factor's sign is inverted
- **type**: physics · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE decisions, the (2026-08) re-projection entry: "whose divergence … is damped only by $\exp(+\nu\kappa^{2}\Delta t)$, nearly nothing at the largest scales"
- **contradicts**: `velocity_integrating_factor`: "$\mathcal{E}(\boldsymbol{\kappa}) = \exp\bigl((A(\boldsymbol{\kappa}) - \nu\lvert\boldsymbol{\kappa}\rvert^{2})\tau\bigr)$" (damping multiplier < 1). Axis: the sign in the viscous decay factor.
- **description**: A quantity damped over a step is multiplied by $\exp(-\nu\kappa^{2}\Delta t)$; as written the factor exceeds 1 and would amplify. The surrounding argument (weak damping at large scales) is right; the explicit factor carries the wrong sign.

## 7. Architecture §10 names "the $\tfrac{1}{3}$ in the energy" as a checked normalization — the energy's factor is $\tfrac{1}{2}$
- **type**: physics · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE architecture, §10 (the `/check-docs` bullet): "normalization checking (the $1/N$, the $2\varkappa$, the $\tfrac{1}{3}$ in the energy, Parseval factors)"
- **contradicts**: architecture §4.3 and notation: "$k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle$". Axis: which factor sits in the kinetic-energy definition.
- **description**: No ⅓ appears in any energy definition on the site; the checkable factors in the energy are the ½ of $k$ (or the 3/2 of $k = \tfrac{3}{2}u'^2$). The battery description names a normalization that does not exist, in the very sentence teaching what to check.

## 8. The `energy_spectrum` supersession note is appended to the wrong decision entry
- **type**: organization · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE decisions, end of the (2026-07) memory-audit entry: "(Superseded 2026-08-23 …: `energy_spectrum` now returns the density … so the seam this entry documents is gone …)"
  - PAGE decisions, the (2026-07) validation-harness entry: "`energy_spectrum` returns the per-shell energy $E_n$ … $E_n \approx E(\kappa_n)\,\Delta\kappa$"
- **contradicts**: axis: which entry documents the $E_n$-vs-$E(\kappa)$ seam. The memory-audit entry (ledgers, liveness bounds) documents no spectrum seam; the seam lives in the validation-harness entry, which carries no supersession note.
- **description**: Where it stands, "the seam this entry documents" is false — the host entry documents buffer ledgers. A reader of the validation-harness entry never learns its bin-sum convention was superseded; a reader of the memory-audit entry is told a seam it never described is gone.

## 9. Bin-sum vocabulary residue: "per-shell energy" survives where the corpus now says density
- **type**: clarity · **severity**: minor · **confidence**: medium
- **locations**:
  - PAGE observables_cache, §2.4 table: "$E_n$, the per-shell energy | per shell | no | — | not computed"
  - PAGE api/Observables, module map: "the energy spectrum reduces to a per-shell energy over wavenumber"
- **contradicts**: `energy_spectrum` docstring and notation: "the measured spectral density $E(\kappa)$ … directly comparable to a `Phenomenology` model spectrum with no conversion". Axis: what kind of object `energy_spectrum` yields (an energy per shell vs a density per unit wavenumber).
- **description**: After the density supersession, two surfaces still name the observable by the retired bin-sum object. The module-map phrase "per-shell energy over wavenumber" is at best ambiguous ("over the shell width" is what makes it a density); the §2.4 row plainly re-introduces $E_n$ the energy. This is the density-vs-energy category distinction the corpus itself enforces.

## 10. The §2.4 table breaks its own Built-column rule on the sample-history row
- **type**: contradiction · **severity**: minor · **confidence**: high
- **locations**:
  - PAGE observables_cache, §2.4 preamble: "Its Built column … reads `—` wherever Cached is not yes."
  - PAGE observables_cache, §2.4 table, sample-history row: "depends | yes | kept only when a multistep trajectory scheme asks for depth"
- **contradicts**: axis: the stated column convention vs the row's value. Cached = "depends", Built = "yes" — the rule demands "—".
- **description**: Either the rule needs a "depends" clause (the natural reading: the history is built today, when configured) or the row needs "—". As written the table disobeys the convention announced two sentences above it.

## 11. The MD-thermostat analogy places `VarianceController` beside Nosé–Hoover, but its law is exactly Berendsen's weak coupling
- **type**: method · **severity**: minor · **confidence**: low
- **locations**:
  - PAGE api/Forcing, `VarianceController`: "feedback inside the equations is the Nosé–Hoover move …, and gain-limited relaxation toward a target is Berendsen weak coupling"
- **contradicts**: same docstring: "$\mathrm{d}k/\mathrm{d}t = -G(k - k_\infty)/t_\ell$: the variance relaxes exponentially" — precisely the Berendsen relaxation law. Axis: which thermostat the controller is the analogue of.
- **description**: Nosé–Hoover adds an extended variable and delivers correct canonical fluctuations; the Bassenne controller is deterministic proportional feedback with no extended variable — Berendsen-class, whose known caveat (distorted fluctuations of the held quantity) the `Simulation` docstring does honestly admit ("a controlled variable's fluctuation"). The three-item list is individually correct, but its framing ("the mechanism is the one MD settled on") invites reading the controller as the Nosé–Hoover node rather than the Berendsen one.

## 12. "Its host-side random increment is the one allocation-free exception" — the phrase asserts the opposite of what it means
- **type**: clarity · **severity**: nit · **confidence**: medium
- **locations**:
  - PAGE architecture, §7 (StochasticOU bullet): "its host-side random increment is the one allocation-free exception (invariant 4)"
- **contradicts**: axis: none (a self-inverting phrase). The memory-audit entry states the fact correctly: "an OU-forced step is not allocation-free today".
- **description**: The increment is the one exception *to* allocation-free stepping (it allocates); "the one allocation-free exception" reads as an exception that is allocation-free. One preposition flips the claim about the archived forcing's hot-loop behaviour.

# Logician hat — definitions and arguments as formal objects

Substrate: `manuscript-full.md` (the rendered site, reader-text consolidation). Adjudicated list read first; nothing below re-flags an adjudicated item. Candidates weighed before the cap: 29.

---

## 1. "The sharp 3/4 rule by default" — one page, against the whole corpus
- **type**: contradiction · **severity**: blocker · **confidence**: high
- **Locations**: Architecture §4.1: "the dealias kernel of the run's chosen strategy (the sharp $3/4$ rule by default)". Home "What it solves": "dealiased by the default $2/3$ rule"; `scalar_rhs!`: "(the sharp $2/3$ rule by default)"; `FixedDomain` args: "`TwoThirds` (the sharp $2/3$ rule)".
- **Contradicts**: every other statement of the default; the axis is the default dealias fraction (3/4 vs 2/3).
- The default strategy is named `TwoThirds` throughout; §4.1's "3/4" is a wrong number in the spec document itself.

## 2. Decision 62's headline contradicts its own body
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: Decision log: "The `Simulation` keyword and field `scheme` → `integrator`." — the same entry's body: "The keyword family is now uniformly `<role>_scheme`: `integration_scheme`". `Simulation` page: "`integration_scheme = IFLowStorageRK3()`".
- **Contradicts**: itself and the API page; the axis is what the keyword was renamed *to* (`integrator` vs `integration_scheme`).
- A reader trusting the headline would look for a keyword `integrator` that does not exist.

## 3. Stale host-readback counts survive the fused multi-weight reduction
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: `add_forcing_source!`: "three per stage for `VarianceController`, one for `ConstantPower`". `VarianceRescaling`: "each step blocks on a device-to-host transfer — two under `:total`".
- **Contradicts**: decision log (PF request delivered): "the default row fell 10 → 4 crossings (one fused reduction per stage plus the $\Delta t$ choice)" and "`VarianceRescaling`'s `:total` pair" wired to the fused reduction. Axis: blocking transfers per stage/step after fusion.
- The docstrings still price the pre-fusion schedule the decision log says was retired.

## 4. `FixedDomain` "Nothing here defaults" vs an example calling it with one keyword
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: `FixedDomain`: "All keyword, all required" and admonition "Nothing here defaults". `DeferredForcing` example: "`domain = FixedDomain(; grid_points_per_axis = 64)`".
- **Contradicts**: the axis is whether `side_length`, `dealiasing`, `element_type`, `array_type` are required. Under the stated contract the example cannot run.

## 5. Inconsistent rule pair: "$\varphi$, never $\theta$" — and a $\theta$ in the same document
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: Architecture §9: "The scalar is denoted $\varphi$, never $\theta$ — in code, mathematics, and prose." Architecture §4.7: "When the scalar is forced, $\langle\theta^2\rangle$ must settle too".
- **Contradicts**: the invariant and its violation, three sections apart in the document that states the rule as binding.

## 6. One sentence gives the developed-cascade skewness two values
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: Decision log (warm-up entry): "against the $\lvert S\rvert \approx 0.5$ of a developed cascade ($S$ runs from $0$ toward $\approx -0.05$)".
- **Contradicts**: itself; the axis is the asymptotic value (−0.5 vs −0.05). Every other page (e.g. `derivative_skewness`: "$S \approx -0.5$") gives −0.5.

## 7. "`deposit!` fills every slot" vs "the particle-velocities slot is not among them"
- **type**: contradiction · **severity**: major · **confidence**: high
- **Locations**: Cache module docstring: "The solver's side of the contract is that `deposit!` fills every slot at the iteration's end and sets its epoch." `deposit!` docstring: "The particle-velocities slot is not among them".
- **Contradicts**: axis is which verb fills the particle slot (`deposit!` vs `record_particle_velocities!` + `deposit_sample!`). For a tracered run the module's universal contract is false as stated; only the `deposit!(sim)` form does the record for the caller.

## 8. The §2.4 table violates its own column legend
- **type**: contradiction · **severity**: minor · **confidence**: high
- **Locations**: observables_cache §2.4: "Its Built column … reads `—` wherever Cached is not yes." Same table, sample-history row: "depends | yes".
- **Contradicts**: the legend and the row; the axis is what Built may read when Cached = depends. Either the legend's rule or the row is wrong.

## 9. The zero-cost design choice is absolute in §1.1, excepted in §1.4, and circular for its one number
- **type**: contradiction (with a circularity core) · **severity**: major · **confidence**: medium
- **Locations**: observables_cache §1.1: "Caching an observable adds nothing to what an iteration computes, moves, or stores." §1.3: "The reduction inside every other closing deposit … is work the following first stage would have done anyway". §1.4: "one physical-vector pass every iteration, paid even by a hand-fixed-$\Delta t$ run that never reads the number".
- **Contradicts**: §1.3's unconditional "would have done anyway" against §1.4's fixed-$\Delta t$ exception; and §1.1's absolute choice against §1.4's "with one exception". Deeper: §1.2's "Computed — some component must produce it anyway" test is satisfied for `max_speed` under fixed $\Delta t$ only because the cache's own fixed schedule produces it — the test's premise is supplied by the design it is meant to derive, so for that slot the derivation cannot fail (the `UNIFORM DEPOSIT SCHEDULE` holder prices the cost honestly, but the four-test derivation is presented as unconditional).

## 10. Rogallo dated 1984 in one docstring, 1981 everywhere else
- **type**: citation · **severity**: minor · **confidence**: high
- **Locations**: `PhaseShift`: "the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315". Architecture §References: "Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315."; decision 27: "Rogallo 1981".
- **Contradicts**: same memorandum, two years; the axis is the publication year.

## 11. $\tau$ carries two senses on the notation page that fixes "one symbol per concept"
- **type**: contradiction (equivocation) · **severity**: minor · **confidence**: high
- **Locations**: Notation, Derived scales: "$\tau$ | eddy-turnover time, $k/\varepsilon$". Notation, Spectral operators ($\mathcal{E}$ row): "over an interval $\tau$ — a Runge–Kutta stage substep"; the generator protocol uses `τ` as the substep argument.
- **Contradicts**: the page's own charter ("The page above fixes one symbol per physical concept") and its own precedent — $G$'s dual use gets an explicit "two unrelated constants wear this glyph" note; $\tau$'s does not.

## 12. "Opportunistic, never load-bearing" vs the documented quiet-wrongness case
- **type**: contradiction · **severity**: minor · **confidence**: medium
- **Locations**: `ResolvedGenerator` admonition: "It is opportunistic, never load-bearing: a `scalar_rhs!` handed a different `û` … rebuilds … value-identically." `scalar_rhs!`: "a false promise over the same container is quietly wrong".
- **Contradicts**: axis is whether the reuse contract can produce a wrong result. The record half can only force a rebuild, but the keyword half is, by `scalar_rhs!`'s own words, "the load-bearing half" — so the unqualified "never load-bearing" safety claim on the type page overstates what only holds when the caller's promise is truthful.

## 13. "The declaration is measured at construction, not trusted" — no observation could refute a false one
- **type**: contradiction (unfalsifiable claim + non sequitur) · **severity**: minor · **confidence**: medium
- **Locations**: `AbstractForcing`: "The declaration is measured at construction, not trusted." `ResolvedGenerator` admonition (the only construction check described): rejects "a forcing that implements `set_forcing_rate!` without also declaring". `set_forcing_rate!`: "the default method is never reached in a run".
- **Contradicts**: steadiness-in-time cannot be measured at a single construction instant; the documented guard checks the implements↔declares pairing, not steadiness, so a state-dependent rate that *declares* steady is refuted by nothing at construction. And "never reached in a run" does not follow: a strategy declaring `true` without implementing the hook IS handed a rate array and falls to the default.

## 14. "Iteration" and "closing deposit" defined differently across pages
- **type**: contradiction (equivocation) · **severity**: minor · **confidence**: medium
- **Locations**: Home: "One ITERATION is one advance: a step, then the DEPOSIT that closes it." Notation vocabulary: "iteration | … choose the timestep, step! the fields, deposit! to close them, then advance any tracers and record their sample"; same table, deposit entry: "The closing deposit is the one that ends an iteration".
- **Contradicts**: axis is the iteration's extension: Home's two-part definition omits the timestep choice, push, and sample the vocabulary includes; and "the closing deposit … ends an iteration" is inconsistent with the tracer push and sample deposit occurring *after* it yet *inside* the iteration on the vocabulary's own ordering.

## 15. `ModelSpectrum` names a `ref` field its constructor and Fields section do not have
- **type**: contradiction · **severity**: minor · **confidence**: medium
- **Locations**: `ModelSpectrum`: "`ref` is its `Reference`" — but "The (sole, positional) constructor above takes the three fields directly" listing only `C_K`, `large_scale`, `dissipation`.
- **Contradicts**: the prose asserts a fourth constituent the sole constructor cannot supply and the Fields section does not list; either `ref` exists (Fields incomplete, constructor not sole) or it does not (prose wrong).

## 16. "The $\tfrac{1}{3}$ in the energy" — a checked normalization matching no formula on the site
- **type**: contradiction · **severity**: minor · **confidence**: medium
- **Locations**: Architecture §10 (`/check-docs` battery): "the $1/N$, the $2\varkappa$, the $\tfrac{1}{3}$ in the energy, Parseval factors". Notation/Observables: "$k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle$".
- **Contradicts**: every energy definition on the site carries $\tfrac{1}{2}$ (or the $\tfrac{3}{2}$ of $k = \tfrac{3}{2}u'^2$); no $\tfrac{1}{3}$ appears in any energy formula, so the battery's example names a factor its own corpus never uses.

## 17. A supersession note appended to the wrong decision entry
- **type**: organization · **severity**: minor · **confidence**: medium
- **Locations**: Decision log, the memory-audit entry (frozen buffer ledger / liveness bound) closes with "(Superseded 2026-08-23, owner-directed: `energy_spectrum` now returns the density … so the seam this entry documents is gone …)".
- **Contradicts**: the entry it closes documents ledgers and liveness bounds — no spectrum seam; the "$E_n$ vs density" seam is documented by the *validation-harness* entry ("the two sides are not the same kind of object and the comparison must convert"). The note's "this entry" fails to refer.

## 18. One quantity, two names across a constructor and its Fields: `turnover_time` vs `relaxation_time`
- **type**: contradiction (equivocation) · **severity**: nit · **confidence**: medium
- **Locations**: `VarianceController` signature: "`turnover_time = nothing`"; Fields: "`target`, `gain`, `relaxation_time` — $k_\infty$, $G$ and $t_\ell$".
- **Contradicts**: the same $t_\ell$ enters under one name and is stored under another, with the renaming nowhere remarked — against the corpus rule that a field "holds the value documented for the keyword of the same name".

## 19. `valid_Reλ` is a guard that discriminates nothing, yet a safety argument leans on it
- **type**: contradiction (vacuous discrimination) · **severity**: minor · **confidence**: low
- **Locations**: `Reference`: "it is advisory: a comparison that opts in reads it, nothing enforces it." `Lundgren2002` admonition: "the law's `provenance` records a validity floor of $\mathrm{Re}_\lambda = 50$; a comparison that honours `valid_Reλ` never evaluates it in the region where the sign flips."
- **Contradicts**: the Lundgren admonition presents the recorded floor as what keeps the wrong-sign region unreached, but by `Reference`'s own contract the floor excludes nothing — the protection is entirely the caller's opt-in, so the recorded floor by itself discriminates no evaluation. The conditional ("that honours") is literally true; the rhetorical weight ("This is why…") is carried by a guard defined not to guard.

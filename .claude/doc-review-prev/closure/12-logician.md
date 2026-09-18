# Closure audit — 12-logician

Blind adjudication against the current corpus only (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`, `CLAUDE.md`). No `.claude/` file other than the banked hat file was read; no `closure*` directory was consulted.

---

## 1. "The sharp 3/4 rule by default" — one page, against the whole corpus
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md:189` and `docs/src/architecture.md:189` now read "the sharp ``2/3`` rule by default", matching `Generator.jl:613`, `SimulationDomain.jl:47,162`, and `observables_cache.md`. Grepped `3/4` corpus-wide (excluding `.claude/`) — only hit is an unrelated RK abscissa `c = (0, 1/3, 3/4)` in `Propagator.jl:250`. No dealiasing-default "3/4" survives.

## 2. Decision 62's headline contradicts its own body
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md:2039` decision 62 headline now reads "The `Simulation` keyword and field `scheme` → `integration_scheme`", matching its own body and `SimulationRun.jl` (`integration_scheme` used throughout, e.g. lines 214, 271, 295–296, 352, 407, 565) and `docs/src/decisions.md:1141`. No stray `integrator` keyword claim found.

## 3. Stale host-readback counts survive the fused multi-weight reduction
**VERDICT: ABSENT**
`Forcing.jl:261`: "Measuring the state costs one blocking device-to-host transfer **at every stage** — a single fused multi-weight reduction answers `VarianceController`'s three weighted sums together". `Forcing.jl:366` (`VarianceRescaling`): "each step blocks on one device-to-host transfer: the band and whole-field observables ride a single fused traversal, in either mode." Both now match the decision log's fused-reduction claim; no "three per stage" / "two under :total" text remains.

## 4. `FixedDomain` "Nothing here defaults" vs an example calling it with one keyword
**VERDICT: ABSENT**
The `DeferredForcing` example (`Forcing.jl:163-164`) now calls `FixedDomain(grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(), element_type = Float64, array_type = Array)` — all five required keywords present, runnable under the "all keyword, all required" / "Nothing here defaults" contract (`SimulationDomain.jl:159,184`).

## 5. Inconsistent rule pair: "φ, never θ" — and a θ in the same document
**VERDICT: ABSENT**
Grepped `\theta|θ` across `docs/ARCHITECTURE.md`, `docs/src/*.md`, `src/*.jl`. Only two hits, both the rule statement itself: `ARCHITECTURE.md:838` ("never ``\theta``") and `notation.md:32` ("never ``\theta``"). §4.7's `⟨θ²⟩` no longer exists.

## 6. One sentence gives the developed-cascade skewness two values
**VERDICT: ABSENT**
`ARCHITECTURE.md:947` (warm-up entry) now reads "``S`` runs from ``0`` toward ``\approx -0.5``", matching `derivative_skewness` (§331: "``S \approx -0.5``") and `notation.md:78`. No "-0.05" skewness value found anywhere (grep hits for `-0.05`/`0.05` are unrelated warm-up `tol`/`skew_floor` parameters).

## 7. "`deposit!` fills every slot" vs "the particle-velocities slot is not among them"
**VERDICT: ABSENT**
`Cache.jl:36`: "The solver's side of the contract is that `deposit!` fills every **field-derived** slot at the iteration's end (the particle-velocities slot has its own pair of verbs, recorded below) and sets its epoch." The universal claim is now explicitly qualified with the exact carve-out `Propagator.jl:521` states.

## 8. The §2.4 table violates its own column legend
**VERDICT: ABSENT**
`observables_cache.md` §2.4 legend now reads: "Its **Built** column says whether the package holds the observable today, and reads `—` wherever *Cached* is *no* or *never* … (a *depends* row is built whenever its configuration asks for it)." This explicitly reconciles the legend with the sample-history row (`depends | yes`).

## 9. The zero-cost design choice is absolute in §1.1, excepted in §1.4, and circular for its one number
**VERDICT: PRESENT**
§1.1 (`observables_cache.md:38`) still states the unqualified design choice as a blockquote: "Caching an observable adds nothing to what an iteration computes, moves, or stores." §1.3 (line 154) still says, unconditionally, "is work the following first stage would have done anyway (§1.4)" — a bare forward-reference, not a qualification in the sentence itself. §1.4 (line 198) still carries the exception verbatim: "with one exception — nothing on the traffic axis: the closing deposit's maximum-speed reduction is one physical-vector pass every iteration, paid even by a hand-fixed-``\Delta t`` run that never reads the number." No sentence in §1.1/§1.2 acknowledges that the "Computed" test's own premise (§1.2, "some component must produce it anyway") is supplied by the cache's own fixed schedule for `max_speed` under fixed ``\Delta t`` — the circularity is unaddressed. The three original quotes remain textually intact.

## 10. Rogallo dated 1984 in one docstring, 1981 everywhere else
**VERDICT: ABSENT**
`SimulationDomain.jl:114` (the `PhaseShift` docstring) now reads "Rogallo (1981) — *Numerical experiments in homogeneous turbulence*, NASA TM-81315 (no DOI)", matching `ARCHITECTURE.md:2110`, `decisions.md:1212`, and `decisions.md:246`. Grepped `1984` corpus-wide — the only hits are the unrelated Nosé (1984) / Berendsen (1984) MD citations.

## 11. τ carries two senses on the notation page that fixes "one symbol per concept"
**VERDICT: ABSENT**
`notation.md:92` now carries the explicit disambiguation the finding demanded: "Two unrelated quantities wear this glyph: in the integrating factor's row below, ``\tau`` is a Runge–Kutta stage substep, the generator protocol's argument" — the same treatment as the `G` precedent the finding cited.

## 12. "Opportunistic, never load-bearing" vs the documented quiet-wrongness case
**VERDICT: PRESENT**
`Generator.jl:309` (`ResolvedGenerator` admonition) still reads, verbatim: "It is opportunistic, never load-bearing: a `scalar_rhs!` handed a different `û` … rebuilds … value-identically." `Generator.jl:635-636` (`scalar_rhs!`) still reads: "the keyword is the load-bearing half — containers are rewritten in place, so a false promise over the *same* container is quietly wrong." Both sentences are textually unchanged from the finding's quotes; the type-page safety claim still overstates what only holds when the caller's keyword promise is truthful.

## 13. "The declaration is measured at construction, not trusted" — no observation could refute a false one
**VERDICT: ABSENT**
The mechanism changed since the finding was banked: `Generator.jl`'s `_check_rate_is_steady` (called from `_forcing_rate`, wired into `ResolvedGenerator`'s constructor at lines 372-374) now genuinely probes `set_forcing_rate!` twice, with two different field states (all-ones, then a spatially varying ramp), and throws unless the two returned rates agree — a real measurement of state-independence, not merely a check of the implements/declares pairing. `Generator.jl:180-184` also now throws when a forcing declares `uses_steady_linear_rate = true` but does not implement the hook, closing the "declares without implementing" gap the finding flagged — so `set_forcing_rate!`'s "the default method is never reached in a run" (`Forcing.jl:189`) is now literally enforced, not a non sequitur. (Note: the `ResolvedGenerator` docstring admonition itself, `Generator.jl:297-303`, still describes only the implements-without-declaring direction and is stale relative to the fuller code-level guard — but that is a completeness gap in a different finding's territory, not the falsifiability contradiction this finding named.)

## 14. "Iteration" and "closing deposit" defined differently across pages
**VERDICT: PRESENT**
`docs/src/index.md:104` (Home) still gives the two-part definition: "one advance of the run: a step plus the deposit that closes it" — omitting the timestep choice, tracer push, and sample that `notation.md:127`'s iteration entry includes ("choose the timestep, `step!` … `deposit!` … then advance any tracers and record their sample"). `notation.md:128` still asserts "The closing deposit is the one that ends an iteration," but corpus-wide usage (`SimulationRun.jl:567`: "The closing deposit: fill every slot… the tracer push then completes its Heun pair… completing the iteration's deposits"; `ARCHITECTURE.md:480`: "the closing `deposit!`") consistently uses "closing deposit" for `deposit!`, which the run's own code (`SimulationRun.jl:571-580`) executes *before* `advect!` and `deposit_sample!` — i.e. before the iteration actually ends. The inconsistency is unchanged.

## 15. `ModelSpectrum` names a `ref` field its constructor and Fields section do not have
**VERDICT: ABSENT**
`src/phenomenology/Spectra.jl:290-323` now carries an explanatory comment ("The `Reference` is NOT a field. It is a property of the parametrization…") directly above the `ModelSpectrum` docstring, and the docstring's `# Fields` section (line 320-323) lists only `C_K`, `large_scale`, `dissipation` — no `ref` is asserted anywhere in the docstring text. `provenance(m::ModelSpectrum)` (line 336) computes the reference from the type pair rather than storing it.

## 16. "The 1/3 in the energy" — a checked normalization matching no formula on the site
**VERDICT: ABSENT**
`ARCHITECTURE.md:894` and `CLAUDE.md:271` now both read "the ``\tfrac{1}{2}`` in the energy", matching `notation.md`'s ``k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^2\rangle``. No "1/3" energy-normalization example remains.

## 17. A supersession note appended to the wrong decision entry
**VERDICT: ABSENT**
The "(Superseded 2026-08-23, owner-directed: `energy_spectrum` now returns the density…)" note is now attached to decision 19 (`ARCHITECTURE.md:994-1003`), the validation-harness entry that itself states "The two sides are not the same kind of object and the comparison must convert: `energy_spectrum` returns the per-shell energy ``E_n``, a model returns the density ``E(\kappa)``…" — exactly the entry the note's content refers to. The memory-audit entries (decisions 33, 36, `ARCHITECTURE.md:1269,1426`) no longer carry this note.

## 18. One quantity, two names across a constructor and its Fields: `turnover_time` vs `relaxation_time`
**VERDICT: ABSENT**
`Forcing.jl:592` (`VarianceController` Fields section) now reads "`target`, `gain`, `turnover_time` — ``k_\infty``, ``G`` and ``t_\ell``", matching the constructor keyword `turnover_time` (line 144, 529, 531) and the struct field `turnover_time::T` (line 598). No `relaxation_time` name survives.

## 19. `valid_Reλ` is a guard that discriminates nothing, yet a safety argument leans on it
**VERDICT: PRESENT**
`Phenomenology.jl:187` still reads: "it is advisory: a comparison that opts in reads it, nothing enforces it." `StructureFunctions.jl:196-198` (`Lundgren2002` admonition) still reads, verbatim: "This is why the law's `provenance` records a validity floor of ``\mathrm{Re}_\lambda = 50``; a comparison that honours `valid_Reλ` never evaluates it in the region where the sign flips." The rhetorical "This is why…" still leans on a guard defined, by `Reference`'s own contract, to exclude nothing unless the caller opts in — unchanged from the banked finding.

---

### Summary
19 findings adjudicated. ABSENT: 1,2,3,4,5,6,7,8,10,11,13,15,16,17,18 (15). PRESENT: 9,12,14,19 (4). No PARTIAL, REGRESSED, or NOT-A-DEFECT verdicts returned — no finding showed a surviving class at a *different* site than the one it named, and none of the fixes introduced a new textual defect I could find.

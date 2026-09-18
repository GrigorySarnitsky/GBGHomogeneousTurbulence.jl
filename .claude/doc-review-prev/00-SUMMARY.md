# Panel round — 2026-08-23 (13 hats: 10 core + 3 trial lanes; economy; SEEDED)

**The instrument's first calibrated run.** Eight labeled defects were planted in the manuscripts
before the round (`seed-truth.json` in the session scratchpad); recall was **8/8 — every class
detected**, the panel's first measured denominator. Per-class: normalization 1/1, sign-flip 1/1,
citation-drift 1/1, quantifier 1/1, cross-page 1/1, notation 1/1, stale-name 1/1, wrong-constant
1/1. The anchors did the heavy lifting (dimensional 7/8, logician 5/8, theoretician 5/8); the free
readers took 4–5 each.

**SEEDED FINDINGS — planted, not real; already subtracted from every count below. Do not fix the
corpus from these:** the θ² scalar (arch §4.7), Rogallo "1984", skewness "−0.05", the "3/4 rule"
(§4.1), the "⅓ in the energy" (§10), `exp(+νκ²Δt)` (re-projection entry), decision 62's title
"`scheme` → `integrator`", "all but the last stage". Many hats ranked these top — correctly, which
is the calibration working. The build tree never carried them.

**Truncation signals (C11):** no hat exceeded the 25-cap. candidates_considered: matrix ~50,
plain-sense 38, logician 29, theoretician 20, free readers 20–25 — all selective, none capped.

**Trial-lane verdict (first-run evidence; admission needs a second run):** the three new lanes
produced 24 findings nearly disjoint from the other ten hats' — `external-standard` 7 (all
absence-shaped: validity ranges, averaging windows, transient markers — no other lane can produce
these), `reader-standpoint` 9 (all silent-wrong-number-shaped), `conjunction-coverage` 8 (incl. the
ν=0 × IFRK2 catch). Strong first data points.

---

## Tier 1 — stale after this same day's work (multiple hats, high confidence, verified real)

1. **Stale readback counts in two Forcing docstrings** [fr-a 4; matrix 4; theoretician 3;
   logician 3; dimensional 5; conjunction 1 — 6 hats]. `add_forcing_source!` still says "three per
   stage for `VarianceController`"; `VarianceRescaling` still says "two under `:total`". The fused
   wiring (decision 63) collapsed both to one; the docstrings were missed by the decision-63 sweep.
2. **The density-cutover supersession bracket sits on the wrong decision entry** [theoretician 8;
   logician 17; dimensional 6 — 3 hats]. "(Superseded 2026-08-23 …)" was appended to the
   memory-audit entry, which documents no spectrum seam; the Eₙ-vs-density seam lives in the
   validation-harness entry, which carries no marker.
3. **Bin-sum residue the density sweep missed** [theoretician 9; dimensional 9 — 2 hats]. The
   Observables module map still reads "reduces to a per-shell energy over wavenumber";
   observables_cache §2.4 still carries the "Eₙ, the per-shell energy" row. The class-not-line
   lesson, re-measured.

## Tier 2 — cross-page contradictions and API-doc drift (verified quotable, need src check before fix)

4. **A non-running example**: `DeferredForcing`'s example calls `FixedDomain(; grid_points_per_axis
   = 64)` while `FixedDomain` documents "All keyword, all required / Nothing here defaults"
   [logician 4].
5. **`VarianceController` naming split**: keyword `turnover_time`, field `relaxation_time` — the
   corpus's sole Arguments-vs-Fields name divergence [matrix 3; logician 18].
6. **`VarianceController` and the two-form family rule**: arch §4.4 claims every forcing has an
   operator-taking + operator-free form with one named exception; VC's docstring shows only the
   keyword form and the `DeferredForcing` enumeration omits it [fr-b 3; cold 4]. (Src has a
   domain-taking method — the doc surface is what's wrong; verify exact rendered signature.)
7. **`deposit!` "fills every slot" vs "the particle-velocities slot is not among them"** — the
   Cache module map's universal contract is false for a tracered run [logician 7].
8. **Iteration order/definition drift**: notation vocabulary (deposit → then tracers) vs
   observables_cache §1.1 (push listed before deposits) vs Home's two-part definition
   [matrix 5; logician 14].
9. **"Staleness counter" (Home) vs "freshness counter" (4 sites)** for the same epoch [cold 1].
10. **2N register composition told two ways**: arch §4.5 (accumulator + assembly) vs Propagator
    (state + accumulator, assembly excluded) [matrix 6].
11. **τ carries two senses** on the notation page that promises one-symbol-per-concept (turnover
    time vs RK substep), with no dual-use note like G's [logician 11].
12. **Home's component list** is captioned "build order" but puts Phenomenology last where two
    pages say it leads [fr-a 5]; **arch §4.1 omits `unit_kernel`** from the frame walkthrough
    [fr-c 4].
13. **Cache-page forward references**: the hand-run recipe names `record_particle_velocities!` /
    `restart!` four pages before their definitions, unlinked; `history_depth`'s source
    (`history_depth(trajectory_scheme)`) never stated where the keyword is documented [cold 2, 3].
14. **notation.md lacks a row for S** (the derivative skewness) [fr-b 4]. **"summationorder"**
    renders glued in arch §6 [fr-c 3]. **Kolmogorov 1941 page range** "30, 301–305" vs the usual
    299–303 — verify against the source before touching [fr-b 5].

## Tier 3 — the three trial lanes' classes (each a judgment call for the owner)

15. **`Li2008` has no stated validity range** yet silently sets ν for every grid-mode default; its
    sibling `Lundgren2002` treats exactly this as worth a named floor [external 1; standpoint 1 —
    both new lanes, independently].
16. **Silent invalidation of grid-mode ν** by a hand-built forcing's target/band — named in prose,
    checked nowhere [standpoint 2]. **`initial_spectrum` + decaying-run mode mismatch**
    [standpoint 3]. **`envelope_wavenumber` unguarded** where a forcing band is warned
    [standpoint 4]. **`Pope2000` c_L/c_η override silently breaks the stated normalization
    identity** [standpoint 6]. **`AdamsBashforth(order > 8)` behavior unspecified**
    [standpoint 7]. **Hand-built cache with too-small `history_depth`: consequence undocumented**
    [standpoint 8]. **`turnover_time` default in explicit-ν mode** [standpoint 9].
17. **No averaging-window statement for any diagnostic** before a Phenomenology comparison
    [external 3]. **Scalar-resolution warning's mode scope unstated** [external 4]. **No
    forcing-magnitude term in the timestep discussion** [external 2]. **No decaying-run
    transient-end marker** [external 7]. **No user-runnable conservation recipe** [external 5].
18. **The ν=0 truncated-Euler oracle is silently incompatible with IFRK2** (its stability region
    is empty at ν=0 by its own docstring) — §7 states the oracle per-scheme [conjunction 2].
    **Skewness aliasing residual priced only for TwoThirds** [conjunction 3]. **`max_dt`'s
    diffusive bound doesn't say which diffusivity when Sc ≠ 1** [conjunction 4]. **EndpointHeun's
    crossover-N given, AdamsBashforth's not** [conjunction 5]. **AB order measured only at 4**
    [conjunction 6]. **read-only caveat missing on `Cache.particle_velocities` alone of the four**
    [conjunction 7]. **gain=0 drift figure carries no element type** [conjunction 8].
19. **Empty-band floor: no runtime signal when it clamps mid-run** [standpoint 5 — the threshold
    half was fixed this same day (relative floor documented); the no-signal half stands].

## Tier 4 — prose (plain-sense, 24 findings; the Built-column rule also by logician 8, theoretician 10)

20. **observables_cache §2.4's Built-column rule contradicts its own sample-history row**
    [plain-sense 1; logician 8; theoretician 10 — 3 hats]. The rest: garbled routing sentence
    (§2.2), collapsed double-parenthetical (§4.4), "isa Pope2000" fossils ×3, "is still with its
    epoch cleared", gerund-subject recipe sentence, ~120-word initial_spectrum entry with a
    duplicated clause, elliptical "when the run must be", `turnover_time = nothing` behavior
    unstated, two ~60–95-word architecture sentences, mis-scoped "before any iteration runs",
    "nothing to cache" antecedent, epoch "takes three values" category slip, false-causal "so the
    state cannot go stale", recommended_cfl run-on + ambiguous "holds its energy", three names for
    the diffusive cap, "constructor-first convention" house term on a user surface, §2 run-ons,
    underivable epoch arithmetic (missing seeding-deposit premise), quick-start lecture comment,
    "one smaller again", "inherits the base's standing", "not by this catalogue" [plain-sense
    2–24, each with CUT/REWRITE verdict in the banked file].

## Cross-package (pf-parity; decisions for the owner, not defects)

21. **Citation architecture**: PF has one verbatim format on both surfaces (title-as-link); IT has
    two per-surface formats policed by a dedicated script, and inline link text is the bare DOI,
    never the title [parity 1, 2]. **Author-truncation inconsistency**: "Berendsen et al." vs
    "Bassenne, Urzay, Park & Moin" at the same author count; no rule in IT's CLAUDE.md
    [parity 3]. **The bullets-vs-prose argument threshold is practiced but unwritten** [parity 4].
    **Reverse-transfer candidates to PF**: the Known-weaknesses self-guards section; the
    citation-may-open-identity clause [parity 5, 6].

## Judgment-flavored physics notes (theoretician; low-urgency)

22. Nosé–Hoover framing beside a controller whose law is exactly Berendsen [theo 11]; StochasticOU
    "the one allocation-free exception" reads inverted [theo 12]; ResolvedGenerator's "never
    load-bearing" overstates what only holds for truthful promises [logician 12]; AbstractForcing's
    "measured at construction, not trusted" cannot measure steadiness [logician 13]; Lundgren's
    valid_Reλ rhetoric leans on an advisory guard [logician 19]; Lie–Trotter unglossed
    [cold 5]; `flow_parameters` forward reference [cold 6]; checked reads/accessors label drift
    [cold 7]; particle_velocities dual-name forward note [cold 8]; zero-cost §1.1 absolute vs
    §1.4 exception, with the §1.2 test circular for max_speed under fixed Δt [logician 9].

---

## Verified clean (the panel's negative space)

Every hat's own verified-clean list is in its banked file; the union is broad: all energy /
dissipation / scalar normalizations, C_S = (4/7)√(15/2), the L11/L22/L_E π-factors, Δκ = 2π/L and
the Parseval quadrature, the PhaseShift cutoff arithmetic at every site, the transform tables
(18/9, 21/18, ×2), CFL calibrations, G = (3/2)C_ε^(−2/3), Yaglom's −(2/3)ε_φr, the ζ_p families,
the epoch arithmetic, every Arguments-vs-Fields pairing except VC's, and the API index pages.

## Dispositions (fix pass 2026-08-23, owner-directed; closure = verify.js round below)

**Blind severity re-rate (C10) ran first**: 26 sampled findings, fresh raters, self-assigned
severities withheld. Real findings held their tiers; every seed-derived sample was independently
called fabricated-against-the-tree — the calibration confirming itself from the other side.

**FIXED (committed, suite + docs green):** all of Tier 1; Tier 2 items 4–14 (the VC field rename
`relaxation_time` → `turnover_time`; the runnable `FixedDomain` example; VC's domain form and
`DeferredForcing` membership; the scoped `deposit!` claim; one iteration order; "freshness counter"
everywhere; the 2N bookkeeping disambiguation; the τ note; Home's Phenomenology position; §4.1's
`unit_kernel`; the glossary S row; the broken §6 italic — worse than reported: it split its bullet
and rendered literal asterisks; the Cache recipe links and `history_depth` source). Tier 3: the
documentation halves of external 4, standpoint 3/4/6/7/9, conjunction 2/3/4/7/8, cold 5; Li2008's
extrapolation standing stated. Tier 4: 20 of 24 plain-sense verdicts applied.

**NOT-A-DEFECT:** fr-b 5 (Kolmogorov 1941 pagination — the literature itself circulates both
299–303 and 301–305 for DAN 30); conjunction's "FlowConditions constraint vacuous today" (its own
notes already concede it); logician 9's max_speed circularity (the UNIFORM DEPOSIT SCHEDULE holder
prices it; the §1.4 exception is stated where it bites).

**ESCALATED to the owner (each needs a decision, not a fix):**
- A numeric `valid_Reλ` floor for `Li2008` — the honest range is unmeasured; inventing one violates
  the verification rule. Options: measure one against low-Re DNS, or leave the stated extrapolation
  caveat as the guard.
- A construction-time consistency check between grid-mode ν and a hand-built forcing's
  target/band (standpoint 2) — a behavior change with noise tradeoffs.
- An `envelope_wavenumber`-vs-cutoff warning (standpoint 4's guard half) — same tradeoff.
- A runtime signal when the empty-band floor clamps mid-run (standpoint 5's other half) — a hot-loop
  warning is not free; needs a design.
- external 2/3/5/7 (forcing-magnitude timestep discussion, averaging-window guidance, a
  user-runnable conservation recipe, a decaying-run transient marker) — content additions whose
  numbers must be measured, not asserted.
- pf-parity 1–3 (citation architecture: one format vs two; title-as-link; an author-truncation
  rule) — cross-package policy decisions; parity 5–6 are reverse-transfer candidates TO PF.
- theoretician 11 (the Nosé–Hoover/Berendsen framing) — a judgment call on the analogy's weight.

**RULED 2026-08-24 (the escalation list, one by one):** Li2008's floor was set by the owner
(`valid_Reλ = (100, Inf)`); the grid-mode ν-vs-forcing check, the envelope-vs-cutoff warning, and
the empty-band floor's one-time signal are all BUILT and witnessed; the thermostat analogy now maps
the controller to Berendsen; the citation architecture adopted PF's title-as-link one-format
convention with the et-al rule; the AB study ran (orders 6/8 = the bootstrap's third-order ceiling,
worse than 4; no floor crossover — two to three orders below the time error at CFL steps), and its
numbers are in the two docstrings, witnessed. The averaging-window, conservation-recipe,
decay-marker, and forcing-Δt items were ruled out of scope / no-unverified-claim — banked in the
adjudicated list.

**DEFERRED (recorded, low):** plain-sense 19's §2 architecture run-ons (readable, long); cold 6
(`flow_parameters` forward reference — inherent to reading order); conjunction 5/6's numeric
crossover measurements for `AdamsBashforth` (need runs, not prose).

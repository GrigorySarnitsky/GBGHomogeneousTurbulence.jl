# /check-consistency 2026-08-24 — consolidated summary (core profile, 10 hats)

Round: post-decision-75 site (21 pages), manuscripts from docs/build at fc14170..0b3d58c-era HEAD.
Hats: 3 free readers, consistency-matrix, turbulence-theoretician (anchor), logician (anchor),
dimensional (anchor), cold-reader, plain-sense, pf-parity. ~84 raw findings, deduplicated below.
**Collect-only: nothing has been fixed.** Every Tier-1 item was verified in the main thread
against `src/` / `docs/ARCHITECTURE.md` with the decisive line quoted in the per-hat files.

## Dispositions (fix pass 2026-08-25, owner-ruled "go" on T1–T6 + Tier 2)

Tier 1: T1 FIXED (cascade-timescale hypothesis, both sites + the α bullet). T2 FIXED (κ=0 exact by
construction; roundoff attributed to the velocity route only). T3 FIXED (runnable `energies` push).
T4 FIXED (both sites concede the Lagrangian sample history). T5 FIXED (Berendsen named, Bussi full
reference inline). T6 FIXED (write_forcing glosses `StochasticOU` archived, un-exported).
T7 FIXED (752149e + 5a6157f). T8 FIXED (decision 76). T9 FIXED (full-reference inline citations,
CLAUDE.md policy clause).

Per hat, per finding:
- 01 free-reader-a: 1 FIXED (0.95Δx) · 2 FIXED (quick-start comment de-jargoned) · 3 DISMISSED
  (the decision log is a deliberate append-only ledger; its audience is recorded in CLAUDE.md) ·
  4 FIXED (the shared defence passage cut on all three pages) · 5 FIXED (fused pair added to both
  tours). 5/5 closed.
- 02 free-reader-b: 1 FIXED (T3) · 2 FIXED (T7) · 3 ESCALATED to owner (demonstrated validation /
  performance numbers are a docs-scope decision, not an edit) · 4 DISMISSED (deliberate symmetry:
  the keyword names the quantity the observable measures) · 5 DISMISSED (`valid_Reλ` advisory by
  design, stated in `Reference` and Lundgren's caveat) · 6 DISMISSED (as a-3) · 7 FIXED (the one
  semicolon-less `FixedDomain` example). 7/7 closed.
- 03 free-reader-c: 1 FIXED (§7 names the constructor) · 2 FIXED (τ row names the table above) ·
  3 FIXED (`injection_rate` added; defaults principle scoped) · 4 DISMISSED-with-note (the
  ``\mathrm{Re} = 1/\nu`` vs ``2\pi/\nu`` passage is correct and thrice-identical; rewrite offered
  to the owner, not taken unilaterally). 4/4 closed.
- 04 consistency-matrix: 1 FIXED (the family convention stated in the notation header:
  allocating name lists the family, `!` appends). 1/1 closed.
- 06 turbulence-theoretician: 1 FIXED (T1) · 2 FIXED (T2) · 3 FIXED as a class ("spectral
  field/state/fields" swept: Generator ×2, Observables map, api/Observables blurb, notation chart
  row, ARCH §4.1, State map + api/State) · 4 FIXED (ℓ) · 5 FIXED (τ row) · 6 FIXED (the
  convention-invariance parenthetical makes the no-conversion claim self-supporting). 6/6 closed.
- 12 logician: 1–2 FIXED (T2/T4) · 3 FIXED (the cross-check named: hook-without-trait throws;
  steadiness stays the author's promise) · 4 FIXED (decision 76) · 5 FIXED (Simulation constructor
  seeds) · 6 FIXED (deposit scoped to the announced-mutation re-seed) · 7 FIXED (Propagator's
  `deposit!`) · 8 FIXED (backend recoveries named) · 9 FIXED (Built column dropped) · 10 FIXED
  (default instance named, departures priced) · 11 FIXED (the §1.4 exception named at the rule) ·
  12 FIXED (glossary resolves both senses) · 13 FIXED (HouLi vacuity conceded) · 14 FIXED (the
  probe-position widening stated) · 15 FIXED ("on every strategy") · 16 FIXED (extrapolation, not
  geometry, for the empirical base) · 17 DISMISSED (both presets disclose their provenance in
  place; the handle names the law's parametrization) · 18 FIXED (scoped to the layer) · 19–20
  FIXED (τ row; n+1 observation count) · 21 FIXED (relative order) · 22 FIXED (series vs clock).
  22/22 closed.
- 18 dimensional: 1 FIXED (τ row) · 2 FIXED (t_ℓ parenthesized) · 3 FIXED (κ_min bound in place) ·
  4 FIXED ("on every strategy") · 5 FIXED (recovered bulk, never the Nyquist-adjacent remainder) ·
  6 FIXED (transverse). 6/6 closed.
- 21 cold-reader: 1 FIXED (T6) · 2 FIXED (T5) · 3 FIXED (`FlowConditions` @ref-linked at both
  Forcing mentions) · 4 FIXED (`Base.finalize` disclaimer) · 5 FIXED (`ScalarBuffers` glossed
  internal, entry = full description) · 6 FIXED (scratch row added to the Vocabulary) · 7 FIXED
  (restart! disclaims the checkpoint reading) · 8 DISMISSED (the `@extref` exception for PF types
  is recorded policy) · 9 FIXED ("the velocity default") · 10 DISMISSED (G is bound in the same
  docstring's Arguments entry). 10/10 closed.
- 22 plain-sense: 1–18 ALL FIXED (max-speed §1.3/§1.4 contradiction; both reuse-contract
  compressions; the doubled `Simulation`; the "'s two" ellipsis; all four over-long ARCH sentences;
  the ×3 defence passage; the circular "listed last"; the τ row; both "(the closing note)"
  pointers; the history_depth loop; the initial_spectrum aside; both "off the fields" readings;
  "measured at construction"; the DealiasingStrategy default named `TwoThirds`; "at the next use"
  ×2; "smaller than ℓ₀"; "after that first argument"; the Li2008 agent). 18/18 closed.
- 27 pf-parity: 1 FIXED (T9) · 2 FIXED (the divergence recorded as deliberate in CLAUDE.md's
  module-map rule) · 3 RECORDED (reverse-transfer candidate TO PF, not an IT defect) · 4 DEFERRED
  to owner (adopt PF's verbatim in-place-steer sentence, or record its absence as deliberate) ·
  5 RECORDED (named, considered adaptation, not a defect). 5/5 closed.

Owner rulings 2026-08-25 on the four open items: free-b-3 (validation numbers) — planned once the
package is near shipping (OPEN-ITEMS E6); pf-parity-4 — option (b), PF's steer sentence
deliberately not adopted, recorded in CLAUDE.md with the reason; free-c-4 — FIXED (the passage now
leads with ``\mathrm{Re} = u'L/\nu`` at all three sites); pf-parity-2 — RATIFIED, with a standing
todo to reconsider in detail (OPEN-ITEMS E7).

## Verifier round (verify-fixes.js, 84 findings, 0b3d58c..HEAD): 67 HONORED, 17 triaged

Nine real misses repaired in the follow-up commit: the second quick-start "closing deposit"
comment; the tripled References preamble shortened to one sentence per page; the §2 cross-ref
corrected (a hand-fixed Δt is priced in §1.4, not §2.3); ARCH §4.8 now concedes the two disclosed
handle exceptions (logician-17 upgraded from dismissal to fix); both SimulationRun persistence
docstrings gloss the stochastic forcing as archived; `FlowConditions` glossed at its
forward-referencing first mention; the ResolvedGenerator admonition regained the
`displaced_velocity_current` condition (verifier NEW-DEFECT); the restart-record triple split; the
initial_spectrum caveat restructured caveat-first; and the AbstractForcing steadiness sentence
corrected — the construction-time probe DOES measure steadiness (`_check_rate_is_steady`, two
field probes; the hook has no time argument), so "measured, not trusted" is stated with its
mechanism (my intermediate "no check can watch a rate over time" was the verifier's sharpest
catch: false against the code).

Verdicts dismissed with reasons: the Obukhov–Corrsin INSERTED (the flagged clause is *correct* —
the dimensional hat verified the convention invariance; the parenthetical supplies the missing
justification, so nothing false survives); decision-60's roundoff claim (the §11 decision log is
append-only history, exempt by standing rule — the current docstring states the exact-by-
construction truth); free-c-4 and cold-10 UNDONE (both are recorded dispositions: the first is in
the owner's open list, the second is a false-premise finding — G is bound in the same docstring's
own Arguments entry).

## Tier 1 — verified blockers/majors (9)

- **T1 · Pao's hypothesis mis-stated** (physics; theoretician, high). `Pao1965`/`PaoDissipation`
  say "the spectral energy flux stays constant through the dissipation range" — constant flux
  means zero dissipation and no cutoff; Pao's actual closure keeps the *cascade timescale*
  (flux-to-spectrum ratio) in its inertial form, and the flux decays by dF/dκ = −2νκ²E, which is
  what produces the displayed exp(−(3/2)C_K(κη)^{4/3}). Verified: Spectra.jl:223, 407. The
  formula is right; the stated hypothesis contradicts it.
- **T2 · `scalar_rhs!` asserts κ=0 conservation both exact and roundoff-only** (logician +
  theoretician). Generator.jl:642 "conserves the scalar mean exactly: the divergence has no κ=0
  component" vs :670 "⟨∇·(uφ)⟩ = 0 holds discretely only to roundoff". At κ=0 the multiplier iκ
  is identically zero, so the scalar tendency's mean is exactly zero — the roundoff rationale is
  the velocity's (Lamb-mean) situation pasted onto the scalar.
- **T3 · ARCHITECTURE §2's "runs as written" example doesn't** (free readers a+b). The block calls
  `accumulate_statistics!(my_stats, s)` — neither defined nor imported anywhere — two lines above
  the claim "the example above runs as written". Verified: ARCHITECTURE.md:66, 88.
- **T4 · "It holds the present instant only … no history" overclaims** (logician). The new
  SimulationRun map sentence and §4.7's "the present instant, no history" contradict the cache's
  Lagrangian sample history — genuinely *past-instant* data (K−1 rings + steps) a multistep run
  holds and the checkpoint stores. Introduced this session; the panel caught it fresh.
- **T5 · The Berendsen/Bussi caveat ARCH promises for `VarianceRescaling` isn't there**
  (cold-reader). ARCH §4.4:382 says VarianceRescaling carries "its Berendsen-class caveat (Bussi,
  Donadio & Parrinello)"; §References says Berendsen is "named there". Verified: `Bussi` appears
  nowhere in src/; `Berendsen` only in VarianceController's docstring (Forcing.jl:586); the
  VarianceRescaling caveat is an unattributed "molecular dynamics reached the same conclusion".
  Residue of the escalation-round reword that half-landed.
- **T6 · `StochasticOU` is discussed as live by the new persistence docstrings while archived**
  (cold-reader). `write_forcing`/`write_simulation`/`read_simulation` describe its checkpoint
  behaviour in present tense; it is unexported, absent from the Forcing page/@docs, the index, and
  the Home forcing menu. A cold reader cannot learn what it is or that it doesn't ship.
- **T7 · The "comparison machine" has no public entry point** (free-reader-b; OWNER DECISION).
  §3 and the Phenomenology page frame run-vs-reference comparison as the architecture's point; the
  one comparer (`validate_spectrum`) was deliberately moved to test/validation.jl as
  `compare_to_model`. Either re-expose a thin public helper or reword the prose so "the validation
  layer" clearly means the test suite.
- **T8 · The documented hand-run loop cannot advance the particles epoch without destroying the
  history** (logician; OWNER DECISION). The history-keeping announcement
  (`advance_particles_epoch!`) is internal; the public verb (`particles_modified!`) discards the
  history. Consequence as documented: a hand loop either freezes the particles counter (the
  two-epoch guard on `velocity_at_particles` can never fire across a push) or loses the AB
  history. Export/document the keeping verb, or state the limitation.
- **T9 · Citation architecture parity** (pf-parity; OWNER DECISION). Today's citation trim
  produced compact inline cites — "Author (Year, [*Title*](doi))", no venue/volume/pages — while
  PF's rule (which IT's one-format ruling cites as its source) keeps a FULL verbatim `Reference:`
  line inline. Either record the compact form as IT's deliberate narrowing, or restore full
  inline references.

## Tier 2 — verified minors (selection; full lists in the per-hat files)

- **τ glossary row points "below" at a row that is above** — 5 hats independently
  (notation.md:92); the strongest-corroborated finding of the round.
- "The `Simulation` `Simulation` must start somewhere" — alias-purge fossil, ARCH:631-632
  (verified in source, not an extraction artifact).
- 0.96Δx should be 0.95Δx (3/π = 0.9549; SimulationRun.jl:127); downstream 31% claim unaffected.
- `ModelSpectrum` prose calls the roll-off length "L", the glyph the glossary reserves for the
  box side (its own formula writes ℓ).
- "the spectral field" / "the spectral state" — the house field-vs-representation rule violated
  in the new `velocity_rhs!`/`scalar_rhs!` bullets and the Observables map (this session's text).
- "front door" leaked into ARCH §7 (outside its sanctioned §4.7/decision-log scope); the glossary
  resolves only the constructor sense while §4.7's heading uses the run-layer sense.
- observables_cache: seeding deposit attributed to the cache constructor ("when the cache is
  built" — impossible; the Simulation constructor makes it); "a caller … never deposits" vs the
  mandated re-deposit after out-of-band mutation; "the recoveries are exported" (false — they are
  backend operations); the §2.4 Built column is a function of the Cached column (vacuous); §2's
  configuration enumeration excludes what §2.3 then prices; §1.3 calls the max-speed reduction
  free while §1.4 calls it the standing cost (plain-sense major, verified).
- `deposit!` attributed to "the run layer" in Cache's fields_modified! (Propagator owns it).
- Forcing page uses `FlowConditions` (and its ArgumentError behavior) one module before its
  definition site; module map's required-keyword list omits ConstantPower's `injection_rate`.
- `ScalarBuffers` named and described but no definition site/index entry; `finalize!` collides
  with Base's finalize vocabulary unacknowledged; "scratch" never defined against "register";
  `restart!` reads checkpoint-adjacent next to read_simulation's "restore".
- max_wavenumber's "resolved signal" predicate excludes nothing under HouLi (f = 1); the
  skewness aliasing "priced/unpriced" split partitions the strategies differently in the module
  map vs the docstring ("on either"); recommended_cfl's "is geometric" claim outruns its
  derivation for IFHeun; the Forcing "a default never hides a choice" principle vs the front
  door's forcing default (unscoped rule pair); notation's "observation… once per iteration" vs
  run!'s n+1; κ_min unbound; t_ℓ unparenthesized in the copyable formula; PhaseShift "top third"
  (recovers ~83% of it); lateral/transverse both used for L22.
- Plain-sense rewrites: the PhaseShift reuse-contract compressions, "…mirroring
  `particles_modified!`'s two", four over-long ARCH sentences, the ×3 Phenomenology References
  boilerplate (+ its unprovoked-defence sentence), "listed last because a reader meets it last"
  (circular), "(the closing note)" pointers, the history_depth self-referential bullet, the
  initial_spectrum nested-aside sentence, "read … off the fields directly" (struct fields),
  "measured at construction" (measured how?), DealiasingStrategy answering WHO not WHAT
  (default never named), register "at the next ___", "3.7 times smaller" (than what), "leader",
  the Li2008 anthropomorphism.
- Tours: kinetic_energy_and_dissipation missing from Home/api Observables bullets; Home's
  "(the default)" is only the velocity's default; quick-start leans on epoch/deposit jargon.
- pf-parity (besides T9): module-map essay-vs-no-essay template divergence (internally consistent,
  unstated); the verbatim in-place-steer sentence PF mandates and IT lacks; IT's "Known
  weaknesses" section flagged as a reverse-transfer candidate TO PF (not an IT defect).
- consistency-matrix: notation's operator rows list PF names without their `!` (low; likely the
  family-catalogue convention, unstated).

## Verified clean (the anchors' expansions)

Both physics anchors re-derived and passed: the Betchov constant C_S = (4/7)√(15/2); both
dissipation forms and the dilatation difference; ε_φ = 2ϰ⟨|∇φ|²⟩ everywhere; the Yaglom −(2/3)ε_φr
conversion; C_OC convention invariance; E(κ) density and Parseval quadrature; L11/L22/L_E; η, τ_η,
λ, Re_λ; the integrating factor's sign and |κ|²; the CFL algebra; every phase-shift cutoff number
at all six sites; the 2κ_max < N criterion; the transform tables; the viscosity derivation chain
(0.96 rounding aside); Pope/von Kármán/Pao formula algebra (T1 is the *hypothesis prose*, not the
formula); K62/She–Lévêque; the envelope κ_p/√2; ConstantPower and VarianceController amplitude
algebra; the memory arithmetic; the AB order cap. The consistency matrix's ~45-entry sweep found
one nit — the corpus's cross-page consistency is otherwise exact.

## False positives / artifacts

None found among Tier-1 candidates this round (the doubled-`Simulation` was suspected an
extraction artifact and verified REAL in source). Extraction-artifact classes from the
adjudicated list were respected by the hats and not re-flagged.

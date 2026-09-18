# Closure audit — hat 22 (plain-sense editor)

Adversarial re-check of the 24 banked findings in `.claude/doc-review/22-plain-sense.md`, against the
current corpus only (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`). Default verdict is PRESENT;
anything else is earned with a quoted current-state check.

---

## 1. Built-column rule contradicts its own table
**VERDICT: ABSENT**
`docs/src/observables_cache.md` §2.4 now reads: "reads `—` wherever *Cached* is *no* or *never* (a
*depends* row is built whenever its configuration asks for it)." The sample-history row (Cached =
depends, Built = yes) is now consistent with the stated rule — depends is explicitly exempted.

## 2. "An additive source is what a state-dependent rate takes" — garbled routing sentence
**VERDICT: ABSENT**
§2.2 now reads: "An additive source enters the right-hand side at each stage; a state-dependent
rate — the default velocity forcing's among them — must take this route…". Subject/verb order
fixed; the routing claim now parses on first read.

## 3. Double-parenthetical sentence in §4.4 collapses grammatically
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md` §4.4 (lines 387–390) now reads as two clean sentences: "Each forcing has an
operator-taking constructor and an operator-free keyword form; `NoForcing`, taking no operators, has
only the one. The keyword form — `ConstantPower(injection_rate = 0.1)` — returns a `DeferredForcing`,
materialized when `Simulation` builds the frame, so a case can name its forcing before the grid
exists." No back-to-back parentheticals, predicate resolves cleanly.

## 4. "so `spec isa Pope2000` holds" — a language triviality asserted five times
**VERDICT: ABSENT**
Grepped `isa Pope2000|isa EnergySpectrum|isa VonKarman1948|isa Pao1965` across the corpus
(excluding `.claude/`): the three per-preset closings are gone from `src/phenomenology/Spectra.jl`
(`Pope2000`, `VonKarman1948`, `Pao1965` docstrings contain no `isa` sentence — confirmed by
`grep -rn "isa " src/phenomenology/` returning nothing). The Spectra module docstring's own
"either way" sentence was rewritten to carry only the alias-vs-struct content, no triviality. One
surviving instance remains at `docs/src/phenomenology.md`:11–12 ("so `spec isa Pope2000` and
`spec isa EnergySpectrum` both hold — the composite model spectra name the `ModelSpectrum`
specialization…") — this is exactly the one statement the finding itself said "earns its place"
and was not part of the CUT instruction.

## 5. "if a slot is still with its epoch cleared" — broken English
**VERDICT: ABSENT**
`docs/src/observables_cache.md` §1.3 now reads: "the completeness check throws if any slot's epoch
is still at the cleared sentinel — an un-redeposited slot." Grammatical predicate restored.

## 6. "Announcing to a bare cache … also takes `restart!`" — verb carries no actor
**VERDICT: ABSENT**
`src/Cache.jl` (`particles_modified!` docstring) now reads: "A loop announcing to a bare cache
rather than a `Simulation` must also call [`restart!`](@ref)… itself, for a scheme carrying its own
registers." Explicit actor ("a loop … must also call … itself") replaces the bare gerund + "takes".

## 7. `initial_spectrum` entry: one ~120-word sentence states the integral scale twice
**VERDICT: ABSENT**
`src/SimulationRun.jl` lines 186–202: the entry is now several sentences; the integral-scale value
`1/envelope_wavenumber` (vs. ``L_{11}``) appears exactly once, inside the "assumed state reads: …"
list. No duplicate clause, no ~120-word run-on.

## 8. `gate_skewness` entry: ellipsis "when the run must be", plus duplicated advice
**VERDICT: ABSENT**
`src/SimulationRun.jl` lines 819–833: the `gate_skewness` entry no longer carries the
raise-toward-0.4 advice at all; "Raise it toward `0.4` when the run's statistics depend on the
cascade being mature" now appears once only, in the `skew_floor` entry. No ellipsis, no duplication.

## 9. `turnover_time = nothing` — the default's behaviour is never stated
**VERDICT: ABSENT**
`src/Forcing.jl` lines 579–583 (`VarianceController` Arguments): "Left at `nothing` it is computed
for you from that formula, with ``\varepsilon_\infty`` the stationary estimate for this box…" —
the auto-behaviour clause the finding asked for is present.

## 10. §4.5 IFRK2 sentence: predicate resumes after two nested em-dash lists
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md` lines 403–411: split into two sentences exactly as the fix suggested — one
states IFRK2's identity/cost/(in)stability, the next opens "The memory comparison counts the
solver's scratch registers per field: …" as its own sentence with the register breakdown.

## 11. §4.6 `EndpointHeun` sentence: ~95 words, six-plus clauses
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md` lines 431–441: split at the ``\boldsymbol{v}_2`` clause as the fix
specified — "The default scheme, `EndpointHeun`, is Heun-in-time…" / "``\boldsymbol{v}_1`` is the
**trajectory sample**…" / "``\boldsymbol{v}_2`` interpolates the just-deposited…" are now separate
sentences. The "previous closing deposit deposited" cacophony is gone (now "recorded by the
previous closing deposit").

## 12. "before any iteration runs" says the wrong thing at every $t_n$
**VERDICT: ABSENT**
`docs/src/observables_cache.md` §1.1 now reads: "At each instant ``t_n`` between iterations, before
the next one begins, sits the **observation**." Matches the suggested fix verbatim in substance.

## 13. "there is nothing to cache" — about a quantity the cache does cache
**VERDICT: ABSENT**
§1.2 now reads: "the per-point speed field is never whole anywhere — no field exists to cache; the
number itself is what the cache holds." The noun ("no field") is now supplied; no contradiction
with §2.4's `max_speed` row.

## 14. "A slot's epoch … takes three values: the observable …" — a counter cannot hold a field
**VERDICT: ABSENT**
§1.3 now reads: "A slot's epoch says which of three states the slot is in: holding the observable
at a named ``t_n``, holding the producer's scratch, or holding nothing yet deposited." Matches the
suggested fix verbatim.

## 15. "so the state itself cannot go stale" — the "so" claims a causation that isn't there
**VERDICT: ABSENT**
`src/State.jl` (`ResolvedFields` docstring) now reads: "since the state holds no derived copies,
nothing in it can fall out of date." Correct causal premise (no derived copies in the state, not
"deposited into the cache") now stated.

## 16. `recommended_cfl`: a double-"and" run-on, and "a run that holds its energy" is ambiguous
**VERDICT: ABSENT**
`src/Propagator.jl` lines 606–609: "No code-level guard exists — adding one would give a
grid-and-scheme property a physics argument." (em-dash, not chained "and"s) and "…verify stability
directly: the run's energy must stay bounded over a trial stretch." — the ambiguous "holds its
energy" phrase is gone, replaced by the unambiguous "energy must stay bounded".

## 17. `max_dt`: the diffusive cap acquires a third, unbound name mid-entry
**VERDICT: PARTIAL**
`src/SimulationRun.jl` lines 203–213: the `max_dt` entry itself now reuses one name consistently
("the longest mode's diffusive-decay time" / "it is the diffusive-decay bound that stops that"),
and the collision with the unrelated "resolution criterion" (`κ_max_η`, lines 100–171) is gone —
"resolution bound" no longer appears. But the class survives: `advance!`'s docstring
(`src/SimulationRun.jl:538`) still names the same quantity "the box-and-diffusivity cap" — a third
phrase for the identical bound, not reconciled with "diffusive-decay bound"/"diffusive-decay time".
**surviving_class**: `src/SimulationRun.jl:538` — "the longest mode's diffusive-decay time (the
box-and-diffusivity cap)" — a second, unmatched alias for the `max_dt`-adjacent bound named
"diffusive-decay bound" two entries away.

## 18. "per the constructor-first convention for small records" — a house term on a user surface
**VERDICT: ABSENT**
Grepped `constructor-first` across the corpus excluding `.claude/`: the only remaining hit is
`CLAUDE.md:145` (the house rulebook itself, where the term belongs). `src/phenomenology/Spectra.jl`'s
module docstring no longer cites it; the roll-off pieces are now introduced as "plain positional
parameter records" with no house-convention reference.

## 19. Architecture §2: the run-layer paragraph is two ~70-word sentences
**VERDICT: PRESENT**
`docs/ARCHITECTURE.md` lines 70–80 are essentially unchanged. The first sentence ("The run layer
holds the pieces of §4 in one `Simulation` value, chooses a stable timestep… and runs the
observation-first loop: …") is 70 words across four coordinated main clauses with an em-dash aside
("— ``n`` iterations, ``n+1`` observations —") interrupting the last. The following `warmup!`
sentence is 52 words with its own em-dash aside and a trailing semicolon clause. Neither was split;
word counts verified by direct count.

## 20. Decision-log epoch example: the arithmetic is underivable as stated
**VERDICT: ABSENT**
`docs/ARCHITECTURE.md` lines 1820–1824 (decision 53) now reads: "the constructor's seeding deposit
leaves the fields epoch at 1, so after two steps and one announced mutation the clock reads step 2
and the fields epoch reads 4 — measured, not assumed." The missing premise (seed = 1) is now in the
same sentence: 1 + 2 + 1 = 4 is derivable as stated.

## 21. Quick-start comment block is a five-line conceptual lecture
**VERDICT: ABSENT**
`docs/src/index.md` lines 50–51: the ITERATION/DEPOSIT/EPOCH definitional essay is gone, replaced
by two short comment lines: "The state is always current; the cache serves what the last
iteration's closing deposit recorded (the epoch — the cache's freshness counter — is what a read is
checked against)." No caps-vocabulary lecture remains between the example lines.

## 22. "and the integral-scale one smaller again" — ellipsis below the parse threshold
**VERDICT: PRESENT**
`src/Generator.jl` lines 55–57 (`FlowConditions` docstring), unchanged: "…the box-scale value is
``2\pi/\nu``, and the integral-scale one smaller again)." Exact text as originally flagged; the
elliptical "one smaller again" still requires the reader to recover "value" and "still".

## 23. "though it inherits the base's standing" — "standing" is a guess
**VERDICT: ABSENT**
`src/Propagator.jl` line 616 (`recommended_cfl` docstring) now reads: "…holding whether the base
was computed or measured — the scaled value is only as trustworthy as its base." The unbound term
"standing" is gone, replaced with the plain-language clause the finding itself suggested.

## 24. "and not by this catalogue" fails the delete test
**VERDICT: PRESENT**
`src/SimulationDomain.jl` lines 50–52 (`DealiasingStrategy` docstring), unchanged: "…decided by the
`Simulation` constructor that builds a whole run from a few keywords — the **front door** — and not
by this catalogue." Exact text as originally flagged; the unprovoked, self-referential closing
clause is still there.

---

## Summary

- ABSENT: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 21, 23 (20)
- PARTIAL: 17 (1)
- PRESENT: 19, 22, 24 (3)
- REGRESSED: none
- NOT-A-DEFECT: none

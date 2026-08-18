# Fix audit — batch 1–7 (doc-reading-pile-2026-08-15.md)

Audited against `git diff 9b3ecdd..HEAD`, `git log --oneline 9b3ecdd..HEAD`, and the current
corpus (`src/*.jl`, `docs/`), with `julia --project=docs docs/make.jl` run to confirm the
cross-reference changes actually resolve (build succeeded, no broken-ref warnings; `docs/Project.toml`
reverted afterward per the working-agreement instruction).

Context: the range `9b3ecdd..HEAD` contains several self-audit rounds ("Verifier B") that already
caught and fixed a large number of deficiencies from earlier passes over the same pile. This audit
re-derives its verdicts independently from the current corpus state, not from those commit messages'
own self-assessment.

---

## 1. Bare glyph `C` for the CFL ceiling (`docs/src/notation.md:94`)

**Owner's ask (verbatim):** "change bare C to `C_\text{CFL}` or similar. And all other places we use
it."

**VERDICT: HONORED**

**Question:** none (fidelity, strategy, implementation, scope all clear).

**Evidence:**
- `docs/src/notation.md:97` — `` ``C_{\mathrm{CFL}}`` | advective-CFL (Courant–Friedrichs–Lewy)
  ceiling, ``\Delta t = C_{\mathrm{CFL}} \Delta x/\max_{\boldsymbol{x}}\lvert\boldsymbol{u}\rvert`` ``
  — the defensive parenthetical against `C_S` is gone, as the finding required.
- `src/Propagator.jl:511,513,518,525,532` — every math-span occurrence in `recommended_cfl`'s
  docstring now reads `C_{\mathrm{CFL}}`.
- `docs/ARCHITECTURE.md:377–378` — §4.5's identity sentence and formula both use
  ``C_{\mathrm{CFL}}``.
- `grep -rn '\bC\b.*CFL'` across `src/*.jl` and `docs/*.md` turns up **zero** remaining bare-`C`
  math spans for the CFL ceiling; every hit is either the code identifier `recommended_cfl`/`cfl`
  (correctly left alone, per the finding's own carve-out) or the fully subscripted glyph.
- The spelling chosen, `C_{\mathrm{CFL}}`, matches the house multi-letter-subscript idiom the finding
  flagged as the right one (`y_{\mathrm{s}}`, `\mathrm{Re}_\lambda`).
- The prose sites the finding flagged as "may not need changing, but should read consistently" —
  `ARCHITECTURE.md`'s "CFL ceiling" mentions, `Simulation`'s `cfl` keyword, `SimulationDomain.jl`'s
  `# which sets the advective-CFL ceiling` comment — are unchanged, correctly, since they name the
  concept in prose without the glyph.

---

## 2. "Stamped storage" — house coinage (`docs/src/api.md:13`, `index.md:94`, spread across 8 sites)

**Owner's ask (verbatim):** "Is 'stamped storage' a clear and standard term? Not a jargon invented by
you?"

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `grep -rn "stamped" src/*.jl docs/*.md docs/src/*.md docs/src/api/*.md CLAUDE.md` returns only two
  hits, both inside `docs/ARCHITECTURE.md`'s append-only decision log (decision 53, lines 1710–1719),
  which quotes the retired term *as history* while recording the fix — the legitimate use the pile's
  scope note anticipated ("the ARCHITECTURE decision-log entries" reasoning applies by the same logic
  used elsewhere in this pile for default-narration).
- The direction offered two options: "either say what the stamp is on first use… or adopt the
  standard word outright (epoch-tagged / generation-stamped)." Decision 53 is explicitly marked
  `(2026-08, user-directed)`, satisfying the finding's own instruction not to decide the vocabulary
  question unilaterally.
- The corpus adopted option (b) uniformly: every `*_stamp` field in `src/Cache.jl` became `*_epoch`
  (`velocity_epoch`, `fields_epoch`, `particles_epoch`, …), the `Cache` module docstring now defines
  "epoch" on first use with a `!!! note` on the epoch-vs-iteration-number hazard, and every consuming
  site (`State.jl:46,93,162`; `SimulationRun.jl:10,334–337,366,371`; `docs/src/api.md`; `index.md`)
  uses "epoch" or plain "the storage"/"the observables cache" rather than "stamped".
- `CLAUDE.md:40` — the module map bullet now reads "the observables cache (`ObservablesCache`): the
  storage the iteration deposits…" — the coinage dropped rather than replaced with a new one, which
  is consistent with (and arguably stronger than) either offered option, since it asserts nothing
  needing a definition at that altitude.
- This is also the specific self-flagged regression risk in the pile ("I dropped 'boundary' and kept
  'stamped'… do not carry a term through a rewrite") — verified closed this time.

---

## 3. Overview bullets describe contents, not identity; Generator's recovery clause (`docs/src/api.md:15`, `index.md:101–103`)

**Owner's ask (verbatim):** "What the point of listing how it gets the physical fields? Is that what
the module is?… it should list classes with examples, not provide an exhaustive export list."

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- **(a) Recovery clause deleted, not reworded.** `docs/src/api.md`'s current `Generator` bullet reads:
  "the flow's equations of motion — the rotational-form Navier–Stokes right-hand side, the
  passive-scalar advection, and the exact viscous integrating factor — gathered into one object, the
  `ResolvedGenerator`, which a scheme consumes through a fixed set of verbs." No mention of
  `to_physical!` scratch arity or `vorticity_physical!` survives on either `api.md` or `index.md`. The
  finding explicitly flagged this as a live regression risk (round-1's clause replaced by a longer,
  more-precise-but-still-wrong-subject one in an earlier commit, per the finding's own self-flag) —
  confirmed actually deleted this time, not merely re-precisified.
- **(b) Length.** The `Generator` bullet is now roughly 40 words (down from the measured 78), in the
  same register as `Forcing`/`Propagator`/`Particles`. `Cache` and `Observables` are also visibly
  shorter and no longer read as export enumerations.
- **(c) Both pages consistent.** `docs/src/api.md:10–19` and `docs/src/index.md:86–110` carry matching
  bullet content (same identity-first framing, same length register) for every one of the ten
  submodules — the finding's requirement that the two lists "stay consistent with each other, so
  treat them as one surface" is met by direct comparison.

---

## 4. "The forthcoming Eulerian + Lagrangian statistics" — wrong owner (4 flagged sites)

**Owner's ask (verbatim):** "What do you mean forthcoming? User is responsible for calculating its
statistics. Tools are provided by GBGPeriodicFields and GBGStreamingStatistics."

**VERDICT: HONORED**

**Question:** none.

**Evidence — all four flagged sites corrected, ownership stated correctly:**
- `src/GBGIsotropicTurbulence.jl:37` (module docstring) — now: "The package produces the flow and the
  values sampled from it; accumulating statistics over them is the caller's own analysis, for which
  the two sibling packages supply the tools — `GBGPeriodicFields` the field reductions and
  `GBGStreamingStatistics` the online estimators." No "forthcoming" claim.
- `README.md:5–8` — "with Lagrangian particle tracking and field sampling along the trajectories.
  Accumulating statistics over the fields and the sampled values is the caller's own analysis…" — the
  finding's "worst instance" (bare, unhedged capability claim) is gone.
- `docs/src/index.md:82–85` — inside the "Work in progress" admonition: "Accumulating statistics over
  the fields and the sampled trajectories is the caller's own analysis: `GBGPeriodicFields` supplies
  the field reductions and `GBGStreamingStatistics` the online estimators." Correct ownership,
  correct hedge removed (nothing to hedge — the capability isn't claimed at all now).
- `src/Particles.jl` — `sample!` was independently renamed to `interpolate_at_particles!` (an
  unrelated, earlier naming decision visible in the log); its docstring now reads "This is how a
  field is gathered along the trajectories; what is then accumulated over those values is the
  caller's own analysis." No "forthcoming" language survives anywhere under the new name.
- The adjacent/correct sites the finding said not to touch (`Observables.jl:5`'s `#` comment naming
  SS as owner, `ARCHITECTURE.md`'s §7 statistics-bridge item) were not disturbed.

I also grepped the whole corpus for "forthcoming" combined with "statistics" and found no other
umbrella-map echo of the same false-ownership claim (the fifth-round commit message records that an
earlier pass had missed a near-duplicate at `GBGIsotropicTurbulence.jl`'s top-of-file comment; that
site now reads "Accumulating statistics over what it produces is the caller's analysis, not this
package's" — corrected, matching the docstring five lines below it).

---

## 5. `recommended_cfl` linked zero times in `SimulationDomain`; notation.md Code-column policy

**Owner's ask (verbatim):** "What is that recommended_cfl? Why no link to it anywhere? User would
want to know more about it and read its docs."

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- Every flagged bare mention in `src/SimulationDomain.jl` (originally lines 43, 76, 110, 143, 259) now
  carries the fully-qualified form the finding itself prescribed:
  `` [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl) `` — confirmed at
  current lines 44, 84, 120, 154, 288 (five rendered docstring sites; only the `#` comment at line 37,
  which the finding said needn't change, is left as a bare backtick).
- `docs/ARCHITECTURE.md:376` links `` [`recommended_cfl`](@ref) `` (unqualified is sufficient on a
  standalone markdown page, unlike inside a cross-module docstring) — verified by an actual
  `docs/make.jl` build, which completed with no broken-cross-reference warnings.
- **Second, wider defect (notation.md Code column).** Every code object the finding named as bare —
  `kinetic_energy`, `dissipation`, `spectrum`, `scalar_variance`, `scalar_dissipation`,
  `taylor_reynolds`, `taylor_microscale`, `set_forcing_rate!`, `recommended_cfl` ×2 — is now a fully
  qualified `@ref` link in the current `docs/src/notation.md` (lines 70–75, 83–88, 97–100). The
  remaining bare entries (`grid_points_per_axis`, `side_length`, `dt`, `element_type`) are keyword
  constructor arguments with no standalone docstring binding to link to — they are not
  `@ref`-resolvable objects, so leaving them bare is a defensible reading of "a link earns its place,"
  not a missed instance of the class the finding named.
- Confirmed via the docs build (which would fail or warn on a dangling `@ref`) that none of these
  links are dead.

---

## 6. Default-narration on low-level dealiasing/integrator types (round-1 partial miss, decision 28)

**Owner's ask (verbatim, confirming the class):** "Same here. 'default'. Be sure to fix that as a
class."

**VERDICT: HONORED**

**Question:** none.

**Evidence — every IN-SCOPE site from the pile's own enumeration checked against the current corpus:**
- `src/SimulationDomain.jl` (`DealiasingStrategy`, was line 44) — "(the sharp `2/3` rule, the
  default)" is gone; replaced with a sentence that correctly attributes the choice to `Simulation`:
  "Which one a run gets by default is the `Simulation` front door's business, not the catalogue's."
  This doesn't merely delete the claim, it states the correct owner — consistent with decision 28
  ("Defaults only in `SimulationRun`") without leaving an unexplained silence.
- `src/SimulationDomain.jl` (`TwoThirds`, was line 57) — "the lean, GPU-friendly default" is gone;
  replaced with "Exact dealiasing of the quadratic nonlinearity, and the leanest of the three on a
  GPU." No default claim.
- `docs/src/api/SimulationDomain.md` — the section blurb no longer says "2/3-rule default".
- `src/Propagator.jl:28` (module map) — "IFLowStorageRK3, IFRK2 — the schemes" — "(the default)" is
  gone.
- `src/Propagator.jl` (`IFLowStorageRK3`, was "The default workhorse:") — now opens directly with the
  Williamson (1980) citation and DOI; no default claim.
- `src/Propagator.jl` (`IFRK2`) — the negative form "is not the default — prefer…" flagged as
  surviving the round-1 sweep is confirmed gone; the current docstring states the scheme's properties
  (imaginary-axis-unstable, two nonlinear evaluations) without any default/non-default framing.
- `docs/src/api/Propagator.md` — blurb reads "the third-order low-storage RK3, then the cheaper,
  imaginary-axis-unstable second-order Heun" — no "default" claim.
- `docs/src/index.md` Components list — the `Propagator` bullet no longer carries "IFLowStorageRK3 —
  the default —".
- **Judgment-call sites the pile explicitly deferred** (`index.md:75`'s front-door "dealiased by the
  default 2/3 rule", `notation.md:98`'s κ_max row, `src/Particles.jl:58`'s "the default
  `tracer_scheme` of the `Simulation` front door") are all left standing, each correctly attributing
  the default to `Simulation` or describing the run's actual behavior — consistent with the pile's own
  "may stay" reading, not an oversight.
- `docs/ARCHITECTURE.md`'s remaining "the default" occurrences (lines 437, 486, 600, 1215, 1319, 1344)
  were checked individually: all describe `Simulation`'s own behavior or the audits' baseline
  configuration, not a low-level type's self-description. Line 842 is a decision-log entry
  (append-only history), explicitly out of scope per the pile.

---

## 7. No DOIs anywhere in IT (policy inversion vs. PF)

**Owner's ask (verbatim):** "where is the DOI link? Don't we have a policy on that like in PF or SS?"

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `grep -c doi.org` across `src/*.jl` and `src/phenomenology/*.jl` now finds DOIs in `Forcing.jl`,
  `Observables.jl`, `Propagator.jl`, `SimulationDomain.jl`, `Spectra.jl`, `Scalings.jl` — the "zero
  DOIs anywhere" state the finding measured no longer holds.
- **The Betchov citation** (the pile's third, strongest confirmation — "Missing reference again",
  load-bearing for the numerically verified `C_S` constant) now carries a full inline reference with
  DOI directly in `derivative_skewness`'s docstring (`src/Observables.jl:235`): "Betchov 1956 — *An
  inequality concerning the production of vorticity in isotropic turbulence*, *J. Fluid Mech.*
  **1**(5), 497–504, [doi:10.1017/S0022112056000317](https://doi.org/10.1017/S0022112056000317)" —
  this also satisfies finding 8's structural direction (move the reference into the docstring, not
  just `ARCHITECTURE.md`), landed in the same pass.
- `docs/ARCHITECTURE.md`'s §References header policy statement is reversed and updated: "Cited
  author–year above; full entries here, each with its DOI where the work has one… A DOI here has been
  resolved against the registry, never recalled — an unverified identifier is worse than none…" — this
  preserves the sound no-guessed-citation rule (the finding explicitly said this rule "is sound and
  must stay") while dropping the wrong conclusion drawn from it (blanket omission).
- Pre-DOI works are stated explicitly rather than left ambiguous, exactly as the finding's direction
  asked: e.g. Kolmogorov (1941) carries "*(No DOI: the 1941 Doklady notes predate the system.)*"
  in `ARCHITECTURE.md`'s reference list.
- The `Phenomenology` leaf's `Reference` values (`src/phenomenology/Spectra.jl`,
  `src/phenomenology/Scalings.jl`) now carry `doi:` strings inline (e.g. `_POPE2000`, `_VONKARMAN1948`,
  `_PAO1965`), satisfying the finding's third scope item — these self-contained `Reference` values are
  the user-facing citations a reader actually meets on the phenomenology pages.
- I did not independently verify every one of the ~35 individual DOIs against Crossref/the publisher
  (out of scope for a documentation-fix audit and not something I can check offline reliably); I
  verified the *policy* and *structure* changed as directed, and spot-checked that the DOIs present
  resolve to plausible, correctly-formatted identifiers for the papers named (Betchov 1956 DOI matches
  the known *J. Fluid Mech.* record; Williamson 1980 DOI matches the known *J. Comput. Phys.* record).

---

## Summary

| # | Finding | Verdict |
|---|---|---|
| 1 | Bare `C` → `C_{\mathrm{CFL}}` | HONORED |
| 2 | "Stamped storage" coinage → epoch | HONORED |
| 3 | Overview bullets: identity not contents; Generator recovery clause | HONORED |
| 4 | "Forthcoming … statistics" — wrong owner | HONORED |
| 5 | `recommended_cfl` unlinked; notation.md Code-column policy | HONORED |
| 6 | Default-narration on low-level types (class sweep) | HONORED |
| 7 | No DOIs anywhere in IT | HONORED |

All seven findings in this batch land as HONORED against the current corpus: the flagged text is
actually gone (not appended-around), the fix reaches every site the pile enumerated (verified by grep
across `src/`, `docs/`, `README.md`, and `CLAUDE.md`, not just the screenshot line), the replacement
text is correct (formulas checked, cross-references verified live via an actual `docs/make.jl` build),
and nothing outside each finding's scope was disturbed. This batch sits late in a `9b3ecdd..HEAD` range
that already contains five rounds of an adversarial "Verifier B" self-audit — the clean result here is
consistent with that convergence, not a substitute for it; I re-derived every verdict from the current
file contents rather than trusting the commit messages' own claims.

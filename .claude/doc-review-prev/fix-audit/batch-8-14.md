# Fix audit — batch 8–14

Audited against `git diff 9b3ecdd..HEAD` (round-2 pile fix pass plus five subsequent "Verifier B"
re-audit rounds, `ee362b5` the tip) and the current corpus at HEAD. Every verdict below is from
direct inspection of the current source/docs — greps and `Read` calls quoted below — not from
trusting commit messages or the prior draft of this file (`.claude/doc-review/fix-audit/batch-8-14.md`
as it stood before this pass), two of whose claims did not survive re-verification against source
(noted at 11(a) and 12(b)).

---

## Finding 8 — IT's citation architecture cannot satisfy IT's own self-containedness rule

**Owner's ask (verbatim):** "How comes it lacks the source too? PF is quite good at catching and
fixing things like this."

**Direction from the finding:** move the full reference into the citing docstring, PF-style, with
the DOI link; keep `ARCHITECTURE.md` §References as the design doc's own list; make the DOI
cross-check bidirectional.

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `src/SimulationDomain.jl:56-58` (`TwoThirds`), `:70-72` (`HouLi`), `:102-105` (`PhaseShift`), and
  `src/Observables.jl:235-236` (`derivative_skewness`, the "THIRD CONFIRMATION" instance) all carry
  full author/title/journal/volume/pages plus a resolved, linked DOI, directly in the docstring —
  matching PF's `Interpolation.jl` model the finding named.
- `docs/ARCHITECTURE.md:1800-1809` (§References) now states the reason a DOI is *absent* per entry
  ("a 1941 *Doklady* note, a NASA technical memorandum, and a CTR research brief predate or sit
  outside the DOI system") and states DOIs are "resolved against the registry, never recalled" —
  replacing the old "DOIs are omitted rather than filled from memory" policy the finding flagged as
  the wrong conclusion.
- `.claude/commands/check-docs/doi_crosscheck.py` is bidirectional (its own docstring: "The reverse
  pass... a one-directional check certifies half the rule"). Run live:
  `docstring DOIs: 7   §References DOIs: 15   mismatches: 0   uncited entries: 0` — non-vacuous.

---

## Finding 9 — `dealias!` names an outcome it cannot deliver alone

**Owner's ask (verbatim):** "applying the filter may not be the whole dealiasing, e.g. for
PhaseShift... shall we rename the operation?"

**Name settled by the user:** `truncate_to_band!`.

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `grep -rn "dealias!"` across `src/`, `test/`, `docs/`, `CLAUDE.md` returns nothing;
  `truncate_to_band!` is the verb everywhere.
- `src/SimulationDomain.jl:352-372` — the renamed docstring carries the required
  `!!! note "Truncating the band is not always the whole of dealiasing"`, stating the `PhaseShift`
  split (the generator's averaging is the first half, this kernel only the spherical truncation).
- `docs/src/api/SimulationDomain.md:51` — section heading is "## Band truncation".
- `domain.dealias` (the field) and `DealiasingStrategy` (the type) both keep their names, as the
  finding directed.

---

## Finding 10 — `State` module docstring: obvious clause, a parenthetical, a 71-word sentence

**Owner's ask (verbatim):** "'a passive record with every operation external' — just omit this...
make the note in parenthesis just a regular sentence. The sentence 'The physical representations are
recovered from the state...' is too long, break it."

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `src/State.jl:9-28`: "a passive record with every operation external" does not appear.
- The parenthetical is now a plain sentence: "This is the single source of truth: the physical
  fields are recovered from it and never held in the state." — no parentheses.
- The former 71-word sentence is now four: "The recoveries do not disturb the state." / "An inverse
  transform consumes the coefficients it runs from... so a naive recovery would destroy the state it
  read." (31 words) / "Recovery therefore goes through the four-argument `to_physical!`..." (27
  words) / "The recovered values are deposited into the `ObservablesCache`."

---

## Finding 11(a) — "arity" is unfriendly jargon

**Owner's ask (verbatim):** "a bit scary for the user, that 'arity thing'. Can you think of
something more friendly?"

**VERDICT: LINE-ONLY**

**Question failed: STRATEGY (2b) — line, not class.**

**Evidence:** Every site the finding's own grep-verified spread named is fixed —
`src/State.jl:4` ("the source-preserving four-argument form of PF's `to_physical!`"),
`docs/src/api/State.md:11`, `docs/src/api.md`, and the earlier-file occurrences in
`docs/ARCHITECTURE.md`. But the bare term survives, describing the identical concept (the
`to_physical!` scratch-argument mechanism), on the same rendered page, three times:

```
docs/ARCHITECTURE.md:1616:    in `GBGPeriodicFields` as the scratch arity `to_physical!(physical, spectral, plans,
docs/ARCHITECTURE.md:1629:    has; a source of truth calls the scratch arity — and no `to_spectral!` twin exists or is wanted,
docs/ARCHITECTURE.md:1633:    through the backend, as every other field operation is. Bit-identical: the arity performs
```

This is decision-log entry 47 ("(2026-08, user-directed) The chart recoveries are not package
verbs..."), landed inside the very commit range under audit. A prior draft of this file dismissed
this survival as "a legitimate exemption... not a miss" because decision-log entries are append-only
history. That dismissal does not survive comparison with this codebase's own precedent in the *same*
fix pass: decision 48's own entry records that the "tail"/"boundary" terminology sweep was "retired
across every surface — src, the pages, the design docs, and the decision log" (commit `27fc437`) —
i.e. a jargon-retirement sweep in this repository *does* reach decision-log prose when the entry
describes ongoing terminology (as opposed to quoting a past ruling verbatim, the genuinely exempt
case at decision 26's "bare, inert record..." quote). Decision 47's "scratch arity" is descriptive
prose about a mechanism, not a quoted ruling, so it is the same class as decision 48's swept terms —
and it was missed across all five audit rounds recorded in the commit log.

---

## Finding 11(b) — "a passive container with every operation external" — drop

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `src/State.jl:39-54` (the `ResolvedFields` type docstring) — the phrase does not
appear anywhere in the type docstring.

---

## Finding 11(c) — "stamped" / ambiguous "its"

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `src/State.jl:43-46`: "The iteration recovers them at its end into the
`ObservablesCache`, never on a read: each cached slot records which epoch its value belongs to, and
a read serves that value or throws." "Stamped" is gone (replaced by "epoch"), and "its" now
unambiguously attaches to "The iteration" — the sentence's own grammatical subject, immediately
before "at its end" — rather than floating between `ObservablesCache` and "slots" as in the flagged
original ("into the stamped slots of the `ObservablesCache` at its end").

---

## Finding 11(d) — the trailing parenthetical — cut

**Owner's ask (verbatim):** "too vague, makes the sentence unnecessary long."
**Finding's explicit direction:** "Cut it; the `ObservablesCache` link carries the reader to the
definition."

**VERDICT: ADJACENT**

**Question failed: STRATEGY (2a/2c) — the flagged clause was reworded and kept, not cut.**

**Evidence.** Original (`27fc437`'s diff): `"...at its end (a slot's stamp records the instant its
value belongs to; never on a read — a cached read serves the deposited value or throws), so the
state itself cannot go stale."` Current (`src/State.jl:43-47`): `"...never on a read: each cached
slot records which epoch its value belongs to, and a read serves that value or throws. The state
itself therefore cannot go stale."` The vagueness is resolved ("epoch" replaces "stamp") and the
sentence is split rather than left as one long run-on, which is a real improvement — but the
specific instruction was to **cut** the clause and let the `[ObservablesCache](@ref)` link (already
present two words earlier) carry the definition. The content was not removed; it was rewritten and
kept in the main clause. This is a different, adjacent repair from the one the finding named, not a
scope failure and not a no-op, but not the ask either.

---

## Finding 11(e) — `velocity_spectral`/`scalar_spectral`/`velocity_physical` renames

**Decided by the user:** `ResolvedFields.velocity`→`velocity_spectral`, `.scalar`→`scalar_spectral`;
`ObservablesCache.velocity`→`velocity_physical`.

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `src/State.jl:56-57` — `ResolvedFields` fields are `velocity_spectral`, `scalar_spectral`.
- `src/Cache.jl:116-118` — `ObservablesCache` fields are `velocity_physical`, `vorticity_physical`,
  `scalar_physical`, matching the pile's own "Recommend: suffix all three" extension beyond the
  two-field ask, with matching accessors (`Cache.jl:166,182,196`) and `take_`/`deposit_` verbs
  (`:244-252`).
- `grep -rnoP '\b(state|cache)\.(velocity|scalar|vorticity)\b(?!_)'` across `src/*.jl`, `test/*.jl`,
  `docs/**/*.md`, `CLAUDE.md` returns **zero** hits — no straggler old field names anywhere,
  including `test/memory_audit.jl`'s completeness walk and `test/audit_ops.jl`'s op-model registers
  (which use symbol aliases unaffected by the field rename).
- `CLAUDE.md:101` — the naming-rule exemplar itself now reads `state.velocity_spectral`, closing the
  "policy example is not evidence the example is right" risk the finding flagged.

---

## Finding 12(a) — suffix the seeders

**Owner's ask (verbatim):** "Also suffix here … same with the scalar."

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `random_solenoidal_velocity!`→`random_solenoidal_velocity_spectral!`,
`random_scalar!`→`random_scalar_spectral!` complete: zero remaining unsuffixed hits across `src/`,
`test/`, `docs/`, `CLAUDE.md` (`grep -c` count across the renamed names: 47 hits spread over `src/`,
`test/`, `docs/src/api/State.md`, `docs/ARCHITECTURE.md`, matching the pile's claimed ~50-site blast
radius). `truncate_to_band!` correctly was **not** suffixed, matching the pile's own stated boundary.

---

## Finding 12(b) — the seeding note buries its subject

**Owner's ask (verbatim):** "The 'Note' is about the cache behaviour? Then why doesn't it state from
the beginning, that it is about the cache..."
**Finding's explicit direction (parenthetical, same finding):** "(Also fixes the trailing 'nothing is
recomputed on a read', which restates the cache contract a third time.)"

**VERDICT: LINE-ONLY**

**Question failed: STRATEGY (2b) — the primary ask landed, a named residue in the same finding did
not.**

**Evidence.** Both seeders' notes now lead with the cache and its consequence, exactly as directed:
`src/State.jl:89-90` and `:155-156` — `!!! note "Seeding a running case invalidates the observables
cache"` / "The cache holds what the last deposit left, so a seed written into a live run makes every
cached observable wrong." — the two imperative calls (`fields_modified!`, `deposit!`) now follow the
stated reason rather than precede it. That half is honored cleanly.

But the finding's own explicit second instruction — cut the trailing "nothing is recomputed on a
read" restatement — was **not** applied. Current text, both copies, verbatim:

```
src/State.jl:94-95:      [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again. Nothing is
                          recomputed on a read, so the interval between the two calls is yours to close.
src/State.jl:163-164:    [`deposit!`](@ref GBGIsotropicTurbulence.Propagator.deposit!) before advancing again. Nothing is
                          recomputed on a read, so the interval between the two calls is yours to close.
```

"Nothing is recomputed on a read" is the exact phrase the finding named as a third restatement of
the cache contract, still present, unedited, in both copies. (A prior draft of this audit file
asserted this phrase "is gone too — replaced by 'the interval between the two calls is yours to
close'" — that claim does not survive a direct read of the current source: the replacement clause
was appended after the flagged phrase, not in place of it, and the flagged phrase itself is still
there verbatim.)

---

## Finding 13 — "Their plateaus gate warm-up" — unbound pronoun, false quantifier

**Owner's ask (verbatim):** "Their plateaus — who are they? The vorticity and max_speed?"

**VERDICT: HONORED**

**Question:** none.

**Evidence:** `src/Observables.jl:26-31`: "Three of them gate the automatic warm-up (`warmup!`),
which advances until the dissipation ``\varepsilon`` stops drifting, the derivative skewness reaches
its plateau, and — when the scalar is forced — the scalar variance settles too. The kinetic energy is
deliberately **not** among them: a constant-energy forcing clamps it flat and a fixed-injection
forcing makes it ring, so it is measured (it normalizes the eddy-turnover clock) but never gated on."
This names exactly the three observables verified against `StationarityCriterion` (dissipation,
derivative skewness, scalar variance), drops the unbound "their", and states the `kinetic_energy`
exclusion the finding said the old text contradicted, matching `SimulationRun.jl:495-496`'s own
reasoning. The sibling claim the finding flagged for re-check ("Each is a function of the state") is
now qualified: "...the vorticity recovery alone produces a field" — `vorticity_physical!` carved out
rather than silently folded into the scalar-reduction claim. The top-of-file `#` comment
(`Observables.jl:4`) was also updated to "three of them gate warm-up", consistent with the docstring.

*Minor residual, not weighted into the verdict:* the rewritten sentence presents dissipation and
derivative-skewness gating as unconditional, while `StationarityCriterion`'s `gate_skewness` keyword
(default `true`) makes skewness gating togglable exactly like the scalar's `gate_scalar` — the
pile's own suggested wording had the same simplification, so this is not a fresh defect introduced
by the fix.

---

## Finding 14 — code-span-abutting-math-span pattern (16 sites) + `kinetic_energy`'s missing binding

**Owner's ask (verbatim):** "look how awkwardly code û and latex are rendered together... for the
kinetic energy there is no stated link between code u and its latex form." Confirmed on a second
instance: "Same here" (`scalar_dissipation`).

**VERDICT: HONORED**

**Question:** none.

**Evidence:**
- `src/Observables.jl:52-53` (`kinetic_energy`) now opens with the prescribed one-span binding:
  ``\texttt{kinetic\_energy} \equiv k = \tfrac{1}{2}\langle\lvert\boldsymbol{u}\rvert^{2}\rangle`` —
  the missing binding is now explicit.
- `src/Observables.jl:80-85` (`dissipation`, the screenshot site) and `:191-193`
  (`scalar_dissipation`, the confirmed second instance) both separate code and math spans with words
  rather than abutting them: "a vorticity field ``\boldsymbol{\omega}`` (the `ω` argument)"; "the
  velocity in spectral representation ``\hat{\boldsymbol{u}}`` (the `û` argument)"; "in spectral
  representation ``\hat\varphi`` (the `φ̂` argument)... scalar diffusivity ``\varkappa = \nu/
  \mathrm{Sc}`` (the `diffusivity` argument)".
- `docs/ARCHITECTURE.md:1436-1438` (the factor-parameter triple) uses `\texttt{}`-wrapped
  single-span bindings: ``\texttt{coefficient} = -D\tau``, ``\texttt{offset\_scale} = \tau``,
  ``\texttt{offset} = \hat A`` — none split across a code/math boundary.
- The instrument gap the finding named is closed: `.claude/commands/check-docs/abutting_spans.py`
  matches both bare and `@ref`-linked code spans (per its own header note about the earlier gap) and
  is wired into `.claude/commands/check-docs.md:181`. Run live against the full surface list
  (`src/*.jl`, `src/phenomenology/*.jl`, `docs/src/*.md`, `docs/src/api/**/*.md`,
  `docs/ARCHITECTURE.md`): one hit, at `docs/ARCHITECTURE.md:1349` (`` ``256^{3}`` `PhaseShift` ``)
  — the exact false positive the script's own docstring names as the expected non-hit ("a grid size
  next to a strategy name... not a split formula"). Effectively clean.

---

## Summary

| Finding | Verdict |
|---|---|
| 8 | HONORED |
| 9 | HONORED |
| 10 | HONORED |
| 11(a) | LINE-ONLY — "arity" survives ×3 in `ARCHITECTURE.md` decision 47 |
| 11(b) | HONORED |
| 11(c) | HONORED |
| 11(d) | ADJACENT — reworded and kept, not cut as directed |
| 11(e) | HONORED |
| 12(a) | HONORED |
| 12(b) | LINE-ONLY — "nothing is recomputed on a read" survives verbatim, both copies |
| 13 | HONORED |
| 14 | HONORED |

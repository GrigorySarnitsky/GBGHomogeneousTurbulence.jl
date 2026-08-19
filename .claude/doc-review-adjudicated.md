# Adjudicated non-defects — do NOT re-flag

The one file a `/check-consistency` hat is shown from prior rounds. It lists ONLY findings settled as
**not defects** — manuscript-extraction artifacts and design decisions the package owner closed
deliberately. Previously-FIXED items are deliberately absent: re-flagging a bad fix is the panel's
whole value. Keep entries short: what was flagged, why it is not a defect.

- **Saffman-spectrum attribution** (round 1): flagged as a misattribution; verified CORRECT against
  the literature — the citation stands as written.
- **`kinetic_energy` default target 1.5 vs 0.5** (round 1): the `Simulation` default `kinetic_energy
  = 1.5` gives u' = 1 (k = 3/2 u'²); not a normalization slip.
- **Decision-log entries describing superseded APIs** (any round): the ARCHITECTURE decision log is
  append-only HISTORY — an old entry naming a renamed verb or a deleted register records what was
  decided then and is not stale prose. Only *current-state* sections (§1–§10) must match the code.
- **The absence of a statistics layer, a sheared frame, inertial/oriented particles, an LES
  closure, high-Schmidt machinery** (any round): recorded deferrals (ARCHITECTURE §7), not gaps.
- **`vorticity_spectral(sim)` does not exist** (any round): deliberate — an accessor exists exactly
  for what the run holds, and the spectral vorticity is materialized nowhere (decision 43).
- **`Lundgren2002` "missing" from the StructureFunctions `## References`** (round 2): a
  manuscript-extraction artifact — the rendered page's `@eval` block lists all five citations,
  including "Lundgren (2002), *Phys. Fluids* **14**, 638"; verified in the built HTML.
- **`deposit_velocity!` / `take_velocity!` "do not exist"** (round 2): they exist — internal,
  undocumented-by-design verbs in `src/Cache.jl`, consumed by `Propagator`. (Whether the Cache
  module map should name undocumented internals is a separate, open finding — do not re-flag their
  *existence*.)

## Round 2026-08-14/15 — settled as NOT defects (do not re-flag)

- **The host-device sync floor is not a contradiction.** The decision-35/37 entry gives the *floor*
  ("none under a fixed step"); the decision-40 entry gives the *achieved* count and names the holder
  (`UNIFORM DEPOSIT SCHEDULE`). Floor vs achieved with a named holder is the optimality register's own
  bidirectional language, working as designed — not two claims about the same number.
- **`integrator` as a SciML false cognate.** In OrdinaryDiffEq an `integrator` bundles state and
  caches; here it is a stateless dispatch tag. Deliberate: the package's arrows-external style keeps the
  state, cache, generator, and buffers as explicit arguments, and `AbstractIntegrator`/`IFRK2`/
  `IFLowStorageRK3` name schemes consistently throughout.
- **PascalCase composed spectrum presets** (`Pope2000`, `VonKarman1948`, `Pao1965`). Deliberate: the
  author-year handle is the naming scheme for every reference law, concrete subtype or composition
  alike. (Corrected 2026-08-18: each is a `const` **type alias** for one `ModelSpectrum`
  specialization with a keyword constructor — *not* a factory function, so `spec isa Pope2000` holds.
  The earlier wording here was wrong and was itself propagating into the docs.)


## Round 2026-08-18 (closure verifier) — settled as NOT defects (do not re-flag)

- **`No DOI` vs `no DOI` capitalization.** Not an inconsistency: `ARCHITECTURE.md`'s §References
  instances open an italic parenthetical *sentence* (`*(No DOI: the 1941 Doklady notes predate the
  system.)*`), while the `Phenomenology` `Reference` strings are mid-sentence parentheticals
  (`**13**, 58 (no DOI)`). Both follow ordinary sentence capitalization; harmonizing them would break
  one of the two.
- **`CatmullRom` passed bare, without parentheses.** Correct as written: in `GBGPeriodicFields` it is
  `const CatmullRom = LalescuSpline(1, 1)` — a ready-made *value*, not a type — so the parenthesised
  form its neighbours use would be a call on a value. A panel round asked for the opposite change; the
  docstring now states why it is bare.
- **Both a `-> Type` arrow and a trailing `Returns x.` sentence.** Two sanctioned shapes, not a
  drift: the arrow states a return type fixed by the signature, the sentence covers an in-place
  mutator whose signature carries none. `CLAUDE.md` records the discriminator.
- **A named-method citation opening the docstring, ahead of the formula.** Not an inversion of the
  physical-meaning-first rule but the corpus-wide convention `CLAUDE.md` states: an inline citation
  *may* open the identity sentence when it names the method ("the smooth spectral filter of Hou & Li
  (2007) …"). The formula still lives in the docstring, below the identity.

## Round 2026-08-19 (panel) — settled as NOT defects (do not re-flag)

- **Two DOI link formats.** A `§References` entry ends in a bare autolink `<https://doi.org/…>`
  (bibliography style); an inline docstring cite uses the labelled `[doi:10.…](https://doi.org/…)`.
  One form per surface, recorded in `CLAUDE.md`; `doi_crosscheck.py` compares the two decoded because
  the same identifier percent-encodes differently in each.
- **`HouLi(; order = 36)` sharing the value 36 with the `Float64` auto-`strength`.** Not a
  copy/paste leak: Hou & Li's own filter takes both as 36. Stated in the docstring now.
- **The `max_speed` cost split (`O(N³)` field form vs `O(1)` cache form under one name).** Deliberate
  — one generic, one docstring, the field method measuring and the cache method serving the deposit
  (decision 46). A distinguishing verb was considered and rejected when the decision was recorded.
- **`Tracers`' two construction paths in one method.** `number_of_particles` and `positions` are
  mutually exclusive keywords, and keywords do not dispatch in Julia; the runtime `ArgumentError` is
  the language's behaviour, not a design choice, and the docstring says so.

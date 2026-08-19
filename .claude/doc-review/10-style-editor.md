# Style / Copy-Editor hat — findings

Reviewed: the full manuscript consolidation (Home, api overview, architecture, notation,
observables_cache, phenomenology, every `api/*` page, every `api/phenomenology/*` page) plus the
raw built HTML under `docs/build/` (checked for silent rendering failures: table fallback,
dead cross-references, unrendered math, admonition breakage). Adjudicated items from
`.claude/doc-review-adjudicated.md` are excluded throughout.

---

## Finding 1 — "Stamp" was declared retired corpus-wide, but survives on the Home page, the
Notation glossary, and the Cache API page

**Type:** contradiction
**Severity:** major
**Confidence:** high

**Locations:**
- ARCHITECTURE.md decision log (2026-08, user-directed): *""Stamp" is retired... The `*_stamp`
  fields become `*_epoch`, and the verb goes with the noun — a deposit fills a slot and sets its
  epoch rather than "stamping" it."* — and later in the same entry: *"the sweep covered the
  decision log too, so the log reads in the current vocabulary."*
- **Home page**, Quick start comment: *"each stamped with the epoch of the state they were
  computed from"*
- **Notation page**, Vocabulary table, `epoch` entry: *"the value of that counter stamped on it
  when it was filled. A slot is readable exactly when the stamp it carries still equals the
  counter it depends on."*
- **Cache API page**, `ObservablesCache` docstring: *"each slot carries a stamp, the counter's
  value at the moment that slot was filled. A slot is readable exactly when its stamp still
  equals the counter it depends on"*; Fields list: *"each slot's stamp, or a sentinel"*; *"the
  particle velocities' two stamps"*; `deposit_sample!` docstring: *"this call stamps both from
  the cache's current counters."*

**Contradicts:** the decision-48 claim that the rename swept "every surface, prose and code
alike" and that the noun "stamp" no longer describes what a slot carries.

**Description:** The decision log explicitly retires "stamp"/"stamped" in favor of "epoch" and
records that the sweep covered even the decision log's own historical prose. Yet the word
survives, unretired, in the three most user-facing surfaces of the site: the landing-page quick
start, the canonical glossary's own `epoch` entry, and the primary `ObservablesCache` type
docstring (used four separate times there, plus once more in `deposit_sample!`). A reader who
learns the vocabulary from the glossary or the Home page comes away calling the same thing by
the retired name. This is exactly the "sweep that skips its own surfaces" failure pattern the
project's own CLAUDE.md names as a live risk.

**Resolution hint:** replace "stamp"/"stamped"/"stamps" with "epoch" (or "recorded at [the]
epoch") in the four locations above.

---

## Finding 2 — Grammar: "an scheme"

**Type:** language-tone (grammar)
**Severity:** nit
**Confidence:** high

**Locations:**
- ARCHITECTURE.md §7: *"The $\nu = 0$ truncated-Euler experiment — an scheme and dealiasing
  oracle."*

**Description:** "an" before a consonant-initial word ("scheme"); should be "a scheme". Isolated
typo — the rest of the manuscript's a/an usage is clean (checked systematically).

---

## Finding 3 — Citation format: em-dash vs comma splits the three sibling dealiasing-strategy
docstrings

**Type:** format (citation)
**Severity:** minor
**Confidence:** medium

**Locations:**
- **SimulationDomain API**, `TwoThirds`: *"The sharp isotropic $2/3$-rule truncation of Orszag
  (1971) — On the elimination of aliasing..."* (em dash after the year)
- Same page, `HouLi`: *"The smooth spectral filter of Hou & Li (2007) — Computing nearly
  singular solutions..."* (em dash)
- Same page, `PhaseShift`: *"Patterson & Orszag (1971), Spectral calculations of isotropic
  turbulence..."* and *"...of Rogallo (1981), Numerical experiments in homogeneous
  turbulence..."* (comma, not em dash, for both citations)

**Contradicts:** `TwoThirds` and `HouLi`, its immediate siblings in the same "Dealiasing
strategies" section, doing the identical job (an inline citation opening/embedded in the
identity sentence, per CLAUDE.md's named-method convention).

**Description:** All three dealiasing-strategy docstrings inline a full bibliographic citation
(author-year, title, journal, DOI) in the same rhetorical slot. Two use "Author (Year) — Title…"
(em dash); `PhaseShift`, citing two works, uses "Author (Year), Title…" (comma) for both. This
may be a deliberate choice to avoid stacking three em dashes in one already-compound sentence,
which is why confidence is medium rather than high, but the corpus gives no stated rule for the
switch, so a reader sees two visually different citation styles within one API section.

---

## Finding 4 — "the default `BandRescaling(over = :total)`" reads as if `over` had a default,
contradicting the decision that made it required

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- **observables_cache page**, §1.2: *"Under the default `BandRescaling(over = :total)` the
  forcing does form the whole-field $k$ every step..."*
- **Forcing API**, `BandRescaling` signature: `BandRescaling(domain; target, over,
  lowest_shell = 1, highest_shell = 2)` — no default shown for `over`; its own prose: *"The
  `over` keyword... **is required**: a deterministic clamp destroys the physical fluctuation..."*
- ARCHITECTURE.md decision log (2026-08): *"`BandRescaling`'s `over` is **required**... Decision
  15 called `over` "a modeling choice with two defensible answers"... and then defaulted it to
  `:band`, **contradicting itself inside one sentence**. It is now required..."*

**Contradicts:** the decision log's own point that `over` must never look like it carries a
house default, since exactly that ambiguity was the earlier design's flaw and the reason `over`
became a required, undefaulted keyword.

**Description:** The observables_cache.md phrase "the default `BandRescaling(over = :total)`"
is defensible as shorthand for "the `Simulation` front door's default forcing, which happens to
be a `BandRescaling` called with `over = :total`" — but read literally it presents `over = :total`
as if it were `BandRescaling`'s own default, which the constructor signature and its own
docstring explicitly deny (`over` has no default and is required precisely so no such reading is
possible). Given the decision log spends a full paragraph on why a default here was the wrong
call, this phrasing in a different page undoes the clarity that decision bought.

**Resolution hint:** reword to "Under the `Simulation` front door's default forcing,
`BandRescaling(over = :total)`, …" or similar.

---

## Finding 5 — Inconsistent spacing around `\times` for the same `M × 3` quantity

**Type:** typesetting
**Severity:** nit
**Confidence:** medium

**Locations:**
- **Particles API**, `record_particle_velocities!`: *"Storing them costs $M \times 3$ values for
  $M$ tracers"* (spaced)
- **ARCHITECTURE.md** §4.6, §9(memory audit), and **observables_cache page** §1.2/§2.3 (three
  separate occurrences): *"$M\times3$ arrays"* / *"an $M\times3\times$..."* (unspaced)

**Description:** The same dimensional quantity, the tracer point-value array shape, is
typeset with a space around `\times` in one docstring and without a space everywhere else it
appears (five other occurrences checked). Minor, but a copy-editor-visible inconsistency in a
symbol used repeatedly across the corpus.

---

## Finding 6 — "checked accessor" vs "checked read" used for the same concept without a
stated distinction

**Type:** language-tone
**Severity:** nit
**Confidence:** low

**Locations:**
- **Cache API** section header: *"## The checked reads"* and prose *"the checked reads of the
  cached fields"*
- **Home page** / module map: *"read through checked accessors that serve the deposited value or
  throw"*

**Description:** "Checked accessor" and "checked read" name the same mechanism (an accessor that
serves the deposited value or throws) in different pages. This may be intentional register
variation (accessor = the function, read = the act of calling it), which is why confidence is
low, but the corpus's own glossary (`notation.md`'s Vocabulary section) does not carry either
term, so a reader has no anchor confirming they are synonyms rather than two different things.

---

## Notes on what was checked and found clean

- All Markdown tables in `notation.md` and `observables_cache.md` render as real `<table>`
  elements in the built HTML (9 and 2 respectively) — no literal-pipe fallback.
- No `katex-error` class anywhere in the built site; no dead (`href="#"`-only) cross-references
  found in the pages spot-checked.
- The retired terms "tail" (for the closing deposit) and "boundary" (for the instant between
  iterations) do not leak outside the decision-log entry that retires them; every other
  occurrence is a different, exempted sense (spectral tail, extraction boundary, ownership
  boundary, consumer boundary, `max_speed`'s "boundary case").
- Other previously-retired names (`resolved_fields_modified!`, `ForcingSpec`, `scalar_type`,
  `physical_velocity`/`physical_vorticity`, `tracer_velocities`/`tracer_positions`/
  `number_of_tracers`, `X_to_physical!`) do not leak outside decision-log history either.
- "Front door" capitalization, bold-italic vector notation, `\varkappa`/`\kappa`/`k` glyph
  separation, and the constructor-first / plain-constructor-naming convention (present exactly
  where CLAUDE.md's own example list says it should be, absent exactly where it says it should
  be omitted) were all sampled across many type docstrings and found uniform.
- No stray "knob"/"tweak" register violations found.

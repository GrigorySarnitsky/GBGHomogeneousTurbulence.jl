# Closure — Hat 10: Style / Copy-Editor

## Finding 1 — "Stamp" retired but surviving on Home/Notation/Cache API
**VERDICT: ABSENT**

Evidence: `rg -i stamp` across `src/`, `docs/src/`, `docs/ARCHITECTURE.md`, `CLAUDE.md`, and
`docs/build/` returns zero hits outside `docs/ARCHITECTURE.md` decision-log entries 53–54, which are
the exempted historical record (explicitly narrating that older entries "originally said 'stamp'").
`src/Cache.jl` now uses `epoch`/`*_epoch` throughout (`velocity_epoch`, `fields_epoch`, "the checked
read shared by every accessor... epoch"), and `docs/src/index.md` / `docs/src/notation.md` carry no
"stamp" occurrence. Full sweep confirmed.

---

## Finding 2 — Grammar: "an scheme"
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:678` now reads "The ``\nu = 0`` truncated-Euler experiment — **a**
scheme and dealiasing oracle." — corrected from "an scheme" to "a scheme".

---

## Finding 3 — Citation format: em-dash vs comma splits the three dealiasing-strategy docstrings
**VERDICT: PRESENT**

Evidence: `src/SimulationDomain.jl`. `TwoThirds` (line ~59): "Orszag (1971) — *On the elimination of
aliasing...*" (em dash). `HouLi` (line ~73): "Hou & Li (2007) — *Computing nearly singular
solutions...*" (em dash). `PhaseShift` (line ~102): "Patterson & Orszag (1971), *Spectral
calculations...*" and "Rogallo (1981), *Numerical experiments...*" (comma, both citations). The
three-way split is unchanged.

---

## Finding 4 — "the default `BandRescaling(over = :total)`" implying `over` has a default
**VERDICT: ABSENT**

Evidence: `docs/src/observables_cache.md:87` now reads "Under the `BandRescaling(over = :total)` the
front door builds, the forcing *does* form the whole-field ``k``..." — the word "default" preceding
the constructor call is gone, and the phrasing now reads as a relative clause ("the ... that the
front door builds") rather than presenting `over = :total` as `BandRescaling`'s own default.
`BandRescaling`'s signature (`src/Forcing.jl:223,303`) still shows `over` with no default, required.

---

## Finding 5 — Inconsistent spacing around `\times` for the same `M × 3` quantity
**VERDICT: PRESENT**

Evidence: `src/Particles.jl:248` now reads ``M\times 3`` (no space before `\times`, one space after)
— changed from the fully-spaced form the finding quoted, but still inconsistent with the five other
occurrences, all fully unspaced ``M\times3``: `docs/ARCHITECTURE.md:422,1349` and
`docs/src/observables_cache.md:324,343,358`. The class (inconsistent `\times` spacing for this
quantity) survives at the same site, in a new form.

---

## Finding 6 — "checked accessor" vs "checked read" for the same concept
**VERDICT: PRESENT**

Evidence: `docs/src/index.md:100-101` (Home page module map) still reads "read through checked
**accessors** that serve the deposited value or throw." Meanwhile `src/Cache.jl` (module docstring,
lines 24-25) and `docs/src/api/Cache.md:20` ("## The checked **reads**") both consistently use
"checked read(s)." `docs/src/notation.md` still carries no glossary entry for either term. The
two-term split across pages is unchanged.

# Closure — Hat 27: cross-package parity reviewer (IT vs PF)

## Finding 1 — Citation architecture: two link formats (IT) vs one verbatim-identical format (PF)

**VERDICT: PRESENT**

Evidence: `CLAUDE.md:141` still states the two-format split verbatim ("a `§References` entry
ends in a bare autolink … an inline docstring cite uses the labelled `[doi:10.…](…)`… which is
why `doi_crosscheck.py` compares them decoded"). `docs/ARCHITECTURE.md` §References entries
(e.g. lines 2101, 2151, 2155) confirm bare autolinks `<https://doi.org/…>` with plain-text
titles. `src/Forcing.jl:536` confirms the inline labelled-DOI form is still in use. The
architectural divergence from PF's single-format rule is unchanged; no decision was recorded
reconciling the two.

## Finding 2 — IT's inline citation link text is the bare DOI, never the paper's title

**VERDICT: PRESENT**

Evidence: `src/Forcing.jl:536` — `Bassenne, Urzay, Park & Moin (2016, [doi:10.1063/1.4944629](https://doi.org/10.1063/1.4944629))` — link text is the numeric DOI string, not the paper's
title. Same pattern confirmed at `src/Forcing.jl:330,567,568,570,721`, `src/Particles.jl:297,336`,
`src/SimulationDomain.jl:61,75`, and throughout `src/phenomenology/*.jl`. No inline docstring in
`src/` uses the title as link text; the format PF uses is absent from IT's inline convention.

## Finding 3 — PF's author-truncation rule absent from IT's `CLAUDE.md`; corpus inconsistent (Berendsen et al. truncated, Bassenne/Li not)

**VERDICT: PRESENT**

Evidence: `CLAUDE.md` has no author-count truncation rule (grep for "et al", "First et al",
"three authors" returns no policy text). `src/Forcing.jl:569` still reads "Berendsen weak
coupling (Berendsen et al. 1984, …)" (truncated) while `src/Forcing.jl:535-536` still spells out
"Bassenne, Urzay, Park & Moin (2016, …)" in full — same author count (4/5), inconsistent
truncation. `docs/ARCHITECTURE.md:2123` still lists all 9 Li et al. authors in the bibliography.

## Finding 4 — PF's numeric arguments-shape threshold (≥3 args or any keyword → bulleted) is practiced by IT but never written into `CLAUDE.md`

**VERDICT: PRESENT**

Evidence: `CLAUDE.md`'s docstring-template section (point 3, "each argument … and its effect")
still states no bullets-vs-prose count rule; grep for "three or more arguments", "bulleted
form" finds nothing matching PF's rule. Corpus still follows the threshold unstated: 
`derivative_skewness(û, domain)` (`src/Observables.jl:275-324`, 2 args) is documented in running
prose with no bullets; `kinetic_energy_and_dissipation(û, domain, viscosity)`
(`src/Observables.jl:138-162`, 3 args) uses "The arguments are: - `û` … - `domain` … -
`viscosity` …", the bulleted form. Practice-vs-policy gap unchanged.

## Finding 5 — IT's "Known weaknesses — self-guards" section has no PF counterpart

**VERDICT: NOT-A-DEFECT**

Evidence: The finding's own text states "Not a defect in IT — this looks like a genuinely
valuable IT-side invention … Worth naming … as a candidate reverse-transfer to PF, not IT work
to do." The section is confirmed still present unchanged at `CLAUDE.md:381` ("## Known
weaknesses — self-guards"). The finding names no IT-side defect to adjudicate; it recommends
action on a sibling package outside this corpus.

## Finding 6 — IT's "a citation may open the identity sentence" clause has no PF counterpart

**VERDICT: NOT-A-DEFECT**

Evidence: The finding states "Already adjudicated that this is *not* an inversion of IT's own
physical-meaning-first rule … reads as a reasonable IT-side refinement worth naming as a
candidate reverse-transfer, not a defect." Clause confirmed still present verbatim at
`CLAUDE.md:140` ("which may open the identity sentence when the citation *names* the method").
No IT-side defect asserted.

## Finding 7 — Wavenumber glyph remapping (bold `κ` vector / plain `κ` magnitude vs PF's `k`/`κ`) — judged an adaptation, not a defect

**VERDICT: NOT-A-DEFECT**

Evidence: The finding's own title and description conclude "reads as a correct, well-motivated
adaptation rather than an unexplained divergence — recorded here only because it was a candidate
worth checking, not because it needs a decision." Confirmed still present unchanged at
`docs/src/notation.md:21,57-58` ("Kept distinct: bold `\boldsymbol{\kappa}` is the wavenumber
vector, `\kappa` its magnitude … italic scalar `k` is the turbulent kinetic energy"). No IT-side
defect asserted.

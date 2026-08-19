# Scientific-Integrity & Citations Audit

Hat: citations-integrity. Scope: the full rendered manuscript (Home, architecture, notation,
observables_cache, phenomenology overview, and every `api/*` page including the three
`api/phenomenology/*` pages).

Overall: the citation apparatus is unusually disciplined for a codebase this size — every named
numerical method (Williamson 2N-RK3, Hou–Li, Patterson–Orszag/Rogallo phase-shift, the Orszag 2/3
rule, Betchov's skewness invariant, the Berendsen/Bussi thermostat pair, Mori–Zwanzig, the
metriplectic lens) carries a matching, DOI-bearing `ARCHITECTURE.md §References` entry, and every
inline docstring copy I checked (Betchov 1956, Hou & Li 2007, Patterson & Orszag 1971 + Rogallo
1981, Williamson 1980, the Berendsen/Bussi pair) is verbatim-consistent with its reference-list
entry. The `Phenomenology` leaf's three self-contained reference lists (Scalings, Spectra,
StructureFunctions) are internally consistent with the `provenance(law)` they claim to mirror, and
the Kolmogorov 1962 / Obukhov 1962 "same JFM issue, adjacent pages" claim checks out. No
inaccessible or private source is cited on the user-facing surface, and no "exact"/"optimal"/
"allocation-free" claim I traced was left unsubstantiated (each is hedged or has a stated
exception). The findings below are the residue.

---

## Finding 1 — `Sreenivasan1995`'s cited provenance is not the source of its default value

**Type:** citation
**Severity:** minor
**Confidence:** medium
**Locations:**
- `api/phenomenology/Scalings`, `Sreenivasan1995`: *"The default $C_K = 1.5 \pm 0.1$ used here is the consensus value as quoted by Sagaut & Cambon (2018), not a figure read off the 1995 paper"*
- `api/phenomenology/Scalings`, §References: *"Sreenivasan (1995), Phys. Fluids 7, 2778. doi:10.1063/1.868656"*

**Description:** The type is named, and its `provenance(law)` presumably resolves to, Sreenivasan
(1995) — the corpus's stated mechanism for "the single source of the law's attribution"
(`api/phenomenology/Phenomenology`, `provenance`). Yet the docstring itself discloses that the
shipped default is *not* Sreenivasan's number but a different, later textbook's "consensus" value.
The prose is honest about the discrepancy, but the machine-readable `Reference` a caller inspects
via `provenance(law)` still points only to the 1995 paper, with no `Reference` entry (or even a
mention in the `citation` string) naming Sagaut & Cambon (2018) as the actual source of the
constant in use. A caller who trusts `provenance` over the prose would misattribute the number.

---

## Finding 2 — an unattributed bare-name citation breaks the corpus's own author–year rule

**Type:** citation
**Severity:** minor
**Confidence:** high
**Locations:**
- `api/phenomenology/Spectra`, `ExponentialDissipation`: *"the form the triadic spectral closures … consistently predict (Sagaut & Cambon 2018, whose review is the source used here; the closure result is originally Kaneda's)"*
- `architecture`, §10 Conventions: *"Citations follow author–year; the full references are §References."*

**Description:** "Kaneda's" is the only named-but-undated attribution anywhere in the manuscript —
every other named contributor (Betchov, Williamson, Wray, Sreenivasan, Khurshid, Chen et al.,
Saffman, Townsend, Qian, Ishihara, Kraichnan, Obukhov, Corrsin, …) carries a year and, in every
other case, a resolvable citation. "Kaneda's" here has neither a year nor a §References entry
anywhere in the document, so a reader cannot locate the paper the sentence attributes the closure
result to. This is a small, checkable violation of the house rule quoted above, not a fabrication —
but it is the one citation in the corpus that cannot be chased down from the text as given.

---

## Finding 3 — two inline comparison citations omit DOIs with no "no DOI" disclosure, unlike the rest of the corpus

**Type:** citation
**Severity:** minor
**Confidence:** medium
**Locations:**
- `api/phenomenology/Spectra`, `ObukhovCorrsin1949`: *"the high-Reynolds-number value of Sreenivasan 1996, Phys. Fluids 8, 189"* (no DOI given)
- `api/phenomenology/StructureFunctions`, `Kolmogorov1962`: *"proposed independently by Obukhov (1962, J. Fluid Mech. 13, 77)"* (no DOI given)
- Contrast, `architecture` §References: *"Rogallo … NASA TM-81315. (No DOI; a NASA technical memorandum.)"*; *"Lundgren … CTR Annual Research Briefs … (No DOI; a Center for Turbulence Research brief.)"*

**Description:** Every genuinely DOI-less source in the manuscript (a NASA TM, a CTR brief, the
pre-DOI-era 1941/1949 Doklady notes) is explicitly marked "no DOI" with a reason, per the stated
policy ("A DOI here has been resolved against the registry, never recalled — an unverified
identifier is worse than none"). Sreenivasan (1996) and Obukhov (1962), by contrast, are ordinary
AIP/Cambridge journal articles of the kind that carry DOIs elsewhere in this same corpus (compare
Sreenivasan 1998/1995 and Kolmogorov 1962 itself, both DOI'd two lines away in the same
`StructureFunctions`/`Scalings` reference lists) — yet these two carry neither a DOI nor a stated
reason for its absence. Likely just an incomplete lookup rather than a deliberate omission, but it
breaks the corpus's otherwise-universal DOI-or-say-so discipline.

---

## Finding 4 — one reference-list entry alone uses an issue-number format the other 18 entries omit

**Type:** format / citation
**Severity:** nit
**Confidence:** high
**Locations:**
- `architecture`, §References: *"Betchov, R. (1956). … J. Fluid Mech. 1(5), 497–504."*
- Same list, every other journal entry, e.g. *"Patterson, G. S. & Orszag, S. A. (1971). … Phys. Fluids 14, 2538–2541."* (volume, pages — no issue number)

**Description:** Of the 18 journal-article entries in `ARCHITECTURE.md`'s consolidated `§References`
list, Betchov (1956) is the only one carrying a parenthetical issue number `(5)` between the volume
and the page range; every other entry (Orszag, Orszag & Patterson, Hou & Li, Cichowlas et al.,
Chollet & Lesieur, Eswaran & Pope, Li et al., Williamson, Mori, Zwanzig, Morrison, …) gives
volume-then-pages only. A single reference list is otherwise held to one citation-per-line
formatting; this is the one line that departs from the shared "volume, pages" shape.

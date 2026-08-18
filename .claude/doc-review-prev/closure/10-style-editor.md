# Closure audit — 10-style-editor

## Finding 1 — `record_trajectory_velocity!` call-order contradiction
**VERDICT: ABSENT**

Evidence: `docs/src/api/Particles.md:57-63` ("## The tracking loop") now reads "the run records
the sample at the iteration's end, off the just-deposited velocity, and the next iteration's
`advect!` reads it back as the first half of its pair." This matches the function docstring
(`src/Particles.jl:222`, "Call it at the end of each iteration, on the just-deposited velocity at
the just-advanced positions") and `advect!`'s Note (`src/Particles.jl:264-265`, "recorded by
`record_trajectory_velocity!` at the previous iteration's end"). Cross-checked against the actual
`advance!` code (`src/SimulationRun.jl:370-383`): `step!` → `deposit!` → `advect!` →
`record_trajectory_velocity!` → `deposit_sample!` — the call is genuinely after the advance, on
the freshly deposited velocity. All three surfaces now agree with the code.

---

## Finding 2 — bare `$C$` vs `$C_S$` in ARCHITECTURE.md §4.3
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:321-322` reads "...with the exact isotropy constant
``C_S = \tfrac{4}{7}\sqrt{15/2}``..." — the subscript is present at both occurrences in the file
(`docs/ARCHITECTURE.md:321` and `:902`). `grep -n "C_S\|3C\b" docs/ARCHITECTURE.md` finds no bare
`$C$` (or `` C `` ) left unsubscripted in the derivative-skewness formula.

---

## Finding 3 — "the instant between steps" vs settled "between iterations"
**VERDICT: ABSENT**

Evidence: `docs/src/index.md:47-48` now reads "One ITERATION is one advance: a step, then the
deposit that closes it. The state is always current; the cache holds what the last deposit left,
so its reads are valid **between iterations**." `grep -rn "between steps"` across
`docs/src/*.md`, `docs/src/api/*.md`, and `docs/ARCHITECTURE.md` returns zero hits; every instance
of the phrase in the corpus is now "between iterations."

---

## Finding 4 — citation-format mismatch, ARCHITECTURE.md vs `Phenomenology` pages
**VERDICT: PARTIAL**

Evidence: the specific sub-defect quoted (a bare single page number, "301") is fixed —
`src/phenomenology/StructureFunctions.jl:37` and the rendered
`docs/build/api/phenomenology/StructureFunctions/index.html` now both show the full range
"301–305 ... and 32, 16–18." Each Phenomenology page's References section also now carries an
added rationale paragraph (`docs/src/api/phenomenology/{Scalings,Spectra,StructureFunctions}.md`,
"This list is scoped to the laws' own provenance..."). But the underlying format class is
unchanged: ARCHITECTURE.md (`docs/ARCHITECTURE.md:1815`) still cites full name + initials + full
article title — "Kolmogorov, A. N. (1941). The local structure of turbulence in incompressible
viscous fluid for very large Reynolds numbers. *Dokl. Akad. Nauk SSSR* **30**, 301–305." — while
every `Reference(...)` value across `src/phenomenology/Scalings.jl`, `Spectra.jl`, and
`StructureFunctions.jl` uses the short "Author (year), *Journal* **vol**, page" register with no
initials and no title, for every entry (Sreenivasan, Li et al., She & Lévêque, von Kármán, Pao,
Obukhov, not just Kolmogorov). Same author/year, two visibly different citation conventions,
site-wide.

**surviving_class:** every `const _X = Reference("Author (year), *Journal* **vol**, page...")` in
`src/phenomenology/Scalings.jl` (Sreenivasan1998, Sreenivasan1995, Li2008), `Spectra.jl`
(Pope2000, VonKarman1948, Pao1965, Obukhov), and `StructureFunctions.jl` (Kolmogorov1962,
She–Lévêque, Yaglom, Lundgren) — all short-form, none matching ARCHITECTURE.md's full-name/title
register.

---

## Finding 5 — inconsistent "(front door only)" annotation in `Simulation` Keywords
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:128,137,138,140` — `grid_points_per_axis`, `side_length`,
`element_type`/`array_type`, and `dealiasing` all now read "(front door only)" uniformly; line 138
in particular ("the real element type and storage backend (front door only)") is the entry the
finding flagged as missing "only," and it now has it.

---

## Finding 6 — decision-log sentence opens with lowercase code identifier
**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:1611-1612`, decision 47, now reads "...The **two chart recoveries**
`velocity_to_physical!` and `scalar_to_physical!` are deleted: each was the same two lines..." —
the sentence containing the identifiers now opens with the capitalized "The two chart recoveries,"
not the lowercase identifier itself.

---

## Finding 7 — `StationarityCriterion` Fields section asymmetry (`gate_scalar` named, `gate_skewness` folded into `monitor`)
**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl:568-572` (the `# Fields` section) now carries an explicit
disclosure sentence: "Note the keyword arguments above do **not** map one-to-one onto these
fields: `gate_skewness`, `min_turnovers`, `window_turnovers`, `tol` and `skew_floor` are all
stored inside `monitor`, which holds the sampled series together with the thresholds that judge
them." The structural layout (one bullet per field, `monitor` still one bullet) is unchanged, but
the reader-facing problem the finding raised — "cannot tell where `gate_skewness` lives" — is
directly answered in prose immediately above the bullet list.

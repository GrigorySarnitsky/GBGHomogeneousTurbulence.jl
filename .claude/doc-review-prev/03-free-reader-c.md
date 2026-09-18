# Free-eyed reader C — findings

Hat: unconstrained fresh-eyed reader (third of three), reading the whole rendered manuscript
top to bottom as if preparing to teach the package to a colleague next week. No checklist;
findings below are only the places that genuinely tripped the read.

---

## Finding 1 — `⟨θ²⟩` appears where every other instance of this claim says `⟨φ²⟩`

- **Type:** contradiction
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: architecture, §2 "Running a simulation": *"…rather than the kinetic energy a constant-energy forcing clamps flat… When the scalar is forced, `$\langle\theta^2\rangle$` must settle too) — and `warmup!(sim; ...)` its one-line sugar."*
  - PAGE: architecture, §11 decision log, the `warmup!` stationarity-detection entry (2026-07): *"When the scalar is forced, `$\langle\varphi^2\rangle$` must flatten too — the scalar reaches stationarity after the velocity."*
- **Contradicts:** the exact same claim (the scalar-variance stationarity gate) is stated once with `θ` and once with `φ`, within the same document. It also contradicts the explicit invariant stated in the very same page, §9: *"The scalar is denoted `$\varphi$`, never `$\theta$` — in code, mathematics, and prose."*
- **Description:** `θ` is never defined anywhere in the document or in `notation.md` — every other mention of the scalar, including the immediately-following decision-log entry describing the identical mechanism, uses `φ`. A reader hits an undefined, explicitly-banned symbol in the one place (the headline `§2` walkthrough of `warmup!`) most likely to be read first. This reads as a stray, uncorrected edit rather than a deliberate choice.

---

## Finding 2 — the Rogallo citation is dated both 1981 and 1984 for the same report

- **Type:** citation
- **Severity:** major
- **Confidence:** high
- **Locations:**
  - PAGE: api / SimulationDomain, `PhaseShift` docstring: *"combined with the spherical truncation of Rogallo (1984) — Numerical experiments in homogeneous turbulence, NASA TM-81315 (no DOI)"*
  - PAGE: architecture, §References: *"Rogallo, R. S. (1981). Numerical experiments in homogeneous turbulence. NASA TM-81315. (No DOI…)"*
  - PAGE: architecture, §11 decision log, decision 27 (phase-shift dealiasing): *"Patterson & Orszag 1971, Rogallo 1981"*
- **Contradicts:** identical title and identical technical-memorandum number (NASA TM-81315) cited with two different years for the same report — 1981 everywhere else in the corpus, 1984 only in the `PhaseShift` type docstring.
- **Description:** A reader who looks up "Rogallo 1984" to find the spherical-truncation source will not find the cited TM under that year (Rogallo's TM-81315 is 1981); the year in the `PhaseShift` docstring needs to match the rest of the corpus.

---

## Finding 3 — a glued-together italic phrase reads as one garbled word

- **Type:** typesetting
- **Severity:** nit
- **Confidence:** medium
- **Locations:** PAGE: architecture, §6 "Precision and footprint as studied axes": *"Accuracy is bought there by *summationorder*, not by a wider accumulator: the backend's reductions sum pairwise…"*
- **Description:** every other emphasized phrase in the document keeps its internal word spacing; here "summation order" renders as the single run-together word "summationorder", which stops a first read cold (it looks like an unfamiliar technical term rather than the ordinary phrase "summation order"). Likely a dropped space in the source markdown's `*…*` span.

---

## Finding 4 — `unit_kernel` is documented on the API page but absent from `ARCHITECTURE.md`'s description of the frame

- **Type:** organization
- **Severity:** minor
- **Confidence:** low
- **Locations:**
  - PAGE: architecture, §4.1: *"On top of those sit the per-mode symbols: the spectral multipliers; `$\lvert\boldsymbol{\kappa}\rvert^2$` as a lazy radial kernel… and the dealias kernel of the run's chosen strategy…"* — no mention of a unit/identity weight.
  - PAGE: api / SimulationDomain, `FixedDomain` Fields: *"`unit_kernel` — the constant weight `$1$`, the same lazy form: the identity weight that lets a plain variance join a multi-weight fused reduction…"*
  - PAGE: architecture, §11 decision log ("three-item PF request…"): *"The `FixedDomain` gained `unit_kernel` (the constant-`$1$` weight in the same lazy form, so a plain variance can join a fused traversal)."*
- **Description:** `ARCHITECTURE.md`'s §4.1 walkthrough of what sits on the `FixedDomain` frame (multipliers, the squared-wavenumber kernel, the dealias kernel) predates and does not mention `unit_kernel`, even though the decision log two pages later records adding it to that same frame. A reader building a mental model from §4.1 alone would not know this field exists; minor since the API page and decision log do carry it correctly.

---

*Candidates considered before selection: roughly 20 (numeric-formula cross-checks across the
notation, decisions, and Phenomenology pages that all reconciled correctly; several apparent
transform-count mismatches in the decision log that resolved once the before/after framing was
tracked down; the repeated "TitleBody" admonition-gluing pattern, judged a manuscript-extraction
artifact rather than a site defect and not reported). No truncation — all findings judged
significant are listed above.*

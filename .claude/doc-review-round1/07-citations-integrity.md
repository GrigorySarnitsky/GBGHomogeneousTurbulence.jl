# Citations & Scientific-Integrity Audit — findings

Hat: **SCIENTIFIC-INTEGRITY & CITATIONS auditor.** Focus: every named/published method
carries a consistent author–year citation; references agree across pages; no
inaccessible/private source is cited on a user-facing surface; nothing overclaims
("exact", "optimal", "allocation-free", "the highest/first") beyond what the docs
substantiate.

General note (positive): the `Phenomenology` citations are, on the whole, accurately
attributed (Pope 2000 coefficients, Kaneda et al. 2003 for the periodic box, Sreenivasan
1995/1998, She–Lévêque 1994, Yaglom 1949, Williamson 1980's RKW3 coefficients, the Betchov
1956 skewness constant `C = 4/7·√(15/2) ≈ 1.5649` — all check out). The findings below are
the exceptions.

---

## Finding 1 — Phase-shift method cites "Patterson & Orszag (1971)", which has NO entry in §References (and is confusable with the listed "Orszag & Patterson (1972)")

- **type:** citation
- **severity:** major
- **confidence:** high

**Locations:**
- PAGE: API — SimulationDomain, §De-aliasing strategies (`PhaseShift`): *"Phase-shift
  de-aliasing follows **Patterson & Orszag (1971)**; the combination with spherical
  truncation is Rogallo (1981)."*
- PAGE: Architecture, §11 decision 27: *"a single half-cell shift is exact only in 1-D;
  **Patterson & Orszag 1971**, Rogallo 1981"*
- PAGE: Architecture, §References (preamble): *"Cited author–year above; **full entries
  here**."*
- PAGE: Architecture, §References (the only Orszag/Patterson entry): *"**Orszag, S. A. &
  Patterson, G. S. (1972)**. Numerical simulation of three-dimensional homogeneous isotropic
  turbulence. Phys. Rev. Lett. 28, 76–79. (Pseudospectral method; the 2/3 dealiasing rule,
  Orszag 1971.)"*

**Description:** The user-facing `PhaseShift` docstring attributes phase-shift dealiasing to
"Patterson & Orszag (1971)". The §References list promises "full entries here" for every
author–year cited, yet contains **no** Patterson & Orszag 1971 entry — only *Orszag &
Patterson **1972*** (a different paper: the PRL DNS paper, cited for the pseudospectral
method in §4.2). So a reader who hits "Patterson & Orszag (1971)" in the docstring and
consults §References finds only a flipped-author-order, year-off-by-one "Orszag & Patterson
(1972)" and cannot tell whether it is (a) the same work mis-cited or (b) a distinct work with
a missing entry. Both readings are defects. (In fact the two are distinct: the 1971 Phys.
Fluids "Spectral calculations of isotropic turbulence: efficient removal of aliasing
interactions" is the phase-shift source, so the correct fix is a **missing reference entry**,
not a merge.) The doc's own §10 rule — "Never cite an inaccessible source ... the full
references are §References" — is violated: a cited method carries no locatable full reference.

**resolution_hint:** Add a distinct `Patterson, G. S. & Orszag, S. A. (1971). Phys. Fluids
14, 2538` entry, and keep the 1972 entry for the pseudospectral method — the flipped
author order between the two adjacent-year papers is real, so both entries must coexist and
be verifiable.

---

## Finding 2 — Overclaim: "the highest Reynolds number the grid resolves" is contradicted by the same page's `k_max_η = 2` default, which "trades Reynolds number for margin"

- **type:** contradiction
- **severity:** major
- **confidence:** high

**Locations:**
- PAGE: API — SimulationRun, §The simulation ("Setting the Reynolds number"): *"Grid mode
  (no `viscosity`): the constructor picks **the highest Reynolds number the grid resolves**."*
- PAGE: API — SimulationRun, §The simulation (Keywords): *"`k_max_η = 2` ... **≥ 1.5 is
  well-resolved, higher trades Reynolds number for margin**."*
- PAGE: Architecture, §4.7: *"The viscosity is set from the grid by default — **the highest
  Reynolds number the grid resolves** (decision 20)"*
- PAGE: Architecture, §11 decision 20: *"then sets ν so the resolution criterion κ_max η
  equals the `k_max_η` option (default `2`) — **the highest Reynolds number the grid
  resolves**."*

**contradicts:** Same page (API — SimulationRun, Keywords) states `k_max_η = 2` (the default)
sits *above* the well-resolved floor of 1.5 and therefore "trades Reynolds number for margin"
— i.e. one could push `k_max_η → 1.5` for a *higher* Re at the same grid. Axis of
disagreement: whether the default is the *maximum* attainable Re (superlative claim) or a
deliberately margin-carrying, sub-maximal Re.

**Description:** The unqualified superlative "the highest Reynolds number the grid resolves"
appears three times, but the constructor fixes ν at the default `k_max_η = 2`, which the
keyword doc explicitly labels as carrying margin above the `1.5` well-resolved threshold.
Since `Re_λ ~ N^{2/3}` grows as `k_max_η` is lowered toward the resolution floor, `k_max_η =
2` yields a **lower** Re than the grid can still-well-resolve at `k_max_η ≈ 1.5`. The default
is thus not "the highest Reynolds number the grid resolves"; at most it is "the highest Re
consistent with the chosen (conservative) resolution criterion." As written it overstates
what the default delivers and contradicts the page's own resolution guidance.

**resolution_hint:** Qualify to "the highest Reynolds number consistent with the chosen
resolution criterion `k_max_η`", or reconcile the default value with the superlative.

---

## Finding 3 — "Orszag 1971" (the 2/3 rule) is cited but has no standalone reference entry — only a parenthetical inside the 1972 entry

- **type:** citation
- **severity:** minor
- **confidence:** medium

**Locations:**
- PAGE: Architecture, §4.2: *"dealiased by the 2/3 rule to remove the aliasing of the
  quadratic product (the pseudospectral method; Orszag & Patterson 1972, **the 2/3 rule
  Orszag 1971**)."*
- PAGE: Architecture, §References: the *only* mention of Orszag 1971 is the parenthetical
  tail of the 1972 entry — *"(Pseudospectral method; **the 2/3 dealiasing rule, Orszag
  1971**.)"* — with no venue, volume, or pages of its own.

**Description:** The 2/3-rule dealiasing (used on every step, cited as "Orszag 1971") has no
full bibliographic entry: it is folded into the parenthetical of the *Orszag & Patterson
1972* entry. Orszag 1971 is a distinct paper (J. Atmos. Sci. 28, 1074 — "On the elimination
of aliasing ..."). A reader cannot locate the 2/3-rule reference from §References, contrary
to the "full entries here" promise. Compounds Finding 1 — three distinct Orszag-related
citations ("Orszag & Patterson 1972", "Orszag 1971", "Patterson & Orszag 1971") but only one
full entry.

**resolution_hint:** Give Orszag 1971 its own entry (or explicitly fold-and-cite the two
1971 papers, disambiguated from the 1972 one).

---

## Finding 4 — Rogallo 1981's §References annotation credits only the deferred §7 sheared frame, omitting its actual user-facing use for phase-shift + spherical-truncation dealiasing

- **type:** citation
- **severity:** minor
- **confidence:** high

**Locations:**
- PAGE: Architecture, §References: *"Rogallo, R. S. (1981). Numerical experiments in
  homogeneous turbulence. NASA TM-81315. **(The sheared-frame scheme, §7.)**"*
- PAGE: API — SimulationDomain, §De-aliasing strategies (`PhaseShift`): *"the combination
  with spherical truncation is **Rogallo (1981)**."*
- PAGE: Architecture, §11 decision 27: *"Patterson & Orszag 1971, **Rogallo 1981**"* (phase-
  shift + spherical truncation).

**Description:** The §References parenthetical attributes Rogallo 1981 solely to "the
sheared-frame scheme, §7" — a *deferred*, un-shipped feature. But the reference's actual
user-facing citation is on the `PhaseShift` docstring (a shipped feature) for the phase-shift
+ spherical-truncation combination. The annotation thus names the wrong (deferred) use and
omits the real (shipped) one. Rogallo 1981 legitimately covers both, but the reference-list
gloss means a user cross-checking the `PhaseShift` docstring's "Rogallo (1981)" finds it
labeled as being about something else (§7 shear).

**resolution_hint:** Broaden the annotation to name both uses ("the phase-shift + spherical-
truncation dealiasing, §4.1 / decision 27; and the deferred sheared frame, §7").

---

## Finding 5 — "Allocation-free time loop" (home page) is broader than the substantiated invariant, given `warmup!` gates by default on `derivative_skewness`, which "allocates its rank-2 buffers per call"

- **type:** performance
- **severity:** minor
- **confidence:** low

**Locations:**
- PAGE: Home (index): *"The GPU is the primary target, so **the time loop is in-place and
  allocation-free** over preallocated buffers."*
- PAGE: Architecture, §9 invariant 4 (the precise claim): *"**A time step allocates no
  field-sized memory** over the preallocated `IntegratorBuffers`."*
- PAGE: API — SimulationRun, `warmup!` (defaults): *"`gate_skewness = true` ... the
  velocity-derivative skewness (`derivative_skewness`) must also have plateaued"*.
- PAGE: Architecture, §11 decision 20: *"this diagnostic [`derivative_skewness`] **allocates
  its rank-2 buffers per call** (sampling cadence) rather than keeping them resident."*

**Description:** The home page's blanket "the time loop is ... allocation-free" is looser than
the precise invariant, which scopes allocation-freedom to `step!` ("a time step allocates no
field-sized memory"). By default `warmup!` gates on `derivative_skewness`, which by design
allocates rank-2 (field-sized) tensor buffers per call; if that gate is evaluated per step,
the warm-up *loop* is not literally allocation-free. The narrower invariant-4 wording is
defensible; the home-page superlative is not, unless "time loop" is read as "`step!` only".
(Low confidence: the docs never state the warm-up sampling cadence, so per-step allocation is
inferred, not certain.)

**resolution_hint:** Align the home page to invariant 4's scoping ("each time *step* is
allocation-free over preallocated buffers; occasional diagnostics allocate").

---

## Finding 6 — Inaccessible internal sources cited on the rendered Architecture page, against the doc's own "never cite an inaccessible source" rule

- **type:** citation
- **severity:** minor
- **confidence:** low

**Locations:**
- PAGE: Architecture, §10 (the rule): *"**Never cite an inaccessible source**; the material
  under `inspiration/` is private and never referenced."*
- PAGE: Architecture, §11 decision (2026-07, `warmup!`): *"A fixed turnover/time/step budget
  is the explicit alternative. **(Follows the DNS warm-up research review.)**"*
- PAGE: Architecture, §11 decision 27: *"the shift theorem's phase, **PF decision 28**"*.

**Description:** The rendered Architecture page (a user-facing site page) cites two sources a
reader cannot access: "the DNS warm-up research review" (an internal/private research
document — no author, venue, or locator) and "PF decision 28" (a cross-package decision-log
number in a sibling package's private design doc). Both are un-locatable from the published
site, in tension with §10's "never cite an inaccessible source" and "the full references are
§References". (Confidence low because the decision log is arguably an internal design record
even though rendered, and neither is an author–year citation.)

**resolution_hint:** Replace "the DNS warm-up research review" with the published
author–year sources it distilled (e.g. the Bassenne / Eswaran–Pope literature) or drop the
locator; render "PF decision 28" as prose rather than a cross-package decision number.

---

## Finding 7 — `ConstantPower` attributed to "Lundgren 2003" in Architecture §4.4, but its own docstring carries no citation and constant-power forcing is a distinct lineage from Lundgren's fixed-rate linear forcing

- **type:** citation
- **severity:** minor
- **confidence:** low

**Locations:**
- PAGE: Architecture, §4.4: *"`Linear` and `ConstantPower` (**negative-damping, Lundgren
  2003**, folded into ℰ) are provided"*.
- PAGE: API — Forcing, `Linear`: *"Linear (negative-damping) forcing ... in a low-wavenumber
  band (**Lundgren 2003**)"*.
- PAGE: API — Forcing, `ConstantPower`: *(no citation)* — *"Constant-injection-rate forcing:
  a banded linear forcing ... whose rate A is set each step so the field's injection rate
  holds the `target`."*

**Description:** Architecture §4.4 lumps `ConstantPower` with `Linear` under a single
"Lundgren 2003" attribution. But Lundgren (2003) is specifically the *fixed-rate* linearly
forced turbulence scheme (the `Linear` forcing); the constant-*power* variant — rate adjusted
each step to hold the injection rate / dissipation — is a different construction (a
constant-power / Bassenne-style controller), and the `ConstantPower` docstring itself cites
no one. Attaching "Lundgren 2003" to `ConstantPower` over-attributes. Minor inconsistency
between the two surfaces (docstring: uncited; Architecture: Lundgren 2003).

**resolution_hint:** Scope the Lundgren 2003 citation to `Linear` alone, and cite the
constant-power controller separately (or leave it classical) in both places.

---

## Finding 8 — `ObukhovCorrsin1949` blends two surnames with a single (Obukhov) year, departing from the stated "first-author-surname author–year" naming convention; Corrsin's contribution is 1951

- **type:** citation
- **severity:** minor
- **confidence:** medium

**Locations:**
- PAGE: Phenomenology — Spectra: type `ObukhovCorrsin1949(; C_OC = 0.67)`, *"The
  **Obukhov–Corrsin** inertial-convective scalar spectrum"*.
- PAGE: Phenomenology — Overview / Architecture §4.8 (the convention): *"the paper is the
  **author-year type** (`Pope2000`, **first author's surname**, the full list in
  `provenance`)"*.

**Description:** The naming convention is "author-year type, first author's surname". The
scalar-spectrum type is named `ObukhovCorrsin1949` — two surnames, and the year `1949` is
Obukhov's alone (Corrsin's independent derivation is 1951). This is a joint-eponym exception
that the stated single-surname/single-year convention does not cover, and the year silently
excludes the second author's work. The name is a common dual eponym, but it is internally
inconsistent with the convention the docs assert for every type name.

**resolution_hint:** Either note the joint-eponym exception in the naming rule, or record
both years (Obukhov 1949; Corrsin 1951) in the type's `provenance` so the `1949` handle is
explained.

---

## Finding 9 — `SaffmanDissipation` attributes a Gaussian dissipation spectrum `exp(-2(κη)²)` to "Saffman 1963"; a separate "Saffman-type" (σ = 2) large-scale form is cited without a year — two different Saffman works under one bare name, one attribution questionable

- **type:** citation
- **severity:** minor
- **confidence:** low

**Locations:**
- PAGE: Phenomenology — Spectra, `SaffmanDissipation`: *"Saffman's Gaussian dissipation-range
  roll-off f_η(κη) = exp(-2(κη)²) **(Saffman 1963)** — a simple, parameter-free cutoff"*.
- PAGE: Phenomenology — Spectra, `ModelSpectrum`: *"σ = 2 (**Saffman-type**, the
  `PopeLargeScale` default)"* (no year).

**Description:** Two distinct Saffman contributions appear under the bare name: the low-
wavenumber σ = 2 range ("Saffman-type", conventionally Saffman 1967) with no year, and a
Gaussian dissipation-range cutoff attributed to "Saffman 1963". The nearby year-bearing vs
year-less usage invites conflation. Separately, the attribution of the parameter-free
Gaussian tail `exp(-2(κη)²)` to Saffman 1963 is not a standard, easily-verifiable result and
smells off (Saffman 1963 concerns fine-scale scalar/vector structure, not a Gaussian energy
cutoff). Flagging for verification of the 1963 Gaussian-cutoff attribution and the
year-vs-no-year inconsistency across the two Saffman references. (Low confidence: a
`Phenomenology` law whose full citation lives in its `Reference` value, not visible in the
rendered site.)

**resolution_hint:** Confirm the Saffman 1963 Gaussian-cutoff attribution against the source;
add the year to "Saffman-type" (Saffman 1967) so the two are visibly distinct.

---

## Finding 10 — `Li2008` attributes "Re_λ ≈ 400–2500" to "the JHTDB isotropic datasets"; JHTDB's forced-isotropic set is Re_λ ≈ 433, and Re_λ ≈ 2500 is beyond it

- **type:** citation
- **severity:** minor
- **confidence:** low

**Locations:**
- PAGE: Phenomenology — Scalings, `Li2008`: *"nearly Reynolds-number-independent across **the
  JHTDB isotropic datasets (Re_λ ≈ 400–2500)** and comparable box DNS."*

**Description:** The upper bound Re_λ ≈ 2500 is characteristic of the Kaneda/Ishihara
Earth-Simulator periodic-box runs (up to Re_λ ≈ 2300 at 12288³), not of the Johns Hopkins
Turbulence Database forced-isotropic dataset (Re_λ ≈ 433). Attaching the full "400–2500"
range to "the JHTDB isotropic datasets" over-ascribes to JHTDB a range that "comparable box
DNS" (the next clause) actually covers. A reader taking the parenthetical at face value would
overstate JHTDB's reach. (Low confidence — JHTDB has grown; verify current holdings.)

**resolution_hint:** Split the attribution: JHTDB (Re_λ ≈ 433) *and* higher-Re periodic-box
DNS (Kaneda et al., to Re_λ ≈ 2300) span the range — don't fold both under "JHTDB".

---

## Finding 11 — The Pope reference is cited without a year on the Notation page ("Pope, Turbulent Flows") but with the year everywhere else ("Pope (2000)")

- **type:** citation
- **severity:** nit
- **confidence:** medium

**Locations:**
- PAGE: Notation: *"The physical conventions are standard turbulence usage — see **Pope,
  Turbulent Flows**"* (no year).
- PAGE: Architecture (intro): *"**Pope (2000)** is a standard reference for turbulence
  notation (§References)."*
- PAGE: Architecture, §References: *"**Pope, S. B. (2000).** Turbulent Flows. Cambridge
  University Press."*

**Description:** The same book is cited three ways — "Pope, Turbulent Flows" (no year, Notation),
"Pope (2000)" (Architecture), and the full entry. The house rule is author–year; the Notation
page's year-less form is the lone exception. Also the reader-facing `Pope2000` preset type and
"Pope (2000)" spectra all carry the year, so the Notation form is the outlier.

**resolution_hint:** Write "Pope (2000), Turbulent Flows" on the Notation page for uniformity.

---

## Finding 12 — The empirical derivative-skewness value `S ≈ -0.5` is parenthetically attributed to "(Kolmogorov)"

- **type:** citation
- **severity:** nit
- **confidence:** low

**Locations:**
- PAGE: API — Observables, `derivative_skewness`: *"while fully developed isotropic
  turbulence has **S ≈ -0.5 (Kolmogorov)** — the enstrophy-production / vortex-stretching
  signature."*

**Description:** The parenthetical "(Kolmogorov)" placed directly after the numerical value
`S ≈ -0.5` reads as if Kolmogorov established the value −0.5, which is empirical (measured;
weakly Re-dependent). K41 furnishes the framing (the 4/5 law, the marker's *existence*), not
the number. The rest of the docs correctly frame it as "the K41 marker" (Observables module,
§4.3); the value-attribution here is the loose spot. Contrast: the isotropy *constant* in the
same docstring is precisely and correctly attributed to "(Betchov 1956)".

**resolution_hint:** Drop "(Kolmogorov)" after the value, or reword to "the K41 marker of
developed turbulence, S ≈ -0.4 to -0.5 (empirical)".

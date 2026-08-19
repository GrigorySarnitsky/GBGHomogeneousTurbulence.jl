# Scientific-integrity & citations audit

Hat: citations-integrity. Reviewed the full rendered-docs manuscript (Home, architecture, notation,
observables_cache, phenomenology, and every `api/*` page) against the corpus's own citation
conventions (author–year, a `§References` entry per cite, verbatim-consistent docstring copies, no
inaccessible sources, no overclaiming beyond what is substantiated). Items already settled in
`.claude/doc-review-adjudicated.md` (Saffman attribution, `Lundgren2002` "missing" from the
StructureFunctions references, the `kinetic_energy` default, decision-log staleness) are not
re-flagged. The corpus is, on the whole, unusually disciplined about citations — every
`ARCHITECTURE.md`-listed reference I checked is verbatim-consistent with its docstring copy
(Betchov 1956, Hou & Li 2007, Patterson & Orszag 1971, Orszag 1971, Rogallo 1981, Williamson 1980,
Lundgren 2003, Bussi/Donadio/Parrinello 2007, Li et al. 2008) — so the findings below are the
exceptions, not a pattern.

---

## Finding 1 — "No privileged default" is contradicted by the front door's own concrete defaults

- **Type:** other (overclaim) — **Severity:** major — **Confidence:** high

**Locations:**
- *architecture*, §6: "Both precisions are supported equally, **with no privileged default**."
- *architecture*, §9 (invariants): "**No privileged precision or backend.** $T$ and the array type
  flow from the frame; both precisions and CPU/GPU are first-class (§6)."
- *api / SimulationRun*, `Simulation` signature: `Simulation(; grid_points_per_axis, κ_max_η = 2,
  kinetic_energy = 1.5, side_length = 2π, **element_type = Float64, array_type = Array**,
  dealiasing = TwoThirds(), kwargs...)`

**Contradicts:** itself — the invariant is stated as an unqualified package-wide property ("no
privileged default"), yet the one constructor most users call (`Simulation`, "the front door") has
a literal, hard-coded privileged default for both axes it claims are unprivileged: `Float64` and
`Array` (CPU).

**Description:** The decision log itself half-concedes the tension ("Defaults only in
`SimulationRun`... `FixedDomain`... require their arguments; the `Simulation` front door supplies
the run-layer values"), but §6 and §9's "no privileged default" claims are never qualified to say
"except at the front door." Compounding it: the Home page's identity claim is "The GPU is the
primary target," yet the front door's own default backend is CPU (`Array`), not a GPU array type —
so the one line a new user runs (`Simulation(grid_points_per_axis = 64)`) exercises neither GPU nor
`Float32`, the two things the package advertises as primary and unprivileged respectively. Either
the invariant needs the front-door exception stated, or the claim overclaims.

---

## Finding 2 — Meyers & Meneveau (2008) is cited for the generic spectrum form, but their actual
## contribution appears to be exactly the bottleneck parametrization this page defers

- **Type:** citation — **Severity:** major — **Confidence:** medium

**Locations:**
- *api / phenomenology / Spectra*, `ModelSpectrum`: "This is the standard generic form for a model
  spectrum (Sagaut & Cambon 2018; Pope 2000; **Meyers & Meneveau 2008**)."
- *api / phenomenology / Spectra*, `DissipationFactor`: "**Bottleneck models are deliberately
  deferred**... a bump before the cutoff (Qian 1984...; Ishihara et al. 2005...; Kraichnan 1959...)."

**Description:** "Meyers & Meneveau (2008)" carries no journal, volume, or DOI anywhere in the
document — the only bare citation in the whole corpus with zero identifying detail (contrast every
neighboring aside, which gives at least a DOI: Qian 1984, Ishihara 2005, Kraichnan 1959, Khurshid
2018, Chen 1993, Saffman 1963, Townsend 1951 all carry one). The likely referent — J. Meyers & C.
Meneveau's 2008 *Physics of Fluids* paper on a functional spectrum form parametrizing the
bottleneck and intermittency effects — is specifically about the bottleneck bump that
`DissipationFactor`'s own docstring says is "deliberately deferred" two paragraphs later on the same
page. If that is the intended reference, it is cited in support of a claim (the plain
core-times-roll-offs form with no bottleneck) that its own subject matter argues against.

---

## Finding 3 — Kaneda (1993) is a bare, undated-in-detail citation beside a fully-detailed Kaneda (2003)

- **Type:** citation — **Severity:** minor — **Confidence:** medium

**Locations:**
- *api / phenomenology / Spectra*, `ExponentialDissipation`: "the form the triadic spectral
  closures... consistently predict (**Kaneda 1993**; Sagaut & Cambon 2018)."
- *architecture*, §9.3/`Li2008` docstring: "Kaneda et al. **2003**, doi:10.1063/1.1539855, for the
  periodic box" — same surname, fully resolvable.

**Description:** "Kaneda 1993" gives no journal, volume, or DOI — unresolvable as written. This is
not a policy violation on its own (the page's stated convention licenses an unrepeated inline aside,
per its own worked example "Sagaut & Cambon, *Homogeneous Turbulence Dynamics*, 2nd ed., Springer,
2018"), but that worked example sets the bar at *full* identifiability, which this citation misses
entirely — and the corpus's own next-door use of a properly detailed "Kaneda et al. 2003" in the
very same document shows the fuller form was known and available.

---

## Finding 4 — Kolmogorov (1941) sits in `ARCHITECTURE.md`'s `§References` with no author-year inline citation anywhere on the DNS side

- **Type:** citation — **Severity:** minor — **Confidence:** medium

**Locations:**
- *architecture*, §References: "Kolmogorov, A. N. (1941). The local structure of turbulence in
  incompressible viscous fluid for very large Reynolds numbers. Dokl. Akad. Nauk SSSR 30, 301–305."
- *architecture* §4.3 / *api / Observables* module docstring (identical text): "an empirical,
  weakly Reynolds-number-dependent value — **K41** implies a constant skewness but fixes no number."

**Description:** `CLAUDE.md`'s house rule is explicit: "every such cite has a §References entry and
every entry a citing docstring." Every other DNS-side reference-list entry I checked has a matching
"(Author Year)" inline citation outside `Phenomenology` (which is separately exempt). Kolmogorov
(1941) has none — only the informal "K41" shorthand, which never takes the "(Kolmogorov 1941)"
form the corpus otherwise uses uniformly (compare "Orszag & Patterson 1972," "Betchov 1956," etc.,
all cited in that exact format at their point of use). A reader who does not already know "K41"
means Kolmogorov 1941 has no inline pointer to the reference list that resolves it.

---

## Finding 5 — Sreenivasan (1996) cited with journal/volume/page but no DOI, unlike its same-author neighbors

- **Type:** citation — **Severity:** nit — **Confidence:** low

**Locations:**
- *api / phenomenology / Spectra*, `ObukhovCorrsin1949`: "$C_{OC}$... the high-Reynolds-number
  value of **Sreenivasan 1996, Phys. Fluids 8, 189**."
- *api / phenomenology / Scalings*, §References: "Sreenivasan (1998), Phys. Fluids 10, 528.
  **doi:10.1063/1.869575**" / "Sreenivasan (1995), Phys. Fluids 7, 2778. **doi:10.1063/1.868656**."

**Description:** The same author's 1995 and 1998 papers both carry resolved DOIs in this corpus;
the 1996 paper, cited on the same page for the analogous scalar constant, carries none. Likely a
minor completeness gap rather than a deliberate omission (`Phys. Fluids` articles from this era do
carry retroactively assigned DOIs), flagged at low confidence since it is only ever used as an
unrepeated aside, which the page's own convention permits without a DOI.

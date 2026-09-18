# Free Reader A — fresh-eyed, no-checklist pass

Read front to back: Home, api overview, architecture (incl. full decision log), decisions
page, notation, observables_cache design page, phenomenology overview, then every api/*
page including the three Phenomenology submodule pages. No lens was applied; findings below
are what actually stopped me on the read, after checking each one against the surrounding
text (most candidate "smells" I chased turned out, on verification, to be correct — this
document is unusually well self-checked, so the yield is a short, high-confidence list
rather than a long one).

---

## Finding 1 — a rounded number is off by a hundredth

**Type:** other (numeric/rounding) · **Severity:** minor · **Confidence:** high

**Location:** PAGE `api / SimulationRun`, `Simulation` docstring, the "The criterion is not
equally strict across dealiasing strategies" callout:

> "$f = 1$ puts $\eta \approx 0.64\Delta x$ at $\kappa_{\max}\eta = 2$ against
> $0.96\Delta x$ for $2/3$"

**Description:** Solving $\kappa_{\max}\eta = f\pi\eta/\Delta x = 2$ for $\eta/\Delta x$
gives $2/(f\pi)$. For $f = 2/3$ this is $3/\pi = 0.954930\ldots$, which rounds to **0.95**,
not 0.96 (the third decimal is 4, so it rounds down). The $f=1$ (HouLi) figure, $2/\pi =
0.6366$, is correctly rounded to 0.64. The downstream "≈31% higher $\mathrm{Re}_\lambda$"
claim a sentence later is unaffected — it only depends on the *ratio* $f_{2/3}/f_{\mathrm{HouLi}}
= 2/3$, which I independently verified gives 31.0%. Only this one decorative decimal is off.

**Resolution hint:** change `0.96Δx` to `0.95Δx`.

---

## Finding 2 — the Quick Start's first example already assumes deep cache vocabulary

**Type:** clarity · **Severity:** minor · **Confidence:** medium

**Location:** PAGE `Home`, "## Quick start":

> "# The state is always current; the cache serves what the last iteration's closing
> deposit recorded (the epoch — the cache's freshness counter — gates every read)."

**Description:** This is the very first code a new reader meets, and its inline comment
already leans on "closing deposit" and "epoch — the cache's freshness counter" — terms
that are not explained anywhere earlier in the reading order and are only really unpacked
much later, in the `observables_cache` design page and the notation glossary's Vocabulary
section. For a "quick start" whose job is to get someone running code fast, front-loading
the cache's internal freshness model reads as premature depth; a first-timer has no way to
parse the parenthetical yet.

**Resolution hint:** trim the parenthetical to a plain-English gloss ("gates every read, so
a stale read throws rather than serving an old value") and let the terms of art get
introduced on their own page.

---

## Finding 3 — the decision log dwarfs, and out-registers, the rationale it is attached to

**Type:** organization · **Severity:** minor · **Confidence:** medium

**Location:** PAGE `architecture`, opening line: "This is the design document ... what the
package is, how it is organized, and why it is shaped the way it is," versus PAGE
`decisions`, which runs to roughly 190 entries of highly granular engineering bookkeeping
(byte counts at specific grid sizes, named audit "holders," retired register counts, e.g.
"768 MiB at $256^3$/Float64, the largest single residency item the optimality campaign has
surfaced").

**Description:** Sections 1–10 of `architecture` read as genuine design rationale at a
consistent altitude. The decision log that follows (and that the page explicitly says to
read "before any structural change") is written at a completely different register —
closer to a commit log or an audit worksheet than to a rationale a newcomer would consult
to understand *why* the package is shaped as it is. A fresh reader following the page's own
instruction meets far more optimization-audit trivia than architecture.

**Resolution hint:** none strong — this may be a deliberate append-only ledger by design
(per CLAUDE.md); flagging only because the page's own framing ("why it is shaped the way it
is") sets an expectation the log's back two-thirds does not match.

---

## Finding 4 — an identical "References" paragraph is repeated verbatim three times

**Type:** organization · **Severity:** nit · **Confidence:** medium

**Location:** PAGE `api / phenomenology / Scalings`, `api / phenomenology / Spectra`, and
`api / phenomenology / StructureFunctions`, each "## References" section opens with the
exact same paragraph word for word:

> "The published provenance of each law on this page, read from its `provenance`(law) — the
> extraction-bound leaf carries its own citations, so a reader never has to leave the page
> for them. A few works are cited in `ARCHITECTURE.md` as well, where the DNS side needs
> them — the leaf's independence means it does not rely on that list, not that the two never
> overlap. ..."

**Description:** Reading the three Phenomenology submodule pages back to back (as the
reading order encourages), the identical boilerplate lands three times in a row. Likely a
deliberate per-page convention, but it reads as mechanical repetition to a reader going
page to page rather than dipping into just one.

**Resolution hint:** could shorten to one sentence per page with the shared rationale
stated once, e.g. on the `Phenomenology` overview page.

---

## Finding 5 — `kinetic_energy_and_dissipation` is missing from both summary tours of `Observables`

**Type:** organization · **Severity:** minor · **Confidence:** medium

**Location:** PAGE `Home`, "## Components," the `Observables` bullet, and PAGE `api`, the
matching (near-identical) `Observables` bullet — both list: "the energy and dissipation
diagnostics of the flow and the scalar, the developed-turbulence marker
(`derivative_skewness`), the spectrum-derived scales, the CFL speed bound (`max_speed`),
and the one field-valued observable, the vorticity recovery." Contrast with PAGE
`api / Observables`'s own module docstring, which explicitly lists
`kinetic_energy_and_dissipation` — "$(k,\varepsilon)$ in one fused traversal" — as one of
its contents, and with PAGE `api / SimulationRun`'s `StationarityCriterion`, which uses
exactly that fused pair every iteration to measure the eddy-turnover clock.

**Description:** A reader who only skims the Home page or the api overview's package tour
(the two most likely first stops) would come away not knowing this function exists, even
though it is exported, publicly listed in the module's own docstring, and load-bearing for
the package's own warm-up detector. This is the kind of "names only a subset of what the
code now provides" gap the project's own documentation policy calls out as a defect class.

**Resolution hint:** add a short clause to both Home/api `Observables` bullets, e.g. "...and
the fused $(k,\varepsilon)$ pair `kinetic_energy_and_dissipation`."

---

### Candidates checked and dropped (for the record, not reported as findings)

Numeric/physical claims I chased fully and verified correct (no defect): the $C_S =
\tfrac47\sqrt{15/2}$ skewness constant chain; the `energy_spectrum`/`integral_scale`
quadrature factors and the $L_{22}=L_{11}/2$, $L_E=\tfrac23 L_{11}$ identities; the
transform-count table (18/9, 21/18, 36/18, 42/36); the `recommended_cfl` $C_{\mathrm{CFL}}
\lesssim 0.83$ derivation; the $G = \tfrac32 C_\varepsilon^{-2/3}$ conversion and its
$G\approx0.81$ numeric check against the $L/L_{11}\approx5$ ratio; the
`PopeLargeScale`/`VonKarmanLarge` $L_{11}/\ell_0$ conversion and its 0.42$k$/0.57$k$
examples; the `VarianceController` marginal-law derivation ($\mathrm dk/\mathrm dt =
-G(k-k_\infty)/t_\ell$); the frame's 322.5 MiB figure (reconciles exactly once the mixed
real/complex container typing noted in decision 36's own text is applied); the 2.3 GiB /
384 MiB / 192 MiB working-set figures. Also checked and found to be already-adjudicated or
non-issues: `IFRK2`→`IFHeun` naming across old vs. current decision-log entries (explicitly
recorded as a rename, decision "the scheme names keep the method"); the `VarianceController`
vs. `VarianceRescaling` dual "Berendsen" framing (internally consistent — the smooth
relaxation is the general Berendsen recipe, the rescale is its full-strength limiting case,
and the docs say so); manuscript page ordering versus the api overview's stated reading
order (pre-adjudicated extraction artifact).

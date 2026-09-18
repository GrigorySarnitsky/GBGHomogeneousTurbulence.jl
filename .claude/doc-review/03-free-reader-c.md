# Free Reader C — unconstrained fresh-eyed pass

Standpoint: reading straight through as if I have to teach this package to a colleague next
week from the docs alone, flagging every spot where I'd have to say "that's not quite right,"
"ignore what it says here," or "you'll have to read the source for this." No checklist was
used; these are the places that actually stopped me on a full, linear read of the manuscript
(Home → Architecture → Decision log → Notation → the observables-cache design page →
Phenomenology → every API page).

Overall impression: this document has clearly been through many prior audit rounds — I spot
checked a very large number of formulas, cross-references, unit conversions, and numeric
claims (the τ-clash disclosures, the PhaseShift ×2 transform counts against the mask-rule
table, the Re_λ ~ N^(2/3), f^(-4/3) viscosity-scaling arithmetic, the G ≈ 0.81-vs-0.9 Li2008/
Sreenivasan cross-check, the von Kármán κ⁴ exponent algebra, the Pope roll-off formulas, the
memory-footprint GiB arithmetic) and every one of them checked out exactly. The residue below
is genuinely thin.

---

## Finding 1 — "front door" used outside its own sanctioned scope

**Type:** contradiction
**Severity:** minor
**Confidence:** high

**Locations:**
- PAGE: architecture, §7 ("Deliberately deferred"): *"neither the domain nor the `Simulation`
  front door exposes an override"*
- PAGE: decisions, the 2026-08 "constructor forms name their mechanism" entry: *"Front door
  survives in its sanctioned entry-point sense (§4.7's heading, the decision log)"*
- PAGE: notation, Vocabulary: *"front door | the historical name — kept by the decision log —
  for what current docs call the domain-building `Simulation` constructor"*

**Contradicts:** CLAUDE.md's owner-ruled naming policy (2026-08-24, same day as this manuscript
is dated): *"`Simulation` may be called the front door only in its own description — its
docstring and its own api-page/§4.7 sections, where the term is introduced — and every other
surface names `Simulation` explicitly... an alias lives where it is defined, nowhere else."*
The decision log itself narrows the sanctioned uses to "§4.7's heading" and "the decision
log" — §7 is neither. The glossary row calls the term "historical," i.e. superseded outside
its home, yet §7 still uses it live, unqualified, as the working name for the `Simulation`
constructor.

**Description:** ARCHITECTURE.md §7 calls `Simulation` "the `Simulation` front door" in a
current-state sentence about the FFT-planner-effort deferral. Every other current-state mention
of the term is confined to §4.7 (its sanctioned home) or the decision log (exempt as history).
This is a live instance of the exact pattern the corpus's own naming rule was written to
prevent — an alias leaking outside its defined home — and, given the rule was ruled the same
day this manuscript is dated, reads like a sweep that stopped one section short.

---

## Finding 2 — a directional cross-reference error: "below" should be "above"

**Type:** clarity
**Severity:** nit
**Confidence:** high

**Locations:**
- PAGE: notation, "Derived scales": *"τ | eddy-turnover time, k/ε ... Two unrelated
  quantities wear this glyph: in the integrating factor's row below, τ is a Runge–Kutta stage
  substep, the generator protocol's argument | warmup!"*
- PAGE: notation, "Spectral representation and operators" (the row this refers to):
  *"$\mathcal{E}(\boldsymbol{\kappa})$ | the diffusive integrating factor ... over an
  interval $\tau$ — a Runge–Kutta stage substep..."*

**Contradicts:** the page's own reading order — "Spectral representation and operators"
(where the integrating-factor row with its own τ sense lives) is a full section *earlier*
in the notation page than "Derived scales" (where the disambiguating note sits). The note
says "below" for a row that is textually above it.

**Description:** A reader following the pointer from the τ row in "Derived scales" to find
"the integrating factor's row below" will not find it below — it is the $\mathcal{E}(\boldsymbol{\kappa})$
row already read several screens earlier, in "Spectral representation and operators." Small,
but it is exactly the kind of pointer a reader trusts literally when disambiguating a
deliberately overloaded symbol, so a wrong direction costs a moment of genuine confusion.

---

## Finding 3 — the Forcing module's "run-specific, no default" keyword list omits `injection_rate`

**Type:** clarity
**Severity:** nit
**Confidence:** medium

**Locations:**
- PAGE: api / Forcing, module docstring: *"A canonical band (`lowest_shell = 1`,
  `highest_shell = 2`) is the method's and defaults; what a run holds fixed —
  `target`, `rate`, `over` — has no canonical value and is required."*
- PAGE: api / Forcing, `ConstantPower`: `ConstantPower(domain; injection_rate,
  lowest_shell = 1, highest_shell = 2)` — `injection_rate` carries no default and is required.

**Description:** The module-level generalization enumerates the required, run-specific
keywords across the forcing family as `target` (VarianceRescaling/VarianceController),
`rate` (Linear), and `over` (VarianceRescaling) — but `ConstantPower`'s own required,
no-default keyword is `injection_rate`, which the sentence never names. A reader who takes the
module docstring's list as exhaustive (as its "does the value come from the method, or from
this run?" framing invites) would not learn from it that `ConstantPower` also has a required,
run-specific parameter — they would have to notice it by reading `ConstantPower`'s own
signature. Minor, since the per-strategy docstrings are individually complete, but the summary
sentence reads as a closed list and is not one.

---

## Finding 4 — the "Re = 1/ν" vs "2π/ν" phrasing needs a second read every time it appears

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- PAGE: architecture §4.2: *"the viscosity ν ($\mathrm{Re} = 1/\nu$ in units where
  $u' = L = 1$; $2\pi/\nu$ on the shipped defaults, where $L = 2\pi$)"*
- PAGE: api / Generator, `FlowConditions`: *"with the box in units where $u' = L = 1$ this is
  $\mathrm{Re} = 1/\nu$; on the shipped defaults ($u' = 1$, $L = 2\pi$) the box-scale value is
  $2\pi/\nu$"*
- PAGE: notation, Parameters: same construction verbatim a third time.

**Description:** Not a contradiction — the same formula is repeated identically (and
correctly: $\mathrm{Re} = u'L/\nu$, so fixing $u' = 1$ and reading off $L = 2\pi$ gives
$2\pi/\nu$) in three places, so it is internally consistent. But the juxtaposition "in units
where $u' = L = 1$... $2\pi/\nu$ on the shipped defaults, where $L = 2\pi$" reads, on a first
pass, as if $L$ is simultaneously asserted to be $1$ and $2\pi$, and only resolves once a
reader reconstructs that the first clause fixes the *unit* of length (via $u'=1$) while the
second clause states the box's *value* in that unit. Worth a rewrite (e.g., "with length
measured in units of $u'/\text{(rate)}$...") the next time this passage is touched, purely for
a first-time reader's sake — I had to stop and do the algebra myself the first time I hit it,
even though it is correct every time.

---

## Candidates considered but ruled not-defects on inspection

For the record (not reported as findings): the `dissipation` two-form equivalence
($\nu\langle|\omega|^2\rangle = 2\nu\langle S_{ij}S_{ij}\rangle$ for a solenoidal periodic
field) checks out via the standard identity; the PhaseShift transform-count table
(18/9, 21/18 mask vs 36/18, 42/36 PhaseShift) is exactly self-consistent at the claimed 2×
factor in every cell; the `κ_max η` / Re_λ / viscosity-scaling arithmetic in the `Simulation`
docstring (the `f^{-4/3}` viscosity scaling and the resulting 31% Re_λ gap between `HouLi` and
`TwoThirds`) is exactly reproducible by hand; the Li2008-vs-Sreenivasan1998 cross-check
($G \approx 0.81$ from $C_\varepsilon \approx 0.5$ at the stated $L/L_{11}\approx5$, against
the quoted $G \approx 0.9$) is correct arithmetic and is honestly flagged in the text itself as
not required to close; the `PopeLargeScale`/`VonKarmanLarge` roll-off exponents reproduce the
claimed $\kappa^2$/$\kappa^4$ low-wavenumber slopes on expansion. All of the renamed-API sweeps
I spot-checked (`IFRK2`→`IFHeun`, `EndpointHeun`→`Heun`, `particle_velocities`→
`velocity_at_particles`, the eight retired `Simulation` forwarding reads, `MultistepBuffers`
folded away) leave no stale occurrence outside the (exempt, append-only) decision log.

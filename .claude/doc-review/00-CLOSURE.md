# Closure audit — round 2 (2026-08-17, after the fix pass)

Blind re-run of `verify.js` over the same 85 banked findings, on the corpus as it stands after
the round-2 fix pass. Round-1 numbers in brackets.

**Read the table as the audit's snapshot, not the current state.** Eleven of the twenty items it
lists were closed in the commit that followed it (03#3, 03#8, 05#3, 05#7, 07#3, 07#4, 08#7, 10#6,
11#2, 11#10, and seven of 09#3's eight citations) — that commit cites them by number. What genuinely
remains is the *Escalated* block below plus four template-uniformity nits (05#5 closed with a written
reason, 05#9, 05#10 partly addressed by the new tracer examples, 10#4). A third blind run is the way
to confirm that claim rather than assert it.

| hat | n | ABSENT | PRESENT | PARTIAL | REGRESSED |
|---|---:|---:|---:|---:|---:|
| 01-consistency-matrix | 2 | 2 | 0 | 0 | 0 |
| 02-software-architect | 7 | 2 | 5 | 0 | 0 |
| 03-turbulence-theoretician | 10 | 8 | 0 | 2 | 0 |
| 04-dns-practitioner | 5 | 5 | 0 | 0 | 0 |
| 05-structure-consistency | 12 | 7 | 4 | 1 | 0 |
| 06-latex-typesetter | 6 | 6 | 0 | 0 | 0 |
| 07-api-user | 8 | 6 | 1 | 1 | 0 |
| 08-dimensional | 9 | 8 | 0 | 1 | 0 |
| 09-citations-integrity | 4 | 3 | 1 | 0 | 0 |
| 10-style-editor | 7 | 5 | 0 | 2 | 0 |
| 11-cold-reader | 15 | 13 | 1 | 1 | 0 |
| **TOTAL** | **85** | **65** [59] | **12** [13] | **8** [12] | **0** [1] |

## Still open

Every remaining item, by hat and number. Four are design questions escalated to the owner
rather than edits; the rest are template-uniformity nits.

- **02-software-architect #1** [PRESENT] — velocity_rhs!/scalar_rhs! destroy non-predictable argument positions
- **02-software-architect #3** [PRESENT] — FlowParameters.scalar_dissipation uses NaN sentinel
- **02-software-architect #4** [PRESENT] — prepare_forcing!'s position 2 is read-only vs mutated in the other three hooks
- **02-software-architect #6** [PRESENT] — step!'s integrator arg name collides with SciML stateful-object convention
- **02-software-architect #7** [PRESENT] — Pope2000/VonKarman1948/Pao1965 are Functions with Type-shaped names
- **03-turbulence-theoretician #3** [PARTIAL] — Energy-conserving: rotational form vs exact dealiasing
  - class alive at: architecture.md:834 (§11 decision-log entry 2) still says verbatim 'Cheap, energy-conserving spectral advection' attached to rotational form unqualified.
- **03-turbulence-theoretician #8** [PARTIAL] — StationarityCriterion documented as not reading k
  - class alive at: architecture.md:447 (§4.7) still reads verbatim 'reading ε rather than the clampable k(t)', unchanged, still implying k is never read.
- **05-structure-consistency #3** [PARTIAL] — Module-map bullet order vs page section order (Cache, Particles)
  - class alive at: Particles.jl module docstring interleaves AbstractParticleIntegrator/EndpointHeun between Tracers and particle_positions/number_of_particles, while Particles.md's "## The tracer set" section keeps Tracers+particle_positions+number_of_particles together before "## The trajectory integrator".
- **05-structure-consistency #5** [PRESENT] — Plain-constructor preamble inconsistently present
- **05-structure-consistency #7** [PRESENT] — IntegratorBuffers sub-headed Fields section
- **05-structure-consistency #9** [PRESENT] — dissipation's bulleted routes list vs sibling inline prose
- **05-structure-consistency #10** [PRESENT] — Examples heading inconsistently present
- **07-api-user #3** [PARTIAL] — Checked-read exception type stated once, off to the side
  - class alive at: src/Cache.jl particle_velocities(cache) and src/Observables.jl max_speed(cache) — both checked reads via _checked's ErrorException, neither names nor links the type.
- **07-api-user #4** [PRESENT] — No worked example wiring Simulation tracers with particle_velocities/sample!
- **08-dimensional #7** [PARTIAL] — E(κ) one glyph, two dimensions
  - class alive at: docs/ARCHITECTURE.md:324 still writes "energy_spectrum ≡ E(κ)" (should be E_n); docs/src/observables_cache.md:328's table row labels the per-shell quantity "E(κ) | per shell" — same conflation, untouched.
- **09-citations-integrity #3** [PRESENT] — Secondary Spectra citations unresolvable, unlike Sagaut & Cambon 2018
- **10-style-editor #4** [PARTIAL] — Citation-list format differs (ARCHITECTURE.md vs Phenomenology)
  - class alive at: All 12 Reference(...) strings across src/phenomenology/*.jl (StructureFunctions.jl:37,80,104,136,169; Scalings.jl:49,87,113; Spectra.jl:275,295,316,347) use short form 'Author (year), *Journal* **vol**, page' with no initials/title, vs ARCHITECTURE.md:1728-1729's long form for the same Kolmogorov 1941 citation.
- **10-style-editor #6** [PARTIAL] — Decision-log sentence opens with lowercase code identifier
  - class alive at: ARCHITECTURE.md:1680 (decision 51): '...unchanged). `advect!` keeps its generic verb and dispatches per kind...' — a new sentence opens directly with the lowercase identifier `advect!` in continuous decision-log prose, not exempt as a bulleted arg/signature. Corpus-wide grep found no other instance.
- **11-cold-reader #2** [PARTIAL] — iteration/deposit/stamp used on Home before defined
  - class alive at: index.md:48 (Quick start comment) precedes index.md:96-97 (Components gloss) in reading order.
- **11-cold-reader #10** [PRESENT] — "reified"/"reification" never glossed

## Escalated, not closed

- **02#1** `velocity_rhs!` / `scalar_rhs!` destroy different argument positions.
- **02#3** `FlowParameters.scalar_dissipation` uses a `NaN` sentinel rather than `Union{Float64,Nothing}`.
- **02#4** `prepare_forcing!`'s second argument is read-only where the other three hooks mutate theirs.
- **02#6** `integrator` names a stateless dispatch tag; in SciML it is a stateful object.
- **02#7** `Pope2000()` and friends are PascalCase *functions*, so `isa` fails on the preset name.
- **09#3** the eighth Spectra citation: "Kaneda 1993" is attached to a claim the Kaneda 1993
  paper does not appear to make. Not decorated with a DOI — an unverifiable attribution made
  authoritative is exactly what the no-guessed-citation rule forbids.

## Closed with a reason, not an edit

- **05#5** the plain-constructor preamble. Present on the small parameter records, absent on the
  types whose positional form takes preallocated internals — a distinction now written into
  `CLAUDE.md`, since naming that constructor is a claim about *who builds the value*.

# Panel round 3 — 15 hats, 2026-08-18

Fresh-eyed run over the rendered site after ~45 commits of change (ten rename classes, five
signature changes, the `Tracers` split, decisions 49–56). **114 findings.** First outing for
hats 13–15 (the rulebook hats) and for the cold reader's widened brief.

| # | hat | findings | blocker | major | minor | nit |
|---|---|---:|---:|---:|---:|---:|
| 01 | `consistency-matrix` | 4 |  | 1 | 2 | 1 |
| 02 | `software-architect` | 10 |  | 4 | 5 | 1 |
| 03 | `turbulence-theoretician` | 9 |  | 3 | 4 | 2 |
| 04 | `dns-practitioner` | 3 |  |  | 2 | 1 |
| 05 | `structure-consistency` | 10 |  | 4 | 5 | 1 |
| 06 | `latex-typesetter` | 6 |  | 1 | 3 | 2 |
| 07 | `api-user` | 8 |  | 2 | 5 | 1 |
| 08 | `dimensional` | 6 | 1 | 1 | 3 | 1 |
| 09 | `citations-integrity` | 4 |  | 1 | 1 | 2 |
| 10 | `style-editor` | 6 |  | 2 | 3 | 1 |
| 11 | `cold-reader` | 11 |  | 3 | 5 | 3 |
| 12 | `plain-sense` | 22 |  | 6 | 14 | 2 |
| 13 | `naming-policy` | 9 |  | 4 | 5 |  |
| 14 | `doc-policy` | 3 |  | 1 | 2 |  |
| 15 | `invariants-and-decisions` | 3 |  | 3 |  |  |
| | **TOTAL** | **114** | **1** | **36** | **59** | **18** |

## Verified before reporting

The discipline requires the crux of every Tier-1/2 finding checked against `src/` and the built
HTML before it is relayed. Six were checked; the results split three ways.

### CONFIRMED — the blocker, narrowed

**`max_speed`: two answers across four surfaces** (`dimensional`). Ground truth is
`max_speed(u) = maximum(norm, u)` — the whole-vector magnitude — so three of the four surfaces are
correct. The fourth is false: `docs/src/observables_cache.md:335` still says *"the `max_speed`
reduction takes the largest component magnitude directly"*, and the same row claims no component
forms the speed "even pointwise", which the fused `maximum(norm, u)` now does. **A stale sentence I
left behind when I changed the behaviour this session**, on the divisor of the adaptive timestep.
Real, but one site rather than a genuine ambiguity.

### CONFIRMED — and also mine, from this session

**The two CFL loosenesses do not "pull the same way"** (`dimensional`, major). `recommended_cfl`
says they do. They do not: a grid maximum *under*estimates the continuum supremum, making the step
too large (unsafe), while the eigenvalue bound *over*estimates the spectral radius, making the
ceiling too small (conservative). They pull in opposite directions, and the sentence is the stated
justification for the conservative factor.

### REFUTED — all three findings of one new hat

`invariants-and-decisions` returned exactly three findings, all major, all asserting that
`CLAUDE.md` still holds retired names — "stamped", `resolved_fields_modified!`, `velocity_factor`,
`cache.vorticity`, `state.velocity`. **All five terms are absent**, from both the working tree and
`HEAD`; the sweep that removed them held. A hat's first run scoring 0/3 is a fact about the
instrument, not the corpus, and it belongs in the record next to the hat that earned its keep.

## Ranked findings

### BLOCKER (1)

- **max_speed: whole-vector magnitude or largest single component? Four surfaces, two answers** — `dimensional`, high confidence.

### MAJOR (36)

- **Decision-log entries disagree about what "decision 46's pattern" is** — `consistency-matrix`, high confidence.
- **tracer_scheme (front door) renames interpolation_scheme (Tracers), beside a confusable sibling keyword** — `software-architect`, high confidence.
- **advect! argument order breaks the step!/deposit! shared-order contract** — `software-architect`, high confidence.
- **Simulation's fields expose internal per-step scratch (buffers, generator) at the same level as the sanctioned reading surfaces** — `software-architect`, medium confidence.
- **"One forcing instance per field" is enforced only by a doc warning, unlike the package's throw-on-misuse pattern elsewhere** — `software-architect`, medium confidence.
- **`max_speed` defined two incompatible ways: vector magnitude vs largest velocity component** — `turbulence-theoretician`, high confidence.
- **"No component of the iteration computes k" is false under the default forcing the page assumes** — `turbulence-theoretician`, high confidence.
- **Emptying the forced band is described as "a step with no forcing at all"** — `turbulence-theoretician`, high confidence.
- **Admonition titling is not uniform: bare Note/Warning vs. custom titles** — `structure-consistency`, high confidence.
- **Formula placement (display block vs. inline) inconsistent within one module** — `structure-consistency`, high confidence.
- **Bulleted Arguments header used for some multi-keyword types, folded into prose for siblings with equal keyword count** — `structure-consistency`, medium confidence.
- **Cache's module docstring interposes a conceptual aside before its contents list; every sibling module docstring lists first** — `structure-consistency`, medium confidence.
- **C_{OC} renders as bare italic letter-product, not upright label** — `latex-typesetter`, high confidence.
- **advance!'s docstring omits the closing deposit it performs** — `api-user`, high confidence.
- **ObservablesCache's particle_velocities keyword: type/wiring undocumented** — `api-user`, medium confidence.
- **CFL margin: two "loosenesses" said to pull the same way actually pull opposite ways** — `dimensional`, high confidence.
- **Phenomenology pages' "not duplicated in ARCHITECTURE.md" claim is false for 3 works** — `citations-integrity`, high confidence.
- **Admonition titles render literal backticks instead of code formatting** — `style-editor`, high confidence.
- **Phenomenology References-list DOIs render as dead text, unlike identical DOIs elsewhere** — `style-editor`, high confidence.
- **"deposit" is jargon used inside its own would-be definition** — `cold-reader`, high confidence.
- **No glossary exists for the package's own operational vocabulary** — `cold-reader`, high confidence.
- **FlowConditions and FlowParameters: near-identical names, overlapping fields, different jobs** — `cold-reader`, medium confidence.
- **`step!`'s argument-order paragraph states an order that is false on its natural reading** — `plain-sense`, high confidence.
- **`deposit!`'s second sentence: ~95 words, five clauses, cost accounting where the reader wants the arguments** — `plain-sense`, high confidence.
- **`Simulation`'s `initial_spectrum` entry nests parentheses two deep and buries its subject** — `plain-sense`, high confidence.
- **"not a filtered subset of the scales" — a fossil that plants the reading it denies** — `plain-sense`, high confidence.
- **Architecture §4.1's State bullet is one ~600-word paragraph containing an 85-word sentence** — `plain-sense`, medium confidence.
- **Grid mode: a dangling "which" leaves the reader guessing what credits what** — `plain-sense`, medium confidence.
- **tracer_scheme / particle_scheme swap the axis decision 51 assigns them** — `naming-policy`, high confidence.
- **Linear claims sole ownership of an identity ConstantPower shares** — `naming-policy`, high confidence.
- **peak_wavenumber promises a spectrum peak the code does not deliver** — `naming-policy`, high confidence.
- **k_max_η spells the wavenumber magnitude with the letter reserved for kinetic energy** — `naming-policy`, high confidence.
- **Spectra module docstring embeds a formula, violating "map, no formulas"** — `doc-policy`, high confidence.
- **CLAUDE.md's Cache bullet uses two terms decision 53/30 retired: "stamped" and resolved_fields_modified!** — `invariants-and-decisions`, high confidence.
- **CLAUDE.md's Generator bullet names nonexistent verbs velocity_factor / scalar_factor** — `invariants-and-decisions`, high confidence.
- **CLAUDE.md's naming-convention examples cite stale field names cache.vorticity and state.velocity** — `invariants-and-decisions`, high confidence.

### MINOR (59)

- **tracer_scheme default shown without parens, unlike sibling defaults** — `consistency-matrix`, high confidence.
- **Three docstrings credit three different actors with making particle_velocities readable** — `consistency-matrix`, low confidence.
- **FlowParameters.scalar_dissipation uses a NaN sentinel, diverging from the package-wide nothing-sentinel convention** — `software-architect`, medium confidence.
- **Cache's central epoch invariant is written from Propagator, not from Cache itself** — `software-architect`, medium confidence.
- **ObservablesCache.particle_velocities is externally-owned aliased storage, unlike every other self-allocated slot** — `software-architect`, medium confidence.
- **Simulation's explicit mode silently ignores k_max_η when viscosity is also given** — `software-architect`, medium confidence.
- **The four AbstractForcing hooks reuse the parameter name field for three physically distinct instants** — `software-architect`, medium confidence.
- **`Sreenivasan1995` preset defaults to a Kolmogorov constant that paper does not give** — `turbulence-theoretician`, medium confidence.
- **`Lundgren2002` changes sign below Re_λ ≈ 34 and states no validity floor** — `turbulence-theoretician`, medium confidence.
- **Warm-up skewness gate's default floor is a fifth of the marker it claims to enforce** — `turbulence-theoretician`, medium confidence.
- **Two current-state surfaces still call the composed spectrum presets factory functions** — `turbulence-theoretician`, high confidence.
- **"Float64 is the production precision" sits oddly against the package's own "no privileged default / fitness-tested" precision policy on a GPU-primary, consumer-GPU-targeted code** — `dns-practitioner`, medium confidence.
- **The §2.3 transform-count table's "three-stage scheme" scope is stated once, two paragraphs before the table, and not repeated at the table itself** — `dns-practitioner`, medium confidence.
- **State's two random-seeding functions omit the 'Returns x' sentence their template class otherwise always includes** — `structure-consistency`, medium confidence.
- **FlowConditions's Fields section duplicates full prose (plus Julia types); FlowParameters's equivalent is a one-line back-reference** — `structure-consistency`, medium confidence.
- **ResolvedGenerator's admonition sits mid-docstring, not near the end like its siblings** — `structure-consistency`, medium confidence.
- **Phenomenology's module docstring carries two separate contents lists where every sibling has exactly one** — `structure-consistency`, medium confidence.
- **Particles is the only API page opening with a usage-example section before its reference material** — `structure-consistency`, medium confidence.
- **Big-O order symbol styled two ways for the same concept** — `latex-typesetter`, high confidence.
- **Word-subscript labels mix \text{} and \mathrm{}, even on one page** — `latex-typesetter`, medium confidence.
- **Same constant typeset as stacked fraction and as bare slash fraction within one file** — `latex-typesetter`, high confidence.
- **Tracers' two-signature block implies dispatch the architecture says is impossible** — `api-user`, medium confidence.
- **Return-value documentation style split across modules (prose vs signature arrow)** — `api-user`, high confidence.
- **Observables' scalar reductions never show a return-type arrow, unlike Phenomenology's** — `api-user`, medium confidence.
- **Bare physical-convention symbol names document accepting spectral input** — `api-user`, medium confidence.
- **advect!'s argument order diverges from step!'s shared convention** — `api-user`, medium confidence.
- **det S — materialized by the warm-up skewness gate, or never materialized?** — `dimensional`, high confidence.
- **Scalar Dirichlet form written with φ where its velocity twin writes û** — `dimensional`, high confidence.
- **Composed spectrum presets called "factory functions" in two maps, "types" in three current-state places** — `dimensional`, high confidence.
- **Williamson (1980) "his recommended case 7" attribution is unverifiable/possibly wrong** — `citations-integrity`, low confidence.
- **Stray space renders before closing punctuation after a code/link span** — `style-editor`, high confidence.
- **Two prose sentences open with a lowercase code identifier** — `style-editor`, medium confidence.
- **The @extref exception for backend/element types is applied in notation.md but not in ARCHITECTURE.md's own prose** — `style-editor`, low confidence.
- **"register" used in two unrelated senses before the package sense is defined** — `cold-reader`, medium confidence.
- **"CFL" used unexpanded at its first two appearances** — `cold-reader`, medium confidence.
- **"the developed-turbulence markers" (plural) but only one marker is ever documented** — `cold-reader`, medium confidence.
- **"Berendsen-thermostat limit" borrowed from molecular dynamics, never explained mechanically** — `cold-reader`, medium confidence.
- **"EDQNM, DIA, LRA" acronyms never expanded anywhere on the site** — `cold-reader`, low confidence.
- **`step!`: "the step allocates and resides nothing"** — `plain-sense`, high confidence.
- **`AbstractForcing` states the return-value contract twice** — `plain-sense`, high confidence.
- **The Particles page says "changing the scheme changes nothing here" three times** — `plain-sense`, high confidence.
- **`truncate_to_band!`'s admonition argues about its own name and repeats the blurb above it** — `plain-sense`, high confidence.
- **The `Cache` module map points at verbs a reader cannot look up** — `plain-sense`, high confidence.
- **Architecture §4.7 explains an API that no longer exists** — `plain-sense`, high confidence.
- **"A fifth name is not a hook" — a denial with nothing to deny** — `plain-sense`, medium confidence.
- **`Simulation` glosses the docs' own house word inside its own docstring** — `plain-sense`, high confidence.
- **`run!` leaks the audit ledger into the front-door loop verb** — `plain-sense`, medium confidence.
- **"a solver with no cache serving only its own dynamics" — a dangling modifier** — `plain-sense`, medium confidence.
- **`SaffmanDissipation`: "about half the earlier Townsend 1951 spectrum"** — `plain-sense`, medium confidence.
- **`PhaseShift`: a relative clause torn from its noun by a 14-word gloss** — `plain-sense`, high confidence.
- **`particle_scheme` apologises for a name instead of stating what it does** — `plain-sense`, medium confidence.
- **The epoch-vs-step worked example is printed four times, verbatim** — `plain-sense`, medium confidence.
- **target names two different physical kinds of quantity across sibling forcings** — `naming-policy`, high confidence.
- **Tracers.trajectory_velocity (singular) stores what particle_velocities (plural) reads** — `naming-policy`, medium confidence.
- **Li2008's constant field uses the least specific name in its own family** — `naming-policy`, medium confidence.
- **stationary_dissipation's energy argument breaks the package-wide kinetic_energy name** — `naming-policy`, medium confidence.
- **finalize! borrows a software-engineering term where a physics verb is available** — `naming-policy`, medium confidence.
- **Pope2000 duplicates ModelSpectrum's generic formula verbatim** — `doc-policy`, medium confidence.
- **Named-method citations open the identity sentence, ahead of the formula** — `doc-policy`, low confidence.

### NIT (18)

- **"the developed-turbulence markers" (plural) names only one built marker** — `consistency-matrix`, low confidence.
- **k_max_η mixes ASCII-folded κ with literal Unicode η, contradicting its own "spelled in ASCII" claim** — `software-architect`, medium confidence.
- **Re = 1/ν asserted absolutely while the default box side is 2π** — `turbulence-theoretician`, medium confidence.
- **E_n ↔ E(κ) presented as an exact conversion by the shell width** — `turbulence-theoretician`, medium confidence.
- **IFLowStorageRK3's "two field registers per field" headline sits next to a three-array IntegratorBuffers field list** — `dns-practitioner`, low confidence.
- **Examples sections appear on a minority of types with no stated selection rule** — `structure-consistency`, low confidence.
- **theta reused in archived StochasticOU docstring against the house glyph rule** — `latex-typesetter`, medium confidence.
- **\exp\!\big(...\big) uses non-directional \big throughout vs directional \bigl/\bigr elsewhere** — `latex-typesetter`, low confidence.
- **tracer_scheme (front door) vs interpolation_scheme (Tracers) renamed forward** — `api-user`, medium confidence.
- **"Of order 10² flops per grid point" per scalar transform against the package's own 5/2·N³log₂N³** — `dimensional`, medium confidence.
- **"Kaneda 1993" cited with no bibliographic detail, unlike its paragraph neighbors** — `citations-integrity`, low confidence.
- **"the leanest of the three on a GPU" (TwoThirds) is an unsubstantiated superlative** — `citations-integrity`, low confidence.
- **"No DOI" capitalization is inconsistent between ARCHITECTURE.md and the Phenomenology reference lists** — `style-editor`, high confidence.
- **"arm"/"armed" used before its own gloss, on the same page** — `cold-reader`, low confidence.
- **PointSet / VectorPointValues / ScalarPointValues named but never characterized** — `cold-reader`, low confidence.
- **"resolved" used for two different concepts** — `cold-reader`, low confidence.
- **The notation page states the ϰ-distinctness convention twice** — `plain-sense`, high confidence.
- **"That is bookkeeping, not a slogan"** — `plain-sense`, medium confidence.


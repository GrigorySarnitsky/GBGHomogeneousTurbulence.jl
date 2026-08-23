# Cold-reader hat — first-year turbulence grad student, top-to-bottom read

Reading order followed: Home → api (overview) → notation → phenomenology (index) → api/Cache →
api/Forcing → api/GBGIsotropicTurbulence → api/Generator → api/Observables → api/Particles →
api/Propagator → api/SimulationDomain → api/SimulationRun → api/State → api/phenomenology/*.
Findings below are ordered most-severe first; each names the page where I, reading in that order,
first hit the problem.

---

## 1. The symbol `L` means two different physical lengths, and the corpus's own "single reference" page doesn't say so

**Type:** contradiction (notation) **Severity:** blocker **Confidence:** high

**Locations:**
- PAGE: notation, Numerics table: "`L` | box side (`Ω = [0,L)³`) | `side_length`"
- PAGE: api / phenomenology / Spectra, `ModelSpectrum`: "`E(κ) = C_K ε^{2/3} κ^{-5/3} f_L(κL) f_η(κη)`" and "reads ε and the roll-off's own length `L` (see `large_scale_length` — `L₁₁` for most forms, `k^{3/2}/ε` for Pope's)"

**Contradicts:** The Notation page states, as its own governing claim, "This page is the single reference — a docstring introduces a symbol on first use and need not repeat the convention," then binds `L` exclusively to `side_length` (the numerical box size). The `ModelSpectrum` formula reuses the bare glyph `L` for `large_scale_length` — physically `L₁₁` (the measured integral scale) or `k^{3/2}/ε` (Pope's `L₀`) — a turbulence quantity independent of the box geometry.

**Description:** I read the Notation page first and filed `L` ≡ box side. Two pages later `ModelSpectrum`'s formula `f_L(κL)` reads, at face value, as "wavenumber times box side" — but the prose two sentences later reveals `L` there actually means `L₁₁` or `k^{3/2}/ε`. Since the box side and the integral scale are two different quantities that need not be proportional (a large box with weakly energetic large scales, say), this is a load-bearing symbol reuse the Notation page's own promise says should not happen. A reader who trusts the glossary as instructed will mis-parse the formula.

---

## 2. `epoch` is used, unglossed, in the very first code example — two pages before its definition

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: Home, Quick start code comment: "each recorded against the epoch of the state it came from"
- PAGE: notation, Vocabulary: "epoch | a counter of changes to the state..."

**Description:** `epoch` is an ordinary English word (a period of time / a moment), and the running mental model I formed from the Quick-start prose two lines earlier ("the state came from") reinforced the wrong reading — "the epoch" sounds like it means "the timestamp `t_n`." It is not: it's a monotonic per-dynamical-factor counter that also advances on out-of-band mutations that don't move the clock at all. This is exactly the flagged word-with-package-meaning case: I could not have derived the real (surprising) semantics from the first-use context, and the definition doesn't arrive until the Notation Vocabulary two pages later, then the full Cache-page treatment three pages after that.

---

## 3. `out-of-band` is used for two unrelated things across the same short vocabulary word

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: notation / api Cache: "an announced out-of-band mutation advances an epoch without advancing the clock" (a hand-made state change made outside the iteration cycle)
- PAGE: api / Forcing, `BandRescaling`: "If the out-of-band value alone exceeds `target`, the band is zeroed" (the energy in wavenumber shells outside the forced band)

**Contradicts:** Same two-word phrase, two disjoint referents — a software-control-flow sense (page 3/5) versus a spectral-shell sense (page 6) — with no signal at either site that the phrase is being repurposed.

**Description:** By the time I reached the Forcing page I had "out-of-band = an unsanctioned hand-made mutation" cached from the Cache/Notation pages. Reading "the out-of-band value alone exceeds `target`," I first parsed it as "some value computed outside the normal update path," which is wrong — it means the field's energy in the un-forced wavenumber shells. This is the classic ordinary-phrase-carries-package-meaning trap, doubled: it carries *two* different package meanings.

---

## 4. `ResolvedFields` / `ResolvedGenerator` collide with the numerical sense of "resolve" used on the very same page

**Type:** clarity **Severity:** major **Confidence:** medium-high

**Locations:**
- PAGE: Home, Quick start comment: "ν is set so the grid resolves the dissipation scale" (numerical sense)
- PAGE: Home, Components: "`ResolvedFields`, the single source of truth" and "gathered into one object, the `ResolvedGenerator`" (no gloss given)
- PAGE: notation, Vocabulary (two pages later): "resolved | in `ResolvedFields` and `ResolvedGenerator`, made concrete as one value. The numerical sense — a scale the grid resolves... is the other reading"

**Description:** The Home page uses "resolve" in its ordinary numerical-turbulence sense (line 31) a few lines before introducing two capitalized type names built on the *other* sense of the same word ("made concrete as one value" — closer to "resolved" as in "resolved dependencies"). Nothing on Home page flags that these are different senses; I only learned there even *was* a collision when I reached the Notation Vocabulary's own admission of it, two pages later, and by then I had already silently misread `ResolvedFields` as "the fields the grid resolves."

---

## 5. The module is `Particles`, everything in it is `particle_*`-named, but the only concrete type is `Tracers` — and the corpus never says why

**Type:** clarity **Severity:** major **Confidence:** high

**Locations:**
- PAGE: Home, Components: "`Particles`: Lagrangian tracer tracking..."
- PAGE: api / Particles, module docstring: "`Tracers` — the tracer set..."; "`AbstractParticleIntegrator`, `EndpointHeun` — the trajectory time-integration schemes"; accessors `particle_positions`, `particle_velocities`, `number_of_particles`

**Description:** Every public name in this module is prefixed or rooted `particle_` / `Particle` (the module, `AbstractParticleIntegrator`, `ParticleIntegratorBuffers`, `particle_positions`, `particle_velocities`, `number_of_particles`), but the one concrete state type is called `Tracers`, not `Particles`. Nowhere on any page I read is it said whether "tracer" is simply a synonym for "particle" here, or a specific (massless) case implying other particle kinds exist or are planned. A newcomer is left to guess whether `Tracers` is *the* particle type or *a* particle type.

---

## 6. The bare symbol `A` is used for two unrelated quantities in adjacent API pages

**Type:** contradiction (notation) **Severity:** moderate **Confidence:** medium-high

**Locations:**
- PAGE: api / Propagator, `IFLowStorageRK3`: "with `A = (0, -5/9, -153/128)`, `B = (1/3, 15/16, 8/15)`..." (the RK stage-coefficient tuple)
- PAGE: api / Generator, `velocity_integrating_factor`: "with `A = 0` when no linear forcing is active" (the per-mode forcing rate)

**Description:** The Notation page keeps these apart by subscript/argument (`A_i` vs `A(κ)`), but both docstrings drop to the bare glyph `A` for a "the value is trivially ..." aside, and at that point the two meanings (a fixed 3-tuple of RK coefficients vs. a per-mode forcing-rate field, possibly `nothing`) are indistinguishable from the glyph alone. A reader skimming just the formulas, as the house style encourages, can momentarily attach the wrong value to `A`.

---

## 7. "mode" quietly switches from "Fourier mode" to "code branch" mid-corpus

**Type:** clarity **Severity:** moderate **Confidence:** medium

**Locations:**
- PAGE: api / SimulationRun, `Simulation`: "Grid mode (no `viscosity`): ..." / "Explicit mode: pass `viscosity`..."
- PAGE: api / State, `random_solenoidal_velocity_spectral!`: "the two modes do not seed the same large scale at the same nominal setting"
- (pervasive prior sense) PAGE: notation and many pages: "per-mode multiplier," "the zero mode," "Nyquist mode"

**Description:** By the time I reach `Simulation`'s constructor, "mode" has meant "a single Fourier coefficient" dozens of times. "Grid mode" / "Explicit mode" as labels for two *configuration branches* of the same constructor, and later "the two modes" for the default-envelope-vs-`initial_spectrum` branches of a seeding function, reuse the word for "a way of operating" — a completely different sense, in a document that is otherwise scrupulously spectral. It reads naturally as English but costs a re-parse in a document this saturated with the other sense.

---

## 8. The tracking-loop intro states an order, then its own next sentence reverses it

**Type:** contradiction (organization) **Severity:** moderate **Confidence:** medium

**Locations:**
- PAGE: api / Particles, "The tracking loop": "record the flow velocity where each tracer currently sits, advance the tracers once the fields have moved, then read any physical field..."
- Same paragraph, next sentence: "the run records the sample at the iteration's end, off the just-deposited velocity, and the next iteration's `advect!` reads it back"

**Contradicts:** record → advance → read (first sentence) vs. advance (using last iteration's record) → record (this iteration's end) (second sentence).

**Description:** Read as a literal ordered list — which "the steps of Lagrangian tracking:" strongly invites — the first sentence has recording happen *before* advection within an iteration. The second sentence, and the worked example on the same page (`record_particle_velocities!` called first, annotated "do this first," before `advect!`), together establish that the *effective* per-iteration order is advect-then-record (the record just made is consumed by *next* iteration's advect). The opening sentence is best read as listing the three available verbs, not a per-iteration sequence, but nothing marks that distinction, and a first read gets the wrong mental model.

---

## 9. `taken` is used as an enumerated cache-slot state with no gloss at its first appearance

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: api / Cache, `ObservablesCache`: "a read that finds a stale, taken, or never-deposited slot reports a scheduling error"

**Description:** "Stale" and "never-deposited" are self-explanatory; "taken" is not glossed anywhere as one of the three named failure states, and the fact that it means "currently in use as the step's own mid-iteration scratch" only becomes clear from later, differently-worded passages (`IntegratorBuffers`: "There are deliberately no physical-representation registers here... taken as scratch mid-iteration"). At first encounter it reads like an ordinary adjective ("occupied") whose precise package meaning I had to reconstruct from unrelated text several sections later.

---

## 10. Four different names for the same quantity — `u(t_n, X(t_n))`

**Type:** clarity **Severity:** minor **Confidence:** medium

**Locations:**
- PAGE: notation: "particle velocities" (table entry)
- PAGE: api / Particles, module docstring: "the trajectory velocities are read from the run's observables cache through `particle_velocities`"
- PAGE: api / Particles, `record_particle_velocities!`: "the genuine Lagrangian velocity" / "the Lagrangian sample"

**Description:** The same physical quantity is named "particle velocities" (Notation, and the code symbol), "trajectory velocities" (Particles module docstring's own first sentence about it), and "the Lagrangian velocity" / "the Lagrangian sample" (used repeatedly thereafter). Each occurrence is locally clear from context, but a first-time reader collecting vocabulary has to independently verify these four phrases denote one thing rather than three, in a corpus that otherwise (per its own Vocabulary page) insists on one term per concept.

---

## 11. "checked accessors" (Home) vs. "The checked reads" (Cache page heading) — one concept, two names

**Type:** format **Severity:** nit **Confidence:** medium

**Locations:**
- PAGE: Home, Components: "read through checked accessors that serve the deposited value or throw"
- PAGE: api / Cache, section heading: "## The checked reads"

**Description:** Minor, but the corpus is explicit elsewhere about picking one term per concept (the Notation Vocabulary page). "Checked accessor" and "checked read" refer to the identical thing (`velocity_physical`, `vorticity_physical`, etc.) and are never explicitly equated.

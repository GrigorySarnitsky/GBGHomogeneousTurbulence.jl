# Closure — 05-structure-consistency

Adjudicated against the current corpus (`src/*.jl`, `docs/ARCHITECTURE.md`, `docs/src/`) only.
Seven findings enumerated from the banked hat file; one verdict each below.

---

### Finding 1 — `Returns x.` sentence placement inconsistent across in-place mutators

**VERDICT: PRESENT**

Evidence: the two placements both still occur. Final-sentence group confirmed: `prepare!`
(`src/Generator.jl:257`, "...then consume what it prepared. Returns `generator`.\n\"\"\""),
`finalize!` (`src/Generator.jl:283`, "...sees the forced end-of-step fields.\nReturns `state`.\n\"\"\""),
`deposit!` (`src/Propagator.jl:497`, "...Returns `cache` (or `sim`).\n\"\"\""). Mid-docstring-with-more-prose
group confirmed: `fields_modified!` (`src/Cache.jl:309`, "...Returns `cache`.\n\nThe sanctioned mutators
call this for you: ..."), `particles_modified!` (`src/Cache.jl:329`, same shape), `vorticity_physical!`
(`src/Observables.jl:168`, "Returns `ω`.\n\nThe deposited value is read back with..."),
`truncate_to_band!` (`src/SimulationDomain.jl:363`, "Returns `field`.\n\n!!! note ..."),
`random_solenoidal_velocity_spectral!` and `random_scalar_spectral!` (`src/State.jl:92`/`171`, "Returns
`û`."/"Returns `φ̂`." each followed by a caveat admonition). `step!` itself changed shape — `Returns
`state`.` (`src/Propagator.jl:197`) now precedes its admonition rather than following it — but the
class the finding names (inconsistent placement across the "no-arrow mutator" set) is still broadly
alive across the other seven sites.

**surviving_class**: `fields_modified!`, `particles_modified!`, `vorticity_physical!`,
`truncate_to_band!`, `random_solenoidal_velocity_spectral!`, `random_scalar_spectral!` (mid-docstring)
vs. `prepare!`, `finalize!`, `deposit!` (final sentence).

---

### Finding 2 — Some constructors document keywords only in prose, skipping bulleted Arguments

**VERDICT: PARTIAL**

Evidence: `BandRescaling` (`src/Forcing.jl:220`) now carries a full `# Arguments` section
(`src/Forcing.jl:261-269`) documenting `domain`, `target`, `over`, `lowest_shell`, `highest_shell` —
the specific defect the finding names for it is fixed. `ResolvedGenerator`
(`src/Generator.jl:170`/`238`, `ResolvedGenerator(domain, conditions; scalar = false)`) still has no
`# Arguments` heading; `domain`, `conditions`, `scalar` remain described only in the prose sentence
"Build it on the `FixedDomain` `domain` from the `conditions`; pass `scalar = true`..."
(`src/Generator.jl:187-189`). Compare `ObservablesCache` (`src/Cache.jl:66`), whose comparably-shaped
constructor (`domain` positional + two keywords) *does* list `domain` in its own bulleted `# Arguments`
(`src/Cache.jl:84-88`) — so the inconsistency the finding flags survives at `ResolvedGenerator`.

**surviving_class**: `ResolvedGenerator(domain, conditions; scalar = false)` (`src/Generator.jl:238`).

---

### Finding 3 — Module docstring (Cache) carries a Type-docstring device (titled admonition)

**VERDICT: ABSENT**

Evidence: the `Cache` module docstring (`src/Cache.jl:10-48`) no longer contains any `!!!` admonition;
it now ends in plain prose ("...the clock's `current_step` answers 'how far has the run gone?'.").
`rg --glob '!.claude/**' -n "!!!" src/Cache.jl` limited to lines 10–48 returns nothing. Checked every
other module docstring's span (Forcing, Generator, Observables, Particles, Propagator, SimulationDomain,
SimulationRun, State) for a `!!!` block before its `module X` line — none has one, so the class is not
alive elsewhere either. The epoch-vs-iteration content now lives only in the decision log
(`docs/ARCHITECTURE.md:1734`, decision 53), not in the module docstring.

---

### Finding 4 — `StationarityCriterion`'s Fields section names its own constructor, then disclaims it

**VERDICT: PARTIAL**

Evidence: the exact text quoted by the finding — the full positional signature
`StationarityCriterion(monitor, max_turnovers, gate_scalar, elapsed_turn, last_time, started)` labeled
"internal" — is gone; that string does not appear anywhere in `src/SimulationRun.jl`. But the `# Fields`
section (`src/SimulationRun.jl:591-599`) still uniquely singles out and disclaims its own positional
form: "Build one through the keyword constructor above — the positional form takes assembled internals
and is not part of the interface." Every sibling machinery-type Fields section (`ObservablesCache`
`src/Cache.jl:102`, `Simulation` `src/SimulationRun.jl:191`, `IntegratorBuffers` `src/Propagator.jl:103`)
omits any mention of its own constructor entirely, per the house convention CLAUDE.md states for such
types — `StationarityCriterion` still does not follow either clean pattern (neutral presentation or
silent omission), a softened instance of the same outlier.

**surviving_class**: `StationarityCriterion`'s `# Fields` section (`src/SimulationRun.jl:591-595`) is
the only one in the corpus that discusses its own positional constructor's interface status.

---

### Finding 5 — Two types append explanatory prose after their Fields bullet list

**VERDICT: ABSENT**

Evidence: `IntegratorBuffers` (`src/Propagator.jl:103-116`) now ends its docstring immediately after the
last `# Fields` bullet (`scalar` bullet, line 113) with no trailing paragraph. `Tracers`
(`src/Particles.jl:69-121`) moved the flagged sentence ("The trajectory scheme's own working storage is
**not** here...") to *before* `# Fields` (line 110-111), and its Fields section
(`src/Particles.jl:114-121`) now ends cleanly at the last bullet. Swept every other `# Fields` section in
`src/*.jl` (Cache, Forcing, Generator ×2, Phenomenology ×2, Particles ×2, Propagator, SimulationDomain
×2, State, SimulationRun ×2) for trailing prose after the last bullet before the closing `"""` — none
found; all end at the bullet list or within a bullet's own continuation.

---

### Finding 6 — Two docstrings interleave ordinary prose between two caveat admonitions

**VERDICT: PARTIAL**

Evidence: `max_speed` (`src/Observables.jl:127-158`) is fixed — the plain paragraph ("The second form
reads the number back from an `ObservablesCache`...") now sits *before* both admonitions
(`src/Observables.jl:135-138`), and the two `!!! note` blocks are now consecutive, the second ending the
docstring. `BandRescaling` (`src/Forcing.jl:220-282`) still interleaves: admonition "Which one a run
wants depends on..." (`src/Forcing.jl:238-244`), then the plain sentence "Rescaling preserves the
divergence-free constraint either way." (`src/Forcing.jl:246`), then a `# Arguments` section
(`src/Forcing.jl:261-269`), then the second admonition "A deterministic clamp, not a stationary
sampler..." (`src/Forcing.jl:271-282`) — the last-block convention is still broken here.

**surviving_class**: `BandRescaling` (`src/Forcing.jl:220`).

---

### Finding 7 — `energy_spectrum` states an explicit `Returns` sentence; its Observables siblings never do

**VERDICT: PRESENT**

Evidence: `energy_spectrum` (`src/Observables.jl:283-286`) still closes "...Returns a named tuple `(;
wavenumbers, energy)`: the shell-center wavenumber magnitudes...". `kinetic_energy`
(`src/Observables.jl:48-63`), `integral_scale` (`src/Observables.jl:303-329`), `derivative_skewness`
(`src/Observables.jl:224-263`), and `dissipation` (`src/Observables.jl:97-119`) each still end their
identity/formula prose with no trailing "Returns ..." sentence. `rg -n "Returns" src/Observables.jl`
finds exactly two hits in the whole file: `vorticity_physical!`'s (an in-place mutator, a different
class) and `energy_spectrum`'s — confirming it remains the sole pure reduction with one.

# Closure audit — hat 05-structure-consistency

## Finding 1 — Caveat-admonition placement drifts (BandRescaling, ConstantPower)
**Verdict:** PRESENT
**Evidence:** `src/Forcing.jl` `BandRescaling` still carries a `!!! note` at line 255 (before `# Arguments` at 263) plus two more at lines 279 and 286, both after `# Fields` (274). `ConstantPower`'s `!!! note "An empty band is left alone…"` sits at line 400, before its `# Arguments` at 407. Neither ends on its caveat. (Note: the `Contradicts` example `FlowConditions`, `src/Generator.jl:75`, now shows its warning as a standalone block after `# Arguments`/before `# Fields`, not embedded in a bullet — that sub-detail has changed, but it doesn't affect the core finding.)

## Finding 2 — Forcing's module docstring never bullets its own concrete strategy types
**Verdict:** PRESENT
**Evidence:** `src/Forcing.jl:35-37`: "The strategies are [`NoForcing`](@ref), [`BandRescaling`](@ref), [`Linear`](@ref) and [`ConstantPower`](@ref), one implementation serving both the velocity and the scalar…" — still one prose sentence, no bullets, unlike Cache/Propagator/SimulationDomain module docstrings checked directly.

## Finding 3 — Module-docstring "trailing remark" ranges from none to a multi-paragraph essay
**Verdict:** PRESENT
**Evidence:** `src/Particles.jl:16-32` and `src/Propagator.jl:21-37` end right at the last bullet, no remark. `src/Cache.jl:10-46` carries several trailing paragraphs ending "…advances of the run…". `src/Observables.jl:8-38` ends with a long trailing paragraph, "…the cubic skewness carries the slight residual its own docstring prices." Spread unchanged.

## Finding 4 — `Simulation` inserts a bespoke narrative section before its `# Arguments`
**Verdict:** PRESENT
**Evidence:** `src/SimulationRun.jl:86` `# Setting the Reynolds number` (prose + `!!! note` at 95 + bulleted Grid-mode/Explicit-mode list) still sits between the identity prose (ending ~84) and `# Arguments` (134).

## Finding 5 — `ObservablesCache` doesn't end on its caveat admonition either
**Verdict:** PRESENT
**Evidence:** `src/Cache.jl:95` `!!! note "A cached array is the next iteration's scratch"` is followed by the paragraph at line 100, "The word *epoch* names two things here…", before `# Fields` at 105 — same class as Finding 1.

## Finding 6 — `Phenomenology`'s module docstring is the only one to use an admonition box
**Verdict:** PRESENT
**Evidence:** `src/Phenomenology.jl:42` `!!! note "Extraction-bound"` inside the module docstring. Checked all nine DNS-side module docstrings (Cache, Forcing, Generator, Observables, Particles, Propagator, SimulationDomain, SimulationRun, State) for `!!!` inside their docstring spans: zero admonitions in any of them.

## Finding 7 — `Simulation`'s `# Examples` skips the lead-in sentence every other one has
**Verdict:** PRESENT
**Evidence:** `src/SimulationRun.jl:192-194`: `# Examples` is followed immediately by a fenced code block, no prose sentence. Contrast `src/SimulationDomain.jl:164-166` ("A default box, and one that keeps a wider band…"), `src/Particles.jl:78-80`, `src/Forcing.jl:112-114` — all still frame with a sentence first.

## Finding 8 — Six positional-only presets restate their own already-positional signature in `# Fields`
**Verdict:** PRESENT
**Evidence:** `src/phenomenology/Spectra.jl`: `PopeLargeScale` (126/134), `PopeDissipation` (151/160), `VonKarmanLarge` (173/181), `PaoDissipation` (214/222), `ExponentialDissipation` (233/253), `ModelSpectrum` (281/305) all still open with a positional-only signature and then restate the identical call in "# Fields... takes the N fields directly," with no keyword form anywhere. `HouLi` (`src/SimulationDomain.jl:71` keyword vs `:92` positional) remains the genuine contrast case.

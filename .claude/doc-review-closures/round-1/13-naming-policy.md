# Closure audit — Hat 13: naming-policy

## Finding 1 — `tracer_scheme` / `particle_scheme` swap the axis decision 51 assigns them

**VERDICT: ABSENT**

Evidence: `grep -rn "tracer_scheme\|particle_scheme" src/ docs/` returns nothing — neither
identifier exists anymore. The front-door keywords are now `interpolation_scheme` (spatial,
ladder-general; `src/SimulationRun.jl:158-162,226`) and `trajectory_scheme` (temporal,
`EndpointHeun`-specific; `src/SimulationRun.jl:163-165,227`). Both avoid the loaded
`tracer`/`particle` words entirely — the exact "keep `interpolation_scheme` verbatim, avoiding
both loaded words" alternative the finding's own resolution hint offered. The backwards swap the
finding described no longer exists under any name.

---

## Finding 2 — `Linear` claims an identity `ConstantPower` shares

**VERDICT: PRESENT**

Evidence: `src/Forcing.jl:289-302` — `Linear` docstring still opens "Linear (negative-damping)
forcing … the **fixed-rate** member of the two linear forcings"; `ConstantPower`'s docstring
(`src/Forcing.jl:325-346`) still says "a banded linear forcing" and "like `Linear`, it preserves a
solenoidal velocity." `docs/ARCHITECTURE.md:356` still calls both "the two linear forcings." The
bare type name `Linear` is unchanged; no rename (`FixedRate`, `LinearDamping`, etc.) landed.

---

## Finding 3 — `peak_wavenumber` promises a spectrum peak the code does not deliver

**VERDICT: ABSENT**

Evidence: `grep -rn "peak_wavenumber" src/` returns nothing. The keyword is now
`envelope_wavenumber` everywhere it appears: `src/State.jl:66,77,102,114,137,151,175,188` and
`src/SimulationRun.jl:150,156,225,250,255,256`. The docstrings still correctly caveat that the
shell-summed spectrum peaks at `κ_p/√2` (`src/State.jl:79,153`), but the keyword itself no longer
claims to be a "peak" — it is named for exactly what it delivers, matching the finding's own
resolution hint verbatim.

---

## Finding 4 — `k_max_η` spells the wavenumber magnitude with the kinetic-energy letter

**VERDICT: ABSENT**

Evidence: `grep -rn "[^κ]k_max_η\|^k_max_η" src/*.jl docs/src/*.md docs/ARCHITECTURE.md` returns
nothing — no ASCII-`k` spelling remains. The keyword is now `κ_max_η` (the actual Unicode kappa
glyph, not the Latin letter `k`) throughout: `src/SimulationRun.jl:65,68,101-131,218,234,236` and
`docs/ARCHITECTURE.md:441,935`. This no longer collides with `k` (kinetic energy) — the collision
the notation page's "Wavenumber clash" entry (`docs/src/notation.md:20`) flags.

---

## Finding 5 — `target` names two different physical kinds across sibling forcings

**VERDICT: PRESENT**

Evidence: `src/Forcing.jl` — `BandRescaling` (`:205-267`) and `ConstantPower` (`:325-359`) both
still take a keyword/field literally named `target` (`target::T` at lines 259 and 351). The
`ConstantPower` docstring (`:338-339`) still carries the explicit warning "Note what kind of
quantity that is: here the held observable is a **rate**, where `BandRescaling` holds an
**amplitude**" — unchanged from the finding's quote. No `target_amplitude`/`target_rate` split, or
any other disambiguation, was made.

---

## Finding 6 — `Tracers.trajectory_velocity` (singular) vs `particle_velocities` (plural)

**VERDICT: ABSENT**

Evidence: `src/Particles.jl:118,129,228,242,289` — the `Tracers` struct field is now
`particle_velocities::VV` (plural), matching `Cache.particle_velocities` exactly
(`src/Cache.jl:27,52,63,76-77,102,118,130,133,212,224-232`). The grammatical-number drift the
finding flagged is gone: both sides of the pair now share the identical plural name. (The verb
`record_trajectory_velocity!` still carries "trajectory" singular, but that is a different
identifier — a function name, not the storage field the finding is about.)

---

## Finding 7 — `Li2008(; constant = 0.9)` names its parameter with the least specific word

**VERDICT: PRESENT**

Evidence: `src/phenomenology/Scalings.jl:117,141,147-154` — the keyword, the plain-constructor
field name, and the struct field are all still literally `constant`
(`struct Li2008 <: ScalingLaw; constant::Float64; end` at `:150-152`; `Li2008(; constant = 0.9) =
Li2008(constant)` at `:154`). No rename to `G` or `box_normalized_constant` landed; the docstring
still explains "The `constant` is the group value ``G``" (`:141`), same indirection the finding
quoted.

---

## Finding 8 — `stationary_dissipation`'s `energy` argument breaks with `kinetic_energy`

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Scalings.jl:38,142,158` — the signature is now
`stationary_dissipation(law, kinetic_energy, side_length)` and the method definition
`stationary_dissipation(m::Li2008, kinetic_energy::Real, side_length::Real) = …` (`:158-159`).
`grep -n "energy" src/phenomenology/Scalings.jl` shows only `kinetic_energy` spellings in this
docstring/signature — the bare `energy` argument name is gone, now matching
`Observables.kinetic_energy` and the `Simulation(; kinetic_energy = …)` keyword exactly.

---

## Finding 9 — `finalize!` borrows a software-engineering term for a physics action

**VERDICT: PRESENT**

Evidence: `src/Generator.jl:30,48,186,277,287` — the verb is still `finalize!`
("`finalize!` — close a step: apply the post-step forcing projections to the advanced state").
`docs/ARCHITECTURE.md:1149-1153` still records "**`finalize!` on the generator is a recorded
deviation** from the solver-library precedent (the SciML/PETSc/SUNDIALS right-hand-side objects
are pure evaluators …)" verbatim as before. No rename (`apply_forcing_projections!` or similar)
was made; the finding itself flagged this as low-cost/low-urgency and it was left as-is.

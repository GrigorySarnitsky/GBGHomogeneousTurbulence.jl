# Closure audit — 13-naming-policy

## 1. `tracer_scheme` / `particle_scheme` swap the very axis decision 51 assigns them
**Verdict:** ABSENT
**Evidence:** No occurrence of `tracer_scheme`/`particle_scheme` anywhere in `src/` or `docs/`
(`grep -rn "tracer_scheme\|particle_scheme"` empty). `Simulation`'s front-door keywords are now
`interpolation_scheme = CatmullRom` (spatial) and `trajectory_scheme = EndpointHeun()` (temporal) —
`src/SimulationRun.jl:162,165` — neither reuses the loaded "tracer"/"particle" words, so the swap the
finding flagged cannot recur under these names.

## 2. `Linear` claims an identity `ConstantPower` shares
**Verdict:** PRESENT
**Evidence:** Struct still bare-named `Linear` and exported alongside `ConstantPower`, `BandRescaling`,
`NoForcing` (`src/Forcing.jl:54,319`). `ConstantPower`'s docstring still says "a banded linear forcing"
(`src/Forcing.jl:342`) and explicitly calls itself and `Linear` "the two linear forcings" family
(`src/Forcing.jl:308-309`). Cross-referencing prose was added, but the type name itself — the thing the
finding calls out — is unchanged; no rename to `FixedRate`/`LinearDamping` occurred.

## 3. `peak_wavenumber` promises a spectrum peak the code does not deliver
**Verdict:** ABSENT
**Evidence:** `grep -rn "peak_wavenumber"` across `src/` and `docs/` returns nothing. The keyword is now
`envelope_wavenumber` everywhere (`src/State.jl:66,102,137,175`; `src/SimulationRun.jl:152`), matching
the resolution hint verbatim, and the docstrings state the shell-summed peak sits at
`κ_p/√2` as a caveat rather than a name the keyword contradicts.

## 4. `k_max_η` spells the wavenumber magnitude with the letter reserved for kinetic energy
**Verdict:** ABSENT
**Evidence:** The keyword is now the Unicode `κ_max_η` (`src/SimulationRun.jl:65,68,132,224,240-242`),
not the ASCII `k_max_η`. No remaining ASCII `k_max` spelling found
(`grep -rn "k_max_η\|kappa_max_eta"` empty). The collision with the house rule reserving bare `k` for
kinetic energy is gone since the identifier itself now uses `κ`.

## 5. `target` names two different physical *kinds* of quantity across sibling forcings
**Verdict:** ABSENT
**Evidence:** `ConstantPower`'s keyword is now `injection_rate` (`src/Forcing.jl:341,346,354,370,481`),
distinct from `BandRescaling`'s `target` (`src/Forcing.jl:220,227,279,484`). `ConstantPower`'s docstring
states the keyword "is named for the kind of quantity it is: a rate, where `BandRescaling`'s `target` is
an amplitude — which is why the two strategies do not share one keyword name" (`src/Forcing.jl:359-361`).
No shared ambiguous name remains.

## 6. `Tracers.trajectory_velocity` (singular) stores what `particle_velocities` (plural) reads
**Verdict:** ABSENT
**Evidence:** The `Tracers` struct field is now `particle_velocities` (`src/Particles.jl:118,129,243,290`),
matching the cache accessor/slot name `particle_velocities` (`src/Cache.jl:26,105,121,215,227`) exactly —
same plural spelling on both sides of the pair. (A verb `record_particle_velocity!` still exists but
names an action, not the storage the finding compared.)

## 7. `Li2008(; constant = 0.9)` names its one parameter with the least specific word available
**Verdict:** ABSENT
**Evidence:** The keyword and field are now `dissipation_group`
(`src/phenomenology/Scalings.jl:117,147,150,154,156`), not `constant`. `grep -n "constant" src/phenomenology/Scalings.jl`
shows no residual bare `constant` field/keyword for `Li2008`.

## 8. `stationary_dissipation`'s `energy` argument breaks with the package-wide `kinetic_energy` name
**Verdict:** ABSENT
**Evidence:** Signature is now `stationary_dissipation(law, kinetic_energy, side_length)`
(`src/phenomenology/Scalings.jl:38,142`) and the sole method
`stationary_dissipation(m::Li2008, kinetic_energy::Real, side_length::Real)` (line 158) — argument
renamed to match the package-wide spelling; no other `stationary_dissipation` method exists with a
different argument name.

## 9. `finalize!` borrows a software-engineering term where the physics is a specific, nameable action
**Verdict:** PRESENT
**Evidence:** Verb is unchanged: `finalize!` still exported and used throughout
(`src/Generator.jl:30,48,184,274,284`; `src/Propagator.jl:41,185,320,421`;
`src/GBGIsotropicTurbulence.jl:106,196`). ARCHITECTURE.md:1155 still flags it as "a recorded deviation
from the solver-library precedent." No rename to a physics-facing verb occurred.

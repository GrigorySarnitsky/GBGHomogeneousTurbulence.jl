# Closure — 13-naming-policy

## Finding 1 — `record_particle_velocities!` root mismatch
**Verdict:** PRESENT
**Evidence:** The verb itself is already `record_particle_velocities!` (src/Particles.jl:246), matching the `particle_velocities` root. But the class the finding names — a third root, "trajectory," used for the same Lagrangian-velocity quantity in the same docstring — survives: `src/Particles.jl:22` ("the trajectory velocities are read from the run's observables cache through [`particle_velocities`]") and again verbatim at `src/Particles.jl:107-108` in the `Tracers` docstring. Renders into `docs/build/api/Particles/index.html`.
**Surviving class:** "trajectory velocities" (prose) vs. `particle_velocities` (binding) coexist in both the `Particles` module docstring and the `Tracers` type docstring — the exact one-sentence root mixing the finding flagged, just at the noun phrase rather than the verb.

---

## Finding 2 — `max_wavenumber` reads as grid Nyquist
**Verdict:** PRESENT
**Evidence:** `src/SimulationDomain.jl:277-295`: function is still named `max_wavenumber`; docstring still must say "It is the cutoff the dealiasing sets — **not** the grid Nyquist ``\tfrac{N}{2}\tfrac{2\pi}{L}`` itself." No `dealiased_max_wavenumber` / `resolved_max_wavenumber` binding exists (grep empty).

---

## Finding 3 — `FlowConditions` / `FlowParameters` near-identical names
**Verdict:** PRESENT
**Evidence:** `src/Generator.jl:52-62`: `FlowConditions(; viscosity, schmidt, velocity_forcing, scalar_forcing)`, docstring still reads "Not to be confused with `Phenomenology`'s `FlowParameters`, which shares two field names." `src/Phenomenology.jl:68-71` still defines `FlowParameters(; viscosity, dissipation, rms_velocity, integral_scale, schmidt, ...)`. No `MeasuredFlowState` or similar rename found.

---

## Finding 4 — "spectrum" names two dimensionally different objects
**Verdict:** PRESENT
**Evidence:** `src/Observables.jl:279-299` `energy_spectrum(û, domain)` still returns per-shell ``E_n``; `src/phenomenology/Spectra.jl:311,432` `spectrum(m, κ, fp)` still returns the density ``E(\kappa)``. Docstring still explains "so the two differ by the shell width ... and are not interchangeable" — disambiguation still lives in prose, not the identifiers. No `shell_energy`/`energy_per_shell` rename found.

---

## Finding 5 — `integral_scale` returns specifically ``L_{11}``
**Verdict:** PRESENT
**Evidence:** `src/Observables.jl:304-335`: function still named `integral_scale` (not `longitudinal_integral_scale`); its docstring now opens "The longitudinal integral length scale..." (an improvement to the prose) but still goes on to define ``L_{22}`` and ``L_E`` as siblings, and the module map (`src/Observables.jl:23-24`) still calls it generically "the integral length scale." The identifier itself remains unqualified.

---

## Finding 6 — `*_star_spectral` vs `predictor*` root mismatch
**Verdict:** ABSENT
**Evidence:** `src/Propagator.jl:109,121`: the field-side struct fields are now `stage2`/`velocity_predictor_spectral` (scalar side: `predictor_spectral`), not `velocity_star_spectral`. Searched `rg "_star" src/ docs/src/ docs/ARCHITECTURE.md` — only hits are local math-notation temporaries `u_star`/`ω_star`/`φ_star` (Propagator.jl:404-411), not storage-field names, and those mirror math notation ``\hat u^*`` per the naming convention (math variables are symbol-named). The particle side already used `predictor`/`velocity_predictor` (src/Particles.jl:211-213); both sides now share the "predictor" root as the finding's resolution hint proposed.

---

## Finding 7 — `BandRescaling`'s `over` keyword
**Verdict:** PRESENT
**Evidence:** `src/Forcing.jl:220,235,289` — keyword is still `over` (`BandRescaling(domain; target, over, lowest_shell=1, highest_shell=2)`); docstring: "The `over` keyword selects where the target applies. It is **required**." No `hold`/`pin_scope` rename found.

---

## Finding 8 — `κ_max_η` raw-symbol keyword
**Verdict:** PRESENT
**Evidence:** `src/SimulationRun.jl:65,229,245-250` — keyword is still `κ_max_η` (now defaulting to `nothing` rather than `2`, an unrelated change); sibling settings (`viscosity`, `grid_points_per_axis`, `kinetic_energy`) remain English descriptive words. No `resolution_criterion` rename found.

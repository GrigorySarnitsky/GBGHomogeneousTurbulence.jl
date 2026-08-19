# Closure — 04-dns-practitioner

## Finding 1 — Cache's non-free cost: per-iteration vs per-run contradiction
**VERDICT: ABSENT**
Evidence: `docs/src/observables_cache.md` §1.4 now reads "Those are two different costs and it is worth
keeping them apart: the maximum-speed reduction above recurs **every iteration**, while the only work
the cache *adds* over a cacheless solver is §1.3's final closing deposit … paid **once per run**"
(lines 196–200). §1.3 (lines 146–149) scopes "once per run" strictly to the final closing deposit's
extra cost, and states "the reduction inside every other closing deposit recurs per iteration."
`src/Propagator.jl:485` ("the maximum-speed reduction runs every iteration, including under a
hand-fixed Δt") and `docs/ARCHITECTURE.md:1503` ("once-per-iteration maximum-speed readback … in every
cell; a hand-fixed-Δt iteration still pays it") agree. All four locations now consistent.

---

## Finding 2 — `recommended_cfl` cannot express IFRK2's ν-dependence
**VERDICT: ABSENT**
Evidence: Signature is unchanged (`recommended_cfl(scheme::AbstractIntegrator, domain::FixedDomain)`,
`src/Propagator.jl:568`), so the structural limitation is real, but the docstring now carries an
explicit `!!! warning "The IFRK2 margin does not know the viscosity"` (src/Propagator.jl:536–541):
"This function takes no ν, by design … The same `0.25` is returned at every Reynolds number while the
viscous damping it rests on weakens as ν falls, so at high Reynolds number verify the step against a
run that holds its energy, or set `cfl` yourself." This directly names the gap, its cause, and a
mitigation — no longer silent or bare "prefer another scheme" prose. Confirmed rendered in
`docs/build/api/Propagator/index.html`.

---

## Finding 3 — `max_speed`'s caching justification overstates necessity
**VERDICT: ABSENT**
Evidence: `src/Observables.jl:150-153` docstring note "Why this observable alone has a cached form" now
reads: "The maximum speed qualifies because the run itself needs it: **on the adaptive-CFL path** the
next timestep is chosen from it … Under a hand-fixed Δt nothing consumes it and the pass is spent
anyway." The claim is now explicitly scoped to the adaptive-CFL path, matching `deposit!`'s docstring
(`src/Propagator.jl:484-485`). Confirmed rendered identically in `docs/build/api/Observables/index.html`.

---

## Finding 4 — `IFRK2` called "cheaper" without the memory axis
**VERDICT: ABSENT**
Evidence: `docs/ARCHITECTURE.md:386-387`: "cheaper in transforms (two nonlinear evaluations against
three) but *dearer* in memory — three spectral registers per field against the low-storage scheme's
two." `src/Propagator.jl:31`: "cheaper in transforms, dearer by one register per field." Module
docstring section header echoes it: "imaginary-axis unstable and cheaper in transforms but dearer in
memory" (docs/build/api/Propagator/index.html). Both flagged locations now carry the memory-axis
qualifier; no unqualified "cheaper" survives at either site.

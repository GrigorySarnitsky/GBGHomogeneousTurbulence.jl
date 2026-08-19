# Closure — hat 04: DNS practitioner (performance-focused)

## Finding 1 — StationarityCriterion's skewness "sampling interval" is referenced but never specified

**VERDICT: PRESENT**

**Evidence:** `src/SimulationRun.jl:589-590` still reads "The skewness costs transforms, so it is
measured on the criterion's own sampling interval rather than every iteration" with no keyword,
default, or qualitative cadence given. The actual mechanism, `StationarityMonitor.sample_gap =
window_turnovers / 40` (`src/SimulationRun.jl:488,498`), is an internal field, not a constructor
keyword, and is not mentioned in the `# Arguments` or `# Fields` sections of `StationarityCriterion`
(`src/SimulationRun.jl:581-614`). `rg "sample_gap|1/40|sampling interval"` across `docs/src/`,
`docs/ARCHITECTURE.md` finds no other mention. The rendered build
(`docs/build/api/SimulationRun/index.html`) reproduces the unspecified phrase verbatim. The
decision-log tension the finding raised ("a cadence is the callback's own business",
`docs/ARCHITECTURE.md:1568-1569`) also still stands unaddressed for this packaged callback.

---

## Finding 2 — Worked example of fields-epoch vs current_step does not add up under the stated definition

**VERDICT: ABSENT**

**Evidence:** `src/SimulationRun.jl:355-365`, `current_step`'s docstring, now reads: "The
constructor's seeding deposit already leaves the fields epoch at 1, so after two steps and one
announced mutation the clock reads step 2 and the fields epoch reads 4." This states the baseline
explicitly (1) and 1 + 2 + 1 = 4 checks out arithmetically. Cross-checked against
`ObservablesCache`'s constructor (`src/Cache.jl:141-146`), which literally initializes
`fields_epoch = 1`, and against `fields_modified!`/`step!`'s `fields_modified!(cache)` calls
(`src/Cache.jl:327`, `src/Propagator.jl:325,426`), which each add 1. The example resolves the
resolution hint's first branch (state the baseline explicitly) rather than the second.

---

## Finding 3 — IFRK2's register count is framed with a different accounting convention than IFLowStorageRK3's own docstring uses

**VERDICT: ABSENT**

**Evidence:** `docs/ARCHITECTURE.md:386-389` now reads: "three spectral registers per field against
the low-storage scheme's two, counting the same way on both sides: the scheme's own registers plus
the dealiasing seam's assembly register" — an added clause that states the counting basis explicitly
(own RK stage/predictor registers + the shared dealiasing-seam assembly buffer, on both sides), rather
than leaving the "three … against … two" comparison bare as the finding described. Verified the
composition is internally consistent against the code: RK3's own-registers=`stage1`(1) +
assembly-register=`nonlinear`(1) = 2 (`src/Propagator.jl:244-249`); IFRK2's own-registers=`stage1`+
`velocity_predictor_spectral`(2) + assembly-register=`stage2` (which the code comments confirm
double-duties as dealiasing-seam scratch before being overwritten, `src/Propagator.jl:404-408`) = 3.
No numeric mismatch survives; the disambiguating clause resolves the "nothing on the page says so"
complaint at its quoted location.

---

## Finding 4 — `deposit_sample!`'s two-hop staleness window is not cross-referenced from the page most likely to need it

**VERDICT: ABSENT**

**Evidence:** `src/Particles.jl:229-249`, `record_particle_velocities!`'s docstring, now states
directly: "This call is that slot's only producer of values, but it writes values only: the slot
stays stale, and reads of it throw, until [`deposit_sample!`](@ref) records them as current.
Interpolate here, then mark current there — a run does both at the end of each iteration … and
reading `particle_velocities` after only the first throws." This is exactly the one-hop caveat the
finding asked to be placed on the Particles page / `record_particle_velocities!` itself, rather than
only on the Cache page.

# Closure — Hat 01: consistency-matrix

## Finding 1 — GBGStreamingStatistics: §1 "current consumer" vs §4.9 "deferred"
**Verdict: ABSENT**
Evidence: `docs/ARCHITECTURE.md` §1 (line ~31-32) now reads "...and `GBGStreamingStatistics`
(the statistics — **the division is settled and the bridge to it is deferred, §4.9**)." §4.9
(line ~561) still says the bridge "is deferred (§7)". §1 now explicitly flags the deferred
status inline instead of stating it as an unqualified current dependency; the two sections
agree.

---

## Finding 2 — `deposit_sample!` named in one docstring, unnamed in sibling, absent from index
**Verdict: ABSENT**
Evidence: `rg "deposit_sample"` shows it is now exported (`src/Cache.jl:57`,
`src/GBGIsotropicTurbulence.jl:99,178`), has its own docstring (`src/Cache.jl:263-279`),
appears in `docs/src/api/Cache.md:17`, and is explicitly named with an `@ref` link in
`src/Particles.jl:234` (`record_particle_velocities!`'s docstring: "...
[`deposit_sample!`](@ref GBGIsotropicTurbulence.Cache.deposit_sample!) records them as
current"). Both sibling docstrings now name it and it is indexed.

---

## Finding 3 — `skew_floor` guidance: architecture "toward 0.5" vs API docstring "toward 0.4"
**Verdict: ABSENT**
Evidence: `docs/ARCHITECTURE.md` lines 888-889 (decision-log stationarity entry) now reads
"raise it to `0.4` when the run must be strict, against the ``\lvert S\rvert \approx 0.5`` of
a developed cascade" — matching `src/SimulationRun.jl:583` ("Raise it toward `0.4` when the
run's statistics depend on the cascade being mature."). Both pages now cite 0.4 as the raised
target, with 0.5 kept only as the reference asymptotic skewness value in both places.

---

## Finding 4 — `HouLi` `order=36` default coincides with Float64 `strength` auto-value ≈36
**Verdict: ABSENT**
Evidence: `src/SimulationDomain.jl` lines 77-81 (`HouLi` docstring) now states explicitly:
"(That `Float64` value lands on `36`, which the default `order` also is: Hou & Li's own filter
takes both as `36`, and the coincidence is theirs rather than a transcription slip.)" This
directly addresses the finding's flagged coincidence with a citation-backed explanation, ruling
out the copy/paste-leak concern the finding raised.

---

## Finding 5 — `velocity_predictor` called "not readable"/"never exposed" yet is a plain public struct field
**Verdict: PARTIAL**
Evidence: The two locations the finding originally cited now agree and use softened language:
`docs/ARCHITECTURE.md` §4.6 (line 415) — "`ParticleIntegratorBuffers.velocity_predictor` is a
stage register of the scheme, never a sample of the flow, **and nothing offers it as one**"
(dropped "not readable"); `src/Particles.jl` lines 202-206 (`ParticleIntegratorBuffers` Fields
section) — "**It is reachable like any field of this type**, but it is a scheme intermediate
rather than a sample of the flow at any instant, so nothing in the package offers it as one."
These two now match and concede the field is plainly dot-accessible.
**Surviving class:** `docs/ARCHITECTURE.md` §11 decision 42 (line 1553) still asserts the
stronger, now-contradicted claim: "The register `velocity_predictor` is deliberately **not**
readable — an off-trajectory value must not be servable as a plausible-looking Lagrangian
velocity." This decision-log sentence was not updated to match the softened §4.6/Fields
wording and still contradicts the field's confirmed plain accessibility
(`struct ParticleIntegratorBuffers{P, PS, VV} ... velocity_predictor::VV`, `src/Particles.jl:213`,
no access control).

# Closure audit — hat: consistency-matrix

One verdict per banked finding, adjudicated against the current corpus only.

---

## Finding 1 — Two decision-log entries disagree about what "decision 46's pattern" is

**Verdict:** ABSENT

**Evidence:** `docs/ARCHITECTURE.md:1631-1633` (decision 47) now reads "an f/`f!` **pair**, not
decision 46's single dispatched generic, and the difference is structural rather than a drift"
(mutating recovery vs. checked read cannot share one dispatched name), and closes "Decision 46's
one-generic rule therefore governs reductions; a field-valued observable takes the pair." §4.3
(lines 316-319) cites decision 46 only for `max_speed` and decision 47 only for
`vorticity_physical!`/`vorticity_physical`, with no cross-attribution. Grepped for "pattern
implies" / "decision 46's pattern" / "single dispatched generic" across `docs/ARCHITECTURE.md`,
`docs/src/architecture.md`, `src/*.jl`, `docs/src/*.md` — the only surviving hit is decision 47's
own disclaiming sentence. The two entries no longer contradict; decision 47 explicitly states it is
*not* decision 46's pattern and gives the structural reason.

---

## Finding 2 — `tracer_scheme`'s stated default drops the parens every sibling default keeps

**Verdict:** ABSENT

**Evidence:** `tracer_scheme` no longer exists as a name (renamed to `interpolation_scheme`,
`src/SimulationRun.jl:162,232`); grepped `tracer_scheme` across `src/*.jl` and `docs/src/*.md` —
zero hits. `CatmullRom` is a pre-built `const` in `GBGPeriodicFields` (`const CatmullRom =
LalescuSpline(1, 1)`, confirmed in the installed package source), not a type, so it is correctly
written bare everywhere it now appears (`src/SimulationRun.jl:162,232`, `src/Particles.jl:59-61,100`,
`docs/src/architecture.md:425`) — grepped `CatmullRom()` (parenthesized) across `src/*.jl` and
`docs/src/*.md`: zero hits, so the prior code-example/docstring split is gone. `src/Particles.jl:59-60`
now states this explicitly: "a ready-made value rather than a type, so it is passed bare."

---

## Finding 3 — Three descriptions of what makes `particle_velocities` readable name three different actors

**Verdict:** ABSENT

**Evidence:** All three homes now describe one consistent two-step mechanism explicitly.
`src/Particles.jl:227-229` (`record_particle_velocity!`): "This call is that slot's only producer
of values, but it writes values only: the slot becomes readable when the cache is then told the
values are current, which is a second call the cache owns." `src/Cache.jl:307-317`
(`particles_modified!`): spells the full hand-run sequence — `particles_modified!` →
`record_particle_velocity!` → `deposit_sample!` ("finally `deposit_sample!` to record them at the
current epochs"). `src/Propagator.jl:483-485` (`deposit!`): "filled by `record_particle_velocity!`
... which `advance!` and the `deposit!(sim)` form above both do for you" — no longer conflicting
attributions; `deposit_sample!` (`src/Cache.jl:257`) is the concrete function all three now name.

---

## Finding 4 — "the developed-turbulence markers" (plural) names only one built marker

**Verdict:** ABSENT

**Evidence:** Both summary pages now read singular: `docs/src/api.md:12` "the developed-turbulence
marker" and `docs/src/index.md:97` "the developed-turbulence marker" (grepped both files, zero
remaining plural "markers" hits, zero hits for the plural form anywhere in `docs/src/*.md` /
`src/*.jl`). `derivative_skewness` (`src/Observables.jl:15,262`) remains the only built observable
under this description — singular now matches the single instance.

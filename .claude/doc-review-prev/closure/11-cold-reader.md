# Closure audit — Hat 11: cold-reader

Blind adjudication against the current corpus only (`src/`, `docs/src/`, `docs/ARCHITECTURE.md`,
`docs/build/`). No `.claude/` file other than the banked hat file, no git history, was consulted.

---

## Finding 1 — `L` means two different physical lengths

**VERDICT: PARTIAL**

**Evidence:** The formula itself is fixed: `src/phenomenology/Spectra.jl` `ModelSpectrum` now reads
`E(\kappa) = C_K \varepsilon^{2/3} \kappa^{-5/3} f_L(\kappa \ell) f_\eta(\kappa\eta)` (ℓ, not L), and
`docs/src/notation.md:86` adds a dedicated `ℓ` row: "never the box side `L`." But two sentences later
in the *same* `ModelSpectrum` docstring: "reads ``\varepsilon`` and the roll-off's own length ``L``"
(src/phenomenology/Spectra.jl, the sentence right after the formula) — reintroduces bare `L` for
`large_scale_length`, contradicting notation.md's own new rule in the same breath.

**Surviving class:** Also a new rendering defect at the fix site: `docs/src/notation.md:86` has a
literal double backslash, `` ``\\ell`` `` / `` ``\\ell_{11}`` `` / `` ``\\ell_0 = ...`` ``. Confirmed
in `docs/build/notation/index.html`: renders as literal `<span>$\\ell$</span>` — KaTeX sees `\\` (a
line-break command) followed by `ell`, not the symbol ℓ. The single-source-of-truth notation table
itself fails to render the very symbol it introduces to fix this finding.

---

## Finding 2 — `epoch` unglossed at first use

**VERDICT: PRESENT**

**Evidence:** `docs/src/index.md` Quick start comment is unchanged: "each recorded against the epoch
of the state it came from" (inside a Julia comment, no forward link possible). `docs/src/notation.md:126`
Vocabulary still carries the real definition ("a counter of *changes to the state*... Not an iteration
number...") two pages later, in the section order the hat's stated reading path follows.

---

## Finding 3 — `out-of-band` used for two unrelated things

**VERDICT: PRESENT**

**Evidence:** Control-flow sense unchanged: `src/Cache.jl:42` "announced out-of-band mutation...";
`src/SimulationRun.jl:371` same. Spectral-shell sense unchanged and un-cross-referenced:
`src/Forcing.jl:253` `BandRescaling`, "If the out-of-band value alone exceeds `target`, the band is
zeroed." No gloss or disambiguating note at either site distinguishing the two senses of the phrase.

---

## Finding 4 — `ResolvedFields`/`ResolvedGenerator` collide with numerical "resolve"

**VERDICT: PRESENT**

**Evidence:** `docs/src/index.md:39` still uses the numerical sense ("ν is set so the grid resolves
the dissipation scale") a few lines before `ResolvedFields`/`ResolvedGenerator` are introduced
(lines 99, 111) with no flag of the collision. `docs/src/notation.md:131` Vocabulary entry admits the
collision explicitly, but only two pages later — the exact structure the finding complains about is
unchanged: nothing on Home signals the reader should expect two senses.

---

## Finding 5 — `Particles` module, only concrete type `Tracers`, no stated relationship

**VERDICT: PARTIAL**

**Evidence:** `docs/src/api/Particles.md` / `src/Particles.jl` module docstring and `Tracers`
docstring still never say whether `Tracers` is *the* particle type or *a* (massless) kind among
others — no "massless", "inertial", or "deferred ladder" language anywhere in `src/Particles.jl`.
`docs/ARCHITECTURE.md:403-404` (§4.6) does now explain it explicitly: "a particle is a state-carrying
trajectory object: today a tracer (position x); the deferred ladder is inertial (x,v) and oriented
(x,v,L) probes."

**Surviving class:** The explanation lives only in `ARCHITECTURE.md`, not on the `Particles` API page
or in the module/type docstrings a reader following the API surface would hit, and neither
`docs/src/api/Particles.md` nor `src/Particles.jl` links to it.

---

## Finding 6 — bare `A` collision (RK coefficients vs. forcing rate)

**VERDICT: ABSENT**

**Evidence:** `src/Propagator.jl:240-241`, `IFLowStorageRK3` docstring, now reads: "with the stage
coefficients ``A_i = (0, -5/9, -153/128)`` — unrelated to the forcing rate ``A(\boldsymbol{\kappa})``
of the `Forcing` page —, ``B = (1/3, 15/16, 8/15)``..." — explicit disambiguating clause naming both
symbols and their sources. Checked `IFRK2` (`src/Propagator.jl:331-357`) and `velocity_integrating_factor`
(`src/Generator.jl:402-427`) for residual bare, unlabeled `A`: none found; both consistently write
``A(\boldsymbol{\kappa})``.

---

## Finding 7 — "mode" switches from Fourier mode to code branch

**VERDICT: PRESENT**

**Evidence:** `src/SimulationRun.jl:101,127` still label the two `Simulation` constructor branches
"Grid mode" / "Explicit mode," unchanged. `src/State.jl:79` still reads "...the two modes do not seed
the same large scale..." in the same sentence whose parenthetical reads "the shell's mode count" (the
Fourier sense) — the identical juxtaposition the finding flagged, though the same paragraph elsewhere
now says "the `initial_spectrum` branch below" (branch, not mode) one clause earlier, showing the
inconsistency was not resolved uniformly.

---

## Finding 8 — tracking-loop order stated, then reversed

**VERDICT: PRESENT**

**Evidence:** `docs/src/api/Particles.md` "## The tracking loop" opens "record the flow velocity where
each tracer currently sits, advance the tracers once the fields have moved, then read any physical
field..." (record→advance→read), then next sentence: "the run records the sample at the iteration's
end, off the just-deposited velocity, and the next iteration's `advect!` reads it back" — the
worked example (`src/Particles.jl:103-104`) still calls `record_particle_velocities!` before
`advect!` with the comment "do this first." No note marks the first sentence as a verb list rather
than a per-iteration sequence.

---

## Finding 9 — `taken` unglossed at first appearance

**VERDICT: PRESENT**

**Evidence:** `src/Cache.jl:91` (rendered `ObservablesCache` docstring): "a read that finds a stale,
taken, or never-deposited slot reports a scheduling error" — still unglossed at this, its first
appearance in the docstring. The only definition ("taken as a producer's mid-iteration scratch") is a
plain `#` comment at `src/Cache.jl:58`, which per house style is never rendered. The clarifying prose
lives in `IntegratorBuffers`/`step!` (`src/Propagator.jl:93,205`), reached later.

---

## Finding 10 — four names for `u(t_n, X(t_n))`

**VERDICT: PRESENT**

**Evidence:** Still four terms, unreconciled: "particle velocities" (`docs/src/notation.md:38`,
code name), "trajectory velocities" (`src/Particles.jl:22`, module docstring's own first mention),
"Lagrangian velocity" / "Lagrangian sample" (`src/Particles.jl:28,82,90,124,133,232,245`). Searched
`docs/src/notation.md` for "trajectory velocit" / "Lagrangian sample" / "Lagrangian velocity": zero
matches — the Vocabulary page never equates the four phrases.

---

## Finding 11 — "checked accessors" vs. "The checked reads"

**VERDICT: PRESENT**

**Evidence:** `docs/src/index.md:105-106` (Home, Components list) still reads "read through checked
accessors that serve the deposited value or throw." `docs/src/api/Cache.md:20` heading is still
"## The checked reads," and `src/Cache.jl` uses "checked read" throughout (lines 27, 149, 186, 201,
227). The two phrases for one concept are never equated anywhere searched.

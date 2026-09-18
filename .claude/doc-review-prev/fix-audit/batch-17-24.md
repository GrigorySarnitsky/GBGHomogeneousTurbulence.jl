# Fix audit — batch 17–24

Source pile: `.claude/doc-review/00-checkdocs-2026-08-24-findings.md`
Diff audited: `52ada56..HEAD` (commits `7abb434`, `c587b30`)

---

## 17
**Owner's verbatim ask (finding text):** "VarianceController's `domain` argument (first form) was
undocumented — no framing sentence, no bullet." CLAIM: "a `domain` bullet added at the head of its
# Arguments list, covering both forms."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Forcing.jl:596-597` (current source), added by the diff at
`git diff 52ada56..HEAD -- src/Forcing.jl` hunk `@@ -585,13 +586,15 @@`:
```
+- `domain` — the [`FixedDomain`](@ref) the band kernel is built on (the first form; the
+  operator-free second form defers that to the run, as a [`DeferredForcing`](@ref)).
```
Inserted at the head of the `# Arguments` list, exactly as claimed, and it correctly covers both the
`VarianceController(domain; …)` and `VarianceController(; …)` forms (line 548-552 shows both
signatures). The nearby same-hunk edit that de-linked a repeated `[`VarianceRescaling`](@ref)` to a
bare backtick is a legitimate "link once per docstring" tidy, not a regression of this finding.

---

## 18
**Owner's verbatim ask (finding text):** "StochasticOU had no `# Fields` section (9 stored fields,
siblings all document theirs)." CLAIM: "compact # Fields added, the new shell bounds included."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Forcing.jl:798-805` now carries
```
# Fields
- `band` — the band-pass kernel for the noise.
- `correlation_time`, `variance` — ``T_L`` and ``\sigma^{2}``.
- `rng` — the random stream, persisting across steps.
- `state`, `noise_physical`, `noise_spectral` — the evolving force ``\hat{\boldsymbol{f}}`` and
  its noise scratch, each `nothing` until first use.
- `lowest_shell`, `highest_shell` — the forced band's shell bounds: the parameters `band` is
  derived from.
```
This enumerates all nine struct fields (`band, correlation_time, variance, rng, state,
noise_physical, noise_spectral, lowest_shell, highest_shell` — struct at line 807-817), including
`lowest_shell`/`highest_shell` as claimed. Diff hunk `@@ -792,6 +794,15 @@` shows this is a pure
insertion after the existing `!!! note` admonition and before the struct — correctly positioned
last, before the struct, per the type-docstring template (constructor-first, `# Fields` last).

---

## 19
**Owner's verbatim ask (finding text):** "Cache module docstring used 'tracer' as an unexplained
term of art." CLAIM: "first mention now links [`Tracers`](@ref
GBGIsotropicTurbulence.Particles.Tracers)."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Cache.jl:19-21` (module docstring), diff hunk:
```
-- [`fields_modified!`](@ref), [`particles_modified!`](@ref) — announce a state or tracer mutation
+- [`fields_modified!`](@ref), [`particles_modified!`](@ref) — announce a mutation of the state or
+  of the [`Tracers`](@ref GBGIsotropicTurbulence.Particles.Tracers) the run advects
```
Confirmed this is the first occurrence of "tracer"/"Tracers" in the module docstring (lines 10-48);
no earlier unlinked mention precedes it, and no later mention within the same docstring is left
unlinked (the module docstring's only other "tracer" use, line 74 "the run advects tracers", is a
different docstring — `ObservablesCache`'s — not the module map). `Tracers` is confirmed exported
from `Particles.jl:52` and defined at `Particles.jl:149`, so the `@ref` target resolves. This
satisfies the doc policy's "a term of art is explained or @ref-linked" self-containment rule.

---

## 20
**Owner's verbatim ask (finding text):** "unit_kernel field doc claimed ``\langle f,
1\cdot f\rangle`` 'is the variance itself' — it is the mean square; equals variance only for
mean-zero f (category error, unqualified X-is-just-Y)." CLAIM: "now 'the mean square — the variance
of a mean-zero field'."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/SimulationDomain.jl:205-208`, diff:
```
- once), since ``\langle f, 1\cdot f\rangle`` is the variance itself.
+ once), since ``\langle f, 1\cdot f\rangle`` is the mean square — the variance of a
+ mean-zero field.
```
This is a correction of the flagged clause in place (not an append beside it), and it is
mathematically correct: ``\langle f, 1\cdot f\rangle = \langle f^2\rangle`` is the mean square in
general, equal to the variance only when ``\langle f\rangle = 0``. Checked for the same category
error elsewhere (`grep -rn "is the variance\|mean square"` across `src/`, `docs/src/`) — no other
site asserts the unqualified "mean square = variance" equivalence, so the class is closed, not just
the line.

---

## 21
**Owner's verbatim ask (finding text):** "Bulleted-arguments rule (adopted 2026-08-24):
random_solenoidal_velocity_spectral! and random_scalar_spectral! documented 6 arguments in prose."
CLAIM: "both gained 'The arguments are:' bullets; the redundant domain/rng prose sentence removed."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/State.jl`, both docstrings (`random_solenoidal_velocity_spectral!` at line
84-133, `random_scalar_spectral!` at line 186-…) now carry a "The arguments are:" bulleted list
covering all six parameters (`û`/`φ̂`, `domain`, `kinetic_energy`/`scalar_variance`,
`envelope_wavenumber`, `initial_spectrum = nothing`, `rng = default_rng()`), matching each
function's actual signature (`State.jl:134-136`, `234`). The diff confirms the previously separate
prose sentence — "The `domain` (a `FixedDomain`) is what the field is generated on; the `rng` is
the random stream…" — was deleted (not left behind beside the new bullets) in both docstrings:
```
-The `domain` (a [`FixedDomain`](@ref)) is what the field is generated on; the `rng` is the random
-stream (defaults to `Random.default_rng()`).
-
 Returns `û`.
```
This is a genuine correction (removal + bulleting), not an insertion beside surviving prose.

---

## 22
**Owner's verbatim ask (finding text):** "Same rule: prepare! (4 args) and finalize! (3 args) in
prose." CLAIM: "converted, Returns sentences kept."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Generator.jl:390-397` (`prepare!`) and `:424-431` (`finalize!`) now read:
```
The arguments are:
- `generator` — the [`ResolvedGenerator`](@ref) being opened.
- `state` — the start-of-step [`ResolvedFields`](@ref …) the forcing hooks read.
- `domain` — the [`FixedDomain`](@ref) the rates are formed on.
- `dt` — the timestep the forcings prepare for.

Returns `generator`.
```
and, for `finalize!`, three bullets (`generator`, `state`, `domain`) followed by `Returns `state`.`.
Both match their real signatures (`prepare!(generator::ResolvedGenerator, state, domain::FixedDomain,
dt::Real)` and `finalize!(generator::ResolvedGenerator, state, domain::FixedDomain)`, lines 399 and
432). The diff shows the old inline-prose paragraph replaced by the bulleted form with the trailing
`Returns` sentence preserved as its own line — not appended beside surviving prose.

---

## 23
**Owner's verbatim ask (finding text):** "Same rule: velocity_rhs! (6 args) in prose." CLAIM:
"converted; prose bindings moved into bullets."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Generator.jl:463-470` now bullets all six arguments (`N̂`, `generator`, `û`, `u`,
`ω_consumed`, `domain`), matching the signature
`velocity_rhs!(N̂, generator::ResolvedGenerator, û, u, ω_consumed, domain::FixedDomain)` (line 519).
The diff removed the old sentence that bound `û`/`u`/`ω_consumed`/`domain` in running prose ("from
the stage velocity `û` in spectral representation and its physical velocity `u` and vorticity
`ω_consumed`, on the `FixedDomain` `domain`, using the `ResolvedGenerator` `generator`'s conditions
and scratch") and did not leave that sentence behind — it was replaced by the shorter identity
sentence plus the bullet list. Document order is preserved (identity → arguments → formula → caveat
admonition last), consistent with the template.

---

## 24
**Owner's verbatim ask (finding text):** "Same rule: scalar_rhs! (7 args + keyword) in prose."
CLAIM: "converted, the displaced_velocity_current keyword bulleted with its deep paragraph retained
below."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Generator.jl:629-638` bullets all seven positional arguments plus the keyword:
```
The arguments are:
- `N̂` — the spectral field receiving the assembled term.
- `generator` — the [`ResolvedGenerator`](@ref) whose conditions and assembly scratch are used.
- `û`, `φ̂` — the stage velocity and scalar in spectral representation, consulted by `PhaseShift`;
  a mask strategy leaves both unused.
- `u_consumed` — the stage velocity in physical representation, consumed (the closing note).
- `φ` — the stage scalar in physical representation, only read.
- `domain` — the [`FixedDomain`](@ref) whose dealiasing strategy and transforms assemble the term.
- `displaced_velocity_current = false` — the reuse promise for `PhaseShift`'s displaced velocity,
  explained below.
```
matching the real signature `scalar_rhs!(N̂, generator::ResolvedGenerator, û, φ̂, u_consumed, φ,
domain::FixedDomain; displaced_velocity_current::Bool = false)` (line 682). The keyword bullet
correctly forward-references "explained below," and the deeper paragraph on the reuse contract
("Pass `displaced_velocity_current = true` only if nothing has changed since this generator's
`velocity_rhs!` was called on the same `û`…", lines 661-667) is retained intact further down the
docstring, not deleted or duplicated. Document order (identity → bullets → discussion → the
``\kappa=0`` note → `Returns` → caveat admonition last) matches the template and the caveat is
correctly positioned as the final substantive block, exactly mirroring `velocity_rhs!`'s structure.

---

## Summary

All eight findings in this batch (17–24) are **HONORED**. Each fix corrects or removes the flagged
clause in place (no insertion-beside-defect pattern), lands at the specific site named by the owner,
and — where checked against sibling instances (findings 20 and 21-24, the two findings most exposed
to a class-survival risk) — no equivalent unfixed instance was found elsewhere in `src/`. Formulas,
struct-field enumerations, and cross-reference targets were verified against the current source and
resolve correctly.

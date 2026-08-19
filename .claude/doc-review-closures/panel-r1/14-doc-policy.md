# Closure — Hat 14: Doc-policy

## 1. Cache module docstring embeds formulas in its per-operation bullets

**VERDICT: ABSENT**

Evidence: `src/Cache.jl` module docstring (lines ~17-27) now reads "`max_speed`](@ref …) — the cached
largest flow speed, the number the timestep choice reads (one generic with the field reduction in
`Observables`, whose docstring is the home)." and "`particle_velocities`](@ref) — the checked read of
the velocity sampled along each trajectory." Neither bullet contains a `$…$`/`` ``…`` `` LaTeX span;
grepped the full module-docstring block (lines 9-40) for `\$` and `\[` — no matches. Formulas now live
only in `max_speed`'s and `particle_velocities`' own docstrings.

---

## 2. `StationarityCriterion` names and displays the "internal" positional constructor

**VERDICT: ABSENT**

Evidence: `src/SimulationRun.jl` lines 591-595, `# Fields`: "The fields are not the keywords: … Build
one through the keyword constructor above — the positional form takes assembled internals and is not
part of the interface." No positional signature (`StationarityCriterion(monitor, max_turnovers, …)`)
is spelled out anywhere in the docstring; it now matches the omission treatment given to
`Simulation`/`ObservablesCache`/etc.

---

## 3. `BandRescaling` never enumerates its own keyword arguments

**VERDICT: ABSENT**

Evidence: `src/Forcing.jl` lines 261-268 now carry a `# Arguments` section for `BandRescaling` listing
`domain`, `target`, `over`, and "`lowest_shell = 1`, `highest_shell = 2` — the rescaled band, as
integer shells in units of the box's fundamental ``2\pi/L``." Defaults are stated, matching the
`Linear`/`ConstantPower` treatment the finding cited as the standard.

---

## 4. `VonKarman1948` / `Pao1965` re-derive a formula instead of linking to its declared home

**VERDICT: PARTIAL**

Evidence: `src/phenomenology/Spectra.jl` lines 345-362 (`VonKarman1948`) and 367-383 (`Pao1965`) no
longer restate the fully-composed `E(κ) = C_K ε^{2/3} κ^{-5/3} f_L f_η` formula — both now write
"`ModelSpectrum`'s docstring carries the composed formula" and defer to it, matching `Pope2000`'s
treatment at the composed-spectrum level. But both still write out, in full, the substituted `f_L` /
`f_η` sub-formulas whose own declared home is elsewhere: `VonKarman1948` line 350-351 states
"``f_L`` is von Kármán's ``\bigl((\kappa L)^2/((\kappa L)^2+c_L)\bigr)^{17/6}``" — an exact duplicate of
`VonKarmanLarge`'s own docstring formula (line 171: "``f_L(\kappa L) = \Bigl(\frac{(\kappa L)^2}{(\kappa
L)^2+c_L}\Bigr)^{17/6}``"). `Pao1965` line 373-374 states "``f_\eta`` is Pao's
``\exp(-\tfrac32 C_K(\kappa\eta)^{4/3})``" — duplicate of `PaoDissipation`'s own docstring (line 212:
"``f_\eta(\kappa\eta)=\exp\!\bigl(-\tfrac32\alpha(\kappa\eta)^{4/3}\bigr)``"). `Pope2000` (lines
324-326) avoids this entirely: "with `PopeLargeScale` supplying ``f_L`` and `PopeDissipation` supplying
``f_\eta``" — no formula restated at either level.

**surviving_class:** the "one concept, one home" formula-duplication class survives one level down —
`VonKarman1948` duplicates `VonKarmanLarge`'s ``f_L`` formula; `Pao1965` duplicates `PaoDissipation`'s
``f_\eta`` formula. Both should defer the same way `Pope2000` does, naming the factor type without
restating its formula.

---

## 5. `ResolvedFields` omits naming its plain positional constructor

**VERDICT: ABSENT**

Evidence: `src/State.jl` lines 51-54: "# Fields — The plain constructor
`ResolvedFields(velocity_spectral, scalar_spectral)` takes the two fields directly, in this order."
Now matches `FlowConditions`'s treatment cited in the finding.

---

## 6. `Simulation`'s docstring likely re-links several targets more than once

**VERDICT: ABSENT**

Evidence: checked the actual source (unlike the finding, which worked only from the plain-text render).
`src/SimulationRun.jl` lines 64-205: `grep -n '@ref'` over the full docstring shows `FixedDomain`,
`IntegratorBuffers`, `ResolvedGenerator`, `ObservablesCache`, `Tracers`, `ResolvedFields`,
`FlowConditions` each linked with `[`Name`](@ref …)` exactly once, at first mention (line 70-74). Their
`# Fields`-section reappearances (lines 196-203: "`domain`, `buffers`, `generator`, `scheme` — the
`FixedDomain`, `IntegratorBuffers`, the `ResolvedGenerator` …") and their `# Arguments`-section
reappearances (e.g. line 129, 133 `FixedDomain`) are bare, unlinked backtick spans, not second `@ref`
links — exactly the allowed shape the finding flagged as the open question.

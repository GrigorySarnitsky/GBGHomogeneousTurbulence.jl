# Closure audit — 02-software-architect

## 1. `velocity_rhs!` / `scalar_rhs!` silently destroy different, non-predictable argument positions

**VERDICT: ABSENT**

Evidence: `src/Generator.jl:275` — signature is now `velocity_rhs!(N̂, generator, û, u, ω_consumed, domain)`;
`src/Generator.jl:423` — `scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain)`. Both consumed
arguments are now literally named `_consumed` in the signature itself (not only in prose), and each
docstring cross-references the other: "Which operand is consumed follows the **physics**, not the
argument position … which is why both name the consumed argument rather than leaving a caller to infer
it" (line 317; mirrored at line 453). `grep -rn "no longer holds\|is consumed\|overwritten\|clobber"
src/*.jl` finds no other undocumented/unnamed instance of this pattern. The finding's core complaint —
a caller cannot tell which read-only-looking argument comes back garbage without re-reading the Note —
is resolved: the name itself now carries the information. (Argument *position* of the consumed arg is
still asymmetric between the two functions, but the finding's remedy was inferability, which is fixed.)

---

## 2. No `particles_modified!` counterpart to `resolved_fields_modified!`

**VERDICT: ABSENT**

Evidence: `src/Cache.jl:296` `fields_modified!(cache::ObservablesCache) = (cache.fields_epoch += 1; cache)`
and `src/Cache.jl:311` `particles_modified!(cache::ObservablesCache) = (cache.particles_epoch += 1;
cache)`, each with a full docstring (line 280 "Announce that the resolved fields … were changed outside
the iteration" / line 297 "Announce that the tracer positions were changed outside the iteration …
the particle counterpart of `fields_modified!`"). Both are exported (`src/GBGIsotropicTurbulence.jl:96,174`)
and used in `src/SimulationRun.jl:380`. The two-axis announce-verb gap is closed.

---

## 3. `FlowParameters.scalar_dissipation` uses `NaN` as an "unset" sentinel rather than `nothing`/`missing`

**VERDICT: ABSENT**

Evidence: `src/Phenomenology.jl:88-93` — the default is still `NaN`, but the docstring now explicitly
argues the tradeoff ("`NaN` rather than `nothing` keeps the bundle a plain, type-stable set of
`Float64`s. It is a **sentinel, not a value that propagates**: every law that reads the field checks it
first and throws an `ArgumentError` … so a scalar law applied to a scalar-free state fails loudly rather
than returning `NaN`."). Verified both consumers guard it: `src/phenomenology/Spectra.jl:412`
`isnan(fp.scalar_dissipation) && throw(ArgumentError(...))` and
`src/phenomenology/StructureFunctions.jl:162` same pattern — `grep -rn "fp\.scalar_dissipation"
src/phenomenology/*.jl` shows no unguarded read. Silent propagation is no longer possible at either
consumption site.

---

## 4. The forcing four-hook protocol's second positional argument means "mutated" in three hooks, "read-only" in the fourth

**VERDICT: PRESENT**

Evidence: `src/Forcing.jl:135` `set_forcing_rate!(::AbstractForcing, rate, field, domain)`,
`:163` `apply_forcing!(::AbstractForcing, field, domain)`, `:183` `add_forcing_source!(::AbstractForcing,
nonlinear, domain)` all still mutate/return position 2; `:173` `prepare_forcing!(::AbstractForcing,
field, domain::FixedDomain, dt::Real)` still takes `field` read-only in position 2 while mutating the
forcing's own opaque internal state. Neither the individual docstrings (lines 122-183) nor the module
docstring's four-hook summary (lines 17-45) calls out this asymmetry. Signatures and docs unchanged from
the finding's description.

---

## 5. `displaced_velocity_fresh` couples `velocity_rhs!`/`scalar_rhs!` through a hidden boolean, invisible at the protocol level

**VERDICT: ABSENT**

Evidence: `src/Generator.jl:169-173`, inside the `ResolvedGenerator` type docstring, right after the
protocol description ("The scheme does only stage arithmetic, so it can never assemble the right-hand
side from a mismatched intermediate state"), a new callout: `!!! note "One optimization crosses two
verbs" — Under PhaseShift, velocity_rhs! leaves the stage's displaced velocity fresh for the same
stage's scalar_rhs! to reuse, through the displaced_velocity_fresh flag rather than through either
signature. It is opportunistic, never load-bearing…`. This is exactly the protocol-level callout the
finding asked for (previously it lived only in the field list, still also present at line 197).

---

## 6. `step!`'s `integrator` argument is a stateless dispatch tag, naming-colliding with the SciML convention

**VERDICT: ABSENT**

Evidence: `grep -n "integrator" src/Propagator.jl` returns zero matches. The parameter is now named
`scheme` throughout: `src/Propagator.jl:58` (`AbstractIntegrator` docstring) — "A scheme implements
`step!`(`scheme, state, generator, domain, buffers, cache, dt`)"; `:249` `function
step!(::IFLowStorageRK3, state::ResolvedFields, generator::ResolvedGenerator, …)`; `:358` likewise for
`IFRK2`. This is exactly the finding's own suggested remedy ("A more specific name (`scheme`) would
avoid importing that reader's prior expectation").

---

## 7. `Pope2000` / `VonKarman1948` / `Pao1965` are `Function`s with Type-shaped (PascalCase) names

**VERDICT: ABSENT**

Evidence: `src/phenomenology/Spectra.jl:309` `const Pope2000 = ModelSpectrum{PopeLargeScale,
PopeDissipation}` (a type alias, not a function), with `:311` `Pope2000(; C_K = 1.5, …) =
ModelSpectrum(…)` as its outer constructor; same pattern for `VonKarman1948` (`:335`) and `Pao1965`
(`:362`). The docstrings now state "`Pope2000` is the `ModelSpectrum` carrying Pope's two roll-off
factors, so `spec isa Pope2000` holds for a value this constructor returns" — true by construction, not
a workaround. Confirmed in the rendered build:
`docs/build/api/phenomenology/Spectra/index.html` labels `Pope2000` `<span
class="docstring-category">Type` (previously `Function`). The PascalCase-vs-behavior mismatch is gone.

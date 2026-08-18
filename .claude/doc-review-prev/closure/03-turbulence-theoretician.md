# Closure — Hat 03 (Turbulence theoretician)

## 1. The default run uses the forcing the docs call unfit for measurement, with no caveat at the front door
**VERDICT: ABSENT**

`src/SimulationRun.jl:88-99` — directly under "By default the run is **forced and stationary**" now
sits `!!! note "The default holds ``k`` fixed, so ``k`` is not a measurable of the default run"`
stating the deterministic-clamp caveat and pointing to `ConstantPower` for fluctuation statistics —
exactly the resolution hint's front-door note.

## 2. Does a velocity forcing carry a Leray projection, or does none act on `f`?
**VERDICT: ABSENT**

`docs/ARCHITECTURE.md:357-359` now reads "the only field-specific step a forcing can need is the
solenoidal (Leray) projection … and none of the built strategies needs it … (the archived
`StochasticOU` … is the one that projects)". Matches `docs/src/observables_cache.md:246-248` ("No
projection acts on `f`… every velocity forcing the package provides is already divergence-free").

## 3. "Energy-conserving" is attached to the rotational form, not to the exact-dealiasing condition
**VERDICT: ABSENT**

`docs/ARCHITECTURE.md:252-254`: "under a sharp mask the truncation is exactly Galerkin, so the
discrete advection conserves kinetic energy (`HouLi`, which only damps, is the deliberately
non-conservative strategy)" — conservation is now explicitly credited to the sharp-mask/Galerkin
condition, not asserted as a property of rotational form itself. Consistent with §7's ν=0 entry
(line 664).

## 4. "Spectral fields" / "the spectral velocity" — the field-vs-representation rule the docs themselves set
**VERDICT: ABSENT**

All three flagged instances now read correctly: `docs/ARCHITECTURE.md:191-192` "record of the
evolving fields in spectral representation"; §4.5 (line 369-370) "advances the velocity û and scalar
φ̂, both in spectral representation"; `src/Cache.jl:284-285` (function renamed
`resolved_fields_modified!` → `fields_modified!`) "the resolved fields — û and φ̂, in spectral
representation — were changed". Grep across `docs/ARCHITECTURE.md`, `docs/src/*.md`,
`docs/src/api/*.md`, `src/*.jl` for "spectral velocity|spectral scalar|spectral fields|spectral
field" (excluding "in spectral representation") returns nothing.

## 5. "Every diagnostic is dimensionless" versus the dimensional flow-parameter bundle
**VERDICT: ABSENT**

`docs/ARCHITECTURE.md:746-748` (§9 invariant 1) now reads "No physical units. Quantities are in box
units; control is by Re (through ν) and Sc, and the reference constants a run is judged against (C_K,
C_ε, G) are dimensionless groups" — the false universal quantifier over diagnostics is gone; only the
control and reference constants are claimed dimensionless, matching `Scalings` and `FlowParameters`.

## 6. `C` denotes both the CFL ceiling and the skewness isotropy constant
**VERDICT: ABSENT**

`docs/src/notation.md:97` now binds `C_{\mathrm{CFL}}` (not bare `C`) to the CFL ceiling;
`docs/ARCHITECTURE.md:321-322` and `:902-903` consistently use `C_S` for the skewness isotropy
constant. Grepped for a bare-`C`-in-CFL-formula residue (`C\Delta x` / `C_\Delta x` pattern) —
none found.

## 7. `τ` means the integrating-factor substep everywhere except one turnover budget
**VERDICT: ABSENT**

`docs/src/observables_cache.md:132-133` now reads "accumulates ``\Delta t\,\varepsilon/k`` — the
eddy-turnover clock — and says stop", no longer using `τ` for the turnover time. `notation.md:62`
still binds `τ` only to the integrating-factor substep interval; no second binding remains.

## 8. `StationarityCriterion` is documented as not reading `k`, but its turnover clock is `Δt ε/k`
**VERDICT: ABSENT**

`docs/ARCHITECTURE.md:447-450`: "gates on ε rather than on the clampable k(t); k is still measured,
to normalize the eddy-turnover clock Δt ε/k". `src/SimulationRun.jl:541-546` docstring: "measures the
dissipation ε … and the kinetic energy k, which normalizes the eddy-turnover clock Δt ε/k". The
gate-vs-clock distinction is now explicit and the "(one reduction)" undercount claim is gone.

## 9. The RK3 docstring rotates the accumulator at every stage; the audit records the last rotation skipped
**VERDICT: ABSENT**

`src/Propagator.jl:234`: immediately after the four-line stage system the docstring now adds "(the
accumulator's rotation is skipped at the last stage, where nothing reads it again)" — exactly the
suggested half-sentence reconciliation.

## 10. "The enstrophy" without the ½, against the package's own half-quantity convention
**VERDICT: ABSENT**

`src/Observables.jl:102-104`: the `dissipation` docstring no longer calls ⟨|ω|²⟩ "the enstrophy"; it
now reads "the mean-square vorticity of a divergence-free velocity is its Dirichlet energy … ⟨|ω|²⟩ =
⟨û, |κ|²û⟩" — the ambiguous label is replaced with "mean-square vorticity", exactly the resolution
hint. Remaining "enstrophy" occurrences (`SimulationRun.jl:442` comment, `Observables.jl:252`
"enstrophy-production", `architecture.md:1292` generic mention) do not attach an unqualified
half-convention-violating formula.

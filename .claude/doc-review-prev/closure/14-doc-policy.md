# Closure — 14-doc-policy

## Finding 1 — `Phenomenology` module docstring inserts an essay paragraph before the contents list

**VERDICT: PRESENT**

Evidence: `src/Phenomenology.jl` lines ~9–24. Between the identity paragraph and "The module's
contents:" there is still a full paragraph ("A law family is an abstract subtype of `TurbulenceLaw`
… Choosing a law is choosing the preset … a name is disambiguated by its **submodule** …") — the
exact essay-before-the-list the finding quoted, unchanged.

---

## Finding 2 — Caveat admonitions are not positioned as the docstring's last substantive block (class, 4 instances)

**VERDICT: PRESENT**

Evidence:
- `BandRescaling` (`src/Forcing.jl` ~260–311): `!!! note "Which one a run wants depends on what else
  reads the kinetic energy"` still sits before `# Arguments`; `!!! note "A band with nothing in it is
  left alone"` and `!!! note "A deterministic clamp, not a stationary sampler"` still sit after
  `# Fields`.
- `ConstantPower` (`src/Forcing.jl` ~411–430): `!!! note "An empty band is left alone, not driven
  infinitely hard"` still sits before `# Arguments`.
- `ObservablesCache` (`src/Cache.jl` ~95–104): `!!! note "A cached array is the next iteration's
  scratch"` is still followed by the "The word *epoch* names two things here…" paragraph before
  `# Fields`.
- `recommended_cfl` (`src/Propagator.jl` ~550–562): `!!! warning "The IFRK2 margin does not know the
  viscosity"` is still followed by "It scales that base by the domain's dealiasing…", which ends the
  docstring.

All four sites are byte-for-byte the same shape the finding quoted; none were moved.

surviving_class: same four sites named in the finding — no new instances found, but none of the
originals were fixed either.

---

## Finding 3 — The umbrella `GBGIsotropicTurbulence` module docstring is not a map: no linked one-liner per submodule

**VERDICT: PRESENT**

Evidence: `src/GBGIsotropicTurbulence.jl` lines ~31–48 (the `"""..."""` docstring on `module
GBGIsotropicTurbulence`) still has no bulleted, `@ref`-linked per-submodule list — only identity
prose, the sibling-package pointer, and the Göteborg trivia. The bulleted submodule list that exists
(lines 11–26) is a `#` comment above the docstring, not part of it, exactly as the finding noted.

---

## Finding 4 — `Cache.vorticity_physical` restates the formula its `!` home already owns

**VERDICT: PRESENT**

Evidence: `src/Cache.jl` `vorticity_physical` (~182–190) still opens "The vorticity
``\boldsymbol{\omega} = \nabla\times\boldsymbol{u}`` in physical representation at the current
epoch…", duplicating the formula also given in the home `vorticity_physical!`
(`src/Observables.jl` ~168). Contrast `velocity_physical`/`scalar_physical` in the same file, which
still carry no formula.

---

## Finding 5 — Three `Phenomenology` submodule "References" sections cite the bare `ARCHITECTURE.md` filename on the rendered page

**VERDICT: PRESENT**

Evidence: identical sentence "A few works are cited in `ARCHITECTURE.md` as well, where the DNS side
needs them — the leaf's independence means it does not *rely* on that list…" still present verbatim
in `docs/src/api/phenomenology/Scalings.md:33`, `Spectra.md:67`, and `StructureFunctions.md:27`. No
file was edited.

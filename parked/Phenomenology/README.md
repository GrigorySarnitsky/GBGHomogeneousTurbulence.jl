# Phenomenology — parked

The reference turbulence laws — model spectra, structure-function laws and dimensionless-constant
fits, each an author-year parametrization of one abstract law family per quantity — kept here as a
unit that nothing in `GBGHomogeneousTurbulence` includes, builds or tests (the owner, 2026-10-16,
decision 113 in `docs/ARCHITECTURE.md`). The design it was built to is `docs/ARCHITECTURE.md` §4.8.

The layout is that of the standalone package it becomes when extracted:

- `src/Phenomenology.jl` and `src/phenomenology/` — the module, which depends on nothing but Base.
- `test/runtests.jl` — the module's oracle tests (`phenomenology.jl`) and the comparison of a run of
  the package against a model spectrum (`validation_bridge.jl`). Run from the package root:

  ```
  julia --project parked/Phenomenology/test/runtests.jl
  ```

- `docs/` — the overview and the four API pages, as the package's site rendered them before the
  module was parked. They still say the module is loaded with `using GBGHomogeneousTurbulence.Phenomenology`,
  which was true then; a `make.jl` of the extracted package would replace that line and build them.

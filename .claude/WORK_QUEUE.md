# Work queue

## From the last review


## API shaped by the tests (review of 2026-11-14)

Pieces of the package that a run through `Simulation` never needs and only the tests exercise.
Each needs a ruling: remove it, or name the real use it serves. The particle items of the same
review (the field argument of `advect!` and of the particle `deposit!`, `history_depth`, the
guards on `ParticleIntegratorBuffers`) are settled and go with the particle refactor.

- `VarianceController`'s fallback turnover time, from a placeholder value, reached only when the
  controller is built directly on a domain (`src/Forcing.jl:853`).
- The check for a scalar missing from the buffers or the cache (`src/Propagator.jl:828-838`).
- The checks for a state lacking the forcing's part (`src/Forcing.jl:1199`, `:1388`).
- The hand-loop example in the `Tracers` docstring (`src/Particles.jl:118-127`).
- `new_tensor_field_spectral`: exported, called by nothing but three tests.

Behind the middle three: whether assembling a run piece by piece and driving it by hand is a
supported use at all. Only `Simulation` and the tests do it today.

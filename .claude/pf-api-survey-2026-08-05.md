# PF API survey — full read, 2026-08-05 (clone at ad97d35a)

Read: umbrella + all 8 modules' docstrings (12k lines) + PF CLAUDE.md. This file is the working
digest for refactor task #42 strand 1 (PF adoption). Everything below verified against the clone's
source, not the export list alone.

## What PF ships (one line per module)

- **Fields** — `Grid3D` (uniform, origin-aware, validated), `RealFourierLayout` (permutable rfft
  fold), 6 field types (scalar/vector/tensor × physical/spectral, `R` a type parameter),
  `FieldTransformPlans` (+ `fft_flags = FFTW.MEASURE` option), `to_physical(!)`/`to_spectral(!)`
  (invariant 11: `!`-inverse destroys its spectral source), `FieldSpectralMultipliers` (two
  wavenumber families, Nyquist split, **canonical flag in the type**), `similar_field`,
  `SpectralKernel` supertype + kernel protocol, HDF5 `write_field`/`read_field` (weak dep).
- **FieldAlgebra** — the fiberwise algebra: `add!/subtract!/combine!/multiply!/divide!`,
  `dot/cross/mul!` (α/β), `transpose!/sym/skew/dev/tr/det/norm`, and **`map!`/`map`** (arbitrary
  fiber map φ, physical-only, order-changing, α/β, allocation-free).
- **DifferentialOperators** — `gradient/divergence/curl/symmetric_gradient/laplacian/
  inverse_laplacian/helmholtz_projection` (+`!`), all fused one-pass kernels;
  **`divergence!` and `helmholtz_projection!` take a trailing `kernel[, α, β]`** (operator∘convolve
  in one pass); `curl!` and ℙ are **alias-safe** (dest may BE source).
- **Convolution** — `convolve(!)` (α/β; either argument order; `convolve(g₁,g₂)` composes),
  `exponential_convolve(!)` (lazy `exp(c|k|² + s·ŵ)`; single-operand α/β + **two-operand
  combination forms**), kernel-composed `combine!(dest, α, a, β, b, kernel)`; four kernel classes
  (`StoredKernel`/`SeparableKernel`/`RadialKernel`/`ProductKernel`, bitwise-interchangeable,
  `inv`, `materialize_kernel`); builders `spectral_cutoff`/`spectral_band` (→ Radial),
  `radial_kernel(σ, ref, mult)` (any real symbol of |k|²), `assignment_window`,
  `translation_kernel(!)` (→ Separable, the Nyquist cos factor).
- **Points** — `Point`, `PointSet` ((M,3) SoA), `Scalar/Vector/TensorPointValues`, full mirrored
  algebra + `map!`/`map`, `similar_pointvalues`, HDF5 `write_points`/`read_points`.
- **Interpolation** — `interpolate(!)` (gather W) / `anterpolate(!)` (scatter Wᵀ, α/β), exact
  adjoint + conservation; schemes: `LalescuSpline(n,m)` (TurTLE-pinned, `CatmullRom = (1,1)`
  default), `LagrangeSpline(n)`, spectral `DirectDFT()` (exact O(NM), the oracle) and `NUFFT`
  (plan holds ~8× the field in memory). Callable `field(x)`. **Single-grid only — the BCC
  two-grid raise (#45) is a genuine gap.**
- **Reductions** — `integral/inner/weighted_inner/l2norm/lpnorm`; `mean/std/var/cov` (Statistics;
  need `using Statistics`), `maximum/minimum/extrema`; **mapped forms** `mean(det,A)`,
  `maximum(norm,u)`, `integral(f,·)` (fused, no intermediate section, bitwise
  thread-count-invariant); `radial_spectrum` (+ two-field co-spectrum), `radial_correlation`
  (+ cross), Wiener–Khinchin pair, `sum(spectrum) == inner`.
- **FiberSections** — internal foundation; public: fiber types, `with_threading`,
  `threading_cutoff`/`set_threading_cutoff!` (+ `set_fft_threads!` in Fields).

## The deltas since IT's pin (what the wiring sweep adopts)

1. **`cross!`/index-shuffles alias-safe by construction; `_guard_noalias!` retired** (decisions
   38/39/59). Dest may BE an operand. Backed by the ownership rule. ⇒ Lamb-into-vorticity legal.
2. **Kernel classes** (decisions 50/51/60/61/62): masks/cutoffs are `RadialKernel` (zero storage),
   translation kernels are `SeparableKernel` (3×O(N) — vs the O(N³) complex fields IT holds now),
   `radial_kernel(σ,…)` for any symbol, `ProductKernel` composition, canonical-multiplier
   collapsing. A bare `ScalarFieldSpectral` is **no longer a kernel** — wrap in `StoredKernel`.
3. **`exponential_convolve!`** (decision 33, built FOR IT items 2+7): the integrating factor
   applied lazily — incl. the per-mode offset `s·ŵ` for **armed linear forcing rates** and the
   **two-operand form** `exponential_convolve!(dest, α, a, β, b, mult, c[, s, ŵ])` =
   ℰ⊙(α·a + β·b) in ONE pass.
4. **Kernel-composed operator arities** (decision 32): `helmholtz_projection!(dest, f, mult,
   kernel, α, β)` and `divergence!(…, kernel, α, β)`.
5. **`weighted_inner` takes any kernel class** (decision 62), complex weight refused by type
   (`StoredKernel` exempt — real-part hazard, don't feed it a materialized phase).
6. **Mapped reductions + `map!`/`map` + `cov`** (decisions 30/48/49).
7. **`squared_wavenumber_field` deleted** (decision 60) — |k|² is `radial_kernel(identity, …)`.
8. **Ownership rule** (decision 59): every section constructor **rejects `SubArray` storage**.
9. `Grid3D` validates spacing (decision 45); permuted-layout metadata must ride `similar_field`
   (the `map` bug class); `to_spectral!` may overwrite its physical source on rocFFT.

## Concrete IT wiring candidates (strand 1), by consumer

**Propagator (`step!`):**
- RK stage update `û ← ℰ⊙(û + Bᵢ·hu)` → `exponential_convolve!(û, 1, û, Bᵢ, hu, mult, c)` —
  one pass; `hu ← ℰ⊙hu` → single-operand form. **Deletes `buffers.integrating_factor` (one
  spectral scalar resident) and every per-stage factor build/apply pair.** Field-proportional
  forcing rate A(κ): the `offset_scale, offset` pair (`ŵ` built once, scale per call free) — the
  `velocity_factor!`/`scalar_factor!` protocol verbs become *parameter suppliers* (c, s, ŵ) rather
  than kernel writers: a protocol-shape decision to make consciously (recorded in the old memory
  as exactly that).
- The pre-registered round-3 two-output stage update `(ĥ, û)` stays not-shipped; the two-operand
  exponential closes most of its gap.

**Generator (assembly):**
- Mask chains: `_velocity_lamb!`'s project-then-mask → `helmholtz_projection!(N̂, product, mult,
  dealias_kernel)` — one pass. Scalar: `divergence!(N̂φ, flux̂, mult, dealias, -1, 0)` — the −∇·
  sign folds into α, and the separate `convolve!(…, dealias, -1, 0)` disappears.
- PhaseShift tails: compose `back_average = convolve(spectral_cutoff(√2N/3), ½·back)` ONCE at
  construction (ProductKernel/radial∘separable), then the tail is
  `helmholtz_projection!(N̂, displaced, mult, composed, ½, ½)`-shaped β-accumulate calls — the
  recorded "two β-projection calls" plan. Shift-back rides the same pass.
- `cross!(ω, u, ω)` — Lamb into the vorticity register (cache row consequence: ω leaves).
- Dealias storage: `TwoThirds`/PhaseShift truncation = `spectral_cutoff` (**RadialKernel — zero
  storage**; today's stored mask is O(N³) complex). `HouLi` = `radial_kernel` with the smooth
  exponential symbol. `to_shifted`/`back` = SeparableKernel (O(N) factors). **The FixedDomain
  frame ledger shrinks by every stored kernel field; re-freeze + retire/renarrow holders.**

**Observables:**
- `max_speed` → `lpnorm(u, Inf)` or `maximum(magnitude, u)` with a plain `√Σu²` map (NOT
  `LinearAlgebra.norm` — overflow-safe scaled form is ~4.3× slower; PF docstring says so).
- `derivative_skewness` det mean → `mean(det, S)` fused (no det field); `⟨S:S:S⟩ = 3·mean(det∘sym…)`.
- ε via `ν · weighted_inner(û, radial_kernel(identity, û, mult))` — **exact, no binning, no
  resident |κ|²**; retires decision-36's reconstructed |κ|² route.
- `energy_spectrum` → `radial_spectrum` (E(κ) = ½P(κ)); co-spectra available for u–φ statistics.
- `integral_scale` — two `weighted_inner`s with radial symbols (∫κ⁻¹E / ∫E) are exact spectral
  moments, no shell binning; or `radial_correlation` for the physical-space route.
- `cov(u)` = the Reynolds-stress tensor, free.
- `scalar_variance` → spectral `var(φ̂)` (Parseval, one pass, no transform) — mind the
  cancellation caveat when mean ≫ fluctuations (φ mean is 0 here, fine).

**Run layer / State:**
- HDF5 checkpointing: `write_field`/`read_field` (+ points twins) — a run snapshot = one file of
  named groups + consumer-owned time attrs. Candidate for the SimulationRun redesign (restart).
- `FieldTransformPlans(…; fft_flags = FFTW.MEASURE)` for long CPU runs — a `FixedDomain` option
  worth exposing (PF warns ESTIMATE mis-plans Float32 by 2.3–5.1× on Zen).
- `set_fft_threads!`, `with_threading`, `set_threading_cutoff!` — CPU-run tuning surface.
- `map!`/`map` — the escape hatch IT's docs can point users at for custom pointwise diagnostics
  in callbacks (physical-only, aliased-result caveat).

**Particles:**
- `DirectDFT` as the tracer-interpolation *oracle* in tests (exact, divergence-free on the
  sub-Nyquist band). NUFFT exists but its plan costs ~8× a field — not for the tracer hot path.
- Interpolation stays single-grid ⇒ #45 (BCC) is a real request; expand against
  `interpolate!`/`anterpolate!`/`AbstractTransferScheme` when drafting.

## Adoption risks / contracts to respect

- **IT's allocators break at kernel compression** (user-probed 2026-08-05):
  `_reference(domain) = field_data(domain.dealias)` (SimulationDomain.jl:221) reads the stored
  mask's array as the backend/eltype template — a `RadialKernel` has no storage array. Fix: take
  the reference from the multipliers' O(N) axis arrays. AND: the six domain-first allocators wrap
  with the TWO-argument constructors (`VectorFieldSpectral(data, grid)` — layout dropped to
  default, SimulationDomain.jl:255ff) — the exact metadata-drop class PF's decision-48 postmortem
  records; latent only because IT uses the default layout. Refactor move: keep the domain-first
  names, delegate to PF constructors WITH the layout (or `similar_field` where a reference field
  is in hand); keep `_blank`'s zero-fill only where deliberately wanted (`similar_field` is
  uninitialized).

- **No field on a view** (decision 59): if any IT code wraps a slice of a bigger buffer into a
  field, the new PF throws at construction. Sweep IT's buffer allocation in the wiring pass.
- **A `ScalarFieldSpectral` no longer dispatches as a kernel** (decision 60): every IT call site
  passing a stored mask/kernel field to `convolve!` must wrap it in `StoredKernel` — or better,
  move to the compressed classes. (This broke PF's own demos; it WILL break IT's current calls.)
- Strict same-eltype/same-storage-family on every multi-arg op (invariant 14) — no silent
  promotion anywhere.
- `weighted_inner` StoredKernel complex-weight = silent real part — never feed a materialized
  translation kernel as a weight.
- Mixed spectral `inner(f, g)` allocates O(N²) correction planes per call — hot loop uses
  `inner(f,f)`/`weighted_inner`/physical inner.
- `mean/std/var/cov` need `using Statistics` (not re-exported).
- `translation_kernel` composition ≠ summed displacement at Nyquist (cos·cos ≠ cos-sum) — IT's
  PhaseShift kernels are built per displacement, fine; don't "optimize" by composing.
- `to_spectral!` may overwrite its physical source on rocFFT (invariant 11 now documented both
  directions) — relevant on Aiporetne.
- Cost register: PF docstrings state costs, never cadence; IT doc cross-references should match.

## Notes for the notes (cross-links)

- Cache design (R2 notes): slot=register merging is compatible with the ownership rule — slots
  are whole arrays, never views of an arena. Good.
- The audits: adopting compressed kernels moves several FixedDomain frame-ledger rows to zero and
  changes pass counts (kernel-composed ops remove whole passes) — every adoption lands with a
  conscious re-freeze + holder retirement, per strand-1 obligations in task #42.

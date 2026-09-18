# PF request (2026-09-17): add values on a finite set of Fourier modes to a spectral field

**STATUS (2026-09-17): WITHDRAWN by IT the same day, superseded by `pf-request-2026-09-17-shared-modes.md`.** The owner pointed out that the mode-list design this request serves has IT hand-writing field machinery PF owns (the per-mode Leray projection, the ±κ and self-conjugate-plane bookkeeping, the per-mode variance accounting, bespoke persistence and display). Representing the process as an ordinary spectral field on a coarse grid of the same box returns all of it to PF and leaves one primitive — the shared-mode transfer — serving both forcings. Kept for the record: the problem statement and the measurements below stand, and the ±κ/Nyquist points PF raised carried over into the surviving request.

**From**: GBGIsotropicTurbulence. The owner directed (2026-09-17) that IT's archived Eswaran–Pope
stochastic forcing `StochasticOU` return as a full option, chose the band-sparse design below over a
dense on-device one, and approved sending this request.

## Why the dense form is not usable

Eswaran & Pope (1988) force only the modes of a low-wavenumber band. For shells 1–2 that is 80
lattice wavevectors, 40 conjugate pairs. The archived implementation nevertheless draws white noise on
the whole physical grid, transforms it, band-limits it and Leray-projects it every step, and it holds
three field-scale arrays (the force, a physical and a spectral noise scratch). Measured on the RTX 5070 Ti,
128³ `Float32`, `IFLowStorageRK3`: 17.6 ms per step against 3.2 ms under the default forcing, and 25 MB
of host allocation per step, because the noise is drawn on the host and copied to the device. At 768³
that is 5 GB of host allocation per step. Drawing on the device would remove the copy but keep the three
fields and the three transforms, and a device generator gives a different realization per backend.

## The band-sparse form

The process lives on the band's modes only: one complex value per component per conjugate pair,
advanced on the host (a few hundred numbers — exact per-mode OU, projected onto the plane normal to
`κ` for the velocity), uploaded once per step into a preallocated `(M, NC)` array on the field's
storage family, and added into the right-hand side at every stage. Nothing field-scale is held, no
transform runs, and the realization is identical on every backend because the stream is the host's.

The one step IT cannot express with the current exports is the last: **adding values at a list of
modes into a spectral field.** Checked against the export list before asking: `add!` / `combine!`
need a dense operand; `convolve!(f̂, ĝ, K, α, β)` multiplies an operand by a kernel, so an additive
source needs a dense `ĝ`; a lazy `SpectralKernel` is still a multiplier; `anterpolate` with
`DirectDFT` deposits point sources in physical space, costing a sum over points at every mode. None is
an O(M) additive write.

## What is asked

A physics-free pair; names, argument order and types are PF's call.

1. **A mode set built from a band.** From the same inputs as `spectral_band(multipliers, low, high)`
   — so membership is PF's, identical to the kernel's (`low ≤ |κ| ≤ high`) — the set of nonzero
   lattice wavevectors in the band, **one representative per conjugate pair ±κ**, in a documented,
   deterministic order that does not depend on the storage backend or on the layout's folded axis (so
   a seeded host stream maps to the same modes everywhere). It exposes the representatives'
   wavevectors on the host (M × 3, physical units), which IT needs to project each value onto the
   plane normal to `κ`. It holds whatever index arrays the write needs on the field's storage family,
   built once.

2. **An in-place additive write.** Given a spectral field `f̂` of tensor order `R` (`NC`
   components), a mode set, a values array `v` of shape `(M, NC)` on the field's storage family, and a
   scalar `α`:

   ```
   f̂(κ_j)  += α v_j
   f̂(−κ_j) += α conj(v_j)        for every representative κ_j
   ```

   applied to whichever of `κ_j` and `−κ_j` the layout stores — both on a self-conjugate plane of the
   folded axis, one elsewhere — so the result is the spectrum of a real field whenever `f̂` was.
   **Normalization (corrected by PF on receipt):** PF's forward transform is unnormalized, so
   `inner(f, f) = Σ|f̂(κ)|² / N²` with `N = prod(grid_size)`, and a stored coefficient is `N` times the
   physical amplitude `a_κ` of that mode (`f(x) = Σ a_κ e^{iκ·x}`). IT keeps its process and its
   checkpoint in physical amplitudes and prefers a write that takes them (scaled by `N` inside, as
   PF's constant-add does); a write taking stored coefficients works too, with IT scaling at upload.
   The docstring should say which. Allocation-free after
   construction, one device launch, no field-scale pass. It returns `f̂`.

Not asked now: the reverse gather (`v_j ← f̂(κ_j)`), which would give an O(M) forcing power
`⟨f, u⟩`. IT has no consumer for it yet.

## Other consumers

Anything that injects content on a few named modes: Kolmogorov flow's `sin(k y)` forcing (one pair),
a Taylor–Green or ABC forcing (a handful of pairs), a prescribed-mode initial condition, and the
deterministic single-mode forcings of the forcing literature.

## IT's side, meanwhile

IT builds the rest — the host-side process, the new home of its state on the run's State (IT decision
23(c)), checkpointing of that state and the stream, and the tests — against the shape above, and wires
the write when it lands.

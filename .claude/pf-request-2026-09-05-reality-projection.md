# PF request (2026-09-05): a reality projection on the self-conjugate planes — decision 71's premise fails in a forced run

**STATUS: SHIPPED by PF (decision 83, master 352699a1) and WIRED into IT (decision 88, same day): `reality_projection!` at every scheme's exit beside `helmholtz_projection!`; PF's CUDA lane 494/494 on Enteropia; the seed-1 96³ run holds to t = 100 with residual exactly 0.** Originally: ACCEPTED by PF (owner-decided 2026-09-05), shipping as `reality_projection!` (PF decision 83, ETA same day). Name changed from the proposed `real_projection!` (accurate only at the self-paired corners; `hermitian_*` declined too, LinearAlgebra's `hermitianpart` reads as a fiber operation — both recorded in PF's entry). Semantics exactly as asked below: projection only, returns its argument, no residual, not in `to_spectral!`, all tensor orders, layout-general. PF reproduced the premise check on rocFFT (nonzero at every size, 2e-5 … 8e-4 in coefficient units, Float32) and is correcting decision 71's "by construction" clause on that evidence. IT's follow-up when the commit lands: PF bump, CUDA parity on Enteropia, the wiring below. Channel closed again after the reply.

**From**: GBGIsotropicTurbulence, out of an owner-reported run whose turbulence died after ~65 time
units (reproduced on CUDA and CPU; every seed, every scheme, every dealiasing, both precisions —
numbers below). Draft written by the IT session for the owner to carry; nothing was sent.

## What happens

A `VarianceController` run at 96³ / Float32 holds the spectral kinetic energy at 1.500 for the
whole run while, from t ≈ 45, the energy of the PHYSICAL field (½⟨|u|²⟩ on the grid) falls away
from it and reaches 0.03 by t ≈ 90; the dissipation collapses from 0.45 to 0.027 (= 2νκ²k at κ = 1,
i.e. all the energy sits in the forced shells) and the maximum speed falls to 0.3 — impossible for
a real field with k = 1.5. `reality_residual(û)` tells the story exactly (seed 1, RK4, PhaseShift):

| t | k spectral | k physical | ε | residual | E(k₁ = 0 plane) |
|---|---|---|---|---|---|
| 0 | 1.5000 | 1.5000 | 0.062 | 4.2e-2 | 0.50 |
| 20 | 1.5000 | 1.5000 | 0.442 | 5.5e0 | 0.32 |
| 40 | 1.5000 | 1.5000 | 0.461 | 1.4e3 | 0.40 |
| 55 | 1.5000 | 1.4935 | 0.473 | 8.2e4 | 0.24 |
| 64 | 1.5000 | 0.8603 | 0.292 | 8.3e5 | 0.85 |
| 88 | 1.5000 | 0.0281 | 0.030 | 1.3e6 | 1.48 |

The residual grows exponentially at 0.26 per time unit from its round-off floor (4e-2 in
coefficient units is ~1e-7 relative to the energy-containing coefficients at N³ scaling), and
saturates when the k₁ = 0 plane holds all of k. The Nyquist plane and the mean mode stay at zero.

## Why

The anti-Hermitian part of the folded axis's zero plane is a **parasitic linear mode of any forcing
proportional to the field**. The inverse real transform projects it out, so the nonlinear term —
formed from the physical fields — neither sees it nor feeds it; viscosity damps it at νκ² (0.007 at
κ = 1); and every band-limited forcing of the form `N̂ += A·𝟙_band·û` (the controller, `ConstantPower`,
`Linear`'s steady rate, `VarianceRescaling`'s rescale) amplifies it with the same coefficient A as
the physical modes, which A must hold positive on average to balance ε. Net growth A − νκ² ≈ 0.26
per time unit; from Float32 round-off that reaches order one at t ≈ 60 for every seed (six seeds
died at t = 66–71), for RK3 as for RK4 (68.3 vs 66.8), for TwoThirds as for PhaseShift (71.6), and
in Float64 at t = 142 — the floor is 1e-9 smaller in amplitude, and ln(1e9)/0.26 ≈ 80 time units
later is what the rate predicts. `StochasticOU` is additive (noise drawn in
physical space) and does not amplify. A decaying run is unaffected.

The seed is the real-to-complex transform's own round-off on the k₁ = 0 plane, measured directly on
a random real field (largest |f̂(k) − conj f̂(−k)| over the plane, relative to its largest entry):

| | FFTW 32³ | FFTW 96³ | cuFFT 32³ | cuFFT 96³ |
|---|---|---|---|---|
| Float32 | 0 exactly | 1.5e-7 | 3.0e-7 | 2.4e-7 |
| Float64 | 0 exactly | 3.6e-16 | 3.0e-16 | 4.3e-16 |

FFTW is exact at the power-of-two size and ulp-level elsewhere; cuFFT (and, in the owner's run,
rocFFT) is ulp-level everywhere. So decision 71's premise — "everything the package itself
produces satisfies the constraint by construction" — holds at the ulp level and no further, and a
forced solver turns the ulp into the whole field. (A 32³ CPU control run under all six forcing
laws kept the residual at exactly 0 for 100 time units, which is the same statement from the other
side: no seed, no growth.)

## What is asked — `real_projection!(f̂) -> f̂` (settled by a three-lane design review + critic, 2026-09-05)

An O(N²) in-place verb, the twin of `helmholtz_projection!` in name and in kind: on the folded
axis's stored self-conjugate planes (k₁ = 0, and k₁ = N/2 when the axis is even) replace each stored
pair by its arithmetic mean, `f̂(0,k₂,k₃), f̂(0,−k₂,−k₃) ← ½(f̂(0,k₂,k₃) + conj f̂(0,−k₂,−k₃))`; the
self-paired corners come out as `Re f̂` from the same formula. This is the orthogonal projector onto
real-field spectra in PF's own Parseval weighting (the stored plane counted once), linear and
idempotent; it commutes with every per-mode multiplier satisfying m(−κ) = conj m(κ) — the integrating
factor, the dealias masks, the Leray tensor, and the translation phases alike. Semantics settled:
projection ONLY (no Nyquist zeroing — that is a dealiasing policy, and the consumer's truncation
already keeps those planes empty); a plain mutator returning its argument, no residual returned
(`reality_residual` stays the separate checker, decision 71's report/repair split intact); not folded
into `to_spectral!` (a fresh transform of real data already satisfies the constraint to round-off —
the defect lives in state accumulated in place, not in transforms). Implementation: the traversal of
`reality_residual` written as one KernelAbstractions pass with modular-index mirroring (no
`reverse`/`circshift` temporaries), one launch per field, no host sync, no allocation, every pair
touched once (deterministic on any backend). Measured for contrast: the physical round trip perturbs
EVERY mode by ~1e-7 (F32) and resets the residual only to the transform's floor (5e-8), since the
forward transform reseeds it; the mean projection zeroes it exactly and touches nothing else. TurTLE calls the same thing
`symmetrize()` after every forcing and every step (six call sites in `vorticity_equation.cpp`);
its absence is what this run measured. Decision 71 declined a repairing verb because "the repair
already exists" as the physical round trip: that repair costs six transforms per step on a vector
field where the projection costs two planes, and a solver cannot afford it per step. The consumer
would call it once per iteration, at the closing deposit, so the forcing's amplification never
compounds.

Not asked: enforcing the symmetry inside PF's own operations (the seed is FFTW's, and per-op
enforcement would tax every transform for a problem only a multiplicative forcing creates).

## Prior art in the reference codes (studied 2026-09-05)

- **TurTLE** (`field.cpp`): `symmetrize()` — arithmetic mean of the pair on the kx = 0 plane
  (`(p + conj m)/2`, written to both), the mean mode made real, ALL three Nyquist planes zeroed;
  called after every RK step (after the forcing and the divergence projection), after every
  curl inversion and before the forcing is added, on the acceleration, and on the initial
  condition. Two alternatives kept beside it: `symmetrize_FFT` (the physical round trip) and
  `symmetrize_alternate` (geometric-mean amplitude, mean phase — spectrum-preserving for a
  random-phase field). Its test cross-checks the mean form against the round trip.
- **GHOST**: never symmetrizes in the loop. Its forcing is an additive fixed field, so nothing
  multiplies the state; the one operation that could break the symmetry — the global phase shift
  of the forcing field — is written pair-aware on the kx = 0 plane (`phaseshift`).
- **hit3d**: Machiels forcing `wrk += fac·fields` on the forced shells — the same multiplicative
  form as the consumer's — and no enforcement anywhere; it runs FFTW on the host at power-of-two
  sizes, where the r2c is exactly Hermitian, so it never had a seed.
- **Fluidsim**: 3-D forcings are additive; the 2-D `Proportional` forcing is multiplicative and
  copied spectrally into the fine array with no enforcement — same latent exposure, same FFTW
  immunity on the host.

The pattern: a code with a multiplicative forcing either symmetrizes every step (TurTLE) or is
protected only by its FFT library's exactness (hit3d, Fluidsim). A GPU backend removes that
protection, which is the consumer's situation.

## The literature (searched 2026-09-05)

- **Wang & Rosa (2009)**, *A spurious evolution of turbulence originated from round-off error in
  pseudo-spectral simulation*, Computers & Fluids **38**, 1943–1949 (PII S0045793009000814; DOI not
  resolved from the registry, so not quoted). The exact sibling of this defect on the OTHER
  linear constraint: machine round-off in the divergence-free condition is amplified over ~50
  eddy-turnover times into an unphysical flow state, with a theory for the exponential growth;
  the recommendation is to re-apply the projection at the end of every time step. Same shape:
  a constraint the discretisation does not enforce by construction, a round-off seed, a linear
  amplifier, a re-projection per step as the remedy.
- **Dedalus** (v2.2006 release note, 2020-09-16; troubleshooting page): "numerical instabilities
  may arise due to the loss of Hermitian symmetry in the Fourier components of the solution";
  it re-imposes reality by a grid-space round trip every 100 iterations by default
  (`enforce_real_cadence`), "which may need to be decreased in simulations with strong linear
  instabilities". This consumer's growth rate (0.26 per time unit, ~0.005 per step) makes the
  amplification linear and strong in exactly that sense.
- **Bowman & Roberts** (FFTW++; Bowman, *How to design an efficient pseudospectral code*, CAIMS
  2019, slide 7): evolve only half of the self-conjugate line/plane and fill the other half by
  conjugation — "the white modes in the blue box must agree with their shaded Hermitian
  conjugates!" — with `HermitianSymmetrizeX`/`XY` as the library verbs. The structural
  alternative to a repair: no anti-Hermitian degree of freedom exists to grow.

So the problem is known and has three published answers: re-project every step (Wang & Rosa's
divergence twin, TurTLE's `symmetrize`), re-project at a cadence set by the growth rate
(Dedalus), or never evolve the redundant half (FFTW++). The O(N²) plane projection asked for
above serves the first two; the third is a layout decision PF could take instead.

## Evidence available on request

Scripts and per-step records of the seven GPU runs and the 32³ CPU witness across the six forcing
laws (IT session scratchpad, 2026-09-05); the residual-vs-time table above is from `ghost.jl`.

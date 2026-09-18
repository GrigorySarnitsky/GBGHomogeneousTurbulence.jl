# Request from GBGIsotropicTurbulence (IT) — 2026-08-26, against GBGPeriodicFields master: transform-plan device residency

One item, high value on GPU, no correctness impact. It is a **residency** request, not an API-shape
request: two candidate changes are sketched below with measurements, but the surface design is
yours. Everything here was measured on an RTX 5070 Ti and a Ryzen 9800X3D; every variant produced
**bitwise-identical** spectral and physical output to the current arrangement, at every grid and
precision tested.

## The problem

On a GPU at 256³ in single precision, an IT run evolving no passive scalar holds 1158 MiB of
grid-sized working arrays, and a further 516 MiB — 45% again — inside its Fourier-transform plans;
both scale as ``N^3``, so that ratio holds at every grid and the absolute cost is what bites above
384³. The 516 MiB is four arrays that cuFFT.jl, the Julia wrapper CUDA.jl uses and AMDGPU.jl
mirrors, allocates when the plans are built: one per plan, each sized to the Fourier coefficients
that plan transforms — 193.5 MiB for each of the two velocity plans, whose three components are
transformed together, and 64.5 MiB for each of the two scalar plans, which are built whether or not
a scalar is evolved. Half of that, the two forward plans' 258 MiB, is never touched: it serves a way
of inverting a forward plan that IT never uses, and a marker written into it survives complete
forward and inverse transforms unchanged. The other half exists because a complex-to-real transform
destroys whatever array it reads, so the wrapper copies the caller's coefficients into its own array
and transforms out of that copy, leaving the caller's array intact — but PF has already copied those
coefficients into scratch of its own for precisely that purpose, so every inverse transform copies
the same data twice and runs 14.7% slower than one that does not. Nothing in the plan constructor
lets a caller supply, size, or release that array: it is an ordinary field of the wrapper's plan
type, its type fixed in the plan's type parameters, released only when the plan is finalised.
Enabling IT's strain-tensor diagnostic adds two nine-component plans and 1161 MiB more on the same
grid.

## Where PF sits in it

PF owns exactly one thing in the chain, and it is the thing that decides how many of these arrays
exist:

```
FieldTransformPlans          ← PF's struct (Fields.jl:1289)
  :plan_forward_fft          ← whatever plan_rfft returned   — a foreign object
  :plan_inverse_fft          ← whatever plan_irfft returned  — a foreign object (ScaledPlan → CuFFTPlan)
```

`FieldTransformPlans(physical, spectral)` calls `plan_rfft` (Fields.jl:1312) and `plan_irfft`
(:1316) and stores the results. On CPU those objects hold no Julia array; on a GPU backend each one
holds a device array the size of the field it transforms. **Two plans per field type, and one plan
type per tensor rank, is a PF decision** — and it is the multiplier on the whole cost.

The wrapper's eager allocation is not PF's to fix and is being raised separately with JuliaGPU.
The two changes below are available to PF alone and are independent of that request.

## Prior art — what four comparable codes do instead

Checked in the reference clones and, for the Julia case, measured on the card. Each of these codes
takes at least one escape from the arrangement described above; **PF takes none of them.**

**Transform one component at a time — no multi-component plan exists.**
*Fluidsim* has no vector field type: its state is `vx_fft, vy_fft, vz_fft`, three separate scalars,
and every transform is a scalar transform (`ifft_as_arg(vx_fft, vx)` ×3, `solvers/ns3d/solver.py`
252–254). *GHOST* reaches the same place from the other side: `fftp3d_real_to_complex(plan, in,
out, comm)` (`3D/src/fftp-3/fftp3D.fpp:204`) takes a single scalar field, and a run holds **one plan
pair for everything**, shared by every field of every rank. GHOST's plan does own staging
(`carr`, `rarr`, `ccarr`; on its CUDA backend `cu_ccd_`, `cu_cd_`, `cu_rd_`, `cudaMalloc`'d at sizes
it computes itself) — but one set for the whole run. Its plan scratch is ``O(1)`` in the number of
fields and ranks, where PF's is ``O(R)``. **This is candidate B, with two independent production
precedents.**

**Transform in place, so the caller's array is the staging.**
*TurTLE* passes the same buffer as input and output —
`mpi_plan_many_dft_r2c(..., &buffer[0], (complex*)&buffer[0], ...)`, `cpp/fft/fftw.hpp` 196–216.
Notably it *does* batch by component (`n[3]` is the component count), so it has PF's per-rank
plans — but with in-place execution there is no separate staging array to multiply by rank.
*hit3d* does the same through the classic padded layout, `fields(nx+2, ny, nz, n)`
(`m_fields.f90:21`). This kills the preservation copy rather than the rank multiplication — the
opposite escape.

**Let the caller declare the input expendable.**
*fluidfft* exposes **two** inverse transforms, `ifft_as_arg` and `ifft_as_arg_destroy`, both
declared in its `fft3d/base.py`. Fluidsim uses the distinction exactly as one would hope: in the
ns3d tendency function the vorticity — scratch — goes through `ifft_as_arg_destroy` (solver.py
240–242) while the velocity — state that must survive — goes through `ifft_as_arg` (252–254). That
is **PF's three-argument / four-argument distinction**, with the permission passed *down to the
transform layer* instead of being compensated for by a caller-side copy. The contract PF already
documents therefore has a working implementation elsewhere; what PF lacks is only the channel to
communicate it.

**Use in-place complex transforms.**
*Oceananigans.jl* — Julia, GPU, the identical CUDA.jl surface — plans with `plan_fft!` / `plan_ifft!`.
Measured here: the resulting plan type is `CuFFTPlan{ComplexF32, ComplexF32, -1, true, 3, 3,
Nothing}`, the buffer type parameter being `Nothing`, so it carries no staging array at all. The
price is a full complex field where a half-complex real one would do — right for a single
pressure-solve scratch field, wrong for a DNS state, which is presumably why none of the turbulence
codes above take this route.

## Candidate A — build one plan per field and derive the inverse from it

Instead of building `plan_rfft` **and** `plan_irfft`, build the forward plan and obtain the inverse
as `inv(plan_forward)`. The wrapper hands a derived plan the **same** array rather than a second
one, so the pair costs one array instead of two.

- **Saves exactly half** the plan residency, at every grid and precision.
- **No measurable speed effect anywhere**: within ±2% of the current arrangement in all 36
  measurements — GPU and CPU, Float32 and Float64, 1 and 8 FFTW threads.
- Small change, confined to the `FieldTransformPlans` constructor and the inverse call site.
- **Caveat, and it is the reason this is candidate A and not the recommendation:** the saving rests
  on the wrapper *choosing* to share the array between a plan and its derived inverse. That is
  undocumented. If a future release stopped sharing, the memory would quietly return — a benign
  failure (a number, not wrong physics) but a silent one.

## Candidate B — stop giving each tensor rank its own plan

A real Fourier transform on a periodic box is defined on the box; a rank-``R`` field is that
transform applied along a fiber. PF currently encodes rank in the plan, so every backend that
attaches scratch to a plan pays for it once per rank, **at that rank's size**. Build one plan pair
shaped for a single component and apply it over contiguous component views instead.

- **Saves two thirds** of the plan residency for a vector field, and it is ``1 - 1/R`` in general:
  three quarters for a rank-2 field on the 9-component tensor plans, where it turns IT's 1161 MiB
  diagnostic cost at 256³ into 129 MiB.
- **Rank-independent forever.** A future field rank, or a future backend that hides scratch of its
  own, can then cost only a single component's worth.
- Deletes the need for separate per-rank plan objects in IT's `FixedDomain` (`velocity_plans`,
  `scalar_plans`, `tensor_plans`) — one pair serves all three.
- **Composes with candidate A**: together, one array instead of six.

### Measured cost of candidate B

Percent against the current arrangement, negative = faster. Bitwise-identical output throughout.

| | 96 | 128 | 192 | 256 | 384 |
|---|---|---|---|---|---|
| GPU F32 fwd / inv | — | +10 / −7 | −52 / −39 | −8 / −9 | −1 / −4 |
| GPU F64 fwd / inv | +11 / +6 | +5 / −4 | +1 / +1 | +2 / 0 | 0 / +1 |
| CPU 1 thread F64 | −0 / +0 | −1 / −3 | −5 / −11 | +0 / −3 | — |
| CPU 8 threads F32 | −9 / −14 | −12 / +1 | −14 / −16 | −5 / −10 | — |
| CPU 8 threads F64 | −8 / +5 | −8 / +4 | −6 / −15 | −0 / −10 | — |

Reading, stated conservatively:

- **Small GPU grids cost up to ~11%** on the forward transform (96³/F64, 128³/F32). Batching does
  help when a single component is too small to fill the device.
- **At 256³ and 384³ it is free** — neutral in Float64, mildly favourable in Float32.
- **On 8-thread CPU it is consistently favourable**, 0 to −16%, negative in 13 of 16 cells.
  Plausibly FFTW parallelises one transform across all threads better than a 3-batched one.
- **The −52% at 192³/Float32 should not be counted as a benefit.** It vanishes in Float64 at the
  same size, which no genuine batching effect would do; treat it as cuFFT algorithm selection.
- Noise floor: repetitions drop to 4–5 at 256³ and 384³, so differences under ~5% there are not
  meaningful.

### Known obstacle for candidate B

A single component of an **odd**-``N^3`` field starts at an offset that is not aligned to the
complex element size, and cuFFT refuses it — verified: ``N = 17`` throws `CUFFT_INVALID_VALUE`.
Even ``N`` is unaffected, and IT only ever runs even grids, but PF is general. The fallback (a
batched plan, or a staged copy, for the misaligned case) is a design decision, not a blocker.

## What IT will do either way

Nothing that depends on this. IT's memory audit now measures a device backend and ledgers the cost
explicitly (IT decision 79), so the residency is bounded and named rather than invisible, and the
audit's register is bidirectional: whichever of these lands, IT's `DEVICE_FRAME` falls in the same
commit. IT is **not** working around the cost locally — reaching into a plan's private array from IT
or PF was considered and rejected, because using an array the wrapper still believes it owns fails
as wrong numbers with no error.

## Not requested here

The wrapper's *eager* allocation, and the absence of any way to tell a transform "this input is
expendable" — the second of which would remove the duplicate copy and the 14.7%, and is the real
end state. Both belong to cuFFT.jl/AMDGPU.jl and, for the expendable-input contract, arguably to
AbstractFFTs. That second request need not be argued from first principles: fluidfft ships an API
of exactly that shape (`ifft_as_arg_destroy` beside `ifft_as_arg`), so it can be raised as a known
design rather than a novel one. Raising either is separate and does not block the candidates above.

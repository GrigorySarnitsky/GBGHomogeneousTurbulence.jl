# Memory footprint on a GPU

A run goes on a GPU through the `array_family` keyword of [`Simulation`](@ref): `CuArray` for an NVIDIA card, with [`CUDA`](https://cuda.juliagpu.org/stable/) added to your
environment, or `ROCArray` for an AMD card, with [`AMDGPU`](https://amdgpu.juliagpu.org/stable/). Its `element_type` keyword sets the precision. This
page answers the question a GPU run meets first, whether a grid fits on the card; it also describes how
CUDA's unified memory lets a run outgrow the card. Everything else about driving a device, from writing
efficient device code to the vendors' pitfalls, is on the field library [`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/)'s
[Running on a GPU](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/gpu/) page.

## What a run keeps in memory

The table gives everything a `Simulation` holds: the state, the integrator's per-step storage
([`IntegratorBuffers`](@ref GBGHomogeneousTurbulence.Propagator.IntegratorBuffers)), the generator's workspace for the right-hand side, the
[`ObservablesCache`](@ref GBGHomogeneousTurbulence.Cache.ObservablesCache), and the domain's precomputed spectral multipliers, with every setting not
named in a column at its default. On a grid of ``N^3`` points, ``N`` even, that storage is a cubic polynomial in
``N``. The bytes per grid point are its leading coefficient, and the three right-hand columns evaluate
the whole polynomial, lower-order terms included.

| Dealiasing | Precision | Scalar | Bytes per grid point | ``512^3`` | ``768^3`` | ``1024^3`` |
|:--|:--|:--|--:|--:|--:|--:|
| `TwoThirds()` | `Float32` | no | 72 | 9.0 GiB | 30.4 GiB | 72.1 GiB |
| `TwoThirds()` | `Float32` | yes | 88 | 11.0 GiB | 37.2 GiB | 88.1 GiB |
| `TwoThirds()` | `Float64` | no | 144 | 18.0 GiB | 60.9 GiB | 144.2 GiB |
| `TwoThirds()` | `Float64` | yes | 176 | 22.1 GiB | 74.4 GiB | 176.2 GiB |
| `PhaseShift()` | `Float32` | no | 108 | 13.5 GiB | 45.6 GiB | 108.1 GiB |
| `PhaseShift()` | `Float32` | yes | 136 | 17.0 GiB | 57.5 GiB | 136.2 GiB |
| `PhaseShift()` | `Float64` | no | 216 | 27.1 GiB | 91.3 GiB | 216.2 GiB |
| `PhaseShift()` | `Float64` | yes | 272 | 34.1 GiB | 114.9 GiB | 272.3 GiB |

The table holds for every forcing, for [`HouLi()`](@ref GBGHomogeneousTurbulence.SimulationDomain.HouLi) as for
`TwoThirds()`, and for the integrators `IFLowStorageRK3`, `IFLowStorageRK4` and `IFSSPRK3`. The
[`IFHeun`](@ref) integrator and `HouLi(materialized = true)`, which stores the filter per mode instead of re-evaluating it, each add storage of their own.
Tracers are cheap next to the fields: with the default [`Heun`](@ref) scheme a `Float32` run holds 61 bytes per tracer and a `Float64` run 109.
The package's test suite derives the table and every number in this paragraph from the code, so a
change to the code that moves one of them fails the suite.

On a GPU two costs come on top, and neither is in the table: the CUDA context, fixed in size, and the
FFT library's (cuFFT's) workspace. On an RTX 5070 Ti the whole footprint on the card measured 5 to 38
bytes per grid point above the table across its eight rows, the allocator's rounding included.
That figure was measured once, on one card, and nothing checks it.

## Fields larger than GPU memory

CUDA.jl can allocate every `CuArray` in unified memory, which the driver pages between the GPU and host
RAM, so a run whose fields exceed the card runs unchanged as long as the excess fits in host RAM. The
setting is made once, in the project the run is started from; the call that makes it, the two entries
it writes, and the spelling that leaves it silently off are on the field library's page, under
[Fields larger than GPU memory](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/gpu/#Fields-larger-than-GPU-memory).
AMD's `AMDGPU` has no unified memory, so a run on a ROCm card has to fit in the card's memory.

The package itself needs no change. It never chooses a memory kind where it allocates, so every array a
run holds follows the setting: the state, the scalar, the tracers, and a run restored by
[`read_simulation`](@ref) with `array_family = CuArray`. Each of those was checked once, on one CUDA card. To confirm the setting took
effect in your own run, a `Simulation` `sim`, read the memory kind of its velocity:

```julia
using CUDA
using GBGPeriodicFields: field_data

CUDA.is_unified(field_data(sim.state.velocity_spectral))   # true once the setting is on
```

A displayed `Simulation` shows `CuArray` either way, so this call is the check.

!!! warning "Unified memory changes more than where the fields live"
    The setting covers every array the Julia process allocates, not one run's fields. The cuFFT
    workspace stays in device memory, so it still has to fit on the card. Unified arrays
    ignore `CUDA.allowscalar(false)`, so a scalar index into a unified array runs, slowly, instead of
    raising an error; develop in device memory. The package's own test suite runs only on the CPU. The
    field library's GPU test suites, one of which runs in unified memory, cover the operations a run is
    built from, not a run.

What spilling over costs depends on the link between the GPU and host memory and on the access pattern.
On a PCIe host the field library measured a ``512^3`` `Float64` transform round trip at about 8% slower
in unified memory while every field fit on the card, and about 2.9 times as long once the fields in use
totalled 1.3 times the card's memory. A time step is not a transform round trip, and no run of this
package has been timed in unified memory. On Grace Hopper (GH200) the cost is unmeasured: host memory
sits on a much faster link there, and the setting selects memory that migrates between host and GPU,
not the GPU's direct access to host memory that GH200 also supports. CUDA.jl prefetches a unified array
before each launch only when the process sees exactly one GPU, so a job restricted to its own GPU and
one that sees every GPU on the node page in different regimes. Time a few steps at the target grid, in the job
configuration the campaign will use, before planning on it.

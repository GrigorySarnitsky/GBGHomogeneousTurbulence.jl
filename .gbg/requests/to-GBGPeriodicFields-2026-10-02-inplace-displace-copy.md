Status: open — approved by the owner on 2026-10-02; sent to the GBGPeriodicFields session the same
day. HT records it as broken in test/device_hot_loop.jl and test/device_memory.jl.

# To GBGPeriodicFields: the in-place `displace!` copies an (M, 3) array per call on a device

## The finding

PF's in-place `displace!(points, grid, terms…)` allocates on a GPU, once per call, a copy the size
of the positions. HT's Heun corrector calls it every step
(`displace!(tracers.positions, domain.grid, (Δt/2, v₁), (Δt/2, v₂))`), so a tracked run allocates in
its time loop.

Measured on the RTX 5070 Ti with `CUDA.@allocated`, Float32, PF at the clone HT pins
(`~/.julia/packages/GBGPeriodicFields/REiLA`):

| call, 10⁵ tracers at 64³ | device bytes per call |
|---|---|
| `displace!(dest, src, grid, (Δt, v))`, dest ≠ src | 0 |
| `interpolate!(v₂, u, predictor_points, scheme)` | 0 |
| `displace!(positions, grid, (Δt/2, v₁), (Δt/2, v₂))`, in place | 1,200,000 |
| a whole `advance!` step, tracked | 1,204,532 |
| a whole `advance!` step, no tracers | 2,384 |

That is 12 bytes per tracer, one (M, 3) Float32 array, and it scales linearly in M: 1.16 MB at
32768, 9.2 MB at 262144 over three steps. On the CPU the same call allocates nothing.

## Where it comes from, as read (not verified by a fix)

`_displace_pass!(destination, source, grid::Grid3D, terms)` (Points.jl:1415) assigns each axis
column of the destination from a broadcast that reads `view(source_coordinates, :, axis)`. In place,
destination and source are the same array. On the CPU, `_assign!` for
`Union{Array, SubArray{…, <:Array}}` (FiberSections.jl:288) takes its threaded hand loop when
`_use_threads` says the array is large enough, and that loop does not unalias; below the threshold
it falls back to `materialize!`, as the device path does. HT measured the CPU only at 10⁴ and 10⁵
tracers, both on the threaded path, so whether the small CPU path copies too is not measured. On a
device the generic `_assign!` (FiberSections.jl:285) calls `materialize!`, whose aliasing guard
copies the source column before writing, three columns per call. A pointwise displacement reads each element
before writing that same element, so the copy protects nothing here.

## The second question

The owner asks PF to consider why this was not caught earlier. In HT it went unseen because:
- HT's allocation audit runs on the CPU;
- it uses 8 tracers;
- it bounds allocations only below field scale.

It was found by HT's new GPU memory comparison. What in PF's own checks would have seen a device-only
allocation that the CPU path does not make, and where else might the generic `_assign!` meet an
aliased source on a device?

# Request from GBGIsotropicTurbulence (IT) — 2026-08-24, against GBGPeriodicFields master (post-decision-72)

> **DELIVERED 2026-08-24 (same day), PF decisions 73–74.** Item 1 shipped as `displace!` (fused
> n-term, grid form wraps in-pass); item 2's fork resolved as (a)+: `wrap!` public with IT's
> endpoint-fold and non-finite contract adopted verbatim, AND the grid-free `displace!` keeps the
> universal-cover lift for winding diagnostics. Wired in IT decision 64. This file is now a record.

Two items on the Points layer, both low pressure (``M \times 3`` arrays are small — this is
boundary hygiene, not performance). Each was expanded against the current Points surface before
being raised: the fiberwise algebra covers point **values** in full (`+`, `add!`, `dot`, `cross`,
`map!`, the whole FieldAlgebra mirror), but a `PointSet` sits **outside** that algebra by your own
deliberate role split ("a location rather than a field value … the position-versus-value
distinction is one of role"), so neither ask below is an expressible composition of existing
exports. The requests state the *need*, not the API — surface design is yours.

Context: IT's Lagrangian layer routes every field **sampling** through Points/Interpolation
(`PointSet`, `VectorPointValues`, `interpolate!`) — that boundary is clean. What never crosses the
boundary is the arithmetic that **moves the base**: every trajectory update unwraps with
`point_values(...)` and broadcasts on raw arrays.

---

## 1. Base-space motion: displace a `PointSet` by velocity sections — one traversal, `n` terms

**The need.** A trajectory update is ``X \leftarrow X + \sum_j c_j\,v_j`` — the base displaced
along a linear combination of vector sections over it. IT performs this at every particle push and
today must unwrap both sides. The Heun push (src/Particles.jl):

```julia
v1 = point_values(tracers.particle_velocities)
Xstar .= X .+ Δt .* v1                        # predictor: one-term displacement
...
v2 = point_values(buffers.velocity_predictor)
X .= X .+ (Δt / 2) .* (v1 .+ v2)              # corrector: two-term displacement
```

and the Adams–Bashforth push runs the ``K``-term combination as ``K`` separate broadcast passes
over `X`:

```julia
X .= X .+ T(b[1]) .* f0
for j in 2:K
  X .= X .+ T(b[j]) .* point_values(past[j-1])
end
```

The ask: in-place displacement of a `PointSet` by one, two, or ``n`` coefficient-weighted
point-value sections (host-scalar coefficients), GPU-safe and allocation-free — the one operation
that legitimately crosses your role split, because it is not fiber algebra: it is motion of the
base along a section. The ``n``-term form also fuses the AB update's ``K`` passes into one
traversal (a small win; the boundary is the point).

**Why it is yours rather than ours:** the unwrap-and-broadcast route works, but it writes the
package's only raw-array arithmetic on Points-typed data, outside every contract your layer states
(storage layout, backend movement via `adapt`, the SoA design). And the recorded inertial-particle
ladder will extend per-particle state (velocity, drag) — base-and-state motion ops will then have a
second consumer.

**Acceptance.** IT's `advect!` bodies contain no `point_values(...)` unwrap and no raw broadcast on
positions; the AB combination is one fused call.

---

## 2. The periodic wrap contract, owned once — or ruled unnecessary (a design fork, your call)

**The need.** IT wraps positions into ``[0, L)^3`` after every push (`_wrap!`,
src/Particles.jl), and the subtleties in those four lines are periodic-box knowledge:

```julia
X .= mod.(X, L)
# fold ONLY the excluded endpoint; an `X .< L` test would also catch NaN and Inf
X .= ifelse.(X .== L, zero(eltype(X)), X)
```

- floating-point `mod` can return exactly `L` for a coordinate a hair below zero (measured:
  `mod(-1e-20, 2π) === 2π`), so the excluded endpoint must be folded back explicitly;
- the fold must not test `x < L`, which is false for NaN/Inf and would silently rewrite a
  blown-up trajectory into tidy in-box positions, destroying the one signal a run has diverged.

Meanwhile your own module map states the opposite stance: *"a point set carries no grid; a
periodic domain wraps any coordinate, so the grid is supplied by the transfer operator at use
time"* — and the interpolation kernels do wrap their stencil indices, so sampling tolerates
unwrapped coordinates.

**The fork, honestly posed.** Either
(a) **PF owns a public wrap** — points into the half-open periodic box, with the endpoint fold and
    blow-up transparency documented as the contract — and IT deletes `_wrap!`, the subtleties
    living once, at the layer that owns periodicity; or
(b) **PF documents positions-need-no-wrap as the contract** (interpolation guaranteed correct for
    any finite coordinate), and IT re-derives which of *its* reasons to wrap survive — user-facing
    in-box positions, downstream consumers bucketing by ``\lfloor x/\Delta x\rfloor``, and float
    precision over long runs as ``\lvert x\rvert`` grows. Some survive regardless of
    interpolation, so (a) is IT's preference — but the ruling is a Points-layer design statement
    and therefore yours.

**Acceptance.** Either the wrap ships and IT's `_wrap!` is deleted, or the no-wrap contract is
documented and IT records its wrap as presentation-layer, citing your ruling.

---

*Note, not an ask: when the inertial ladder lands on IT's side (exponential-drag integrating-factor
particles, a recorded deferral), the per-particle state grows beyond positions — at that point a
point-state container with the same algebra becomes the natural extension of item 1, and we would
raise it then, with the concrete consumer in hand.*

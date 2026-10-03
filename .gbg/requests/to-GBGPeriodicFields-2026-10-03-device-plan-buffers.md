Status: open — approved by the owner on 2026-10-03; sent to the GBGPeriodicFields session the same day.
It refiles HT's request of 2026-08-26 (transform-plan device residency, in HT's git history at
`.claude/pf-request-2026-08-26-transform-plan-residency.md`), of which part is delivered. HT records
the rest as the :PF_RAISE gap DEVICE PLAN BUFFERS (test/audit_ops.jl).

# To GBGPeriodicFields: the two plan buffers a device domain still holds

Delivered since the original request: PF's rank-blind plans (its decision 76) gave HT one plan pair
for every field. HT went from 26 spectral-sized device buffers to 2, its `DEVICE_FRAME`, and HT's
device-memory comparison confirms the frame holds exactly these two.

Still open, as the original request measured it on an RTX 5070 Ti:

1. **The forward plan's buffer is never used.** CUDA.jl's `plan_rfft` allocates it for an inverse
   route through the forward plan, which HT never takes; a marker written into it survives full
   forward and inverse transforms. That is one spectral scalar, about 68 MB at 256³ / Float32.
   The original's candidate A built the inverse as `inv(plan_forward)`, so that the pair shares one
   buffer: half the residency, bitwise-identical output, no measurable speed change.
2. **Every inverse transform copies twice.** The wrapper copies the coefficients into its own buffer
   because a complex-to-real transform destroys its input, while PF's four-argument `to_physical!`
   has already copied them into scratch for the same reason. The inverse was measured 14.7% slower
   for it. The original pointed at fluidfft's `ifft_as_arg_destroy` as precedent for passing "the
   input is expendable" down to the transform layer.

The wrapper's allocation is CUDA.jl's (and AMDGPU.jl's, which mirrors it), not PF's. What PF
controls is how many plans it builds and which transform call it makes. How, and whether, is PF's
call.

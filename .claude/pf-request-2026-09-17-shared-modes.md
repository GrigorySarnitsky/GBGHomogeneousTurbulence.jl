# PF request (2026-09-17, second): transfer the modes two spectral fields of the same box share

**From**: GBGIsotropicTurbulence, for the Euler forcing of Pumir (1994) / Vallefuoco, Naso & Godeferd
(2018), which the owner is weighing alongside the returning `StochasticOU`. Companion to
`.claude/pf-request-2026-09-17-band-modes.md`, which stands unchanged.

## The problem, in case PF sees a better cut than the one asked for

In Euler forcing the modes with `|κ| ≤ κ_F` obey the incompressible **Euler** equations and are
independent of every other mode; the modes above obey Navier–Stokes and do see them. The block's
nonlinear term is therefore the convolution **restricted to the ball** — not the full term masked,
which would carry triads with legs outside the ball. IT needs, at every Runge–Kutta stage:

1. the stage velocity's low modes, in a form it can evaluate that restricted term on;
2. the result written back over the assembled term on those same modes (a replacement, not an
   accumulation).

IT's intended route is to evaluate the term on a **coarse domain of the same box** with its own
existing assembly — the rotational form, the Leray projection, the `TwoThirds` truncation — since a
coarse grid's modes are exactly the fine grid's low modes, and a coarse pseudospectral product with
`N_c ≥ 3κ_F` is alias-free inside the ball. IT verified that last point against its own assembly: a
generic bilinear product at `N_c = 3κ_F` errs by 25–60%, while the rotational Lamb-vector form with the
fused projection lands at 1e-13–1e-15. That reuses the whole solver instead of hand-writing an O(M²)
triad sum, which is the alternative and which IT would rather not write.

What is missing is only the transfer between the two resolutions.

## What is asked

**Transfer the modes two spectral fields of the same periodic box share.**

    dest(κ) ← β·dest(κ) + α·source(κ)   for every κ that both fields store
    every other mode of dest untouched

- both directions (coarse→fine and fine→coarse), tensor orders 0 and 1, any storage family;
- `β = 0` is the case IT needs for Euler forcing (an assignment on the shared modes); `β = 1` is the
  accumulate;
- allocation-free after construction, and **no field-scale pass over the fine field** — only the shared
  modes are touched. This is the whole point: the fine field is `768³` and the shared block is `~16³`;
- the scale factor: PF's transforms are unnormalized, so a stored coefficient is `prod(grid_size)` times
  the physical amplitude and a transfer between resolutions carries `N_dest/N_source`. PF's call whether
  the op applies it or takes physical amplitudes, as with the other request;
- whatever index machinery it needs, built once, held on the field's storage family.

**The edge IT is wary of, having been burned by it.** The real-to-complex layout stores both members of
a conjugate pair only on the folded axis's self-conjugate planes, and a coarse grid's Nyquist plane is
*not* a fine grid's Nyquist plane — the same class of asymmetry that produced IT's decision 88 (a
forced run that died at `t ≈ 65` from an unprotected self-conjugate plane) and that PF's own NUFFT
embedding handles by zeroing the Nyquist plane. IT can guarantee a precondition that keeps the transfer
away from it entirely: the coarse grid's content lies strictly inside `|κ| ≤ N_c/3`, so its Nyquist
shell is empty. IT would rather PF **state the contract explicitly** — refuse the ambiguous modes,
define them, or require the precondition — than leave it to a caller's care.

## One primitive, not two (updated 2026-09-17, after the owner's review)

The band-mode request is **withdrawn**. `StochasticOU`'s process is represented as an ordinary
spectral field on a coarse grid of the same box, so it uses this transfer too: a real-space Gaussian
draw transformed on the coarse grid is Hermitian by construction, `helmholtz_projection!` makes it
solenoidal, `combine!` is the Ornstein–Uhlenbeck transition, `write_field` persists it, and the band is
a `spectral_band` mask — needed in any case, since a coarse grid's modes form a cube and a forcing band
must be a sphere. IT needs coarse→fine with `β = 1` for the OU (accumulate into the assembled term) and
both directions with `β = 0` for Euler forcing.

The reason for the reversal is worth recording: the mode-list design had IT re-implementing the
per-mode Leray projection, the ±κ and self-conjugate-plane bookkeeping, the per-mode variance
accounting, and bespoke persistence — all of it PF's. The defence of it rested on the code already
being written and measured, which is not an argument.

## Superseded: is this one primitive with the other request, or two?

The owner's preference is that both forcings use the same PF functions where that is honest. IT's two
needs are:

- **StochasticOU**: values on a list of band modes, added into a field (the first request). Its state is
  a host-side list of ~40 conjugate pairs and it runs no transform, ever.
- **Euler forcing**: a whole coarse field's modes, assigned into a field and read back out.

IT considered representing StochasticOU as a coarse field too, so that one transfer op would serve
both, and **rejected it** after two independent critics: the coarse form earns its cost only when the
companion has its own nonlinear dynamics, and for the OU it would give back measured wins (one kernel
per stage instead of five plus a transform, no second domain, a realization bit-identical across
backends) while still needing a band mask, since a forced band is an annulus and a coarse grid is a
ball.

So IT asks for both, and would welcome PF's judgement that one primitive — a scatter/gather between a
spectral field and either a mode list or another field's shared modes — is the better cut. IT has no
stake in the shape, only in not writing field machinery itself.

## Not asked

Nothing physics-shaped: the restricted convolution is evaluated by IT's own assembly on the coarse
domain; the forcing's dynamics are IT's. No reverse gather beyond the fine→coarse direction above.

# Observables — the functions of the flow state that are measured: kinetic energy, dissipation, the
# velocity-derivative skewness, the scalar variance and its dissipation, the maximum flow speed
# (which feeds the CFL), and the field-valued vorticity recovery. In the Mori–Zwanzig reading
# (ARCHITECTURE §8) these are the observables of the `Generator`: three of them gate warm-up and
# their statistics are to be tracked by GBGStreamingStatistics. Most reduce a field to a scalar — a
# GBGPeriodicFields inner product or moment.

"""
    Observables

The measured functions of the flow state:
- [`kinetic_energy`](@ref), [`scalar_variance`](@ref) — the turbulent kinetic energy and the scalar
  variance.
- [`dissipation`](@ref), [`scalar_dissipation`](@ref) — their dissipation rates.
- [`kinetic_energy_and_dissipation`](@ref) — ``(k, \\varepsilon)`` in one fused traversal.
- [`derivative_skewness`](@ref) — the velocity-derivative skewness, the classical marker of a
  developed cascade.
- [`max_speed`](@ref) — the fastest flow speed on the grid, which sets the advective-CFL step (one
  generic shared with `Cache`: the field reduction is homed here, the cached read there).
- [`vorticity_physical!`](@ref) — the vorticity recovered in physical representation from the
  state's spectral representation, the one field-valued observable
  (its cached read, [`vorticity_physical`](@ref GBGIsotropicTurbulence.Cache.vorticity_physical),
  lives in `Cache`).
- [`energy_spectrum`](@ref), [`integral_scale`](@ref) — the measured energy spectrum and the integral
  length scale derived from it.

Each is a function of the state: most reduce a field to a scalar, the energy spectrum reduces to
the spectral density sampled on the wavenumber shells, and the vorticity recovery alone produces a
field. Each returns
the field's own real element type rather than a fixed `Float64`, so a `Float32` run measures in
`Float32`.

Three observables gate the automatic warm-up
([`warmup!`](@ref GBGIsotropicTurbulence.SimulationRun.warmup!)), which advances until the
dissipation ``\\varepsilon`` stops drifting, the derivative skewness reaches its plateau, and — when
the scalar is forced — the scalar variance settles too. The kinetic energy is **not** among them: a
constant-energy forcing clamps it flat and a fixed-injection forcing makes it ring, so it is
measured (it normalizes the eddy-turnover clock) but never gated on.

None dealiases first: the quadratic reductions are exactly alias-free under a truncating dealiasing
band (see `kinetic_energy` for the condition;
[`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi) meets it only to machine precision),
and the cubic skewness carries a slight aliasing residual — its docstring states the per-strategy
standing (priced for the sharp truncations, unpriced for `HouLi`'s taper).
"""
module Observables

using GBGPeriodicFields
using Statistics: mean                    # the mapped mean — PF extends it, Statistics owns the name
using ..SimulationDomain: FixedDomain, new_tensor_field_physical

export kinetic_energy, dissipation, kinetic_energy_and_dissipation, max_speed, vorticity_physical!,
       scalar_variance, scalar_dissipation, derivative_skewness,
       energy_spectrum, integral_scale


"""
    kinetic_energy(u)
    kinetic_energy(û)

The turbulent kinetic energy
``\\texttt{kinetic\\_energy} \\equiv k = \\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle``
of the velocity field ``\\boldsymbol{u}`` (the `u` argument). Computed as
``\\tfrac{1}{2}\\langle\\boldsymbol{u},\\boldsymbol{u}\\rangle`` with the normalized inner product,
so by Parseval's theorem it accepts the velocity in either representation — the physical field
``\\boldsymbol{u}`` or its spectral coefficients ``\\hat{\\boldsymbol{u}}`` — to the same value.

Like every quadratic reduction here (`dissipation`, `scalar_variance`, `scalar_dissipation`), it
needs no dealiasing of its own: the sum over spectral coefficients is exact, and the equivalent
physical-space mean picks up no aliasing either, because a quadratic's zero mode folds in nothing
when ``2\\kappa_{\\max} < N`` in units of the fundamental ``2\\pi/L`` — satisfied by the ``2/3``
rule, by [`PhaseShift`](@ref GBGIsotropicTurbulence.SimulationDomain.PhaseShift)'s wider
``\\sqrt{2}N/3`` band, and by every narrower band.

[`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi) keeps the full band
``\\kappa_{\\max} = N/2``, where the only pairs that fold to zero are Nyquist modes its taper has
already damped to machine precision — alias-free in practice, not exactly.
"""
kinetic_energy(u) = inner(u, u) / 2


"""
    dissipation(ω, viscosity)
    dissipation(û, domain, viscosity)

The mean kinetic-energy dissipation rate of a homogeneous flow — a single number, not a field:

```math
\\begin{aligned}
\\varepsilon &= \\nu \\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle \\\\
              &= 2\\nu\\langle S_{ij}S_{ij}\\rangle,
\\end{aligned}
```

the two forms equal for a homogeneous, divergence-free flow (periodicity alone removes the
boundary terms; the remaining difference is the dilatation ``\\nabla\\cdot\\boldsymbol{u}``, zero for
the Leray-projected state a run advances), with the strain-rate tensor
``S_{ij} = \\tfrac{1}{2}(\\partial_{x_j}u_i + \\partial_{x_i}u_j)``.

The arguments are:
- `ω` — first form: a vorticity field, in either representation.
- `û` — second form: the velocity in spectral representation.
- `domain` — second form: the [`FixedDomain`](@ref) supplying the
  ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}`` multiplier.
- `viscosity` — both forms: the kinematic viscosity ``\\nu``.

Two routes reach the same rate; take the one whose input is already in hand. The first form measures
from the vorticity as the normalized inner product (Parseval) — use it where
``\\boldsymbol{\\omega}`` exists for its own sake, as the cached vorticity does. The second
measures straight from the velocity, with no vorticity formed at all — use it to measure off the
state, where a ``\\boldsymbol{\\omega}`` would be built only to be reduced away.

The second route trades the curl for a ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``-weighted spectral
inner product against the `domain.squared_wavenumber_kernel` multiplier: from

```math
\\begin{aligned}
\\lvert\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}\\rvert^{2}
  &= \\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\lvert\\hat{\\boldsymbol{u}}\\rvert^{2}
   - \\lvert\\boldsymbol{\\kappa}\\cdot\\hat{\\boldsymbol{u}}\\rvert^{2},
\\end{aligned}
```

the mean-square vorticity of a divergence-free velocity is its **Dirichlet energy** — the mean square
of its gradient, ``H^1`` in the Sobolev naming —
``\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle = \\langle\\hat{\\boldsymbol{u}},\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\hat{\\boldsymbol{u}}\\rangle``.

!!! warning "The velocity route holds only for a divergence-free field"
    The `û` route drops the ``\\lvert\\boldsymbol{\\kappa}\\cdot\\hat{\\boldsymbol{u}}\\rvert^{2}``
    term, so it holds only for a divergence-free velocity — exact for a state advanced by the
    Leray-projected dynamics, wrong for an arbitrary vector field. The vorticity route carries no
    such condition. (The scalar twin, [`scalar_dissipation`](@ref), is unconditional: a scalar has
    no solenoidal constraint to invoke.)
"""
function dissipation end

dissipation(ω, viscosity::Real) = (v = inner(ω, ω); oftype(v, viscosity) * v)

dissipation(û, domain::FixedDomain, viscosity::Real) =
  (v = weighted_inner(û, domain.squared_wavenumber_kernel); oftype(v, viscosity) * v)


"""
    kinetic_energy_and_dissipation(û, domain, viscosity)

Measure the turbulent kinetic energy ``k`` and the viscous dissipation rate ``\\varepsilon``
together, from one fused traversal of the velocity in spectral representation.

The two values are [`kinetic_energy`](@ref)`(û)` and [`dissipation`](@ref)`(û, domain,
viscosity)` — each formula at its own home; the dissipation is bitwise identical to its single
call, the kinetic energy equal to within summation-order roundoff (a few ulp: the single reduces
on a threaded tree, the fused pass serially) — but the pair costs one read of the coefficients and
one blocking device-to-host readback instead of two. Reach for it wherever both are
wanted at every iteration; the standing case is the eddy-turnover clock ``\\Delta t \\varepsilon/k``
of a spin-up or budget loop, which is how
[`StationarityCriterion`](@ref GBGIsotropicTurbulence.SimulationRun.StationarityCriterion) measures it.

The arguments are:
- `û` — the velocity in spectral representation, divergence-free: the dissipation is measured by the
  velocity route of `dissipation`, exact only for a solenoidal field (its docstring carries the
  condition).
- `domain` — the [`FixedDomain`](@ref GBGIsotropicTurbulence.SimulationDomain.FixedDomain) whose lazy
  reduction weights the traversal evaluates.
- `viscosity` — the kinematic viscosity ``\\nu`` scaling the dissipation.

Returns a named tuple `(kinetic_energy, dissipation)`, each in the field's own real element type.
"""
function kinetic_energy_and_dissipation(û, domain::FixedDomain, viscosity::Real)
  whole, dirichlet = weighted_inner(û, (domain.unit_kernel, domain.squared_wavenumber_kernel))
  return (kinetic_energy = whole / 2, dissipation = oftype(dirichlet, viscosity) * dirichlet)
end


"""
    max_speed(u)
    max_speed(cache)

The fastest flow speed on the grid, ``\\max_{\\boldsymbol{x}}\\lvert\\boldsymbol{u}(\\boldsymbol{x})\\rvert``,
of the velocity field `u` in physical representation — the speed that sets the advective-CFL
timestep. The magnitude is formed one grid point at a time and consumed by the maximum immediately,
so no magnitude field is materialized.

The second form reads the number back from an
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache), where the closing deposit
left it — the same quantity, measured once per iteration and served without a reduction (or a
device readback); it throws an `ErrorException` when no deposit is current, like every cached read.

!!! note "A grid maximum, not a continuum supremum"
    The reduction runs over grid points, so between them the flow can be faster than any sampled
    value, which makes the sampled maximum an under-estimate — one of the two loosenesses
    [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl) prices when it sets
    its margin. A CFL condition bounds the *stability* of the explicit advective term; it is not by
    itself a guarantee of accuracy.

!!! note "Why this observable alone has a cached form"
    The cache holds exactly what the iteration already computes and leaves alive at its end; its
    contents follow from the run's fixed computation schedule. The maximum speed qualifies because the
    run itself needs it: on the adaptive-CFL path the next timestep is chosen from it, so the
    reduction happens whether or not anyone reads the value. Under a hand-fixed ``\\Delta t`` nothing
    consumes it and the pass is spent anyway — the schedule is fixed when the cache is built and does
    not vary with how the run is driven. [`kinetic_energy`](@ref) and [`dissipation`](@ref) have no cached form
    because no part of the iteration leaves one alive at its end; caching either would mean adding a
    reduction the run does not otherwise perform, which is the one thing the cache may not do.
"""
function max_speed end

# `maximum(norm, u)` and not `lpnorm(u, Inf)`, which returns the identical number. The choice is a
# measured trade, and it goes the way invariant 4 sets: `norm` on a fibre is StaticArrays'
# overflow-guarded implementation, which rescales by the largest component before squaring, and that
# guard costs ~2.9x the plain magnitude and ~1.7x `lpnorm` on this whole-grid reduction — but
# `lpnorm(u, Inf)` ALLOCATES (2 MiB at 16³ here, scaling with the grid) while this route allocates
# nothing. A per-step allocation in the hot loop is the thing the footprint invariant forbids
# outright, so the compute cost is the one to accept. Measured both ways rather than argued.
max_speed(u) = maximum(norm, u)


"""
    vorticity_physical!(ω, û, domain, spectral_scratch)

Compute the vorticity ``\\boldsymbol{\\omega} = \\nabla\\times\\boldsymbol{u}`` in physical
representation into `ω` — the field-valued observable the iteration deposits into its cache. The
curl is formed as ``\\mathrm{i}\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}`` in spectral
representation and transformed to physical.

The arguments are:
- `ω` — the vector field in physical representation receiving the vorticity.
- `û` — the velocity in spectral representation; only read, so unlike a pure representation
  recovery no preservation copy is needed.
- `domain` — the [`FixedDomain`](@ref) whose plans transform.
- `spectral_scratch` — a vector field in spectral representation the curl is formed in; consumed —
  its coefficients are undefined on return.

Returns `ω`.

The deposited value is read back with
[`vorticity_physical`](@ref GBGIsotropicTurbulence.Cache.vorticity_physical), which serves the
iteration's deposit or throws — measure with this function, read with that one.
"""
function vorticity_physical!(ω, û, domain::FixedDomain, spectral_scratch)
  curl!(spectral_scratch, û, domain.multipliers)
  to_physical!(ω, spectral_scratch, domain.velocity_plans)
  return ω
end


"""
    scalar_variance(φ)
    scalar_variance(φ̂)

The scalar variance ``\\langle\\varphi^{2}\\rangle`` of the scalar field `φ` (for a mean-zero
``\\varphi``). Computed as ``\\langle\\varphi,\\varphi\\rangle`` with the normalized inner product,
so by Parseval's theorem it accepts `φ` in either representation.
"""
scalar_variance(φ) = inner(φ, φ)


"""
    scalar_dissipation(φ̂, domain, diffusivity)

The mean scalar-variance dissipation rate
``\\varepsilon_\\varphi = 2\\varkappa \\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``.

The arguments are:
- `φ̂` — the scalar field in spectral representation.
- `domain` — the [`FixedDomain`](@ref) bundle.
- `diffusivity` — the scalar diffusivity ``\\varkappa = \\nu/\\mathrm{Sc}``.

The gradient energy ``\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle`` — the mean square of the
scalar's gradient, the Dirichlet or ``H^{1}`` energy in the Sobolev naming — equals
``\\langle\\hat\\varphi,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\hat\\varphi\\rangle``: a
``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``-weighted spectral inner product against the
`domain.squared_wavenumber_kernel` multiplier, formed straight from the spectral coefficients with
no physical gradient ``\\nabla\\varphi`` materialized.

It is the scalar twin of [`dissipation`](@ref)'s spectral route, and unconditional where that one
needs a divergence-free velocity. This spectral route is the only form: ``\\nabla\\varphi`` is never
recovered or cached, so there is no field-argument twin.
"""
scalar_dissipation(φ̂, domain::FixedDomain, diffusivity::Real) =
  (v = weighted_inner(φ̂, domain.squared_wavenumber_kernel); 2 * oftype(v, diffusivity) * v)


# The exact isotropy constant relating the coordinate-free strain skewness to the classical longitudinal
# one: ⟨(∂u₁/∂x₁)³⟩/⟨(∂u₁/∂x₁)²⟩^{3/2} = C·⟨tr S³⟩/⟨S:S⟩^{3/2}, from ⟨tr S³⟩ = (105/8)⟨(∂u₁/∂x₁)³⟩ and
# ⟨S:S⟩ = (15/2)⟨(∂u₁/∂x₁)²⟩ for isotropic incompressible turbulence (Betchov 1956; verified numerically).
const _SKEWNESS_ISOTROPY_CONSTANT = (4 / 7) * sqrt(15 / 2)              # ≈ 1.5649


"""
    derivative_skewness(û, domain)

The velocity-derivative skewness ``S``, written coordinate-free as the normalized third invariant of
the strain-rate tensor ``\\boldsymbol{S} = \\operatorname{sym}\\nabla\\boldsymbol{u}`` (the italic ``S``
is the scalar skewness, the bold ``\\boldsymbol{S}`` the strain-rate tensor):

```math
\\begin{aligned}
S &= C_S \\frac{\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}}
   = 3C_S \\frac{\\langle\\det\\boldsymbol{S}\\rangle}{\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle^{3/2}}, \\\\
C_S &= \\tfrac{4}{7}\\sqrt{15/2} \\approx 1.5649.
\\end{aligned}
```

Because ``\\boldsymbol{S}`` is symmetric and, for the incompressible field, traceless,
``\\operatorname{tr}\\boldsymbol{S}^{3} = 3\\det\\boldsymbol{S}``. By isotropy this equals the classical
longitudinal skewness ``\\langle(\\partial_{x_1} u_1)^{3}\\rangle / \\langle(\\partial_{x_1} u_1)^{2}\\rangle^{3/2}``;
the constant follows from ``\\langle\\operatorname{tr}\\boldsymbol{S}^{3}\\rangle = \\tfrac{105}{8}\\langle(\\partial_{x_1} u_1)^{3}\\rangle``
and ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle = \\tfrac{15}{2}\\langle(\\partial_{x_1} u_1)^{2}\\rangle``
(Betchov 1956,
[*An inequality concerning the production of vorticity in isotropic turbulence*](https://doi.org/10.1017/S0022112056000317),
*J. Fluid Mech.* **1**(5), 497–504). So the
reported value is the familiar ``S \\approx -0.5`` of developed turbulence, but from a genuine tensor
invariant rather than an axis-dependent gradient.

From the velocity field `û` in spectral representation, the strain is formed directly with
`symmetric_gradient` and the wavenumber `multipliers` of the [`FixedDomain`](@ref) bundle `domain`
(skipping the full nine-component velocity gradient), carried to physical space by its rank-2 tensor
transform plans, and reduced to ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle`` (`inner`) and
``\\langle\\det\\boldsymbol{S}\\rangle`` (the fused mapped mean over the pointwise determinant, which
materializes no determinant field); `domain` also sizes the per-call tensor scratch.

Because ``\\langle\\det\\boldsymbol{S}\\rangle`` is a **cubic** invariant, its grid mean carries a small
residual aliasing on a ``2/3``-truncated field — negligible for a well-resolved run, but, unlike the
quadratic reductions, not exactly alias-free. That pricing is the sharp-truncation one: the wider
[`PhaseShift`](@ref GBGIsotropicTurbulence.SimulationDomain.PhaseShift) ball carries the same kind of residual over its larger retained band, and [`HouLi`](@ref GBGIsotropicTurbulence.SimulationDomain.HouLi)'s
smooth taper leaves a residual of its own shape that no bound here prices — on every strategy,
treat the skewness as an indicator, not an alias-controlled measurement.

``S`` is the classic marker of *developed* turbulence: a random-phase (Gaussian) field has ``S \\approx 0``
(all odd invariants vanish), while fully developed isotropic turbulence has ``S \\approx -0.5`` (an
empirical, weakly Reynolds-number-dependent value) — the enstrophy-production / vortex-stretching signature. Its plateau is the "real turbulence yet"
gate of the warm-up detector.

!!! note "This is the run's largest transient allocation"
    The rank-2 strain tensor is allocated per call rather than kept resident — an occasional
    diagnostic should not hold field-scale storage for a whole run — but while it lives it is the
    biggest single memory episode a default configuration reaches, larger than the resident working
    set. The [`warmup!`](@ref GBGIsotropicTurbulence.SimulationRun.warmup!) driver calls this every sampling interval, so a run near its memory ceiling
    should size for the diagnostic rather than for the steady state.
"""
function derivative_skewness(û, domain::FixedDomain)
  strain = symmetric_gradient(û, domain.multipliers)                   # Ŝ = sym∇u (fused; skips the full ∇u)
  strain_physical = new_tensor_field_physical(domain)
  to_physical!(strain_physical, strain, domain.tensor_plans)            # S in physical space (Ŝ is consumed)
  ss = inner(strain_physical, strain_physical)                       # ⟨S:S⟩
  ss <= 0 && return zero(ss)      # degenerate strain: keep the field's element type, not a Float64 literal
  # ⟨det S⟩ as the fused mapped reduction: the determinant is formed per grid point in registers and
  # consumed by the mean immediately, so no determinant field is materialized.
  mean_det = mean(det, strain_physical)
  # `oftype` keeps a Float32 run measuring in Float32: a bare Float64 constant would promote it.
  return 3 * oftype(mean_det, _SKEWNESS_ISOTROPY_CONSTANT) * mean_det / ss^oftype(ss, 1.5)  # C · 3⟨det S⟩/⟨S:S⟩^{3/2}
end


"""
    energy_spectrum(û, domain)

The measured kinetic-energy **spectral density** ``E(\\kappa)`` of the velocity field `û` (in
spectral representation): ``E(\\kappa)\\,\\mathrm{d}\\kappa`` is the turbulent kinetic energy
carried by wavenumber magnitudes in ``[\\kappa, \\kappa + \\mathrm{d}\\kappa]``, so
``k = \\int_0^\\infty E(\\kappa)\\,\\mathrm{d}\\kappa`` — the object the reference laws are stated
about, directly comparable to a
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model spectrum with no conversion. The
`domain` (a [`FixedDomain`](@ref)) supplies the wavenumber multipliers and the shell width.

Returns a named tuple `(; wavenumbers, energy)`: the shell-center wavenumber magnitudes ``\\kappa``
and the density estimate at each (positional destructuring `κ, E = energy_spectrum(û, domain)` also
works). Both come back as host `Vector`s whatever backend `û` lives on — the ``O(N)`` shell accumulators
return with the reduction, so a caller needs no transfer of its own.

Each value is the shell's energy — half the `GBGPeriodicFields` radial spectrum, which sums
``\\lvert\\hat{\\boldsymbol{u}}\\rvert^2`` — divided by the shell width
``\\Delta\\kappa = 2\\pi/L``, making Parseval the quadrature
``k = \\sum_n E(\\kappa_n) \\Delta\\kappa`` (exact by construction). At low ``\\kappa`` the
integer shells hold few lattice modes, so the density estimate is correspondingly lumpy there.
"""
function energy_spectrum(û, domain::FixedDomain)
  shells, spec = radial_spectrum(û, domain.multipliers)
  # The DENSITY, not the bin sum: each shell's energy over the shell width Δκ = 2π/L, so the return
  # is the object the theory states laws about (E(κ) = C_K ε^{2/3} κ^{-5/3} is a density) and is
  # directly comparable to a Phenomenology model. On the default 2π box Δκ = 1 and the two
  # conventions coincide numerically — which is exactly how the bin-sum convention survived as long
  # as it did (owner-directed cutover, 2026-08-23).
  # In the spectrum's own element type: a bare `2π` is a Float64 and would promote a Float32 run —
  # the same leak class the element-type invariant test exists to catch (and did).
  T = eltype(spec)
  Δκ = T(2π) / domain.grid.domain_size[1]
  return (; wavenumbers = shells, energy = spec ./ (2 * Δκ))
end


"""
    integral_scale(û, domain)

The longitudinal integral length scale of the velocity field `û`, measured from its
spectral density (from [`energy_spectrum`](@ref)),

```math
L_{11} = \\frac{3\\pi}{4} \\frac{\\int_0^\\infty E(\\kappa)/\\kappa\\,\\mathrm{d}\\kappa}{\\int_0^\\infty E(\\kappa)\\,\\mathrm{d}\\kappa}.
```

``L_{11}`` is the large-eddy scale — the one flow parameter a
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model spectrum needs that the small
scales do not fix. The `domain` (a [`FixedDomain`](@ref)) supplies the wavenumber multipliers.

The integrals above are the idealized continuous definition, written with the spectral density
``E(\\kappa)`` that `energy_spectrum` measures; they are evaluated as quadrature sums over
the shells, the common shell width canceling in the ratio.

The cancellation is exact; what is approximate is the *shell* itself: ``E_n`` is the exact sum over
a shell's lattice modes, and identifying it with ``E(\\kappa_n)\\Delta\\kappa`` is a midpoint
quadrature whose error is largest at the low shells, where the mode count departs most from the
continuum ``4\\pi\\kappa^2``. Those are also the shells this ratio weights most, so read ``L_{11}``
as resolution-limited at coarse grids.

For reference, two related scales follow from the same spectrum. The **transverse** integral scale
is ``L_{22} = L_{11}/2`` (the incompressible-isotropic relation). The scale defined from the **full
trace** velocity correlation
``R_{ii}(r) = \\langle\\boldsymbol{u}(\\boldsymbol{x})\\cdot\\boldsymbol{u}(\\boldsymbol{x}+r\\boldsymbol{e})\\rangle``
(``\\boldsymbol{e}`` a unit vector) — with no directional projection — is

```math
\\begin{aligned}
L_E &= \\frac{\\pi}{2} \\frac{\\int_0^\\infty E(\\kappa)/\\kappa\\,\\mathrm{d}\\kappa}{\\int_0^\\infty E(\\kappa)\\,\\mathrm{d}\\kappa} \\\\
    &= \\tfrac{2}{3}L_{11} = \\tfrac{1}{3}(L_{11} + 2L_{22}),
\\end{aligned}
```

the isotropic average of the one longitudinal and two transverse contributions.
"""
function integral_scale(û, domain::FixedDomain)
  κ, E = energy_spectrum(û, domain)
  # Both sums run where the spectrum lives — no host transfer and no scalar indexing, so the
  # diagnostic works unchanged on a device backend. The κ = 0 shell is excluded from the numerator
  # by the branch rather than by skipping an index, which a fused broadcast cannot do.
  # Excluding the κ = 0 shell, as the numerator does. Testing `sum(E)` instead let a field whose
  # energy is entirely in the mean flow pass the emptiness guard and return a meaningless zero.
  total = sum(broadcast((k, e) -> k > 0 ? e : zero(e), κ, E))
  weighted = sum(broadcast((k, e) -> k > 0 ? e / k : zero(e), κ, E))
  # A field with no energy has no integral scale, and 0/0 would hand back a silent NaN that then
  # propagates into every derived quantity — a Reynolds number, a turnover time — with nothing to
  # say where it came from. The seeders already refuse to produce such a field; a hand-built one can
  # still reach here.
  total > 0 ||
    throw(ArgumentError("this velocity field carries no energy, so it has no integral scale"))
  return oftype(weighted, 3 * π / 4) * weighted / total
end


end # module Observables

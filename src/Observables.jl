# Observables — the functions of the flow state that are measured: kinetic energy, dissipation, the
# velocity-derivative skewness, the scalar variance and its dissipation, and the maximum component
# speed (which feeds the CFL). In the Mori–Zwanzig reading (ARCHITECTURE §8) these are the observables
# of the `Generator`: their plateaus gate warm-up and their statistics are to be tracked by
# GBGStreamingStatistics. Each reduces a field to a scalar — a GBGPeriodicFields inner product or moment.

"""
    Observables

The measured functions of the flow state:
- [`kinetic_energy`](@ref), [`scalar_variance`](@ref) — the turbulent kinetic energy and the scalar
  variance.
- [`dissipation`](@ref), [`scalar_dissipation`](@ref) — their dissipation rates.
- [`derivative_skewness`](@ref) — the velocity-derivative skewness, the classical marker of a
  developed cascade.
- [`max_speed`](@ref) — the maximum velocity component, which sets the advective-CFL step (one
  generic shared with `Cache`: the field reduction is homed here, the cached read there).
- [`energy_spectrum`](@ref), [`integral_scale`](@ref) — the measured energy spectrum and the integral
  length scale derived from it.

Their plateaus gate warm-up (`warmup!`). Each reduces a field to a scalar (the energy spectrum, to a
distribution over wavenumber); none dealiases first — the quadratic reductions are exactly
alias-free under a truncating dealiasing band (see `kinetic_energy` for the condition; `HouLi` meets
it only to machine precision), and the cubic skewness carries the slight residual its own docstring
prices.
"""
module Observables

using GBGPeriodicFields
using Statistics: mean                    # the mapped mean — PF extends it, Statistics owns the name
using ..SimulationDomain: FixedDomain, new_tensor_field_physical
import ..Cache: max_speed                 # one generic: the reduction here, the cached read in Cache

export kinetic_energy, dissipation, max_speed,
       scalar_variance, scalar_dissipation, derivative_skewness,
       energy_spectrum, integral_scale


"""
    kinetic_energy(u)

The turbulent kinetic energy ``\\tfrac{1}{2}\\langle\\lvert\\boldsymbol{u}\\rvert^{2}\\rangle`` of the
velocity field `u`. Computed as ``\\tfrac{1}{2} \\langle\\boldsymbol{u},\\boldsymbol{u}\\rangle`` with
the normalized inner product, so by Parseval's theorem it accepts `u` in either
representation. Like every quadratic reduction here (`dissipation`, `scalar_variance`,
`scalar_dissipation`), it needs no dealiasing of its own: the sum over spectral coefficients is
exact, and the equivalent physical-space mean picks up no aliasing either, because a quadratic's
zero mode folds in nothing when ``2\\kappa_{\\max} < N`` in units of the fundamental ``2\\pi/L`` —
satisfied by the ``2/3`` rule, by `PhaseShift`'s wider ``\\sqrt{2}N/3`` band, and by every narrower
band. `HouLi` keeps the full band ``\\kappa_{\\max} = N/2``, where the only pairs that fold to zero
are Nyquist modes its taper has already damped to machine precision — alias-free in practice, not
exactly.
"""
kinetic_energy(u) = 0.5 * inner(u, u)


"""
    dissipation(ω, viscosity)
    dissipation(û, domain, viscosity)

The mean kinetic-energy dissipation rate of a homogeneous flow — a single number, not a field — at
the kinematic `viscosity` ``\\nu``:

```math
\\varepsilon = \\nu \\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle
            = 2\\nu\\langle S_{ij}S_{ij}\\rangle,
```

the two forms equal for a homogeneous flow, with the strain-rate tensor
``S_{ij} = \\tfrac{1}{2}(\\partial_{x_j}u_i + \\partial_{x_i}u_j)``.

Two routes to the same rate; take the one whose input is already in hand.

  * `dissipation(ω, viscosity)` — from a vorticity field `ω` ``\\boldsymbol{\\omega}`` in either
    representation, as the normalized inner product (Parseval). Use it when
    ``\\boldsymbol{\\omega}`` exists for its own sake: the cached vorticity, or a vorticity
    the caller supplies.
  * `dissipation(û, domain, viscosity)` — straight from the velocity in spectral representation `û`
    ``\\hat{\\boldsymbol{u}}``, with the [`FixedDomain`](@ref) `domain` supplying the multiplier, and
    no vorticity formed at all. Use it to measure off the state, where a
    ``\\boldsymbol{\\omega}`` would be built only to be reduced away.

The second route trades the curl for a ``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``-weighted spectral
inner product against the `domain.squared_wavenumber_kernel` multiplier: from

```math
\\lvert\\boldsymbol{\\kappa}\\times\\hat{\\boldsymbol{u}}\\rvert^{2}
  = \\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\lvert\\hat{\\boldsymbol{u}}\\rvert^{2}
  - \\lvert\\boldsymbol{\\kappa}\\cdot\\hat{\\boldsymbol{u}}\\rvert^{2},
```

the enstrophy of a divergence-free velocity is its Dirichlet (``H^{1}``) energy,
``\\langle\\lvert\\boldsymbol{\\omega}\\rvert^{2}\\rangle = \\langle\\hat{\\boldsymbol{u}},\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\hat{\\boldsymbol{u}}\\rangle``.

!!! warning
    The `û` route drops the ``\\lvert\\boldsymbol{\\kappa}\\cdot\\hat{\\boldsymbol{u}}\\rvert^{2}``
    term, so it holds only for a divergence-free velocity — exact for a state advanced by the
    Leray-projected dynamics, wrong for an arbitrary vector field. The vorticity route carries no
    such condition. (The scalar twin, [`scalar_dissipation`](@ref), is unconditional: a scalar has
    no solenoidal constraint to invoke.)
"""
function dissipation end

dissipation(ω, viscosity::Real) = viscosity * inner(ω, ω)

dissipation(û, domain::FixedDomain, viscosity::Real) =
  viscosity * weighted_inner(û, domain.squared_wavenumber_kernel)


"""
    max_speed(u)
    max_speed(cache)
    max_speed(sim)

The largest velocity component in absolute value, ``\\max_i\\lvert u_i\\rvert``, of the velocity field `u`
in physical representation — an allocation-free reduction used to set the advective-CFL timestep. It
is within a factor ``\\sqrt{3}`` of the true ``\\sup\\lvert\\boldsymbol{u}\\rvert``, a gap absorbed by the
conservative [`recommended_cfl`](@ref GBGIsotropicTurbulence.Propagator.recommended_cfl) ceiling (whose
eigenvalue bound over-estimates the true spectral radius).

The second form reads the number back from an
[`ObservablesCache`](@ref GBGIsotropicTurbulence.Cache.ObservablesCache), where the iteration's tail
deposited it — the same quantity, measured once per iteration and served without a reduction (or a
device readback); it throws when no deposit is current, like every cached read. The third form
reads a `Simulation`'s cache.
"""
max_speed(u) = maximum(abs, field_data(u))


"""
    scalar_variance(φ)

The scalar variance ``\\langle\\varphi^{2}\\rangle`` of the scalar field `φ` (for a mean-zero
``\\varphi``). Computed as ``\\langle\\varphi,\\varphi\\rangle`` with the normalized inner product,
so by Parseval's theorem it accepts `φ` in either representation.
"""
scalar_variance(φ) = inner(φ, φ)


"""
    scalar_dissipation(φ̂, domain, diffusivity)

The mean scalar-variance dissipation rate
``\\varepsilon_\\varphi = 2\\varkappa \\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle``, from the scalar field
in spectral representation `φ̂` ``\\hat\\varphi``, the [`FixedDomain`](@ref) bundle `domain`, and the
scalar `diffusivity` ``\\varkappa = \\nu/\\mathrm{Sc}``.
The gradient energy ``\\langle\\lvert\\nabla\\varphi\\rvert^{2}\\rangle`` is the Dirichlet (``H^{1}``) energy
``\\langle\\varphi,\\lvert\\boldsymbol{\\kappa}\\rvert^{2}\\varphi\\rangle`` — a
``\\lvert\\boldsymbol{\\kappa}\\rvert^{2}``-weighted spectral inner product against the
`domain.squared_wavenumber_kernel` multiplier, formed straight from the spectral coefficients with no
physical gradient ``\\nabla\\varphi`` materialized. It is the scalar twin of
[`dissipation`](@ref)'s spectral route, and unconditional where that one needs a divergence-free
velocity.
"""
scalar_dissipation(φ̂, domain::FixedDomain, diffusivity::Real) =
  2 * diffusivity * weighted_inner(φ̂, domain.squared_wavenumber_kernel)


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
and ``\\langle\\boldsymbol{S}:\\boldsymbol{S}\\rangle = \\tfrac{15}{2}\\langle(\\partial_{x_1} u_1)^{2}\\rangle`` (Betchov 1956). So the
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
quadratic reductions, not exactly alias-free.
``S`` is the classic marker of *developed* turbulence: a random-phase (Gaussian) field has ``S \\approx 0``
(all odd invariants vanish), while fully developed isotropic turbulence has ``S \\approx -0.5`` (an
empirical, weakly Reynolds-number-dependent value) — the enstrophy-production / vortex-stretching signature. Its plateau is the strict "real turbulence yet"
gate of the warm-up detector.
"""
function derivative_skewness(û, domain::FixedDomain)
  strain = symmetric_gradient(û, domain.multipliers)                   # Ŝ = sym∇u (fused; skips the full ∇u)
  strain_physical = new_tensor_field_physical(domain)
  to_physical!(strain_physical, strain, domain.tensor_plans)            # S in physical space (Ŝ is consumed)
  ss = inner(strain_physical, strain_physical)                       # ⟨S:S⟩
  ss <= 0 && return 0.0
  # ⟨det S⟩ as the fused mapped reduction: the determinant is formed per grid point in registers and
  # consumed by the mean immediately, so no determinant field is materialized.
  mean_det = mean(det, strain_physical)
  return 3 * _SKEWNESS_ISOTROPY_CONSTANT * mean_det / ss^1.5         # C · 3⟨det S⟩/⟨S:S⟩^{3/2}
end


"""
    energy_spectrum(û, domain)

The measured kinetic-energy spectrum ``E(\\kappa)`` of the velocity field `û` (in spectral
representation) — the turbulent kinetic energy resolved over wavenumber-magnitude shells,
``k = \\sum_\\kappa E(\\kappa)``. Returns `(κ, E)`: the shell-center wavenumber magnitudes and the energy
in each shell (brought to the host, an occasional diagnostic). It is the `GBGPeriodicFields` radial
spectrum of `û` halved — the field reduction sums ``\\lvert\\hat{\\boldsymbol{u}}\\rvert^2`` while the
kinetic energy carries the ``\\tfrac{1}{2}``. The `domain` (a [`FixedDomain`](@ref)) supplies the wavenumber
multipliers. This is the measured counterpart of a [`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model
spectrum, for validation.
"""
function energy_spectrum(û, domain::FixedDomain)
  shells, spec = radial_spectrum(û, domain.multipliers)
  return Array(shells), Array(0.5 .* spec)
end


"""
    integral_scale(û, domain)

The longitudinal integral length scale of the velocity field `û`, measured from its
[`energy_spectrum`](@ref) ``E(\\kappa)``,

```math
L_{11} = \\frac{3\\pi}{4} \\frac{\\int_0^\\infty E(\\kappa)/\\kappa\\,\\mathrm d\\kappa}{\\int_0^\\infty E(\\kappa)\\,\\mathrm d\\kappa}.
```

``L_{11}`` is the large-eddy scale — the one flow parameter a
[`Phenomenology`](@ref GBGIsotropicTurbulence.Phenomenology) model spectrum needs that the
small scales do not fix. The integrals above are the idealized continuous definition; they are evaluated
as sums over the measured `energy_spectrum` shells (whose per-shell energy makes the shell width
cancel in the ratio). The `domain` (a [`FixedDomain`](@ref)) supplies the wavenumber multipliers.

For reference, two related scales follow from the same spectrum. The **transverse** integral scale is
``L_{22} = L_{11}/2`` (the incompressible-isotropic relation). The scale defined from the **full trace**
velocity correlation ``R_{ii}(r) = \\langle\\boldsymbol{u}(\\boldsymbol{x})\\cdot\\boldsymbol{u}(\\boldsymbol{x}+r\\boldsymbol{e})\\rangle`` (``\\boldsymbol{e}`` a unit vector) — with no directional projection — is

```math
\\begin{aligned}
L_E &= \\frac{\\pi}{2} \\frac{\\int_0^\\infty E(\\kappa)/\\kappa\\,\\mathrm d\\kappa}{\\int_0^\\infty E(\\kappa)\\,\\mathrm d\\kappa} \\\\
    &= \\tfrac{2}{3}L_{11} = \\tfrac{1}{3}(L_{11} + 2L_{22}),
\\end{aligned}
```

the isotropic average of the one longitudinal and two transverse contributions.
"""
function integral_scale(û, domain::FixedDomain)
  κ, E = energy_spectrum(û, domain)
  weighted = zero(eltype(E))
  total = zero(eltype(E))
  for i in eachindex(κ, E)
    total += E[i]
    κ[i] > 0 && (weighted += E[i] / κ[i])
  end
  return (3 * π / 4) * weighted / total
end


end # module Observables

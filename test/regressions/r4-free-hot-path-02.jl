# Witness (r4, lane free-hot-path, 02) — the two frozen audit instruments must MODEL what the
# forcing hooks actually do.
#
# Commit f557311 made the empty-band guard RELATIVE (`_band_is_empty(band_value, total_value)`),
# adding an unconditional whole-field `inner(field, field)` to `project_forcing!(::VarianceRescaling, …)`
# (src/Forcing.jl:322) and to `set_forcing_rate!(::ConstantPower, …)` (src/Forcing.jl:441). Neither
# test/optimality_audit.jl's `_syncs` nor test/compute_audit.jl's `_forcing_pass_delta` was updated,
# so both instruments report FEWER host readbacks and FEWER field-scale passes than the code
# performs — and both pass green, because each is a hand-written model of src/Forcing.jl rather than
# a measurement of it.
#
# This test measures the real hooks with a counting proxy (the `field` argument is untyped, so the
# proxy dispatches) and holds the audit models against the measurement. It fails on the tree as of
# f557311 and passes once the models are re-derived (or the guard's reduction is fused away).
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields
using Random
const PF = GBGPeriodicFields
const F = GBGHomogeneousTurbulence.Forcing

# The audit models under test (each include runs its own testsets once, which pass).
#
# The package root is recomputed INSIDE each module, self-contained. It cannot be a shared top-level
# constant: these includes live in nested `module` blocks, which do not see the file's top-level
# bindings. It cannot be `pkgdir(GBGHomogeneousTurbulence)` for the same reason. And it cannot count
# `..` hops, because this witness is authored under .claude/bug-hunt/witnesses/ and promoted into
# test/regressions/, at different depths. `@__DIR__` is valid in any scope, and the marker is the
# source file itself — `Project.toml` would stop a level early, since `test/` carries one.
module OptModel
  const ROOT = let d = @__DIR__
    while !isfile(joinpath(d, "src", "GBGHomogeneousTurbulence.jl")); d = dirname(d) end
    d
  end
  include(joinpath(ROOT, "test", "optimality_audit.jl"))
end

module PassModel
  const ROOT = let d = @__DIR__
    while !isfile(joinpath(d, "src", "GBGHomogeneousTurbulence.jl")); d = dirname(d) end
    d
  end
  include(joinpath(ROOT, "test", "compute_audit.jl"))
end

# ---------------------------------------------------------------- the measurement
mutable struct CF{T}
  f::T
  inner::Int
  weighted_inner::Int
  convolve::Int
end
CF(f) = CF(f, 0, 0, 0)

PF.field_tensor_order(c::CF) = PF.field_tensor_order(c.f)
# Forwarded, not counted: an element-type query is not a reduction and crosses no device boundary.
# The source hook asks for it, so the double must answer — it is part of the field protocol.
PF.field_scalar_type(c::CF) = PF.field_scalar_type(c.f)
PF.inner(a::CF, b::CF) = (a.inner += 1; PF.inner(a.f, b.f))
PF.weighted_inner(a::CF, k) = (a.weighted_inner += 1; PF.weighted_inner(a.f, k))
PF.convolve!(o::CF, a::CF, k, α, β) = (o.convolve += 1; PF.convolve!(o.f, a.f, k, α, β); o)

const DOMAIN = FixedDomain(grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_type = Array)

function measure(forcing, kind)
  û = new_vector_field_spectral(DOMAIN)
  random_solenoidal_velocity_spectral!(û, DOMAIN; kinetic_energy = 0.5,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(11))
  field = CF(û)
  # BOTH sides are counted and BOTH are returned. The source hook accumulates into a DIFFERENT field
  # from the one it reduces, so `convolve!`'s counter lands on the output double — and a witness that
  # returned only the input double would report zero convolutions and pass whatever the code did.
  # That is exactly how this test went vacuous when the state-dependent forcings moved to the source
  # hook (2026-08-22): the term it was written to measure quietly stopped being measured.
  out = CF(new_vector_field_spectral(DOMAIN))
  if kind === :apply
    F.project_forcing!(forcing, field, DOMAIN)
  elseif kind === :source
    F.add_forcing_source!(forcing, nothing, out, field, DOMAIN, 0.05)
  else
    F.set_forcing_rate!(forcing, new_scalar_field_spectral(DOMAIN), field, DOMAIN)
  end
  return (; field, out)
end

const BAND       = measure(VarianceRescaling(DOMAIN; target = 1.0, over = :band),  :apply)
const TOTAL      = measure(VarianceRescaling(DOMAIN; target = 1.0, over = :total), :apply)
const POWER      = measure(ConstantPower(DOMAIN; injection_rate = 1.0),            :source)
const CONTROLLER = measure(VarianceController(DOMAIN; target = 1.0),               :source)
const LINEAR     = measure(F.Linear(DOMAIN; rate = 0.5),                           :rate)

# every reduction below returns a Julia scalar ⇒ one blocking device→host readback on a GPU
readbacks(m) = m.field.inner + m.field.weighted_inner
# A reduction reads the field once. A rescale's `convolve!` is in place: read + write = 2. The
# source hook's `convolve!` accumulates ACROSS two fields: N̂ read, field read, N̂ write = 3, which is
# how test/audit_ops.jl prices `Op("add OU source", [out, ou_state], [out])`.
rescale_passes(m) = readbacks(m) + 2 * m.field.convolve
source_passes(m)  = readbacks(m) + 3 * m.out.convolve

# how many `Sync` entries the optimality audit's model attributes to one velocity forcing
model_syncs(tag; stages = 1) = count(s -> occursin("(velocity)", s.site),
                                     OptModel._syncs(; adaptive_dt = false, velocity_forcing = tag,
                                                     stages))
# how many spectral-vector passes the compute audit's model attributes to one velocity forcing
model_vector_passes(tag) = PassModel._forcing_pass_delta(tag, :velocity, :RK3).spectral_vector
# The source-routed models are quoted per STEP; `measure` exercises one stage.
const EVALS_RK3 = 3


@testset "the frozen audit models count every reduction the forcing hooks perform" begin
  @testset "the measurement is not vacuous" begin
    # The guard on the guard: if a hook stops convolving where this test expects it to, the pass
    # comparisons below still balance at zero and certify nothing. Assert the traffic exists first.
    @test BAND.field.convolve > 0
    @test POWER.out.convolve > 0
    @test CONTROLLER.out.convolve > 0
    # Since the multi-weight fusion (PF decision 72, wired 2026-08-23) the controller answers its
    # three observables — k, k_f, and the dissipation — in ONE fused readback, the same crossing
    # count as `power`'s single band observable: the distinction moved into the weights. The guard
    # that this hook still reduces at all is the equality itself against the non-zero count.
    @test readbacks(CONTROLLER) == 1 && readbacks(POWER) == 1
  end
  @testset "synchronization ledger (test/optimality_audit.jl `_syncs`)" begin
    @test model_syncs(:band)       == readbacks(BAND)
    @test model_syncs(:band_total) == readbacks(TOTAL)
    # ONE stage's worth, which is what `measure` exercises; the model multiplies by the stage count.
    @test model_syncs(:power;      stages = 1) == readbacks(POWER)
    @test model_syncs(:controller; stages = 1) == readbacks(CONTROLLER)
  end
  @testset "pass ledger (test/compute_audit.jl `_forcing_pass_delta`)" begin
    @test model_vector_passes(:band) == rescale_passes(BAND)
    @test model_vector_passes(:power)      == EVALS_RK3 * source_passes(POWER)
    @test model_vector_passes(:controller) == EVALS_RK3 * source_passes(CONTROLLER)
  end
  # D1 residue (audit-changes round 2): the tag-modelled guard in compute_audit is satisfiable by
  # any wrong number — it proves a tag is PRICED, not that its price is right. The measurement above
  # is what proves the price; `:linear` was the one hook tag still modelled-but-unmeasured. Its hook
  # arms a rate array and reduces NOTHING — zero crossings, zero field passes — and both models must
  # say so (the armed exponential's per-application read is priced inside the step, not the hook,
  # and is cross-checked by the op-list tests in compute_audit).
  @testset "the :linear tag is measured, not merely modelled" begin
    @test readbacks(LINEAR) == 0
    @test LINEAR.field.convolve == 0 && LINEAR.out.convolve == 0
    @test model_syncs(:linear) == 0
    @test model_vector_passes(:linear) == 0
  end
end

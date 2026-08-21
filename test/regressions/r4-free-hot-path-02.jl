# Witness (r4, lane free-hot-path, 02) — the two frozen audit instruments must MODEL what the
# forcing hooks actually do.
#
# Commit f557311 made the empty-band guard RELATIVE (`_band_is_empty(band_value, total_value)`),
# adding an unconditional whole-field `inner(field, field)` to `apply_forcing!(::BandRescaling, …)`
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
using GBGIsotropicTurbulence
using GBGPeriodicFields
using Random
const PF = GBGPeriodicFields
const F = GBGIsotropicTurbulence.Forcing

# The audit models under test (each include runs its own testsets once, which pass).
#
# The package root is recomputed INSIDE each module, self-contained. It cannot be a shared top-level
# constant: these includes live in nested `module` blocks, which do not see the file's top-level
# bindings. It cannot be `pkgdir(GBGIsotropicTurbulence)` for the same reason. And it cannot count
# `..` hops, because this witness is authored under .claude/bug-hunt/witnesses/ and promoted into
# test/regressions/, at different depths. `@__DIR__` is valid in any scope, and the marker is the
# source file itself — `Project.toml` would stop a level early, since `test/` carries one.
module OptModel
  const ROOT = let d = @__DIR__
    while !isfile(joinpath(d, "src", "GBGIsotropicTurbulence.jl")); d = dirname(d) end
    d
  end
  include(joinpath(ROOT, "test", "optimality_audit.jl"))
end

module PassModel
  const ROOT = let d = @__DIR__
    while !isfile(joinpath(d, "src", "GBGIsotropicTurbulence.jl")); d = dirname(d) end
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
PF.inner(a::CF, b::CF) = (a.inner += 1; PF.inner(a.f, b.f))
PF.weighted_inner(a::CF, k) = (a.weighted_inner += 1; PF.weighted_inner(a.f, k))
PF.convolve!(o::CF, a::CF, k, α, β) = (o.convolve += 1; PF.convolve!(o.f, a.f, k, α, β); o)

const DOMAIN = FixedDomain(grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(),
                           element_type = Float64, array_type = Array)

function measure(forcing, kind)
  û = new_vector_field_spectral(DOMAIN)
  random_solenoidal_velocity_spectral!(û, DOMAIN; kinetic_energy = 0.5,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(11))
  c = CF(û)
  if kind === :apply
    F.apply_forcing!(forcing, c, DOMAIN)
  else
    F.set_forcing_rate!(forcing, new_scalar_field_spectral(DOMAIN), c, DOMAIN)
  end
  return c
end

const BAND  = measure(BandRescaling(DOMAIN; target = 1.0, over = :band),  :apply)
const TOTAL = measure(BandRescaling(DOMAIN; target = 1.0, over = :total), :apply)
const POWER = measure(ConstantPower(DOMAIN; injection_rate = 1.0),        :rate)

# every reduction below returns a Julia scalar ⇒ one blocking device→host readback on a GPU
readbacks(c) = c.inner + c.weighted_inner
# a reduction reads the field once; the in-band rescale `convolve!` reads and writes it
vector_passes(c) = c.inner + c.weighted_inner + 2 * c.convolve

# how many `Sync` entries the optimality audit's model attributes to one velocity forcing
model_syncs(tag) = count(s -> occursin("(velocity)", s.site),
                         OptModel._syncs(; adaptive_dt = false, velocity_forcing = tag))
# how many spectral-vector passes the compute audit's model attributes to one velocity forcing
model_vector_passes(tag) = PassModel._forcing_pass_delta(tag, :velocity, :RK3).spectral_vector


@testset "the frozen audit models count every reduction the forcing hooks perform" begin
  @testset "synchronization ledger (test/optimality_audit.jl `_syncs`)" begin
    @test model_syncs(:band)       == readbacks(BAND)
    @test model_syncs(:band_total) == readbacks(TOTAL)
    @test model_syncs(:power)      == readbacks(POWER)
  end
  @testset "pass ledger (test/compute_audit.jl `_forcing_pass_delta`)" begin
    @test model_vector_passes(:band)  == vector_passes(BAND)
    @test model_vector_passes(:power) == vector_passes(POWER)
  end
end

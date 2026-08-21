# Witness r4-free-hot-path-03 — `apply_forcing!(::BandRescaling, …; over = :total)` must reduce the
# whole field ONCE per step, not twice.
#
# `Forcing.jl` (as of this witness) reads:
#
#   321   band_value = factor * weighted_inner(field, forcing.band)
#   322   _band_is_empty(band_value, factor * inner(field, field)) && return field
#   323   target_band = if forcing.over === :total
#   325     total_value = factor * inner(field, field)
#
# Julia evaluates arguments eagerly, so line 322's `inner(field, field)` runs unconditionally and
# line 325 recomputes the byte-identical value — nothing writes `field` between them. Each call is a
# full N³ reduction over the whole vector field and, on the GPU-primary target, a blocking
# device-to-host readback; `:total` is what the `Simulation` front door passes, so this sits in the
# default hot loop. The `BandRescaling` docstring itself states the intended cost: "two host
# readbacks per step … two under `over = :total`, which measures the band and the whole field" —
# i.e. ONE band reduction plus ONE whole-field reduction, not two whole-field reductions.
#
# The whole-field observable is counted by handing `apply_forcing!` (whose `field` argument is
# untyped) a wrapper that forwards every field operation to the real field and tallies `inner`.

using Test
using Random
using GBGIsotropicTurbulence
using GBGPeriodicFields

const SD = GBGIsotropicTurbulence.SimulationDomain
const F  = GBGIsotropicTurbulence.Forcing

# ---- counting wrapper: forwards to the wrapped field, tallies whole-field `inner` calls ----------
const NINNER = Ref(0)
const NWEIGHTED = Ref(0)

struct CountingField{FLD}
  field::FLD
end

GBGPeriodicFields.field_tensor_order(c::CountingField) = GBGPeriodicFields.field_tensor_order(c.field)

function GBGPeriodicFields.inner(a::CountingField, b::CountingField)
  NINNER[] += 1
  return GBGPeriodicFields.inner(a.field, b.field)
end

function GBGPeriodicFields.weighted_inner(a::CountingField, w)
  NWEIGHTED[] += 1
  return GBGPeriodicFields.weighted_inner(a.field, w)
end

function GBGPeriodicFields.convolve!(destination::CountingField, field::CountingField, kernel, α, β)
  GBGPeriodicFields.convolve!(destination.field, field.field, kernel, α, β)
  return destination
end

function forced_velocity(domain, rng)
  û = SD.new_vector_field_spectral(domain)
  d = field_data(û)
  d .= complex.(randn(rng, Float64, size(d)), randn(rng, Float64, size(d)))
  return û
end

@testset "BandRescaling(over = :total) reduces the whole field once per forced step" begin
  domain = SD.FixedDomain(; grid_points_per_axis = 16, side_length = 2π,
                            dealiasing = SD.TwoThirds(),
                            element_type = Float64, array_type = Array)
  rng = MersenneTwister(20260821)

  # --- control: `over = :band` needs the whole-field value NOT AT ALL ---------------------------
  # UPDATED 2026-08-21. This control asserted one whole-field reduction on the `:band` branch,
  # because the empty-band guard then normalized by the total to stay scale-free. The fix for this
  # very finding removed that: emptiness is decided by POSITIVITY, which carries no absolute scale
  # and needs no second reduction (φ → sφ scales the band value by s² and cannot change its sign).
  # So `:band` now reduces the whole field zero times, which is stronger than the control claimed.
  û_band = forced_velocity(domain, rng)
  band_forcing = F.BandRescaling(domain; target = 1.0, over = :band)
  NINNER[] = 0; NWEIGHTED[] = 0
  F.apply_forcing!(band_forcing, CountingField(û_band), domain)
  @test NWEIGHTED[] == 1                      # the band observable
  @test NINNER[] == 0                         # and no whole-field reduction at all

  # --- the claim: `over = :total` needs the SAME whole-field value, so still exactly one ---------
  û_total = forced_velocity(domain, rng)
  total_forcing = F.BandRescaling(domain; target = 1.0, over = :total)
  NINNER[] = 0; NWEIGHTED[] = 0
  F.apply_forcing!(total_forcing, CountingField(û_total), domain)
  @test NWEIGHTED[] == 1                      # the band observable
  @test NINNER[] == 1                         # the whole-field observable, once — not twice

  # --- and the duplicate is provably redundant: the two calls cannot disagree, because nothing
  #     writes the field between them. Re-reducing an untouched field returns the identical value.
  û_check = forced_velocity(domain, rng)
  first_value = inner(û_check, û_check)
  second_value = inner(û_check, û_check)
  @test first_value === second_value
end

# Witness: BandRescaling(:total) computes the whole-field observable `inner(field, field)` TWICE per
# `apply_forcing!` call — once as the eager second argument of `_band_is_empty` (src/Forcing.jl:322)
# and again at line 325 — with no mutation of `field` in between. Each is a field-scale quadratic
# reduction whose scalar result crosses to the host (a blocking device-to-host transfer on a GPU),
# in the hot loop of the DEFAULT run configuration.
#
# The correct behaviour asserted here: ONE whole-field reduction per call — which is also exactly
# what `test/optimality_audit.jl`'s frozen SYNC_LEDGER prices for the default row
# ("default (adaptive dt, BandRescaling :total)", achieved = 3 = 1 max-speed + band + total).

using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, TwoThirds, new_scalar_field_spectral
using GBGIsotropicTurbulence.Forcing: BandRescaling, ConstantPower, apply_forcing!, set_forcing_rate!
using GBGIsotropicTurbulence.State: random_solenoidal_velocity_spectral!
using GBGPeriodicFields
using Random

# A counting wrapper around a field. Not type piracy: `CountingField` is this file's own type, and
# every method below dispatches on it. It forwards to the wrapped field and tallies the field-scale
# reductions whose scalar result crosses to the host.
const COUNTS = Dict(:inner => 0, :weighted_inner => 0, :convolve => 0)

struct CountingField{F}
  f::F
end

GBGPeriodicFields.field_tensor_order(c::CountingField) = GBGPeriodicFields.field_tensor_order(c.f)

function GBGPeriodicFields.inner(a::CountingField, b::CountingField)
  COUNTS[:inner] += 1
  return GBGPeriodicFields.inner(a.f, b.f)
end

function GBGPeriodicFields.weighted_inner(a::CountingField, w)
  COUNTS[:weighted_inner] += 1
  return GBGPeriodicFields.weighted_inner(a.f, w)
end

function GBGPeriodicFields.convolve!(dst::CountingField, src::CountingField, kernel, α::Real, β::Real)
  COUNTS[:convolve] += 1
  GBGPeriodicFields.convolve!(dst.f, src.f, kernel, α, β)
  return dst
end

reset_counts!() = (for k in keys(COUNTS); COUNTS[k] = 0; end)

domain = FixedDomain(; grid_points_per_axis = 16, side_length = 2π,
                     dealiasing = TwoThirds(), element_type = Float64, array_type = Array)

function seeded_field()
  û = GBGIsotropicTurbulence.SimulationDomain.new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.0,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(20260821))
  return CountingField(û)
end

# ── The ledger survey, printed (not asserted): the relative emptiness floor of `_band_is_empty`
# makes EVERY BandRescaling and ConstantPower call reduce the WHOLE field, which neither
# `test/optimality_audit.jl`'s `_syncs` (:band → 1 crossing, :power → 1 crossing) nor
# `test/compute_audit.jl`'s `_forcing_pass_delta` (:band → 3 field-scale passes, with no
# :band / :total distinction) models. Printed rather than asserted because the right number for
# these two rows depends on which way the divergence is closed — the guard's scale or the ledger.
let cf = seeded_field()
  reset_counts!()
  apply_forcing!(BandRescaling(domain; target = 1.5, over = :band), cf, domain)
  @info "measured: BandRescaling(over = :band)" inner = COUNTS[:inner] weighted_inner = COUNTS[:weighted_inner] ledger_crossings = 1
end
let cf = seeded_field()
  rate = new_scalar_field_spectral(domain)
  reset_counts!()
  set_forcing_rate!(ConstantPower(domain; injection_rate = 0.1), rate, cf, domain)
  @info "measured: ConstantPower" inner = COUNTS[:inner] weighted_inner = COUNTS[:weighted_inner] ledger_crossings = 1
end


@testset "BandRescaling(:total) reduces the whole field once per step, not twice" begin
  cf = seeded_field()
  forcing = BandRescaling(domain; target = 1.5, over = :total)

  reset_counts!()
  apply_forcing!(forcing, cf, domain)

  # The band observable — one fused weighted reduction over the field.
  @test COUNTS[:weighted_inner] == 1
  # The whole-field observable — needed once (for the `:total` deficit), and the emptiness guard
  # should be handed that same number rather than recomputing it.
  @test COUNTS[:inner] == 1
  # And the rescale actually happened, so the count above is not from an early return.
  @test COUNTS[:convolve] == 1

  # The total host-crossing reductions the forcing hook issues, which the frozen SYNC_LEDGER's
  # default row prices at 2 (band observable + total observable).
  @test COUNTS[:inner] + COUNTS[:weighted_inner] == 2
end

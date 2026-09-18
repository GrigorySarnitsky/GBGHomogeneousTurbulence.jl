# Witness: VarianceRescaling(:total) computes the whole-field observable `inner(field, field)` TWICE per
# `project_forcing!` call — once as the eager second argument of `_band_is_empty` (src/Forcing.jl:322)
# and again at line 325 — with no mutation of `field` in between. Each is a field-scale quadratic
# reduction whose scalar result crosses to the host (a blocking device-to-host transfer on a GPU),
# in the hot loop of the DEFAULT run configuration.
#
# The correct behaviour asserted here: ONE whole-field reduction per call — which is also exactly
# what `test/optimality_audit.jl`'s frozen SYNC_LEDGER prices for the default row
# ("default (adaptive dt, VarianceRescaling :total)", achieved = 3 = 1 max-speed + band + total).

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.SimulationDomain: FixedDomain, TwoThirds, new_scalar_field_spectral
using GBGHomogeneousTurbulence.Forcing: VarianceRescaling, ConstantPower, project_forcing!, set_forcing_rate!
using GBGHomogeneousTurbulence.State: random_solenoidal_velocity_spectral!
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
  û = GBGHomogeneousTurbulence.SimulationDomain.new_vector_field_spectral(domain)
  random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.0,
                                       envelope_wavenumber = 2.0, rng = MersenneTwister(20260821))
  return CountingField(û)
end

# ── The ledger survey, printed (not asserted): the relative emptiness floor of `_band_is_empty`
# makes EVERY VarianceRescaling and ConstantPower call reduce the WHOLE field, which neither
# `test/optimality_audit.jl`'s `_syncs` (:band → 1 crossing, :power → 1 crossing) nor
# `test/compute_audit.jl`'s `_forcing_pass_delta` (:band → 3 field-scale passes, with no
# :band / :total distinction) models. Printed rather than asserted because the right number for
# these two rows depends on which way the divergence is closed — the guard's scale or the ledger.
let cf = seeded_field()
  reset_counts!()
  project_forcing!(VarianceRescaling(domain; target = 1.5, over = :band), cf, domain)
  @info "measured: VarianceRescaling(over = :band)" inner = COUNTS[:inner] weighted_inner = COUNTS[:weighted_inner] ledger_crossings = 1
end
let cf = seeded_field()
  rate = new_scalar_field_spectral(domain)
  reset_counts!()
  set_forcing_rate!(ConstantPower(domain; injection_rate = 0.1), rate, cf, domain)
  @info "measured: ConstantPower" inner = COUNTS[:inner] weighted_inner = COUNTS[:weighted_inner] ledger_crossings = 1
end


@testset "VarianceRescaling(:total) reduces the whole field once per step, not twice" begin
  cf = seeded_field()
  forcing = VarianceRescaling(domain; target = 1.5, over = :total)

  reset_counts!()
  project_forcing!(forcing, cf, domain)

  # The band AND whole-field observables — ONE fused multi-weight reduction over the field since
  # PF decision 72 (wired 2026-08-23): `weighted_inner(field, (band, unit))`, one traversal.
  @test COUNTS[:weighted_inner] == 1
  # The separate whole-field `inner` is gone — the fusion subsumed it.
  @test COUNTS[:inner] == 0
  # And the rescale actually happened, so the count above is not from an early return.
  @test COUNTS[:convolve] == 1

  # The total host-crossing reductions the forcing hook issues, which the frozen SYNC_LEDGER's
  # `:band_total` row prices at 1 (the fused band+total observable).
  @test COUNTS[:inner] + COUNTS[:weighted_inner] == 1
end

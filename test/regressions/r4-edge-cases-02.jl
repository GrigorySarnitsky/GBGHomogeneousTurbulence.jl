# Witness: a negative `target` handed to `VarianceRescaling` must be handled at the front door, not by an
# internal `sqrt` of a negative ratio.
#
# `target` is a kinetic energy (velocity) or a scalar variance (scalar); both are non-negative by
# definition, so a negative value is not a physical setting. The constructor
# (src/Forcing.jl:311) validates `over in (:band, :total)` but stores `target` unchecked. In
# `project_forcing!` the `:total` branch clamps with `max(zero(band_value), …)` (src/Forcing.jl:326),
# so it can never aim at a negative band value; the `:band` branch (line 328) passes `forcing.target`
# through unclamped and `scale = sqrt(target_band / band_value)` (line 330) then takes the square
# root of a negative number.
#
# The assertion below is deliberately agnostic about WHICH front-door fix lands: rejecting the
# negative `target` at construction with an `ArgumentError` (mirroring the `over` check that already
# sits two lines above it, and the `kinetic_energy > 0` check at the `Simulation` front door), or
# clamping the `:band` branch the way the `:total` branch already clamps, are both acceptable. What
# is NOT acceptable is a `DomainError` escaping from inside the hot loop.

using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: convolve!
using Random


# Run the whole `VarianceRescaling` episode and classify the outcome:
#   :rejected  — refused at construction with an ArgumentError (a front-door rejection)
#   :completed — the rescale ran to completion
#   the exception itself — anything else escaped
function band_rescaling_outcome(domain, û, target, over)
  try
    forcing = VarianceRescaling(domain; target = target, over = over)
    project_forcing!(forcing, û, domain)
    return :completed
  catch err
    return err isa ArgumentError ? :rejected : err
  end
end


@testset "VarianceRescaling rejects a negative `target` instead of taking sqrt of a negative ratio" begin
  N, L, T = 24, 2π, Float64
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_family = Array)

  seeded_velocity() = begin
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain, 1.0;
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(1))
    return û
  end

  # Precondition: the default band (shells 1–2) really is seeded, so the empty-band early return of
  # `project_forcing!` does not fire and the `sqrt` line is genuinely reached.
  @testset "the default band carries energy, so the rescale is not short-circuited" begin
    û = seeded_velocity()
    scratch = new_vector_field_spectral(domain)
    band = VarianceRescaling(domain; target = 1.0, over = :band).band
    @test kinetic_energy(convolve!(scratch, û, band)) > 0
  end

  @testset "over = :band" begin
    outcome = band_rescaling_outcome(domain, seeded_velocity(), -1.0, :band)
    @test outcome in (:rejected, :completed)
  end

  # The sibling branch is the control: its `max(zero(band_value), …)` clamp already absorbs the
  # negative target, which is what makes the `:band` branch's omission a defect rather than a
  # deliberate package-wide stance on negative targets.
  @testset "over = :total (control: already survives a negative target)" begin
    outcome = band_rescaling_outcome(domain, seeded_velocity(), -1.0, :total)
    @test outcome in (:rejected, :completed)
  end

  # A zero target stays legal under both branches — it means "empty the band", a reachable state the
  # docstring describes. A fix must not over-reach and reject it.
  @testset "a zero target remains accepted" begin
    for over in (:band, :total)
      @test band_rescaling_outcome(domain, seeded_velocity(), 0.0, over) === :completed
    end
  end
end

using Test
using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, TwoThirds, max_wavenumber
using GBGPeriodicFields: materialize_kernel, field_data


# The retained band of a FixedDomain, as a Bool array over the spectral grid: 1 where the dealias
# kernel keeps the mode.
function retained_band(domain)
  stored = materialize_kernel(domain.dealias)
  return real.(Array(field_data(stored.field))) .> 0.5
end


# |κ| per mode, in Float64, from the domain's own multipliers.
function wavenumber_magnitude(domain)
  m = domain.multipliers
  s1 = Float64.(Array(m.squared_wavenumber_1))
  s2 = Float64.(Array(m.squared_wavenumber_2))
  s3 = Float64.(Array(m.squared_wavenumber_3))
  return [sqrt(s1[i] + s2[j] + s3[k]) for i in eachindex(s1), j in eachindex(s2), k in eachindex(s3)]
end


@testset "max_wavenumber reports exactly the band the domain builds" begin
  for T in (Float64, Float32), N in (12, 24, 48, 96)
    domain = FixedDomain(; grid_points_per_axis = N, side_length = 2π,
                           dealiasing = TwoThirds(), element_type = T, array_type = Array)
    κ = wavenumber_magnitude(domain)
    κmax = max_wavenumber(domain)
    built = retained_band(domain)
    reported = κ .<= κmax
    mismatches = count(built .!= reported)
    @test (T, N, mismatches) == (T, N, 0)
  end
end

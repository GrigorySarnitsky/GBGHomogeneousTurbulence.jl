# The sharp 2/3 mask keeps the CLOSED ball, boundary shell included, and that is EXACT for the
# rotational-form + Leray-projected discretization — pinned here so a future "match the reference,
# cut strictly below" impulse has to refute this measurement first (a strict edge was implemented
# and reverted 2026-08-23; TurTLE's exclusion serves ITS formulation, not ours).
#
# The mechanism this test pins: at cutoff N/3 the only aliased product image that lands inside the
# ball comes from the axis self-pair (N/3,0,0)+(N/3,0,0), and that image is a pure gradient — the
# single-mode Lamb vector is −∇(|u|²/2) (u·∇u vanishes for one mode), its alias stays gradient-shaped — which the Leray projection
# annihilates exactly. The test therefore populates EVERY stored boundary mode with random
# solenoidal content (the adversarial configuration: any surviving wrap would show) and holds the
# N-grid projected term against a 2N zero-padded oracle, on and below the boundary shell.
using Test, GBGHomogeneousTurbulence, Random
using GBGPeriodicFields: field_data, to_physical!
const SD6 = GBGHomogeneousTurbulence.SimulationDomain
const GEN6 = GBGHomogeneousTurbulence.Generator


@testset "the inclusive 2/3 ball is exact on a 3|N grid, boundary shell populated" begin
  Np, L = 12, 2π
  d23 = FixedDomain(grid_points_per_axis = Np, side_length = L, dealiasing = TwoThirds(),
                    element_type = Float64, array_type = Array)
  d2 = FixedDomain(grid_points_per_axis = 2Np, side_length = L, dealiasing = TwoThirds(),
                   element_type = Float64, array_type = Array)
  û = SD6.new_vector_field_spectral(d23)
  random_solenoidal_velocity_spectral!(û, d23; kinetic_energy = 0.5, envelope_wavenumber = 3.0,
                                       rng = MersenneTwister(3))
  A = field_data(û)
  rng = MersenneTwister(11)
  wn(i, n) = i <= n ÷ 2 + 1 ? i - 1 : i - 1 - n
  populated = 0
  for i3 in 1:Np, i2 in 1:Np, i1 in 1:(Np ÷ 2 + 1)
    κ = (i1 - 1, wn(i2, Np), wn(i3, Np))
    sum(abs2, κ) == 16 || continue                       # the |κ| = N/3 = 4 boundary shell
    c = randn(rng, 3) .+ im .* randn(rng, 3)
    κv = collect(float.(κ))
    c .-= κv .* (sum(κv .* c) / 16)                      # solenoidal: κ·c = 0
    A[i1, i2, i3, :] .= 0.4 .* c
    populated += 1
  end
  @test populated == 5                                   # (4,0,0), (0,±4,0), (0,0,±4) stored modes

  half = Np ÷ 2
  mapidx(i) = i ≤ half + 1 ? i : i + Np
  embed(Aa) = (B = zeros(eltype(Aa), Np + 1, 2Np, 2Np, 3);
               for c in 1:3, i3 in 1:Np, i2 in 1:Np, i1 in 1:half+1
                 B[i1, mapidx(i2), mapidx(i3), c] = 8 * Aa[i1, i2, i3, c]
               end; B)
  restrict(B) = [B[i1, mapidx(i2), mapidx(i3), c] / 8
                 for i1 in 1:half+1, i2 in 1:Np, i3 in 1:Np, c in 1:3]
  function projected_advective_term(domain, ûf)
    u = SD6.new_vector_field_physical(domain); ω = SD6.new_vector_field_physical(domain)
    tmp = SD6.new_vector_field_spectral(domain)
    to_physical!(u, ûf, domain.transform_plans, tmp)
    vorticity_physical!(ω, ûf, domain, tmp)
    out = SD6.new_vector_field_spectral(domain)
    GEN6._velocity_advective_term!(out, u, ω, domain, SD6.new_vector_field_spectral(domain))
    field_data(out)
  end
  raw = projected_advective_term(d23, û)
  û2 = SD6.new_vector_field_spectral(d2)
  field_data(û2) .= embed(field_data(û))
  oracle = restrict(projected_advective_term(d2, û2))

  m = d23.multipliers
  κm = sqrt.(reshape(m.squared_wavenumber_1, :, 1, 1) .+
             reshape(m.squared_wavenumber_2, 1, :, 1) .+
             reshape(m.squared_wavenumber_3, 1, 1, :))
  ref = maximum(abs.(oracle))
  err_on(msk) = maximum(maximum(abs.(view(raw, :, :, :, c) .- view(oracle, :, :, :, c)) .* msk)
                        for c in 1:3) / ref
  @test err_on(κm .< 4 - 1e-9) < 1e-12                   # below the boundary: exact
  @test err_on(abs.(κm .- 4) .< 1e-9) < 1e-12            # ON the boundary shell: exact too
end

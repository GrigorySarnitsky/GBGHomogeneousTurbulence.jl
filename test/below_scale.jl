# kinetic_energy_and_dissipation_below_scale — the kinetic energy and dissipation held in scales below a
# box side l. Two oracles, each independent of the fused kernel path under test:
#   (1) the exact spectral sums ½Σ(1 − W²)|û|² and νΣ|κ|²(1 − W²)|û|², written as plain host loops over
#       the stored coefficients with the rfft Parseval weights;
#   (2) the DEFINITION itself in physical space — cut boxes of side l, remove each box's own mean, and
#       average the remaining kinetic energy over every box position — on a field zero-padded to an
#       8× finer grid, where discrete box means approach the continuum ones the observable measures.
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_data, embed_modes!, to_physical!
using Random


# (1) the exact spectral sums, from the coefficients, with no PF kernel involved
function spectral_oracle(û, domain, ν)
  c = Array(field_data(û))                         # (N/2+1, N, N, 3), reduced axis first
  N = domain.grid.grid_size[1]; L = domain.grid.domain_size[1]; κ₀ = 2π / L
  wave(j) = (j - 1 <= N ÷ 2 ? j - 1 : j - 1 - N) * κ₀
  sinc(y) = iszero(y) ? one(y) : sin(y) / y
  k, ε = zeros(N), zeros(N)
  for n in 1:N, iz in 1:N, iy in 1:N, ix in 1:(N ÷ 2 + 1)
    l = n * L / N
    κx, κy, κz = (ix - 1) * κ₀, wave(iy), wave(iz)
    W = sinc(κx * l / 2) * sinc(κy * l / 2) * sinc(κz * l / 2)
    parseval = (ix == 1 || (iseven(N) && ix == N ÷ 2 + 1)) ? 1 : 2   # the half-spectrum's weights
    power = sum(abs2, @view c[ix, iy, iz, :]) * parseval / N^6
    k[n] += (1 - W^2) * power / 2
    ε[n] += ν * (κx^2 + κy^2 + κz^2) * (1 - W^2) * power
  end
  return k, ε
end


# (2) the definition, in physical space: k(l) = ½⟨|u|²⟩ − ½⟨|⟨u⟩_l|²⟩, the position average of the energy
# left after removing each box's own mean (the box average of |u|² averages back to the global mean)
periodic_box_mean(a, q, dim) = begin
  n = size(a, dim)
  c = cumsum(cat(a, selectdim(a, dim, 1:q); dims = dim); dims = dim)      # wrap by q for the window
  lead = selectdim(c, dim, q:(q + n - 1))
  lag = cat(zero(selectdim(a, dim, 1:1)), selectdim(c, dim, 1:(n - 1)); dims = dim)
  (lead .- lag) ./ q
end

function physical_oracle(û, domain; refine = 8)
  N = domain.grid.grid_size[1]; M = refine * N
  fine = FixedDomain(grid_points_per_axis = M, side_length = domain.grid.domain_size[1],
                     dealiasing = TwoThirds(), element_type = Float64, array_family = Array)
  û_fine = new_vector_field_spectral(fine)
  embed_modes!(û_fine, û)                             # the band-limited field, exactly, on the fine grid
  u = new_vector_field_physical(fine)
  to_physical!(u, û_fine, fine.transform_plans)
  a = field_data(u)
  total = sum(abs2, a) / M^3 / 2
  k = zeros(N)
  for n in 1:N
    box_mean = a
    for dim in 1:3
      box_mean = periodic_box_mean(box_mean, n * refine, dim)
    end
    k[n] = total - sum(abs2, box_mean) / M^3 / 2
  end
  return k
end


@testset "kinetic_energy_and_dissipation_below_scale" begin
  for N in (16, 12)
    domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                         element_type = Float64, array_family = Array)
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.5, envelope_wavenumber = 3.0,
                                         rng = MersenneTwister(N))
    ν = 0.02
    r = kinetic_energy_and_dissipation_below_scale(û, domain, ν)

    @test r.scales ≈ [n * 2π / N for n in 1:N]
    k_oracle, ε_oracle = spectral_oracle(û, domain, ν)
    @test r.kinetic_energy ≈ k_oracle rtol = 1e-12
    @test r.dissipation ≈ ε_oracle rtol = 1e-12

    # the whole box keeps only the mean, so the largest side returns the whole-field pair
    whole = kinetic_energy_and_dissipation(û, domain, ν)
    @test r.kinetic_energy[end] ≈ whole.kinetic_energy rtol = 1e-12
    @test r.dissipation[end] ≈ whole.dissipation rtol = 1e-12
    @test issorted(r.kinetic_energy) && issorted(r.dissipation)
    @test all(>(0), r.kinetic_energy)

    # The definition — cut, remove each box's mean, average over positions — agrees ELEMENTWISE to
    # the fine grid's discretization of the continuum box mean. A box of q fine points biases the
    # removed share by ≈ 1/q² relative (the discrete mean of a mode is sin(qκh/2)/(q sin(κh/2)), not
    # the sinc), so side n, spanning q = 8n points, is held to 2/q². A vector-norm `≈` let the small
    # sides go unchecked; the wrong form ½Σ(1 − W)²|û|² misses by up to ~97% and fails this at every
    # side but the domain-sized one, where W vanishes off the mean and the two forms coincide.
    physical = physical_oracle(û, domain; refine = 8)
    q = 8 .* (1:N)
    @test all(abs.(r.kinetic_energy .- physical) ./ physical .< 2 ./ q .^ 2)
  end

  @testset "a Float32 run measures in Float32" begin
    domain = FixedDomain(grid_points_per_axis = 12, side_length = 2π, dealiasing = TwoThirds(),
                         element_type = Float32, array_family = Array)
    û = new_vector_field_spectral(domain)
    random_solenoidal_velocity_spectral!(û, domain; kinetic_energy = 1.5, envelope_wavenumber = 3.0,
                                         rng = MersenneTwister(3))
    r = kinetic_energy_and_dissipation_below_scale(û, domain, 0.02)
    @test eltype(r.scales) === eltype(r.kinetic_energy) === eltype(r.dissipation) === Float32
    @test r.kinetic_energy isa Vector
  end
end

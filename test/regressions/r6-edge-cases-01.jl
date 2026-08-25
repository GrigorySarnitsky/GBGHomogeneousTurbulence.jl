# Witness: `VarianceController`'s turnover_time guard must report the value it checked.
# When `turnover_time` is omitted, the constructor derives tℓ = 2k/(3ε_∞); for a tiny `target`
# the dissipation estimate underflows to 0.0, tℓ = Inf, and the guard on Forcing.jl:666 fires —
# but the message interpolates the ORIGINAL keyword (`nothing`), not the derived tℓ it checked.
using Test, GBGIsotropicTurbulence

@testset "VarianceController's turnover_time guard reports the checked derived value, not `nothing`" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π,
                       element_type = Float64, dealiasing = TwoThirds(), array_type = Array)
  err = try
    VarianceController(domain; target = 1e-300)   # derived tℓ = Inf → the guard fires
    nothing
  catch e
    e
  end
  @test err isa ArgumentError
  # The guard checked the derived tℓ (here Inf). The message must show that number —
  # it must NOT claim the checked value was `nothing` (the unsupplied keyword).
  @test err isa ArgumentError && !occursin("got nothing", err.msg)
  @test err isa ArgumentError && occursin("Inf", err.msg)
end

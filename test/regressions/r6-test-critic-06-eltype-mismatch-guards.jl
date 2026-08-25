# Witness r6-test-critic-06: the HDF5 element-type-mismatch guards refuse, with an ArgumentError
# naming the element types, a Float64-written state / tracer set read back against a Float32 domain
# of the SAME grid size (and vice versa for state) — the branch the suite's domain-mismatch test
# (grid-size only, Float64 throughout) never exercises.
using Test, Random, HDF5
using GBGIsotropicTurbulence
using GBGPeriodicFields: field_data, point_coordinates, LalescuSpline


make_domain(T) = FixedDomain(; grid_points_per_axis = 8, side_length = 2π, element_type = T,
                             array_type = Array, dealiasing = TwoThirds())


@testset "read_state / read_tracers refuse an element-type mismatch by name" begin
  domain64 = make_domain(Float64)
  domain32 = make_domain(Float32)

  # ——— state: written Float64, read against a Float32 domain of the same grid ———
  path = tempname() * ".h5"
  state = GBGIsotropicTurbulence.State.ResolvedFields(domain64; scalar = true)
  rng = MersenneTwister(11)
  copyto!(field_data(state.velocity_spectral),
          randn(rng, ComplexF64, size(field_data(state.velocity_spectral))))
  copyto!(field_data(state.scalar_spectral),
          randn(rng, ComplexF64, size(field_data(state.scalar_spectral))))
  h5open(io -> write_state(io, "s", state), path, "w")
  err = nothing
  h5open(path, "r") do io
    try
      read_state(io, "s", domain32)
    catch e
      err = e
    end
  end
  @test err isa ArgumentError
  @test err !== nothing && occursin("element type", sprint(showerror, err))
  @test err !== nothing && occursin("ComplexF64", sprint(showerror, err)) &&
        occursin("ComplexF32", sprint(showerror, err))

  # ——— state, the other direction: written Float32, read against a Float64 domain ———
  path2 = tempname() * ".h5"
  state32 = GBGIsotropicTurbulence.State.ResolvedFields(domain32; scalar = false)
  copyto!(field_data(state32.velocity_spectral),
          randn(rng, ComplexF32, size(field_data(state32.velocity_spectral))))
  h5open(io -> write_state(io, "s", state32), path2, "w")
  err2 = nothing
  h5open(path2, "r") do io
    try
      read_state(io, "s", domain64)
    catch e
      err2 = e
    end
  end
  @test err2 isa ArgumentError
  @test err2 !== nothing && occursin("element type", sprint(showerror, err2))

  # ——— tracers: written Float64 positions, read against a Float32 domain ———
  path3 = tempname() * ".h5"
  tracers = Tracers(domain64; number_of_particles = 5,
                    interpolation_scheme = LalescuSpline(2, 1), unwrapped = true,
                    rng = MersenneTwister(12))
  h5open(io -> write_tracers(io, "t", tracers), path3, "w")
  err3 = nothing
  h5open(path3, "r") do io
    try
      read_tracers(io, "t", domain32)
    catch e
      err3 = e
    end
  end
  @test err3 isa ArgumentError
  @test err3 !== nothing && occursin("element type", sprint(showerror, err3))
  @test err3 !== nothing && occursin("Float64", sprint(showerror, err3)) &&
        occursin("Float32", sprint(showerror, err3))
end

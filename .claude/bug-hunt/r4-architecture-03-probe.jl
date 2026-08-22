using GBGIsotropicTurbulence
using GBGIsotropicTurbulence.SimulationDomain: FixedDomain, max_wavenumber
using GBGPeriodicFields: field_data

for (T, N, L) in ((Float32, 33, 2π), (Float32, 64, 2π), (Float64, 33, 2π))
  d = FixedDomain(; grid_points_per_axis = N, side_length = L,
                    dealiasing = TwoThirds(), element_type = T, array_type = Array)
  pf   = d.grid.grid_spacing[1]
  it64 = Float64(d.grid.domain_size[1]) / N
  println("T=$T N=$N")
  println("  PF grid_spacing[1]      = ", pf,   "  (", typeof(pf), ")  bits=", repr(reinterpret(UInt64, Float64(pf))))
  println("  cfl_timestep Float64 L/N= ", it64, "  bits=", repr(reinterpret(UInt64, it64)))
  println("  equal as Float64? ", Float64(pf) == it64, "   equal narrowed to T? ", T(pf) == T(it64))
  println("  rel diff = ", abs(Float64(pf) - it64) / it64)
end

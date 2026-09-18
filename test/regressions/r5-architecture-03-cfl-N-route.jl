# Architecture witness (informational, not a failing test): the two N-routes agree TODAY.
using GBGHomogeneousTurbulence
using GBGPeriodicFields: field_physical_shape, field_data

sim = Simulation(grid_points_per_axis = 8, scalar = false)
N_domain = field_physical_shape(sim.domain.grid, Val(0))[1]
N_cache  = size(field_data(sim.cache.velocity_physical), 1)
println("N via domain (SimulationDomain.jl:307 route) = ", N_domain)
println("N via cache array dim 1 (SimulationRun.jl:422) = ", N_cache)
println("physical array shape = ", size(field_data(sim.cache.velocity_physical)))
println("agree today = ", N_domain == N_cache)

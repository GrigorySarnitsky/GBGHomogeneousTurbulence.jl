# Supporting measurement for the architecture finding "the memory/optimality audits enumerate one
# trajectory scheme". Not a pass/fail regression test: it prints the per-particle residency the
# audits pin (four (M, 3) arrays, EndpointHeun) beside what a front-door `AdamsBashforth` run
# actually holds, using the audits' own reflective walk.
using GBGIsotropicTurbulence
using GBGPeriodicFields: CatmullRom
using Random


# `pkgdir` rather than a path counted from this file: a witness is authored under
# .claude/bug-hunt/witnesses/ and PROMOTED into test/regressions/, so a fixed number of `..` hops
# resolves outside the repository once it moves. (Walking up to the first Project.toml is also wrong
# here — `test/` carries one of its own, so the walk stops a level early.)
include(joinpath((let d = @__DIR__; while !isfile(joinpath(d, "src", "GBGIsotropicTurbulence.jl")); d = dirname(d); end; d end), "test", "audit_ops.jl"))

M = 4
domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                     array_type = Array, dealiasing = TwoThirds())

m_arrays(owner) = (acc = AbstractArray[];
                   collect_field_arrays!(acc, owner, Set{UInt}(), 2);
                   [a for a in acc if size(a) == (M, 3)])

# What the audit's testset pins, verbatim (test/memory_audit.jl:321-333).
tracers = Tracers(domain; number_of_particles = M, interpolation_scheme = CatmullRom,
                  rng = MersenneTwister(1))
heun_buffers = allocate_buffers(EndpointHeun(), tracers)
println("audit-pinned:      tracers=", length(m_arrays(tracers)),
        " buffers=", length(m_arrays(heun_buffers)),
        " total=", length(m_arrays(tracers)) + length(m_arrays(heun_buffers)))

# What a live front-door run holds on each point of the (unswept) trajectory-scheme axis.
for scheme in (EndpointHeun(), AdamsBashforth(order = 2), AdamsBashforth(order = 4),
               AdamsBashforth(order = 8))
  sim = Simulation(domain; viscosity = 0.1, number_of_particles = M,
                   trajectory_scheme = scheme, rng = MersenneTwister(1))
  acc = AbstractArray[]
  collect_field_arrays!(acc, sim, Set{UInt}(), 2)
  n = count(a -> size(a) == (M, 3), acc)
  println(rpad(string(typeof(scheme)), 46), " live (M,3) arrays = ", n,
          "   history slots = ", length(sim.cache.particle_velocity_history))
end

# Why the count above does not move: the reflective walk stops at an `AbstractArray`, so a
# `Vector{<:AbstractArray}` (the history container) is counted as ONE array and never recursed into.
sim8 = Simulation(domain; viscosity = 0.1, number_of_particles = M,
                  trajectory_scheme = AdamsBashforth(order = 8), rng = MersenneTwister(1))
acc = AbstractArray[]
collect_field_arrays!(acc, sim8, Set{UInt}(), 2)
println("AB8 walk, all reached array shapes: ", sort(string.(size.(acc))))
println("history container is itself an AbstractArray: ",
        sim8.cache.particle_velocity_history isa AbstractArray,
        "  eltype = ", eltype(sim8.cache.particle_velocity_history),
        "  bytes held = ", sum(sizeof, sim8.cache.particle_velocity_history))

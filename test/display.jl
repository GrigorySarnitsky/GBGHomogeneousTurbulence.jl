# Display tests — the gate that every concrete struct type of the package shows itself, on the field
# library's two-form convention (its decision 82, adopted here as decision 87): a one-line
# self-delimiting compact form, a REPL form that may spend lines, a body carrying what a check
# REFUSES on, nested objects through their own `show`, and nothing that reads an element.
#
# The gate is DERIVED, not listed: it enumerates every concrete struct type the package defines and
# requires a package-owned `show` or a cited exemption, checked in both directions — a hand-written
# list would go stale the moment a type is added, which is exactly when the check has something to say.

using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence: SimulationDomain, State, Observables, Cache, Forcing, Generator,
                              Propagator, Particles, SimulationRun, Phenomenology
using GBGHomogeneousTurbulence.Phenomenology: Spectra, StructureFunctions, Scalings, FlowParameters, Reference
using GBGHomogeneousTurbulence.Phenomenology.Spectra: Pope2000
using GBGHomogeneousTurbulence.Phenomenology.Scalings: Li2008
using GBGHomogeneousTurbulence.Phenomenology.StructureFunctions: Kolmogorov1941
using GBGHomogeneousTurbulence.Particles: advect!, unwrapped_positions
using GBGPeriodicFields: field_data, point_positions, npoints, LalescuSpline
using Random
using Test


const MODULES = Set(Any[GBGHomogeneousTurbulence, SimulationDomain, State, Observables, Cache, Forcing,
                        Generator, Propagator, Particles, SimulationRun, Phenomenology, Spectra,
                        StructureFunctions, Scalings])

# Types that deliberately carry no display, each with the reason. Every one is a flat record of
# numbers (or strings) whose default display — its positional constructor call, module-qualified
# when the name is not in scope — is already the whole description, short, and round-tripping
# either way (asserted below, so an exemption that stops holding fails); a method would only add a
# second spelling. A record NESTING another package type is not exempt: the default qualifies every
# nested name, which ran a `Pope2000` to 157 characters (the model-spectrum family has displays for
# that reason). The two run-layer records are private besides.
const RECORD_REASON = "a flat record: the default positional-constructor display is complete, " *
                      "short, and round-trips (asserted in the round-trip testset)"
const NO_DISPLAY = Dict(
  :Clock                  => RECORD_REASON * "; private to the run layer",
  :EveryTime              => RECORD_REASON * "; private to the run layer",
  :Reference              => RECORD_REASON,
  :Li2008                 => RECORD_REASON,
  :Sreenivasan1995        => RECORD_REASON,
  :Sreenivasan1998        => RECORD_REASON,
  :ObukhovCorrsin1949     => RECORD_REASON,
  :Kolmogorov1941         => RECORD_REASON,
  :Kolmogorov1962         => RECORD_REASON,
)


"""Every concrete struct type the package defines, keyed by name."""
function package_struct_types()
  found = Dict{Symbol, Any}()
  for m in MODULES, name in names(m; all = true)
    isdefined(m, name) || continue
    object = getfield(m, name)
    object isa Type || continue
    # A parametric type is a `UnionAll`, so asking `isa DataType` of it is false and silently drops
    # most of the package. Unwrap first.
    base = Base.unwrap_unionall(object)
    base isa DataType || continue
    base.name.module in MODULES || continue
    # An empty NON-parametric struct is a singleton whose default `Name()` is its constructor. An
    # empty parametric one is not: its content lives in the type parameter (`AdamsBashforth{K}`),
    # so the default would spell it `Module.Name{3}()`, and it is enumerated like any other.
    isabstracttype(base) && continue
    isempty(fieldnames(base)) && !(object isa UnionAll) && continue
    startswith(string(nameof(base)), "#") && continue
    found[nameof(base)] = object
  end
  return found
end

has_display(type) = any(m -> m.module in MODULES, methods(Base.show, Tuple{IO, type}))

repl(x) = sprint(show, MIME"text/plain"(), x)


@testset "display" begin

  @testset "every package struct type displays, or is exempt with a reason" begin
    types = package_struct_types()
    @test length(types) ≥ 30  # a parser that stops matching must fail, not report a clean sweep

    for (name, type) in sort!(collect(types); by = first)
      if haskey(NO_DISPLAY, name)
        @test !has_display(type)  # a stale exemption is a widened blind spot
      else
        @test has_display(type)
      end
    end

    # Both directions: an exemption naming a type the package no longer defines is stale.
    for name in keys(NO_DISPLAY)
      @test haskey(types, name)
    end

    # Falsified by perturbation: a planted empty-but-parametric struct is enumerated (the shape
    # `AdamsBashforth{K}` has, whose default would print `Module.Name{3}()`), so it cannot ship
    # without a display or an exemption.
    @eval Particles struct _PlantedOrderTag{K} end
    @test haskey(package_struct_types(), :_PlantedOrderTag)
    @test !has_display(Particles._PlantedOrderTag)
  end

  N = 16
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                       dealiasing = PhaseShift(), array_type = Array)
  M = 12
  sim = Simulation(domain; viscosity = 0.05, scalar = true, number_of_particles = M,
                   particle_integration_scheme = AdamsBashforth(order = 3),
                   velocity_forcing = DeferredForcing(d -> ConstantPower(d; injection_rate = 0.1)),
                   scalar_forcing = DeferredForcing(d -> VarianceRescaling(d; target = 0.5, over = :band)))
  tracers = Tracers(domain; number_of_particles = M, interpolation_scheme = LalescuSpline(1, 1),
                    rng = MersenneTwister(1))

  @testset "no display floods" begin
    # The bound is generous: the point is that nothing prints an array, not that any particular
    # wording fits (a 20000-tracer set printed 5.6 million characters by default). The compound
    # objects — the conditions and the generator nest each forcing's display, the criterion nests
    # its monitor — get the wider budget the nesting costs.
    leaves = Any[
      domain, sim.state, sim.cache, sim.tracers, sim.buffers, sim.buffers.scalar,
      sim.generator.phase_shift, sim.particle_buffers, sim.particle_traversal, sim,
      HouLi(), HouLi(order = 24, strength = 30, materialized = true), AdamsBashforth(order = 3),
      ConstantPower(domain; injection_rate = 0.1), Linear(domain; rate = 0.5),
      VarianceRescaling(domain; target = 0.5, over = :total), VarianceController(domain; target = 0.5),
      StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5), DeferredForcing(d -> nothing),
      initial_forcing_state(StochasticOU(domain; forcing_variance = 1.0, correlation_time = 0.5),
                            new_vector_field_spectral(domain), domain),
      StationarityCriterion().monitor,
      FlowParameters(viscosity = 0.01, dissipation = 0.1, rms_velocity = 1, integral_scale = 1),
    ]
    compounds = Any[sim.generator.conditions, sim.generator, StationarityCriterion()]
    for sample in leaves
      @test length(repr(sample)) ≤ 300
      @test !occursin("\n", repr(sample))  # the two-argument form is one line
    end
    for sample in compounds
      @test length(repr(sample)) ≤ 900
      @test !occursin("\n", repr(sample))
    end
    # The particle count never reaches a display as an array: the largest tracer set the old
    # default printed in full is the one this bound is for.
    many = Tracers(domain; number_of_particles = 20000, interpolation_scheme = LalescuSpline(1, 1),
                   rng = MersenneTwister(1))
    big = ObservablesCache(domain; number_of_particles = 20000, history_depth = 3)
    @test length(repr(many)) ≤ 300
    @test length(repr(big)) ≤ 300
    @test length(repr(allocate_buffers(AdamsBashforth(order = 3), many, big))) ≤ 300
  end

  @testset "the compact form is self-delimiting" begin
    # It appears inside a container, inside `$(...)` and inside an exception, so a bare `Type: a, b`
    # could not be told from its neighbours once a container puts commas between elements.
    for sample in (domain, sim.state, sim.cache, sim.tracers, sim.buffers, sim.generator, sim,
                   ConstantPower(domain; injection_rate = 0.1), HouLi(order = 24), StationarityCriterion())
      @test occursin(repr(sample), repr([sample, sample]))
      @test endswith(repr(sample), ")")
    end
  end

  @testset "objects the package refuses to combine display differently" begin
    # The reason the body carries what it carries. Each pair below is refused by the check named
    # beside it, and an error explaining the refusal must not show the reader the same text twice.

    # A state on another grid, or of another element type, is refused adoption by `Simulation`;
    # a state with a scalar is refused by a run built without one.
    other = FixedDomain(grid_points_per_axis = 2N, side_length = 2π, element_type = Float64,
                        dealiasing = PhaseShift(), array_type = Array)
    f32 = FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float32,
                      dealiasing = PhaseShift(), array_type = Array)
    @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = ResolvedFields(other))
    @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = ResolvedFields(f32))
    @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = ResolvedFields(domain; scalar = true))
    @test repr(ResolvedFields(domain)) != repr(ResolvedFields(other))
    @test repr(ResolvedFields(domain)) != repr(ResolvedFields(f32))
    @test repr(ResolvedFields(domain)) != repr(ResolvedFields(domain; scalar = true))
    # The domains themselves: grid, element type, and dealiasing each tell two apart.
    @test repr(domain) != repr(other)
    @test repr(domain) != repr(f32)
    @test repr(domain) != repr(FixedDomain(grid_points_per_axis = N, side_length = 2π, element_type = Float64,
                                           dealiasing = TwoThirds(), array_type = Array))
    # A box differing in the last digit is a different grid to the equality check, and must not collide.
    near = FixedDomain(grid_points_per_axis = N, side_length = 2π + 1e-9, element_type = Float64,
                       dealiasing = PhaseShift(), array_type = Array)
    @test_throws ArgumentError Simulation(domain; viscosity = 0.05, state = ResolvedFields(near))
    @test repr(domain) != repr(near)

    # A scalar state is refused a cache without a scalar slot, and buffers without a scalar set — the
    # two guards at the deposit that closes every iteration.
    scalar_state = ResolvedFields(domain; scalar = true)
    random_solenoidal_velocity_spectral!(scalar_state.velocity_spectral, domain; kinetic_energy = 0.5,
                                         envelope_wavenumber = 2.0, rng = MersenneTwister(1))
    scalar_buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    @test_throws ArgumentError deposit!(ObservablesCache(domain), scalar_state, domain, scalar_buffers)
    @test_throws ArgumentError deposit!(ObservablesCache(domain; scalar = true), scalar_state, domain,
                                        allocate_buffers(IFLowStorageRK3(), domain))
    @test repr(ObservablesCache(domain)) != repr(ObservablesCache(domain; scalar = true))
    @test repr(allocate_buffers(IFLowStorageRK3(), domain)) !=
          repr(allocate_buffers(IFLowStorageRK3(), domain; scalar = true))
    # And the register set is the scheme's signature: a one-step set is not a low-storage one.
    @test repr(allocate_buffers(IFHeun(), domain)) != repr(allocate_buffers(IFLowStorageRK3(), domain))

    # A generator built without a scalar is refused a scalar right-hand side under `PhaseShift`
    # (the guard fires before any assembly, so the fields' contents do not matter).
    conditions = FlowConditions(0.05, 1.0, NoForcing(), NoForcing())
    velocity_only = ResolvedGenerator(domain, conditions)
    @test_throws ArgumentError scalar_rhs!(new_scalar_field_spectral(domain), velocity_only,
                                           scalar_state.velocity_spectral, scalar_state.scalar_spectral,
                                           new_vector_field_physical(domain), new_scalar_field_physical(domain),
                                           domain)
    @test repr(velocity_only) != repr(ResolvedGenerator(domain, conditions; scalar = true))

    # A cache without a particle slot, or with the wrong history depth, is refused by the particle
    # schemes' `allocate_buffers`; the count and the depth are the two things it reads.
    @test_throws ArgumentError allocate_buffers(Heun(), tracers, ObservablesCache(domain))
    @test_throws ArgumentError allocate_buffers(AdamsBashforth(order = 3), tracers,
                                                ObservablesCache(domain; number_of_particles = M))
    @test repr(ObservablesCache(domain)) != repr(ObservablesCache(domain; number_of_particles = M))
    @test repr(ObservablesCache(domain; number_of_particles = M)) !=
          repr(ObservablesCache(domain; number_of_particles = M, history_depth = 3))
    @test repr(ObservablesCache(domain; number_of_particles = M)) !=
          repr(ObservablesCache(domain; number_of_particles = 2M))

    # Buffers built for one Adams–Bashforth order are refused by another's push.
    cache2 = ObservablesCache(domain; number_of_particles = M, history_depth = 2)
    cache3 = ObservablesCache(domain; number_of_particles = M, history_depth = 3)
    buffers2 = allocate_buffers(AdamsBashforth(order = 2), tracers, cache2)
    buffers3 = allocate_buffers(AdamsBashforth(order = 3), tracers, cache3)
    @test_throws ArgumentError advect!(AdamsBashforth(order = 3), tracers, sim.cache.velocity_physical,
                                       domain, buffers2, 0.01)
    @test repr(buffers2) != repr(buffers3)
    @test repr(AdamsBashforth(order = 2)) != repr(AdamsBashforth(order = 3))

    # A tracer set without the unwrapped record is refused the unwrapped read.
    kept = Tracers(domain; number_of_particles = M, interpolation_scheme = LalescuSpline(1, 1),
                   unwrapped = true, rng = MersenneTwister(1))
    @test_throws ArgumentError unwrapped_positions(tracers)
    @test repr(tracers) != repr(kept)
    @test repr(tracers) != repr(Tracers(domain; number_of_particles = 2M,
                                        interpolation_scheme = LalescuSpline(1, 1), rng = MersenneTwister(1)))

    # The forcings: each parameter and the shell band are the constructor's, so two forcings that
    # would drive a run differently print differently.
    @test repr(ConstantPower(domain; injection_rate = 0.1)) != repr(ConstantPower(domain; injection_rate = 0.2))
    @test repr(ConstantPower(domain; injection_rate = 0.1)) !=
          repr(ConstantPower(domain; injection_rate = 0.1, highest_shell = 3))
    @test repr(VarianceRescaling(domain; target = 0.5, over = :band)) !=
          repr(VarianceRescaling(domain; target = 0.5, over = :total))
    @test repr(VarianceController(domain; target = 0.5)) != repr(VarianceController(domain; target = 0.5, turnover_time = 1))
    @test repr(Linear(domain; rate = 0.5)) != repr(Linear(domain; rate = 0.5, lowest_shell = 2))
    @test repr(StochasticOU(domain; forcing_variance = 1, correlation_time = 0.5)) !=
          repr(StochasticOU(domain; forcing_variance = 1, correlation_time = 0.5, seed = 1))
    # The dealiasing strategy's parameters, which change the retained band and the filter.
    @test repr(HouLi()) != repr(HouLi(order = 24))
    @test repr(HouLi()) != repr(HouLi(materialized = true))
    @test repr(HouLi()) != repr(HouLi(strength = 30))
  end

  @testset "the parameter records round-trip" begin
    # A record's display is its constructor call: what it prints rebuilds it. This is also the
    # property every `NO_DISPLAY` exemption rests on, so the exempt records are here too.
    for record in (HouLi(), HouLi(order = 24, strength = 30.0, materialized = true), AdamsBashforth(order = 3),
                   FlowParameters(viscosity = 0.01, dissipation = 0.1, rms_velocity = 1, integral_scale = 1),
                   FlowParameters(viscosity = 0.01, dissipation = 0.1, rms_velocity = 1, integral_scale = 1,
                                  schmidt = 0.7, scalar_dissipation = 0.05),
                   Reference("Someone (2000)", (10.0, 100.0)), Li2008(0.6), Kolmogorov1941(2.1), Pope2000(C_K = 1.6),
                   SimulationRun.Clock(1.5, 3), SimulationRun.EveryTime(0.5, 1.0))
      rebuilt = eval(Meta.parse(repr(record)))
      @test typeof(rebuilt) === typeof(record)
      @test all(isequal(getfield(rebuilt, f), getfield(record, f)) for f in fieldnames(typeof(record)))
    end
    # The unset scalar dissipation is the keyword's default, so leaving it out round-trips to NaN.
    fp = FlowParameters(viscosity = 0.01, dissipation = 0.1, rms_velocity = 1, integral_scale = 1)
    @test !occursin("scalar_dissipation", repr(fp))
    @test isnan(eval(Meta.parse(repr(fp))).scalar_dissipation)
  end

  @testset "the REPL form carries what the compact one abbreviates" begin
    for sample in (domain, sim.state, sim.cache, sim.tracers, sim)
      @test occursin("\n", repl(sample))
    end
    # The domain's REPL form adds the resolved wavenumber; the cache's, each slot's standing.
    @test occursin("max_resolved_wavenumber", repl(domain))
    @test occursin("current", repl(sim.cache))
    @test occursin("0 of 2 past samples filled", repl(sim.cache))
    fields_modified!(sim.cache)
    @test_throws ErrorException velocity_physical(sim.cache)   # the read refuses …
    @test occursin("stale", repl(sim.cache))                     # … and the display says so, without reading
    deposit!(sim)
    @test !occursin("stale", repl(sim.cache))
    particles_modified!(sim.cache)
    @test occursin("tracer positions have advanced", repl(sim.cache))
    deposit!(sim)
    @test occursin("never deposited", repl(ObservablesCache(domain)))
  end

  @testset "nothing reads an element" begin
    # Every quantity is host-side metadata, so these are safe under `allowscalar(false)` and force no
    # synchronisation. Measured here on the host, where a read of a plain `Array` is invisible: the
    # standing guard is that a display allocates less than half the smallest field-scale array of
    # its run — a scalar field of N³ reals — so a copy of any field, or of the spectral
    # coefficients, cannot hide inside the string formatting a nested display legitimately spends.
    # The grid is larger than the rest of the file's so that the floor sits well above that noise,
    # and the tracer count is large enough that the particle arrays (``M \times 3`` reals, and the
    # history's copies of them) are ABOVE the floor too — a display copying the positions of a
    # dozen tracers would allocate a few hundred bytes and slip under a field-scale floor.
    n, m = 32, 20000
    big = Simulation(FixedDomain(grid_points_per_axis = n, side_length = 2π, element_type = Float64,
                                 dealiasing = PhaseShift(), array_type = Array);
                     viscosity = 0.05, scalar = true, number_of_particles = m,
                     particle_integration_scheme = AdamsBashforth(order = 3),
                     velocity_forcing = DeferredForcing(d -> ConstantPower(d; injection_rate = 0.1)),
                     scalar_forcing = DeferredForcing(d -> VarianceRescaling(d; target = 0.5, over = :band)))
    floor = n^3 * sizeof(Float64) ÷ 2
    @test m * 3 * sizeof(Float64) > floor   # the particle arrays are field-scale here, by construction
    for sample in (big.domain, big.state, big.cache, big.tracers, big.buffers, big.generator,
                   big.generator.conditions, big.particle_buffers, big.particle_traversal, big)
      show(IOBuffer(), sample)                       # warm up
      @test (@allocated show(IOBuffer(), sample)) < floor
      show(IOBuffer(), MIME"text/plain"(), sample)
      @test (@allocated show(IOBuffer(), MIME"text/plain"(), sample)) < floor
    end
  end

end

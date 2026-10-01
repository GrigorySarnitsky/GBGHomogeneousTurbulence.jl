# The temporary ledger — what each public operation allocates beyond what it keeps (decision 33's
# episode ledger, made derived, 2026-10-01).
#
# The episode ledger it replaces was a hand-written list of six episodes, and construction,
# checkpointing and every observable added after it were never on it: `FixedDomain`, the rate probe
# of a `Linear` generator and `read_simulation` each allocated a large multiple of a field and no
# ledger saw it. The required set is now the export list itself. Every exported function and
# concrete type is a row, built and called at three grid sizes; an in-place operation is the
# allocation audit's (`test/allocations.jl`), which bounds it below field scale, except `warmup!`,
# which that audit exempts and which is a row here. A new export fails until it has a row.
#
# A row measures the bytes a call allocates and subtracts what its result keeps — every array the
# result reaches, counted once by storage, apart from the arrays of the objects it was built from
# (the domain, the run) — leaving the call's TRANSIENT, in units of N³ reals. A row is either at
# field scale, with its frozen units held at every size, or below it, with its units falling as the
# grid grows. Rows not at field scale are the default, so an operation that starts allocating a
# field shows up as a row whose units stop falling.
using Test
using GBGHomogeneousTurbulence
using GBGPeriodicFields: CatmullRom
using HDF5
using Logging
using Random

include("audit_ops.jl")

const HT = GBGHomogeneousTurbulence
const SIZES = (16, 32, 64)
const PRINT_UNITS = get(ENV, "AUDIT_PRINT", "") == "1"


# ---------------------------------------------------------------- the measurement

# Every array reachable from `x` and not from any of `shared`, counted once by storage.
function _retained_bytes(x, shared)
  seen = Set{UInt}()
  everything = a -> true
  for s in shared
    collect_field_arrays!(AbstractArray[], s, seen, 0; keep = everything)
  end
  kept = collect_field_arrays!(AbstractArray[], x, seen, 0; keep = everything)
  return sum(sizeof, kept; init = 0)
end

quiet(f) = with_logger(f, NullLogger())

# The transient of one call, in N³ reals: allocated minus kept, measured on a warmed call.
function transient_units(call, shared, N)
  quiet(call); quiet(call)
  allocated = @allocated quiet(call)
  result = quiet(call)
  return (allocated - _retained_bytes(result, shared)) / (8 * N^3)
end


# ---------------------------------------------------------------- the context a row is built in

function context(N)
  domain = FixedDomain(grid_points_per_axis = N, side_length = 2π, dealiasing = TwoThirds(),
                       element_type = Float64, array_type = Array)
  sim = quiet(() -> Simulation(domain; viscosity = 0.05, scalar = true, number_of_particles = 8, unwrapped = true,
                               velocity_forcing = ConstantPower(domain; injection_rate = 0.1),
                               rng = MersenneTwister(1)))
  conditions = FlowConditions(viscosity = 0.05, schmidt = 1.0, velocity_forcing = NoForcing(),
                              scalar_forcing = NoForcing())
  path = tempname() * ".h5"
  h5open(f -> write_simulation(f, "run", sim), path, "w")
  return (; N, domain, sim, conditions, path, û = sim.state.velocity_spectral,
          φ̂ = sim.state.scalar_spectral)
end

# One builder per required name: given a context, the call to measure and the objects whose arrays
# the result may share. Rows for families (the strategies, the parameter records) build each member.
const ROWS = Dict{Symbol, Function}(
  # ---- the observables
  :kinetic_energy => c -> (() -> kinetic_energy(c.û), (c.sim,)),
  :dissipation => c -> (() -> dissipation(c.û, c.domain, 0.05), (c.sim,)),
  :kinetic_energy_and_dissipation => c -> (() -> kinetic_energy_and_dissipation(c.û, c.domain, 0.05), (c.sim,)),
  :kinetic_energy_and_dissipation_below_scale =>
    c -> (() -> kinetic_energy_and_dissipation_below_scale(c.û, c.domain, 0.05), (c.sim,)),
  :scalar_variance => c -> (() -> scalar_variance(c.φ̂), (c.sim,)),
  :scalar_dissipation => c -> (() -> scalar_dissipation(c.φ̂, c.domain, 0.05), (c.sim,)),
  :energy_spectrum => c -> (() -> energy_spectrum(c.û, c.domain), (c.sim,)),
  :integral_scale => c -> (() -> integral_scale(c.û, c.domain), (c.sim,)),
  :derivative_skewness => c -> (() -> derivative_skewness(c.û, c.domain), (c.sim,)),
  :max_speed => c -> (() -> max_speed(velocity_physical(c.sim.cache)), (c.sim,)),
  :flow_parameters => c -> (() -> flow_parameters(c.sim), (c.sim,)),
  :reynolds_box => c -> (() -> reynolds_box(2π, 0.1, 0.01), ()),
  :reynolds_taylor => c -> (() -> reynolds_taylor(1.5, 0.1, 0.01), ()),
  :kinetic_energy_in_box_units => c -> (() -> kinetic_energy_in_box_units(ConstantPower(); reynolds_box = 1000.0), ()),
  :band_energy_fraction => c -> (() -> band_energy_fraction(ConstantPower(); reynolds_box = 1000.0), ()),
  :predicted_stationary_state =>
    c -> (() -> predicted_stationary_state(c.domain; kinetic_energy = 1.5, viscosity = 0.05), (c.domain,)),
  :max_resolved_wavenumber => c -> (() -> max_resolved_wavenumber(c.domain), (c.domain,)),
  :max_retained_wavenumber => c -> (() -> max_retained_wavenumber(c.domain), (c.domain,)),
  :recommended_cfl => c -> (() -> recommended_cfl(IFLowStorageRK3(), c.domain), (c.domain,)),
  :velocity_integrating_factor => c -> (() -> velocity_integrating_factor(c.sim.generator, 0.01), (c.sim,)),
  :scalar_integrating_factor => c -> (() -> scalar_integrating_factor(c.sim.generator, 0.01), (c.sim,)),
  # ---- the run's clock, cadence and readouts
  :current_step => c -> (() -> current_step(c.sim), (c.sim,)),
  :current_time => c -> (() -> current_time(c.sim), (c.sim,)),
  :every_steps => c -> (() -> every_steps(3), ()),
  :every_time => c -> (() -> every_time(0.1), ()),
  :velocity_physical => c -> (() -> velocity_physical(c.sim.cache), (c.sim,)),
  :vorticity_physical => c -> (() -> vorticity_physical(c.sim.cache), (c.sim,)),
  :scalar_physical => c -> (() -> scalar_physical(c.sim.cache), (c.sim,)),
  :velocity_at_particles => c -> (() -> velocity_at_particles(c.sim.cache), (c.sim,)),
  :unwrapped_positions => c -> (() -> unwrapped_positions(c.sim.tracers), (c.sim,)),
  :history_depth => c -> (() -> history_depth(AdamsBashforth(order = 3)), ()),
  :uses_steady_linear_rate => c -> (() -> uses_steady_linear_rate(Linear(c.domain; rate = 0.1)), (c.domain,)),
  :initial_forcing_state =>
    c -> (() -> initial_forcing_state(c.sim.generator.conditions.velocity_forcing, c.û, c.domain), (c.sim,)),
  # ---- the allocators: their allocation IS the result, so the transient is zero
  :new_scalar_field_physical => c -> (() -> new_scalar_field_physical(c.domain), (c.domain,)),
  :new_scalar_field_spectral => c -> (() -> new_scalar_field_spectral(c.domain), (c.domain,)),
  :new_vector_field_physical => c -> (() -> new_vector_field_physical(c.domain), (c.domain,)),
  :new_vector_field_spectral => c -> (() -> new_vector_field_spectral(c.domain), (c.domain,)),
  :new_tensor_field_physical => c -> (() -> new_tensor_field_physical(c.domain), (c.domain,)),
  :new_tensor_field_spectral => c -> (() -> new_tensor_field_spectral(c.domain), (c.domain,)),
  :new_scalar_point_values => c -> (() -> new_scalar_point_values(c.sim.tracers), (c.sim,)),
  :new_vector_point_values => c -> (() -> new_vector_point_values(c.sim.tracers), (c.sim,)),
  :allocate_buffers => c -> (() -> allocate_buffers(IFLowStorageRK3(), c.domain; scalar = true), (c.domain,)),
  # ---- the constructors
  :FixedDomain => c -> (() -> FixedDomain(grid_points_per_axis = c.N, side_length = 2π, dealiasing = TwoThirds(),
                                          element_type = Float64, array_type = Array), ()),
  :Simulation => c -> (() -> Simulation(c.domain; viscosity = 0.05, rng = MersenneTwister(1)), (c.domain,)),
  :ResolvedGenerator => c -> (() -> ResolvedGenerator(c.domain, c.conditions; scalar = true), (c.domain,)),
  :ResolvedFields => c -> (() -> ResolvedFields(c.domain; scalar = true), (c.domain,)),
  :ObservablesCache => c -> (() -> ObservablesCache(c.domain; scalar = true), (c.domain,)),
  :IntegratorBuffers => c -> (() -> allocate_buffers(IFLowStorageRK3(), c.domain), (c.domain,)),
  :ParticleIntegratorBuffers => c -> (() -> allocate_buffers(Heun(), c.sim.tracers, c.sim.cache), (c.sim,)),
  :Tracers => c -> (() -> Tracers(c.domain; number_of_particles = 8, interpolation_scheme = CatmullRom,
                                  rng = MersenneTwister(1)), (c.domain,)),
  :ParticleTraversal => c -> (() -> ParticleTraversal(c.domain, c.sim.tracers), (c.sim,)),
  :FlowConditions => c -> (() -> FlowConditions(viscosity = 0.05, schmidt = 1.0, velocity_forcing = NoForcing(),
                                                  scalar_forcing = NoForcing()), ()),
  :StationarityCriterion => c -> (() -> StationarityCriterion(), ()),
  :DeferredForcing => c -> (() -> ConstantPower(), ()),
  :StochasticOUState => c -> (() -> initial_forcing_state(
      StochasticOU(c.domain; forcing_variance = 0.1, correlation_time = 0.5, seed = 1), c.û, c.domain), (c.sim,)),
  # the parameter records and the strategies, each member built
  :TwoThirds => c -> (() -> TwoThirds(), ()), :HouLi => c -> (() -> HouLi(), ()),
  :PhaseShift => c -> (() -> PhaseShift(), ()),
  :IFLowStorageRK3 => c -> (() -> IFLowStorageRK3(), ()), :IFLowStorageRK4 => c -> (() -> IFLowStorageRK4(), ()),
  :IFSSPRK3 => c -> (() -> IFSSPRK3(), ()), :IFHeun => c -> (() -> IFHeun(), ()),
  :Heun => c -> (() -> Heun(), ()), :AdamsBashforth => c -> (() -> AdamsBashforth(order = 3), ()),
  :NoForcing => c -> (() -> NoForcing(), ()),
  :ConstantPower => c -> (() -> ConstantPower(c.domain; injection_rate = 0.1), (c.domain,)),
  :VarianceController => c -> (() -> VarianceController(c.domain; target = 1.5), (c.domain,)),
  :VarianceRescaling => c -> (() -> VarianceRescaling(c.domain; target = 1.5, over = :total), (c.domain,)),
  :Linear => c -> (() -> Linear(c.domain; rate = 0.1), (c.domain,)),
  :StochasticOU => c -> (() -> StochasticOU(c.domain; forcing_variance = 0.1, correlation_time = 0.5, seed = 1),
                         (c.domain,)),
  # ---- variants a single row would miss: what a forcing, a scalar, tracers or a wide band add
  Symbol("ResolvedGenerator/Linear") => c -> (() -> ResolvedGenerator(c.domain, FlowConditions(viscosity = 0.05,
      schmidt = 1.0, velocity_forcing = Linear(c.domain; rate = 0.1), scalar_forcing = NoForcing()); scalar = true),
    (c.domain,)),
  Symbol("Simulation/scalar and tracers") => c -> (() -> Simulation(c.domain; viscosity = 0.05, scalar = true,
      number_of_particles = 8, rng = MersenneTwister(1)), (c.domain,)),
  Symbol("StochasticOU/wide band") => c -> (() -> StochasticOU(c.domain; forcing_variance = 0.1,
      correlation_time = 0.5, seed = 1, highest_shell = 4), (c.domain,)),
  Symbol("ParticleIntegratorBuffers/AdamsBashforth") => c -> (() -> allocate_buffers(AdamsBashforth(order = 3),
      c.sim.tracers, ObservablesCache(c.domain; number_of_particles = 8, history_depth = 3)), (c.sim,)),
  # ---- checkpointing
  :write_simulation => c -> (() -> h5open(f -> write_simulation(f, "s", c.sim), tempname(), "w"), (c.sim,)),
  :read_simulation => c -> (() -> h5open(f -> read_simulation(f, "run"), c.path, "r"), ()),
  :write_domain => c -> (() -> h5open(f -> write_domain(f, "d", c.domain), tempname(), "w"), (c.domain,)),
  :read_domain => c -> (() -> h5open(f -> read_domain(f, "run/domain"), c.path, "r"), ()),
  :write_state => c -> (() -> h5open(f -> write_state(f, "s", c.sim.state), tempname(), "w"), (c.sim,)),
  :read_state => c -> (() -> h5open(f -> read_state(f, "run/state", c.domain), c.path, "r"), (c.domain,)),
  :write_tracers => c -> (() -> h5open(f -> write_tracers(f, "t", c.sim.tracers), tempname(), "w"), (c.sim,)),
  :read_tracers => c -> (() -> h5open(f -> read_tracers(f, "run/tracers", c.domain), c.path, "r"), (c.domain,)),
  :write_forcing => c -> (() -> h5open(f -> write_forcing(f, "f", c.sim.generator.conditions.velocity_forcing),
                                       tempname(), "w"), (c.sim,)),
  :read_forcing => c -> (() -> h5open(f -> read_forcing(f, "run/velocity_forcing", c.domain), c.path, "r"),
                         (c.domain,)),
  # ---- the run loop: the allocation audit's exemption
  :warmup! => c -> (() -> warmup!(deepcopy(c.sim); max_turnovers = 0.01), (c.sim,)),
)

# The rows the allocation audit owns: every in-place operation but `warmup!`.
in_place_owned(n) = endswith(String(n), "!") && n !== :warmup!


# The field-scale rows, each frozen at the largest size in N³ reals and claimed by a holder of the one
# register (audit_ops.jl). A row is below field scale when its units at the largest size are small or
# fall at least twofold from the middle size — a field-scale cost stays flat in these units — and
# every other row must be listed here; a listed row that has fallen below field scale fails too.
const FIELD_SCALE_ROWS = Dict(
  :read_simulation => (24.1, RESTORE_REBUILDS_A_SEEDED_RUN),
  :derivative_skewness => (18.3, FULL_STRAIN_TENSORS),
  :FixedDomain => (11.2, DOMAIN_CONSTRUCTION_TEMPLATES),
  :read_domain => (11.2, DOMAIN_CONSTRUCTION_TEMPLATES),
  :Simulation => (6.0, SEEDING_DOUBLE_DRAW),
  Symbol("Simulation/scalar and tracers") => (8.0, SEEDING_DOUBLE_DRAW),
  Symbol("ResolvedGenerator/Linear") => (4.3, RATE_PROBE),
  :write_simulation => (4.1, CHECKPOINT_STAGING_COPY),
  :write_state => (4.1, CHECKPOINT_STAGING_COPY),
  :read_state => (4.1, CHECKPOINT_STAGING_COPY),
)
const FROZEN_TOLERANCE = 0.3          # N³ reals at the largest size
below_field_scale(u) = u[end] < 0.05 || u[end - 1] >= 2 * u[end]

@testset "temporary ledger: every public operation, at three grid sizes" begin
  required = Set{Symbol}()
  for n in names(HT)
    n === :GBGHomogeneousTurbulence && continue
    x = getfield(HT, n)
    if x isa Type
      isabstracttype(x) || push!(required, n)
    elseif x isa Function
      in_place_owned(n) || push!(required, n)
    end
  end
  @testset "the required set is the export list" begin
    base(name) = Symbol(first(split(String(name), "/")))
    @test isempty(setdiff(required, keys(ROWS)))                # a new export fails until it has a row
    @test isempty(setdiff(Set(base.(keys(ROWS))), required))    # a row names a real export
  end

  units = Dict{Symbol, Vector{Float64}}()
  failures = Dict{Symbol, String}()
  for N in SIZES
    c = context(N)
    for (name, build) in ROWS
      haskey(failures, name) && continue
      try
        call, shared = build(c)
        push!(get!(units, name, Float64[]), transient_units(call, shared, N))
      catch e
        failures[name] = sprint(showerror, e)[1:min(end, 200)]
      end
    end
  end
  for (name, message) in failures
    @error "temporary ledger: the $name row did not run" message
  end
  @test isempty(failures)
  @testset "every field-scale row is listed, and every listed row is at field scale" begin
    for (name, u) in units
      if below_field_scale(u)
        @test !haskey(FIELD_SCALE_ROWS, name)              # else retire its entry
      else
        @test haskey(FIELD_SCALE_ROWS, name)               # an unlisted field-scale temporary
        haskey(FIELD_SCALE_ROWS, name) || @error "temporary ledger: $name allocates $(round(u[end]; digits = 2)) N³ reals and no holder claims it"
      end
    end
    for (name, (frozen, holder)) in FIELD_SCALE_ROWS
      @test holder in ALL_HOLDERS
      haskey(units, name) && @test abs(units[name][end] - frozen) <= FROZEN_TOLERANCE
    end
    # The skewness stays the largest temporary an observable takes — the run-phase peak an opted-in
    # warm-up pays (the stationarity gate is off by default).
    observables = (:kinetic_energy, :dissipation, :kinetic_energy_and_dissipation, :energy_spectrum,
                   :integral_scale, :flow_parameters, :scalar_variance, :scalar_dissipation,
                   :kinetic_energy_and_dissipation_below_scale, :max_speed, :derivative_skewness)
    @test argmax(n -> units[n][end], observables) === :derivative_skewness
  end

  @testset "the ledger catches what it exists to catch" begin
    # Planted: a constructor that allocates an unused field-sized local, the shape of the real
    # `velocity_physical`, keeping only a small result — measured exactly as a row is, it must read
    # as field scale, so an unlisted one fails the check above.
    wasteful(N) = (scratch = zeros(N, N, N); scratch[1] = 1.0; (; total = sum(scratch)))
    planted = [transient_units(() -> wasteful(N), (), N) for N in SIZES]
    @test !below_field_scale(planted)
    @test planted[end] ≈ 1.0 atol = 0.05
    # …and a constant-size allocation, however large at the smallest size, reads below it.
    fixed = [transient_units(() -> (zeros(4096); nothing), (), N) for N in SIZES]
    @test below_field_scale(fixed)
  end

  if PRINT_UNITS
    for name in sort(collect(keys(units)); by = n -> -last(units[n]))
      println(rpad(String(name), 46), join((rpad(string(round(u; digits = 3)), 9) for u in units[name])))
    end
  end
end

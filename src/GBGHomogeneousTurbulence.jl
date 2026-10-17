# GBGHomogeneousTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package is a small, focused pseudospectral DNS of homogeneous isotropic turbulence —
# a velocity field plus a single passive scalar on a periodic box — built on GBGPeriodicFields,
# which supplies every field operation (transforms, differential operators, convolution, interpolation,
# reductions). GBGPeriodicFields is deliberately time- and particle-free (its invariant 12); this
# package is the consumer that owns time integration, forcing, the scalar transport, and particle
# tracking. Accumulating statistics over what it produces is the caller's analysis, not this
# package's. GPU is the primary target, so the time loop is in-place and
# allocation-free over preallocated buffers.
#
# Module layout (each concern its own file). Physics concerns take their names from the Mori–Zwanzig
# lens — the four roles State / Generator / Observables / Propagator; the System's forcing, the frame,
# the instruments and the run layer are named by their job.
#   SimulationDomain — the frame: the `FixedDomain` box (transform plans, multipliers, dealias kernel)
#   Observables      — the measured functions of state (energy, dissipation, skewness, …), including
#                      the field-valued vorticity recovery. Ahead of `State` because the seeders
#                      rescale to a requested energy or variance and call these reductions to do it,
#                      rather than carrying a second spelling of the same formula.
#   State            — the spectral state + initial conditions (the MZ State role)
#   Cache            — the ObservablesCache: the storage the iteration deposits its
#                      observables into at its end (no-recompute; slots double as the step's registers)
#   Forcing          — energy-injection strategies (AbstractForcing) — the RHS source. Included BEFORE
#                      Generator: decision 23(a) earned the Generator → Forcing edge, so Forcing's
#                      types must exist first.
#   Generator        — the Navier–Stokes RHS (rotational form) + scalar advection + integrating factor,
#                      gathered into ResolvedGenerator (FlowConditions + assembly scratch + the protocol
#                      prepare!/velocity_rhs!/scalar_rhs!/velocity_integrating_factor/scalar_integrating_factor/finalize!)
#   Propagator       — integrating-factor schemes (AbstractIntegrator) — the time map
#   Particles        — Lagrangian tracer tracking (instruments)
#   SimulationRun    — the ergonomic run layer (Simulation + run!/warmup!/advance!)


"""
    GBGHomogeneousTurbulence

Tools for simulating homogeneous isotropic turbulence on three-dimensional periodic domains: a
velocity field and a single passive scalar, each optionally forced, sampled along particle
trajectories. It has these submodules:

- [`SimulationDomain`](@ref GBGHomogeneousTurbulence.SimulationDomain) — the discretized box.

- [`State`](@ref GBGHomogeneousTurbulence.State) — the evolving fields.

- [`Observables`](@ref GBGHomogeneousTurbulence.Observables) — the measured quantities.

- [`Cache`](@ref GBGHomogeneousTurbulence.Cache) — the observables cache.

- [`Forcing`](@ref GBGHomogeneousTurbulence.Forcing) — the energy-injection strategies.

- [`Generator`](@ref GBGHomogeneousTurbulence.Generator) — the equations of motion.

- [`Propagator`](@ref GBGHomogeneousTurbulence.Propagator) — the integrating-factor time-steppers.

- [`Particles`](@ref GBGHomogeneousTurbulence.Particles) — the Lagrangian tracers.

- [`SimulationRun`](@ref GBGHomogeneousTurbulence.SimulationRun) — the run layer, checkpointing
  ([`write_simulation`](@ref GBGHomogeneousTurbulence.SimulationRun.write_simulation)) once `HDF5` is loaded.

Statistics over the flow and its samples are the caller's analysis:
[`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl) supplies the field
reductions, [`GBGStreamingStatistics`](https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl/)
the online estimators.

The `GBG` in the name is Göteborg (Gothenburg, Sweden), its birthplace.
"""
module GBGHomogeneousTurbulence

using GBGPeriodicFields


include("SimulationDomain.jl")
include("Observables.jl")
include("State.jl")
include("Cache.jl")
include("Forcing.jl")
include("Generator.jl")
include("Propagator.jl")
include("Particles.jl")
include("SimulationRun.jl")


using .SimulationDomain:
  FixedDomain,
  new_vector_field_spectral,
  new_vector_field_physical,
  new_scalar_field_spectral,
  new_scalar_field_physical,
  new_tensor_field_spectral,
  new_tensor_field_physical,
  truncate_to_band!,
  DealiasingStrategy,
  TwoThirds,
  HouLi,
  PhaseShift,
  max_retained_wavenumber,
  max_resolved_wavenumber

using .State:
  ResolvedFields,
  random_solenoidal_velocity_spectral!,
  random_scalar_spectral!

using .Cache:
  ObservablesCache,
  velocity_physical,
  vorticity_physical,
  scalar_physical,
  velocity_at_particles,
  fields_modified!,
  particles_modified!

using .Generator:
  FlowConditions,
  ResolvedGenerator,
  prepare!,
  velocity_rhs!,
  scalar_rhs!,
  velocity_integrating_factor,
  scalar_integrating_factor,
  finalize!

using .Observables:
  kinetic_energy,
  dissipation,
  kinetic_energy_and_dissipation,
  kinetic_energy_and_dissipation_below_scale,
  reynolds_box,
  reynolds_taylor,
  taylor_length,
  kolmogorov_length,
  kolmogorov_time,
  kolmogorov_velocity,
  max_speed,
  vorticity_physical!,
  scalar_variance,
  scalar_dissipation,
  scalar_variance_and_dissipation,
  derivative_skewness,
  energy_spectrum,
  integral_length

using .Forcing:
  AbstractForcing,
  DeferredForcing,
  NoForcing,
  VarianceRescaling,
  VarianceController,
  Linear,
  ConstantPower,
  StochasticOU,
  StochasticOUState,
  steady_linear_rate,
  project_forcing!,
  initial_forcing_state,
  prepare_forcing!,
  add_forcing_source!,
  kinetic_energy_in_box_units,
  band_energy_fraction

using .Propagator:
  AbstractIntegrator,
  IFHeun,
  IFLowStorageRK3,
  IFSSPRK3,
  IFLowStorageRK4,
  IntegratorBuffers,
  allocate_buffers,
  step!,
  deposit!,
  recommended_cfl

using .Particles:
  Tracers,
  AbstractParticleIntegrator,
  Heun,
  AdamsBashforth,
  ParticleIntegratorBuffers,
  ParticleTraversal,
  rebuild_traversal!,
  restart!,
  history_depth,
  advect!,
  interpolate_at_particles!,
  unwrapped_positions,
  new_vector_point_values,
  new_scalar_point_values

using .SimulationRun:
  Simulation,
  PassiveScalar,
  ParticleTracking,
  advance!,
  run!,
  warmup!,
  StationarityCriterion,
  current_time,
  current_step,
  every_steps,
  every_time,
  predicted_stationary_state


export FixedDomain,
       ResolvedFields,
       ObservablesCache,
       velocity_physical,
       vorticity_physical,
       scalar_physical,
       velocity_at_particles,
       fields_modified!,
       particles_modified!,
       new_vector_field_spectral,
       new_vector_field_physical,
       new_scalar_field_spectral,
       new_scalar_field_physical,
       new_tensor_field_spectral,
       new_tensor_field_physical,
       random_solenoidal_velocity_spectral!,
       random_scalar_spectral!,
       truncate_to_band!,
       DealiasingStrategy,
       TwoThirds,
       HouLi,
       PhaseShift,
       max_retained_wavenumber,
       max_resolved_wavenumber,
       vorticity_physical!,
       ResolvedGenerator,
       prepare!,
       velocity_rhs!,
       scalar_rhs!,
       velocity_integrating_factor,
       scalar_integrating_factor,
       finalize!,
       kinetic_energy,
       dissipation,
       kinetic_energy_and_dissipation,
       kinetic_energy_and_dissipation_below_scale,
       reynolds_box,
       reynolds_taylor,
       taylor_length,
       kolmogorov_length,
       kolmogorov_time,
       kolmogorov_velocity,
       max_speed,
       scalar_variance,
       scalar_dissipation,
       scalar_variance_and_dissipation,
       derivative_skewness,
       energy_spectrum,
       integral_length,
       AbstractForcing,
       DeferredForcing,
       NoForcing,
       VarianceRescaling,
       VarianceController,
       Linear,
       ConstantPower,
       StochasticOU,
       StochasticOUState,
       steady_linear_rate,
       project_forcing!,
       initial_forcing_state,
       prepare_forcing!,
       add_forcing_source!,
       kinetic_energy_in_box_units,
       band_energy_fraction,
       AbstractIntegrator,
       IFHeun,
       IFLowStorageRK3,
       IFSSPRK3,
       IFLowStorageRK4,
       IntegratorBuffers,
       allocate_buffers,
       step!,
       deposit!,
       recommended_cfl,
       FlowConditions,
       Tracers,
       AbstractParticleIntegrator,
       Heun,
       AdamsBashforth,
       ParticleIntegratorBuffers,
       ParticleTraversal,
       rebuild_traversal!,
       advect!,
       restart!,
       history_depth,
       interpolate_at_particles!,
       unwrapped_positions,
       new_vector_point_values,
       new_scalar_point_values,
       Simulation,
       PassiveScalar,
       ParticleTracking,
       advance!,
       run!,
       warmup!,
       StationarityCriterion,
       every_steps,
       every_time,
       predicted_stationary_state,
       current_time,
       current_step



# The HDF5 persistence pairs (methods in the `GBGHomogeneousTurbulenceHDF5Ext` weak-dependency
# extension, loaded alongside the HDF5 package).
using .SimulationDomain: write_domain, read_domain
using .State: write_state, read_state
using .Particles: write_tracers, read_tracers
using .Forcing: write_forcing, read_forcing
using .SimulationRun: write_simulation, read_simulation
export write_domain, read_domain, write_state, read_state, write_tracers, read_tracers,
       write_forcing, read_forcing, write_simulation, read_simulation

end # module GBGHomogeneousTurbulence

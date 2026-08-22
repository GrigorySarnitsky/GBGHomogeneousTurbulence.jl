# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
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
# the instruments, the run layer, and the reference laws are named by their job.
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
    GBGIsotropicTurbulence

Tools for simulating homogeneous isotropic turbulence on three-dimensional periodic
domains: a velocity field and a single passive scalar, each optionally forced, advanced by a choice
of integrating-factor time-stepping scheme, with Lagrangian particle tracking and field sampling.

The package produces the flow and the values sampled from it; accumulating statistics over them is
the caller's own analysis, for which the two sibling packages supply the tools —
[`GBGPeriodicFields`](https://grigorysarnitsky.github.io/GBGPeriodicFields.jl) the field reductions
and [`GBGStreamingStatistics`](https://github.com/GrigorySarnitsky/GBGStreamingStatistics.jl) the
online estimators.

Built on `GBGPeriodicFields`.

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.
"""
module GBGIsotropicTurbulence

using GBGPeriodicFields


# Phenomenology leads as the dependency-light, extraction-bound leaf (ARCHITECTURE §4.8): it is
# deliberately NOT re-exported below — reach the reference laws opt-in through the submodule namespace,
# e.g. `using GBGIsotropicTurbulence.Phenomenology.Spectra`.
include("Phenomenology.jl")

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
  max_wavenumber

using .State:
  ResolvedFields,
  random_solenoidal_velocity_spectral!,
  random_scalar_spectral!

using .Cache:
  ObservablesCache,
  velocity_physical,
  vorticity_physical,
  scalar_physical,
  particle_velocities,
  fields_modified!,
  particles_modified!,
  deposit_sample!

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
  max_speed,
  vorticity_physical!,
  scalar_variance,
  scalar_dissipation,
  derivative_skewness,
  energy_spectrum,
  integral_scale

using .Forcing:
  AbstractForcing,
  DeferredForcing,
  NoForcing,
  VarianceRescaling,
  VarianceController,
  Linear,
  ConstantPower,
  set_forcing_rate!,
  uses_steady_linear_rate,
  project_forcing!,
  prepare_forcing!,
  add_forcing_source!

using .Propagator:
  AbstractIntegrator,
  IFRK2,
  IFLowStorageRK3,
  IntegratorBuffers,
  allocate_buffers,
  step!,
  deposit!,
  recommended_cfl

using .Particles:
  Tracers,
  AbstractParticleIntegrator,
  EndpointHeun,
  AdamsBashforth,
  MultistepBuffers,
  ParticleIntegratorBuffers,
  record_particle_velocities!,
  restart!,
  history_depth,
  advect!,
  interpolate_at_particles!,
  particle_positions,
  number_of_particles,
  new_vector_point_values,
  new_scalar_point_values

using .SimulationRun:
  Simulation,
  advance!,
  run!,
  warmup!,
  StationarityCriterion,
  current_time,
  current_step,
  flow_parameters


export FixedDomain,
       ResolvedFields,
       ObservablesCache,
       velocity_physical,
       vorticity_physical,
       scalar_physical,
       particle_velocities,
       fields_modified!,
       particles_modified!,
       deposit_sample!,
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
       max_wavenumber,
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
       max_speed,
       scalar_variance,
       scalar_dissipation,
       derivative_skewness,
       energy_spectrum,
       integral_scale,
       AbstractForcing,
       DeferredForcing,
       NoForcing,
       VarianceRescaling,
       VarianceController,
       Linear,
       ConstantPower,
       set_forcing_rate!,
       uses_steady_linear_rate,
       project_forcing!,
       prepare_forcing!,
       add_forcing_source!,
       AbstractIntegrator,
       IFRK2,
       IFLowStorageRK3,
       IntegratorBuffers,
       allocate_buffers,
       step!,
       deposit!,
       recommended_cfl,
       FlowConditions,
       Tracers,
       AbstractParticleIntegrator,
       EndpointHeun,
       AdamsBashforth,
       MultistepBuffers,
       ParticleIntegratorBuffers,
       record_particle_velocities!,
       advect!,
       restart!,
       history_depth,
       interpolate_at_particles!,
       particle_positions,
       number_of_particles,
       new_vector_point_values,
       new_scalar_point_values,
       Simulation,
       advance!,
       run!,
       warmup!,
       StationarityCriterion,
       current_time,
       current_step,
       flow_parameters


end # module GBGIsotropicTurbulence

# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package is a small, focused pseudospectral DNS of homogeneous isotropic turbulence —
# a velocity field plus a single passive scalar on a periodic box — built on GBGPeriodicFields,
# which supplies every field operation (transforms, differential operators, convolution, interpolation,
# reductions). GBGPeriodicFields is deliberately time- and particle-free (its invariant 12); this
# package is the consumer that owns time integration, forcing, the scalar transport, particle
# tracking, and the statistics. GPU is the primary target, so the time loop is in-place and
# allocation-free over preallocated buffers.
#
# Module layout (each concern its own file). Physics concerns take their names from the Mori–Zwanzig
# lens — the four roles State / Generator / Observables / Propagator; the System's forcing, the frame,
# the instruments, the run layer, and the reference laws are named by their job.
#   SimulationDomain — the frame: the `FixedDomain` box (transform plans, multipliers, dealias kernel)
#   State            — the spectral state + initial conditions (the MZ State role)
#   Observables      — the measured functions of state (energy, dissipation, skewness, …), including
#                      the field-valued vorticity recovery
#   Cache            — the ObservablesCache: the stamped storage the iteration deposits its
#                      observables into at its end (no-recompute; slots double as the step's registers)
#   Generator        — the Navier–Stokes RHS (rotational form) + scalar advection + integrating factor,
#                      reified as ResolvedGenerator (FlowConditions + assembly scratch + the protocol
#                      prepare!/velocity_rhs!/scalar_rhs!/velocity_factor/scalar_factor/finalize!)
#   Forcing          — energy-injection strategies (AbstractForcing) — the RHS source
#   Propagator       — integrating-factor schemes (AbstractIntegrator) — the time map
#   Particles        — Lagrangian tracer tracking (instruments)
#   SimulationRun    — the ergonomic run layer (Simulation + run!/warmup!/advance!)


"""
    GBGIsotropicTurbulence

Tools for simulating and analyzing homogeneous isotropic turbulence on three-dimensional periodic
domains: a velocity field and a single passive scalar, each optionally forced, advanced by a choice
of integrating-factor time-stepping scheme, with Lagrangian particle tracking and field sampling for
the forthcoming Eulerian + Lagrangian statistics.

Built on [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl).

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
include("State.jl")
include("Observables.jl")
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
  dealias!,
  DealiasingStrategy,
  TwoThirds,
  HouLi,
  PhaseShift,
  max_wavenumber

using .State:
  ResolvedFields,
  random_solenoidal_velocity!,
  random_scalar!

using .Cache:
  ObservablesCache,
  velocity_physical,
  vorticity_physical,
  scalar_physical,
  particle_velocities,
  resolved_fields_modified!

using .Generator:
  FlowConditions,
  ResolvedGenerator,
  prepare!,
  velocity_rhs!,
  scalar_rhs!,
  velocity_factor,
  scalar_factor,
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
  BandRescaling,
  Linear,
  ConstantPower,
  set_forcing_rate!,
  uses_linear_rate,
  apply_forcing!,
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
  record_trajectory_velocity!,
  advect!,
  sample!,
  particle_positions,
  number_of_tracers,
  velocity_buffer,
  scalar_buffer

using .SimulationRun:
  Simulation,
  advance!,
  run!,
  warmup!,
  StationarityCriterion,
  velocity_spectral,
  scalar_spectral,
  current_time,
  current_step,
  flow_parameters,
  validate_spectrum


export FixedDomain,
       ResolvedFields,
       ObservablesCache,
       velocity_physical,
       vorticity_physical,
       scalar_physical,
       particle_velocities,
       resolved_fields_modified!,
       new_vector_field_spectral,
       new_vector_field_physical,
       new_scalar_field_spectral,
       new_scalar_field_physical,
       new_tensor_field_spectral,
       new_tensor_field_physical,
       random_solenoidal_velocity!,
       random_scalar!,
       dealias!,
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
       velocity_factor,
       scalar_factor,
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
       BandRescaling,
       Linear,
       ConstantPower,
       set_forcing_rate!,
       uses_linear_rate,
       apply_forcing!,
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
       record_trajectory_velocity!,
       advect!,
       sample!,
       particle_positions,
       number_of_tracers,
       velocity_buffer,
       scalar_buffer,
       Simulation,
       advance!,
       run!,
       warmup!,
       StationarityCriterion,
       velocity_spectral,
       scalar_spectral,
       current_time,
       current_step,
       flow_parameters,
       validate_spectrum


end # module GBGIsotropicTurbulence

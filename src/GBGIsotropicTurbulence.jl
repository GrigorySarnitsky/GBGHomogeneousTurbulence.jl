# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package is a small, focused pseudospectral DNS of homogeneous isotropic turbulence —
# a velocity field plus a single passive scalar on a periodic box — built on GBGPeriodicFields,
# which supplies every field operation (transforms, spectral operators, convolution, interpolation,
# reductions). GBGPeriodicFields is deliberately time- and particle-free (its invariant 12); this
# package is the consumer that owns time integration, forcing, the scalar transport, particle
# tracking, and the statistics. GPU is the primary target, so the time loop is in-place and
# allocation-free over a preallocated buffers.
#
# Module layout (each concern its own file). Physics concerns take their names from the Mori–Zwanzig
# lens — the four roles State / Generator / Observables / Propagator; the System's forcing, the frame,
# the instruments, the run layer, and the reference laws are named by their job.
#   SimulationDomain — the frame: the `FixedDomain` box (transform plans, multipliers, dealias kernel)
#   State            — the field buffers + initial conditions (the MZ State role)
#   Generator        — the Navier–Stokes RHS (rotational form) + scalar advection + integrating factor;
#                      holds FlowConditions (ν, Sc, the forcings) — the physical conditions it is built from
#   Observables      — the measured functions of state (energy, dissipation, skewness, …)
#   Forcing          — energy-injection strategies (AbstractForcing) — the RHS source
#   Propagator       — integrating-factor schemes (AbstractIntegrator) — the time map
#   Particles        — Lagrangian tracer tracking (instruments)
#   SimulationRun    — the ergonomic run layer (Simulation + run!/warmup!/advance!)


"""
    GBGIsotropicTurbulence

Tools for simulating and analysing homogeneous isotropic turbulence on three-dimensional periodic
domains: a velocity field and a single passive scalar, each optionally forced, advanced by a choice
of integrating-factor time-stepping scheme, with Lagrangian particle tracking and Eulerian +
Lagrangian statistics.

Built on [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl).

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.
"""
module GBGIsotropicTurbulence

using GBGPeriodicFields


# Phenomenology leads as the dependency-light, extraction-bound leaf (ARCHITECTURE §4.7): it is
# deliberately NOT re-exported below — reach the reference laws opt-in through the submodule namespace,
# e.g. `using GBGIsotropicTurbulence.Phenomenology.Spectra`.
include("Phenomenology.jl")

include("SimulationDomain.jl")
include("State.jl")
include("Forcing.jl")
include("Generator.jl")
include("Observables.jl")
include("Propagator.jl")
include("Particles.jl")
include("SimulationRun.jl")


using .SimulationDomain:
  FixedDomain,
  spectral_vector,
  physical_vector,
  scalar_spectral,
  scalar_physical,
  tensor_spectral,
  tensor_physical,
  dealias!,
  DealiasingStrategy,
  TwoThirds,
  HouLi,
  max_wavenumber

using .State:
  FieldBuffers,
  random_solenoidal_velocity!,
  random_scalar!

using .Generator:
  velocity_vorticity!,
  velocity_nonlinear!,
  integrating_factor!,
  scalar_to_physical!,
  scalar_nonlinear!,
  FlowConditions

using .Observables:
  kinetic_energy,
  dissipation,
  max_speed,
  scalar_variance,
  scalar_dissipation,
  derivative_skewness,
  energy_spectrum,
  integral_scale

using .Forcing:
  AbstractForcing,
  ForcingSpec,
  NoForcing,
  BandRescaling,
  Linear,
  ConstantPower,
  set_forcing_rate!,
  apply_forcing!,
  prepare_forcing!,
  add_forcing_source!

using .Propagator:
  AbstractIntegrator,
  IFRK2,
  IFLowStorageRK3,
  step!,
  recommended_cfl,
  default_integrator

using .Particles:
  Tracers,
  advect!,
  sample!,
  tracer_positions,
  tracer_velocities,
  ntracers,
  velocity_buffer,
  scalar_buffer

using .SimulationRun:
  Simulation,
  advance!,
  run!,
  warmup!,
  current_time,
  current_step,
  flow_parameters,
  validate_spectrum


export FixedDomain,
       FieldBuffers,
       spectral_vector,
       physical_vector,
       scalar_spectral,
       scalar_physical,
       tensor_spectral,
       tensor_physical,
       random_solenoidal_velocity!,
       random_scalar!,
       dealias!,
       DealiasingStrategy,
       TwoThirds,
       HouLi,
       max_wavenumber,
       velocity_vorticity!,
       velocity_nonlinear!,
       integrating_factor!,
       scalar_to_physical!,
       scalar_nonlinear!,
       kinetic_energy,
       dissipation,
       max_speed,
       scalar_variance,
       scalar_dissipation,
       derivative_skewness,
       energy_spectrum,
       integral_scale,
       AbstractForcing,
       ForcingSpec,
       NoForcing,
       BandRescaling,
       Linear,
       ConstantPower,
       set_forcing_rate!,
       apply_forcing!,
       prepare_forcing!,
       add_forcing_source!,
       AbstractIntegrator,
       IFRK2,
       IFLowStorageRK3,
       step!,
       recommended_cfl,
       default_integrator,
       FlowConditions,
       Tracers,
       advect!,
       sample!,
       tracer_positions,
       tracer_velocities,
       ntracers,
       velocity_buffer,
       scalar_buffer,
       Simulation,
       advance!,
       run!,
       warmup!,
       current_time,
       current_step,
       flow_parameters,
       validate_spectrum


end # module GBGIsotropicTurbulence

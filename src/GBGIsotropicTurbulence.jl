# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package is a small, focused pseudospectral DNS of homogeneous isotropic turbulence —
# a velocity field plus a single passive scalar on a periodic box — built on GBGPeriodicFields,
# which supplies every field operation (transforms, spectral operators, convolution, interpolation,
# reductions). GBGPeriodicFields is deliberately time- and particle-free (its invariant 12); this
# package is the consumer that owns time integration, forcing, the scalar transport, particle
# tracking, and the statistics. GPU is the primary target, so the time loop is in-place and
# allocation-free over a preallocated workspace.
#
# Module layout (each concern its own file, mirroring the edifice). Physics concerns take their names
# from the Mori–Zwanzig lens — the dynamics and its observables; realization and infrastructure
# concerns are named by their job.
#   SimulationState  — the operator/plan bundle + preallocated buffers + initial conditions
#   Dynamics         — the Navier–Stokes RHS (rotational form) + scalar advection + integrating factor
#   Observables      — the measured functions of state (energy, dissipation, skewness, …)
#   Forcing          — pluggable energy-injection strategies (AbstractForcing)
#   TimeIntegration  — pluggable integrating-factor schemes (AbstractIntegrator)
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

include("SimulationState.jl")
include("Dynamics.jl")
include("Observables.jl")
include("Forcing.jl")
include("TimeIntegration.jl")
include("Particles.jl")
include("SimulationRun.jl")


using .SimulationState:
  SpectralOperators,
  Workspace,
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
  HouLi

using .Dynamics:
  velocity_vorticity!,
  velocity_nonlinear!,
  integrating_factor!,
  scalar_to_physical!,
  scalar_nonlinear!

using .Observables:
  kinetic_energy,
  dissipation,
  max_speed,
  scalar_variance,
  scalar_dissipation,
  derivative_skewness

using .Forcing:
  AbstractForcing,
  ForcingSpec,
  NoForcing,
  BandRescaling,
  Linear,
  ConstantPower,
  StochasticOU,
  forcing_rate!,
  apply_forcing!,
  prepare_forcing!,
  forcing_source!

using .TimeIntegration:
  AbstractIntegrator,
  IFRK2,
  IFLowStorageRK3,
  step!,
  recommended_cfl,
  default_integrator,
  Physics

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
  current_step


export SpectralOperators,
       Workspace,
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
       AbstractForcing,
       ForcingSpec,
       NoForcing,
       BandRescaling,
       Linear,
       ConstantPower,
       StochasticOU,
       forcing_rate!,
       apply_forcing!,
       prepare_forcing!,
       forcing_source!,
       AbstractIntegrator,
       IFRK2,
       IFLowStorageRK3,
       step!,
       recommended_cfl,
       default_integrator,
       Physics,
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
       current_step


end # module GBGIsotropicTurbulence

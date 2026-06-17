# GBGIsotropicTurbulence — umbrella module: it sets the include order and assembles the public API.
#
# This package is a small, focused pseudospectral DNS of homogeneous isotropic (scalar) turbulence —
# a velocity field plus a single passive scalar φ on a periodic box — built on GBGPeriodicFields,
# which supplies every field operation (transforms, spectral operators, convolution, interpolation,
# reductions). GBGPeriodicFields is deliberately time- and particle-free (its invariant 12); this
# package is the consumer that owns time integration, forcing, the scalar transport, particle
# tracking, and the statistics. GPU is the primary target, so the time loop is in-place and
# allocation-free over a preallocated workspace.
#
# Module layout (each concern its own file, mirroring the edifice):
#   SimulationState  — the operator/plan bundle + preallocated buffers + initial conditions
#   Equations        — the Navier–Stokes RHS (rotational form) + diagnostics
#   Forcing          — pluggable energy-injection strategies (AbstractForcing)
#   TimeIntegration  — pluggable integrating-factor schemes (AbstractIntegrator)


"""
    GBGIsotropicTurbulence

Tools for simulating and analysing homogeneous isotropic turbulence on three-dimensional periodic
domains: a velocity field and a single passive scalar ``\\varphi``, each optionally forced, advanced
by a choice of integrating-factor time-stepping scheme, with Lagrangian particle tracking and
Eulerian + Lagrangian statistics.

Built on [`GBGPeriodicFields`](https://github.com/GrigorySarnitsky/GBGPeriodicFields.jl).

The `GBG` part in the name comes from the city of Göteborg (Gothenburg, Sweden), where the primary
development took place.
"""
module GBGIsotropicTurbulence

using GBGPeriodicFields


include("SimulationState.jl")
include("Equations.jl")
include("Forcing.jl")
include("TimeIntegration.jl")


using .SimulationState:
  SpectralOperators,
  Workspace,
  spectral_vector,
  physical_vector,
  scalar_spectral,
  scalar_physical,
  random_solenoidal_velocity!,
  random_scalar!,
  dealias!

using .Equations:
  velocity_vorticity!,
  velocity_nonlinear!,
  integrating_factor!,
  scalar_to_physical!,
  scalar_nonlinear!,
  kinetic_energy,
  dissipation,
  max_speed,
  scalar_variance,
  scalar_dissipation

using .Forcing:
  AbstractForcing,
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


export SpectralOperators,
       Workspace,
       spectral_vector,
       physical_vector,
       scalar_spectral,
       scalar_physical,
       random_solenoidal_velocity!,
       random_scalar!,
       dealias!,
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
       AbstractForcing,
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
       Physics


end # module GBGIsotropicTurbulence

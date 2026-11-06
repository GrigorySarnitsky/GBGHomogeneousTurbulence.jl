# Changelog

## Unreleased

- Breaking: the random seed is set by the shell at which its spectrum peaks, in units of the box's
  fundamental 2π/L. The keyword `envelope_wavenumber` of `Simulation`,
  `random_solenoidal_velocity_spectral!` and `random_scalar_spectral!` is now `peak_shell`,
  default 2. The old default peaked at shell √2 on a box of side 2π and in the wrong shells on any
  other box, and it threw on a box much smaller than 1.
- With a given viscosity and kinetic energy, the predicted dissipation rate is no longer limited to
  [1e-30, 1e30] in the user's units, a root outside which was returned as that limit without an
  error. The warm-up's stationarity test no longer calls any series with a mean below 1e-30 flat.

## 0.1.1 — 2026-11-02

The two-peak scalar mixing example now includes a 512³ run and its video, GH200 Grace Hopper
timings for the 192³ runs, and the call that releases GPU memory under CUDA. The package itself is
unchanged.

## 0.1.0 — 2026-10-22

The first release: a pseudospectral direct numerical simulation of homogeneous isotropic turbulence
on a triple-periodic box, with one incompressible velocity field and one passive scalar, each
optionally forced; interchangeable integrating-factor time stepping; Lagrangian tracers with field
sampling along their trajectories; HDF5 checkpoints; and CPU, CUDA and ROCm backends through
GBGPeriodicFields. It is installed by name from the fleet's registry, GBGRegistry, which brings
GBGPeriodicFields with it.

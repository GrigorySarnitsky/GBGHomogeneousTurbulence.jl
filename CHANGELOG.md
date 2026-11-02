# Changelog

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

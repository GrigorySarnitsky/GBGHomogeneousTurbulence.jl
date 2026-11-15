# Changelog

## Unreleased

The velocity at the particles is kept as a public trail of time-labelled samples, from which the
Lagrangian acceleration is one call, and the particle integration schemes are the Adams family with
a predictor–corrector member. Several names and one file format change.

- New: `ParticleTrail`, the last few samples of one quantity at the particles, each with its time.
  It is read by offset from the newest sample, `trail[0]`, `trail[-1]`, each a pair `(time, value)`;
  filled with `push!(trail, t) do value … end`; and differentiated in time along the trajectories
  with `time_derivative!` and `time_derivative`. `write_trail` and `read_trail` store one.
- New: `ABM(k)`, the Adams–Bashforth–Moulton predictor–corrector of order k + 1, for k from 1 to 7.
  `ABM(1)` is `Heun`.
- New: `shortened_first_steps` on `ParticleTracking`. A multistep scheme starts on lower-order steps,
  which leave an error of third order behind; with this setting the run shortens its first timesteps
  so that the scheme's full order holds from the start.
- Breaking: `AdamsBashforth(order = k)` is now `AB(k)`.
- Breaking: `velocity_at_particles(cache)` is removed. `velocity_at_particles_trail(cache)` returns
  the run's trail of the velocity at the particles; the current sample is `trail[0].value`, a
  `VectorPointValues`, where the old read returned its bare array.
- Breaking: `ParticleIntegratorBuffers`, `history_depth` and the particle form of `allocate_buffers`
  are removed: a particle scheme owns no storage. `ObservablesCache` is built with `tracers` and
  `particle_integration_scheme` in place of `number_of_particles` and `history_depth`.
- Breaking, for a hand-written loop: `advect!(scheme, tracers, domain, cache, dt)` and
  `deposit!(cache, tracers, t)` take no velocity field, since they read the cache's own, and the
  deposit takes the time of the new sample. Both refuse a field and positions that belong to
  different times.
- Breaking: a checkpoint with tracers written by 0.2 is refused by `read_simulation`, because it
  stored the earlier velocity samples without their times; its state and tracers are still read by
  `read_state` and `read_tracers`. A checkpoint without tracers loads as before.
- A run with tracers under the default `Heun` scheme holds one array of the tracers' size fewer,
  and one under a multistep scheme two fewer. Trajectories agree with 0.2 to round-off, not bit for
  bit: the corrector is applied as a correction to the predicted positions.
- The modules are split: `Particles` holds the tracers and what is measured at them,
  `ParticlePropagator` the schemes and the step.

## 0.2.0 — 2026-11-07

Three changes break 0.1 code: the seed is set by its spectrum's peak shell, a run is changed by
building a new `Simulation` that adopts its state, and an adopted state must be the spectrum of a
real field.

- Breaking: the random seed is set by the shell at which its spectrum peaks, in units of the box's
  fundamental 2π/L. The keyword `envelope_wavenumber` of `Simulation`,
  `random_solenoidal_velocity_spectral!` and `random_scalar_spectral!` is now `peak_shell`,
  default 2. The old default peaked at shell √2 on a box of side 2π and in the wrong shells on any
  other box, and it threw on a box much smaller than 1.
- With a given viscosity and kinetic energy, the predicted dissipation rate is no longer limited to
  [1e-30, 1e30] in the user's units, a root outside which was returned as that limit without an
  error. The warm-up's stationarity test no longer calls any series with a mean below 1e-30 flat.
- Breaking: `fields_modified!`, `particles_modified!`, `restart!` and the `deposit!(sim)` method are
  removed. A run is changed (a new viscosity, a reseeded field, moved tracers) by building a new
  `Simulation` that adopts its state and tracers:
  `Simulation(domain; state, particles = ParticleTracking(tracers; …))` takes the arrays without
  copying, measures them, and starts its clock at zero.
- Breaking: a `state` given to `Simulation` must hold the spectrum of a real field. One whose
  conjugate pairs disagree is refused with an `ArgumentError` that names `reality_projection!` as the
  repair; before, it was accepted, and the first step projected the violation away.

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

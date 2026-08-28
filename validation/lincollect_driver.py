#!/usr/bin/env python
# TurTLE data-collection leg: 15 large-eddy turnovers from the frozen handoff state.
# Starts at iteration 100 from collect_checkpoint_0.h5 (= fill_checkpoint_1.h5 @ 100,
# sha256 02c2d253...; immutable safety copy handoff_initial_state_iter100.h5).
# Measured T = k/eps = 2.472 at the handoff, so 15 T = 37.08 t.u.; we run 18500 steps
# x dt = 0.002 = 37.0 t.u. = 14.97 T.
# cpp_random_particles = 0: use the checkpoint's particles (the SAME 10^4 both codes run).
# niter_stat = 5: k(t), eps(t) every 0.01 t.u.; niter_part = 5: trajectory samples every
# 0.01 t.u. (~9.5 per tau_eta) for the VACF and the trajectory-level comparison.
import time
from TurTLE import DNS

t0 = time.time()
with open('lincollect_runlog.txt', 'a') as fh:
    fh.write('launch: {0}  epoch {1:.0f}\n'.format(time.strftime('%Y-%m-%dT%H:%M:%S'), t0))

c = DNS()
c.launch([
    'NSVEparticles',
    '-n', '128',
    '--np', '8', '--ntpp', '2',
    '--precision', 'double',
    '--simname', 'lincollect',
    '--dtfactor', '0.256',
    '--nu', '9.032e-3',
    '--forcing_type', 'linear',
    '--famplitude', '0.42386263',
    
    '--fk0', '0.5', '--fk1', '2.5',
    '--niter_todo', '18500',
    '--niter_out', '3700',
    '--niter_stat', '5',
    '--nparticles', '10000',
    '--niter_part', '5',
    '--tracers0_neighbours', '1',
    '--tracers0_smoothness', '1',
    '--tracers0_integration_steps', '4',
    '--cpp_random_particles', '0',
    '--checkpoints_per_file', '1',
], iter0 = 100)

t1 = time.time()
with open('lincollect_runlog.txt', 'a') as fh:
    fh.write('finish: {0}  epoch {1:.0f}  wall {2:.0f} s\n'.format(
        time.strftime('%Y-%m-%dT%H:%M:%S'), t1, t1 - t0))

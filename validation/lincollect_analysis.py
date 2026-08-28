#!/usr/bin/env python
# Reference data for TurTLE's Linear-forcing leg: k(t), ε(t) (canonical series) and the
# single-origin ρ_u — same estimator as the ConstantPower pair.
import numpy as np
import h5py
from TurTLE.DNS import DNS

c = DNS(work_dir = './', simname = 'lincollect')
c.compute_statistics(iter0 = 100)
t = c.statistics['t']
k = c.statistics['energy(t)']
eps = c.statistics['diss(t)']
print('k/eps series:', t.shape, ' mean eps = %.4f  mean k = %.4f' % (eps.mean(), k.mean()))

p = h5py.File('lincollect_particles.h5', 'r')
iters = sorted(int(s) for s in p['tracers0/velocity'].keys())
v0 = p['tracers0/velocity/100'][()]
C = np.array([(p['tracers0/velocity/%d' % it][()] * v0).sum(axis = 1).mean() for it in iters])
p.close()
rho = C / C[0]
tau = 0.01 * np.arange(len(rho))

out = h5py.File('turtle_linear_reference_data.h5', 'w')
out['t'] = t; out['k'] = k; out['ε'] = eps; out['τ'] = tau; out['ρ_u'] = rho
out.attrs['code'] = 'TurTLE 8.2.1 (NSVEparticles), float64'
out.attrs['run'] = ('lincollect: 128^3, L = 2π, ν = 9.032e-3, dt = 2e-3, LINEAR (Lundgren band) '
                    'forcing famplitude = 0.42386263 = ε̄/(2E_band(t₀)) on |κ| ∈ [0.5, 2.5]; '
                    'iterations 100–18500 from the same frozen handoff as the ConstantPower pair')
out.attrs['initial_state'] = ('handoff_initial_state_iter100.h5, sha256 '
                              '02c2d2530a731f0701608b4fb219f28bc9006f8d2ac39f4c02daef228823e82f')
out.attrs['ρ_u'] = ('single-origin ensemble VACF: ρ_u(τ) = ⟨u(τ)·u(0)⟩/⟨|u(0)|²⟩ over the 10^4 '
                    'tracers, u(0) at the handoff instant (post hoc from stored samples)')
out.close()
print('wrote turtle_linear_reference_data.h5')

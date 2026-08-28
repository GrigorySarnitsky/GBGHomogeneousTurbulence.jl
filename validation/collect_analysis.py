#!/usr/bin/env python
# Build the downloadable reference-data file from the finished `collect` run:
# turtle_reference_data.h5 with datasets k, ε, ρ_u (owner-specified names, Unicode),
# plus their axes t and τ — to be published NEXT TO the frozen initial state
# handoff_initial_state_iter100.h5 (sha256 02c2d253...).
import numpy as np
import h5py
from TurTLE.DNS import DNS

# --- k(t), ε(t): TurTLE's own canonical series (energy from the velocity spectra,
#     dissipation as 2ν·enstrophy = ν⟨|ω|²⟩). ---
c = DNS(work_dir = './', simname = 'collect')
c.compute_statistics(iter0 = 100)
t = c.statistics['t']
k = c.statistics['energy(t)']
eps = c.statistics['diss(t)']
print('k/eps series:', t.shape, ' t in [%.3f, %.3f]' % (t[0], t[-1]),
      ' mean eps = %.4f  mean k = %.4f' % (eps.mean(), k.mean()))

# --- VACF from the stored trajectories: ρ_u(τ) = ⟨u(t+τ)·u(t)⟩ / ⟨|u|²⟩, the dot
#     product summed over components, averaged over the 10^4 tracers and (unbiased)
#     over t across the stationary window. FFT-based, zero-padded to 2N. ---
pf = h5py.File('collect_particles.h5', 'r')
iters = sorted(int(s) for s in pf['tracers0/velocity'].keys())
print('trajectory samples:', len(iters), 'from iteration', iters[0], 'to', iters[-1])
u = np.stack([pf['tracers0/velocity/%d' % it][()] for it in iters])   # (Nt, Np, 3)
pf.close()
Nt = u.shape[0]
sample_dt = c.parameters['dt'] * c.parameters['niter_part']
F = np.fft.rfft(u, n = 2 * Nt, axis = 0)
R = np.fft.irfft(F * np.conj(F), n = 2 * Nt, axis = 0)[:Nt]           # per particle+component
R = R.sum(axis = 2).mean(axis = 1)                                    # dot product, tracer mean
R /= (Nt - np.arange(Nt))                                             # unbiased in t
rho = R / R[0]
tau = sample_dt * np.arange(Nt)
print('ρ_u: ρ(0) = %.6f  first zero crossing at τ ≈ %.3f' %
      (rho[0], tau[np.argmax(rho < 0)] if (rho < 0).any() else float('nan')))

# --- The published file. ---
out = h5py.File('turtle_reference_data.h5', 'w')
out['t'] = t
out['k'] = k
out['ε'] = eps
out['τ'] = tau
out['ρ_u'] = rho
out.attrs['code'] = 'TurTLE 8.2.1 (NSVEparticles), float64'
out.attrs['run'] = ('collect: 128^3, L = 2π, ν = 9.032e-3, dt = 2e-3, constant-power '
                    'forcing ε_inj = 1 in shells 1–2, Hou–Li (SMOOTH) dealiasing; '
                    'iterations 100–18600 = 37.0 time units ≈ 15 k/ε from the frozen '
                    'handoff state')
out.attrs['initial_state'] = ('handoff_initial_state_iter100.h5, sha256 '
                              '02c2d2530a731f0701608b4fb219f28bc9006f8d2ac39f4c02daef228823e82f')
out.attrs['k'] = 'kinetic energy k(t) = ∫E(κ)dκ = ½⟨|u|²⟩, from the velocity spectra'
out.attrs['ε'] = 'dissipation rate ε(t) = ν⟨|ω|²⟩ (= 2ν × enstrophy), from the vorticity spectra'
out.attrs['ρ_u'] = ('Lagrangian velocity autocorrelation ρ_u(τ) = ⟨u(t+τ)·u(t)⟩/⟨|u|²⟩: '
                    'dot product summed over components, averaged over 10^4 tracers, '
                    'unbiased average over t across the full window; ρ_u(0) = 1')
out.attrs['t'] = 'sample times of k and ε, code units, every 5 steps (0.01 time units)'
out.attrs['τ'] = 'lags of ρ_u, code units, every 0.01 time units'
out.close()
print('wrote turtle_reference_data.h5')

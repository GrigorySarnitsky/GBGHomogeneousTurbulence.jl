#!/usr/bin/env python
# Overlay of the two comparison legs: TurTLE solid, GBGHomogeneousTurbulence dashed.
import h5py
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

T = h5py.File('turtle_reference_data.h5', 'r')
G = h5py.File('gbgit_reference_data.h5', 'r')

tT, kT, eT = T['t'][()], T['k'][()], T['ε'][()]
uT, rT = T['τ'][()], T['ρ_u'][()]
# HT's clock starts at the handoff instant = TurTLE absolute t = 0.2
tG, kG, eG = G['t'][()] + 0.2, G['k'][()], G['ε'][()]
uG, rG = G['τ'][()], G['ρ_u'][()]

fig, ax = plt.subplots(1, 3, figsize=(12.5, 3.6))
ax[0].plot(tT, kT, '-',  color='#1f77b4', lw=1.6, label='TurTLE')
ax[0].plot(tG, kG, '--', color='#d62728', lw=1.4, label='GBGHomogeneousTurbulence')
ax[0].set_xlabel('t'); ax[0].set_title('k(t)'); ax[0].legend(fontsize=8)

ax[1].plot(tT, eT, '-',  color='#1f77b4', lw=1.6)
ax[1].plot(tG, eG, '--', color='#d62728', lw=1.4)
ax[1].axhline(1.0, ls=':', c='k', lw=0.8)
ax[1].set_xlabel('t'); ax[1].set_title('ε(t)')

ax[2].plot(uT[:1500], rT[:1500], '-',  color='#1f77b4', lw=1.6)
ax[2].plot(uG[:1500], rG[:1500], '--', color='#d62728', lw=1.4)
ax[2].axhline(0, ls=':', c='k', lw=0.8)
ax[2].set_xlabel('τ'); ax[2].set_title('ρ_u(τ)')

fig.tight_layout()
fig.savefig('comparison_overlay.png', dpi=110)

n = min(len(kT), len(kG))
print('max rel |Δk|  over overlap: %.3e' % np.abs(kG[:n] - kT[:n]).max() / np.abs(kT[:n]).max()
      if False else 'max rel |Δk| : %.3e' % (np.abs(kG[:n] - kT[:n]) / np.abs(kT[:n])).max())
print('max rel |Δε| : %.3e' % (np.abs(eG[:n] - eT[:n]) / np.abs(eT[:n])).max())
m = min(len(rT), len(rG))
print('max |Δρ_u|   : %.3e' % np.abs(rG[:m] - rT[:m]).max())
print('wrote comparison_overlay.png')

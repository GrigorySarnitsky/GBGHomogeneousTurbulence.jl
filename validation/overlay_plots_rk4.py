#!/usr/bin/env python
# Overlay: TurTLE (fixed-dt SSPRK3 reference) solid vs IT IFLowStorageRK4 + adaptive step dashed.
import h5py, numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

T = h5py.File('turtle_reference_data.h5', 'r')
G = h5py.File('gbgit_rk4adaptive_reference_data.h5', 'r')
tT, kT, eT, uT, rT = T['t'][()], T['k'][()], T['ε'][()], T['τ'][()], T['ρ_u'][()]
tG, kG, eG, uG, rG = G['t'][()] + 0.2, G['k'][()], G['ε'][()], G['τ'][()], G['ρ_u'][()]

fig, ax = plt.subplots(1, 3, figsize=(12.5, 3.6))
ax[0].plot(tT, kT, '-',  color='#1f77b4', lw=1.6, label='TurTLE (SSPRK3, fixed dt)')
ax[0].plot(tG, kG, '--', color='#d62728', lw=1.4, label='IT (IFLowStorageRK4, adaptive)')
ax[0].set_xlabel('t'); ax[0].set_title('k(t)'); ax[0].legend(fontsize=7)
ax[1].plot(tT, eT, '-',  color='#1f77b4', lw=1.6)
ax[1].plot(tG, eG, '--', color='#d62728', lw=1.4)
ax[1].axhline(1.0, ls=':', c='k', lw=0.8); ax[1].set_xlabel('t'); ax[1].set_title('ε(t)')
mT = uT <= 15; mG = uG <= 15
ax[2].plot(uT[mT], rT[mT], '-',  color='#1f77b4', lw=1.6)
ax[2].plot(uG[mG], rG[mG], '--', color='#d62728', lw=1.4)
ax[2].axhline(0, ls=':', c='k', lw=0.8); ax[2].set_xlabel('τ'); ax[2].set_title('ρ_u(τ)')
fig.tight_layout(); fig.savefig('comparison_overlay_rk4.png', dpi=110)

# Agreement metrics on the common grid (interpolate IT's irregular series onto TurTLE's).
kGi = np.interp(tT, tG, kG); eGi = np.interp(tT, tG, eG); rGi = np.interp(uT, uG, rG)
for tt in [1.0, 2.0, 5.0, 10.0]:
    j = int(round(tt/0.01))
    print('t=%5.1f  rel|Δk| = %.2e   rel|Δε| = %.2e' % (tt, abs(kGi[j]-kT[j])/abs(kT[j]), abs(eGi[j]-eT[j])/abs(eT[j])))
print('window means: k %.4f vs %.4f | ε %.4f vs %.4f (TurTLE vs IT)' % (kT.mean(), kG.mean(), eT.mean(), eG.mean()))
for tt in [0.5, 1.0, 2.0, 5.0]:
    j = int(round(tt/0.01))
    print('ρ_u(%.1f): TurTLE %.4f  IT %.4f  |Δ| %.1e' % (tt, rT[j], rGi[j], abs(rT[j]-rGi[j])))
print('wrote comparison_overlay_rk4.png')

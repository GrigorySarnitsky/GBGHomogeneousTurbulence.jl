# The TurTLE comparison — reproduction scripts

The scripts behind the results on the documentation's Validation page. Run them in a working
directory holding the release assets (`handoff_initial_state_iter100.h5` and, for the overlay,
the two reference-data files); the page carries the download commands and the SHA-256 hashes.

- `collect_driver.py` — TurTLE's data-collection leg: 18,400 steps of `NSVEparticles` from the
  frozen handoff (requires a TurTLE 8.2.1 installation; launched from Python because `iter0`
  is not a CLI flag).
- `collect_analysis.py` — builds `turtle_reference_data.h5` (k, ε from TurTLE's canonical
  series; the ρ_u dataset was subsequently replaced by the single-origin estimator of
  `overlay_plots.py`'s legs — see the Validation page for the estimator definition).
- `ht_leg.jl` — this package's leg: imports the handoff (axis permutation, amplitude rescale,
  PF's `inverse_curl`, tracer positions and AB4 history), verifies the three witnesses, runs
  18,400 fixed steps collecting k, ε and the in-callback ρ_u, writes
  `gbgit_reference_data.h5`. Backend is `ROCArray`; substitute `CuArray` or `Array` to taste.
- `overlay_plots.py` — the overlay figure (TurTLE solid, this package dashed).

The `*_linear*` variants are the second pair — the same comparison under the band-limited
linear (Lundgren) forcing with fixed rate `A = 0.42386263`: `lincollect_driver.py` /
`lincollect_analysis.py` (TurTLE leg), `ht_leg_linear.jl`, `overlay_plots_linear.py`.

The `*_rk4*` variants are the third repetition — this package on `IFLowStorageRK4` under its
adaptive CFL step against TurTLE's original fixed-step reference leg (no TurTLE rerun needed):
`ht_leg_rk4.jl`, `overlay_plots_rk4.py`.

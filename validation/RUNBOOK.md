# TurTLE code-to-code comparison — the working spec (2026-08-28)

Written on Enteropia for the Aiporetne session to pick up: the owner is installing and running
TurTLE at home. Everything code-side is pushed to `master`; this file (untracked, Dropbox-synced)
carries the run design, the traps, and what is NOT yet built. Transcripts do not sync — this file
and the memory entry are the handoff.

## State of the code (all pushed)

- **`IFSSPRK3` exists** (decision 80): TurTLE's exact tableau and stage arrangement, third-order
  verified, same registers and CFL ceiling as `IFLowStorageRK3`, checkpoint round-trips.
  **Use it for the comparison** — `field_integration_scheme = IFSSPRK3()`.
- **One rank-blind plan pair** (decision 81, on PF's 76): plan residency is no longer a constraint
  anywhere.
- The owner's ruling on trajectories: with identical physics, deterministic forcing, the same
  scheme and the same IC, roundoff seeds divergence at the Lyapunov rate from ~1e-16 — so
  trajectory-level tracking over a substantial window IS a usable comparison, and is why the
  tableau was matched. Do not talk it down.

## The agreed pairing: Hou–Li at 256³ (TurTLE cannot run 2/3 — see traps)

**Run point REVISED 2026-08-28 (owner): 128³, and ν set by the RESOLVED criterion** (decision 82) —
resolved κ_max·η = 1.5 at κ_eff = 0.8·N/2 = 51.2, and ~18× cheaper than the original 256³ point
(measured 0.275 s/iter float64 on Aiporetne; 50 T ≈ 5.5 h). The 256³ warm-up begun at the old
Nyquist-convention ν = 2.655e-3 was aborted (its ν was ⅘^{4/3} too thin) and its checkpoints
deleted; `runs/warmup256/runlog.txt` keeps the record. Estimated Re_λ ≈ 79; checkpoint 49 MiB.

| quantity | IT | TurTLE |
|---|---|---|
| grid, box | 128³, 2π | `nx=ny=nz=128`, `dkx=dky=dkz=1.0` |
| precision | `Float64` | float64 build |
| viscosity | `viscosity = 9.032e-3` (η = 1.5/51.2 = 0.029297, ν = η^{4/3}) | `nu = 9.032e-3` |
| forcing | `ConstantPower(injection_rate = 1.0, lowest_shell = 1, highest_shell = 2)` | `forcing_type = "fixed_energy_injection_rate"`, `injection_rate = 1.0`, `fk0 = 0.5`, `fk1 = 2.5` |
| dealiasing | `HouLi(order = 36, strength = 63.463)` (the N = 128 strength) | `SMOOTH` (compile-time; `dealias_type = 1` is the default and the only honoured value) |
| scheme | `IFSSPRK3()` | its native SSPRK3 |
| timestep | fixed `advance!(sim; dt = 0.002)` | `dt = 0.002` (`dtfactor 0.256` at n = 128) |
| inert TurTLE params | — | `famplitude, fmode, friction_coefficient, variation_strength, variation_time_scale` |

Resolution numbers at this point: κ_eff·η = 1.50 (the resolution claim), κ_Ny·η = 64·0.029297 =
1.875 (grid-band figure only). The 128³ warm-up runs in `runs/warmup128/` (10 jobs × 7,250 steps =
145 t.u. ≈ 50 k/ε; driver + runlog there).

**WARM-UP + FILL: DONE (2026-08-28).** The 128³ warm-up finished (10:13–15:02, 4h49m, exit 0;
72,500 steps = 59 measured turnovers at T = k/ε = 2.47). Stationary tail: ε = 1.0012, k = 2.475,
u′ = 1.284, Re_λ = 67.2, CFL = 0.285; TurTLE's own kMeta = 1.476 — SAME physics as our resolved
κ_max·η = 1.50 (TurTLE normalizes its effective cutoff by 0.8·(N/2−1) = 50.4, ours 0.8·N/2 =
51.2 — the 64/63 conversion goes on the validation page). The fill segment ran 100 NSVEparticles
steps (simname `fill`, src = warmup@72500, seed cpp_random_particles = 2026). **THE HANDOFF =
`runs/warmup128/fill_checkpoint_1.h5` @ iteration 100**: vorticity + tracers0/state (10⁴, NOT
box-wrapped — importer wraps) + tracers0/rhs (4,10⁴,3): slot 0 all-zero by TurTLE convention
(current-step sample recomputed on restart), slots 1–3 the three past AB4 samples — which of 1–3
is newest is for the converter's round-trip witness to pin. `fill_particles.h5` = per-step
position/velocity samples (the VACF raw-material pattern, works). Warm-up intermediates
(checkpoints 0–9, ~490 MB) prunable once the comparison legs land.

**DATA-COLLECTION LEG: DONE (2026-08-28, 16:19–17:51, 5498 s).** One TurTLE subtlety surfaced:
`niter_todo` is the TARGET iteration, so from iter0 = 100 the run ended at 18,500 = 18,400 steps
= 36.8 t.u. = **14.9 k/ε** (marginally under the nominal 15; attributes state it honestly).
Results: k ∈ [2.27, 2.84] mean 2.565; ε ∈ [0.89, 1.10] mean 0.9987; ρ_u decays with T_L ≈ 0.8
t.u. ≈ 0.3 T_E. **The download set** (all in `runs/warmup128/`):
`handoff_initial_state_iter100.h5` sha256 02c2d253…;
`turtle_reference_data.h5` sha256 fa9633599e2f86411a9712ad75c0fad69cb047626d4f59e02de5a2802ca42211
(ρ_u REPLACED 2026-08-28 with the owner's single-origin estimator, matching IT's callback);
`gbgit_reference_data.h5` sha256 394d68ca9f6bd066eb34b484f826c684df605c6901e1eb7364d756ae1b04bf28
(IT's leg, same datasets t/k/ε/τ/ρ_u; t offset +0.2 to TurTLE absolute time, stated in attrs).
Overlay: `comparison_overlay.png`. **RESULTS (both legs done 2026-08-28)**: k/ε identical at t₀,
1e-10 relative through t ≈ 5, Lyapunov growth to the ±fluctuation level by t ≈ 20 (divergence
seeds at ~1e-12 — the NSVE-vs-velocity formulation difference, not roundoff); ρ_u agrees to
1e-11…1e-5 through τ = 5 (ensemble mean robust to phase scrambling), max |Δρ_u| 2e-2 only in the
τ > 10 noise floor. IT leg: 265 s on the 7900 XTX (14.4 ms/step) vs TurTLE 92 min CPU. Converter
witnesses: state import bit-exact (TurTLE stores MODE AMPLITUDES — scale N³ to PF's convention);
curl∘inverse_curl 1.4e-16; interpolation parity 1.6e-14.

**Original leg directive**: TurTLE runs **15 k/ε from the
frozen handoff**. The initial state is FROZEN as **`handoff_initial_state_iter100.h5`** (write-protected; sha256
02c2d2530a731f0701608b4fb219f28bc9006f8d2ac39f4c02daef228823e82f) — the three iter-100 datasets
self-contained. THIS is the canonical file IT's run is prepared from and the eventual release
asset. Its working twin `collect_checkpoint_0.h5` was byte-identical at launch but the TurTLE
wrapper then added its standard zero-filled `tracers0/rhs/0` bookkeeping dataset (ignored by the
solver), so its hash differs — always cite the canonical file's hash. Run `collect` (driver `collect_driver.py`, Python
launch with iter0 = 100 — the CLI cannot set iter0): 18,500 steps × dt 2e-3 = 37.0 t.u. = 14.97 T
(T = k/ε = 2.472 measured); niter_stat = 5 → k(t), ε(t) every 0.01 t.u.; niter_part = 5 →
position/velocity samples every 0.01 t.u. (~9.5/τ_η, ≈1.8 GB in collect_particles.h5);
cpp_random_particles = 0 → the checkpoint's own 10⁴ particles (**owner: both codes run the SAME
particles**). **Owner rulings**: (a) NO shared VACF script — IT computes the VACF online in a
`run!` callback, TurTLE's comes post-hoc from stored trajectories; match the estimator (lag grid,
stationary averaging, normalization) and document it on the validation page. **The VACF estimator (owner-designed, final)**: the SINGLE-ORIGIN ensemble form —
ρ_u(τ) = ⟨u(τ)·u(0)⟩/⟨|u(0)|²⟩ over the 10⁴ tracers, u(0) frozen at the handoff instant. IT
computes it IN the callback with O(M) state (store v₀ once, one scalar per sample); TurTLE's is
the same estimator post-hoc from its stored trajectories. Both codes share u(0) and the
particles, so the curves compare realization-to-realization. History of the miss (owner-caught):
the first IT leg collected samples in RAM and computed the TIME-AVERAGED estimator batch-FFT —
wrong estimator home AND over-engineered; my "online needs a ring buffer" claim confused the
time-averaged form with the estimand. The online-correlator request to SS was dropped (the owner,
2026-10-03: plain Lagrangian correlations are the user's own), and was never on the comparison's path. (b) The converter
WAITS for PF's `inverse_curl` (in preparation on the PF side) — do not hand-roll iκ×ω̂/|κ|² in IT
(belongs-in-PF). (c) **Deliverable format (owner 2026-08-28): the reference data is ONE HDF5
file, `turtle_reference_data.h5`, datasets named `k`, `ε`, `ρ_u` (Unicode) + axes `t`, `τ`,
published for download NEXT TO the frozen initial state** — built by
`runs/warmup128/collect_analysis.py` (k, ε from TurTLE's canonical energy(t)/diss(t) = 2ν·Ω;
ρ_u(τ) = ⟨u(t+τ)·u(t)⟩/⟨|u|²⟩ over the 10⁴ tracers, FFT-based, unbiased in t, ρ_u(0)=1;
definitions in the file's attributes — IT's callback estimator must match these).

**Particle extension (owner, 2026-08-28)**: the comparison includes 10⁴ tracers. After the field
warm-up, continue as `NSVEparticles` (`--nparticles 10000 --cpp_random_particles <seed>`,
defaults: `tracers0_integration_steps 4` = AB4, `neighbours 1`/`smoothness 1` = I4O3 cubic ≡ IT's
Catmull-Rom — interpolation parity REQUIRED, and the BCC two-grid idea must NOT be used in this
leg) for ~100 steps so AB4 runs at full order with authentic history. Handoff = that checkpoint:
vorticity + `tracers0/state` + `tracers0/rhs` (4-slot history; NSVEparticles reads
`/tracers0/rhs/<iter>` natively on restart — verified in source, and the convergence tutorial
hand-builds ICs this way). The converter (still postponed) additionally imports positions + the
rhs history into IT's ParticleIntegratorBuffers; rhs slot ordering must be pinned by the
round-trip witness, not assumed. VACF: neither code computes it in-run — TurTLE samples
position/velocity per `niter_part` into `<simname>_particles.h5`; ONE shared post-hoc script
computes the Lagrangian VACF identically for both legs. The docs skeleton is
`docs/src/validation.md` (in the build nav since 2026-08-28).

**The strength formula** (exact filter match, verified to machine epsilon):
`strength = 36 * (1 - 2/N)^-36` → N=96: 76.818, 128: 63.463, 192: 52.483, **256: 47.745**,
384: 43.446, 512: 41.447.

**Why ν is set this way**: under constant-power forcing ε at stationarity equals the injection
rate exactly (an input, not a model), so η = (ν³/ε)^¼ is known in advance and ν is chosen to hit
the resolution criterion. **The criterion is measured against the RESOLVED cutoff (decision 82,
owner-ratified 2026-08-28)**: Hou–Li adds a per-step damping rate 36(κ/κ_Ny)³⁶/dt that crosses the
viscous rate νκ² at κ/κ_Ny = (ν κ_Ny² dt/36)^{1/34} ≈ 0.8 (insensitive to ν/dt through the 1/34
power; TurTLE's python-side 0.8 factor is the same convention, so both codes' reported numbers
agree by construction) — hence κ_eff = 0.8·N/2 and ν = (1.5/κ_eff)^{4/3} for resolved
κ_max·η = 1.5. Nyquist stays the right κ_max for the CFL (fastest energetic oscillation). The
first 256³ attempt (ν = 2.655e-3) had set Nyquist·η = 1.5 — resolved only ≈ 1.2 — and was aborted
for exactly this. u′ and Re_λ are OUTPUTS — their agreement is the test.

**Verified correspondences** (do not re-derive): IT's amplitude = injection_rate/(2·k_band);
TurTLE's = injection_rate/energy_in_shell with energy_in_shell deliberately NOT halved — identical.
fk0/fk1 are absolute |k| against √(kx²+ky²+kz²), so IT shells 1–2 ⇔ 0.5, 2.5. TurTLE normalizes
the inverse transform (AbstractFFTs convention, same as PF).

## Traps, each verified on TurTLE's source

1. **`dealias_type` is documented but the SOLVER ignores it — RUN-VERIFIED on 8.2.1
   (2026-08-28).** All three time-stepping solvers hard-code `kspace<be, SMOOTH>`
   (vorticity_equation.hpp:57, NSE.hpp:68, NSE_alt_dealias.hpp:70, same lines at 8.2.1);
   the `kspace` class fully implements TWO_THIRDS but no DNS solver instantiates it.
   Empirically (32³ NSVE, runs `d0`/`d1` in `turtle-deploy/runs/dealias-check/`):
   `--dealias_type 0` does **not** silently misreport — it CRASHES at startup
   ("Computed nshells not equal to data file nshells", the consistency guard at
   kspace.cpp:228 / direct_numerical_simulation.cpp:47: the Python wrapper sizes the
   statistics datasets from the TWO_THIRDS shell count, the hard-coded SMOOTH kspace
   computes a different one, abort). So the earlier "silently wrong κ_max·η" reading is
   superseded: on current TurTLE the failure is loud, and 2/3 DNS is simply impossible.
   The `dealias_type = 1` field confirms SMOOTH in the evolved state: every mode between
   the 2/3 cutoff (|k| = 9 at N=32) and k ≈ 15 is nonzero with the exp(−36(k/kM)³⁶)
   rolloff — a 2/3-truncated field would have them exactly zero. The comparison remains
   Hou–Li only. (Worth a TurTLE issue: docs advertise the option the solvers can't take.)
2. **TurTLE's smooth filter normalizes per-axis by (N/2 − 1)·dk; IT's by (N/2)·k₀.** The strength
   formula above closes it exactly on a cubic grid — do not also "fix" it elsewhere.
3. **Filter check** if in doubt: exp(−36·(k/(N/2−1))³⁶) (TurTLE) ≡ exp(−strength·(k/(N/2))³⁶) (IT).

## Build requirements (Ubuntu; TurTLE's CMakeLists: C++17, MPI, HDF5-C, OpenMP, FFTW w/ MPI, GSL opt)

    sudo apt install libfftw3-dev libfftw3-mpi-dev libhdf5-openmpi-dev libopenmpi-dev libgsl-dev
    # then in inspiration/dns/turtle:  pip install -e .   (needs numpy≥1.8, h5py≥2.2.1 — present)

The clone at `inspiration/dns/turtle` is Dropbox-synced (2026-04-15 master, cdcddf42). Current
master is 2026-07-23; the solver files relevant here are unchanged between the two (checked).
TurTLE is CPU/MPI — the comparison does not need matched hardware, and for the trajectory window it
needs matched PRECISION (float64 both sides).

## PF axis convention — VERIFIED (2026-08-28, single-mode witness on Aiporetne)

Witness: `ScalarFieldPhysical(Array, (x,y,z)->cos(m·x+φ), grid)` at N=16, L=2π, transformed with
PF's `to_spectral!`; every probe (axis modes, mixed mode (2,3,5), negative-ky mode
(2,−3,5), phase 0.3) landed exactly as predicted; round trip 1e-15.

- **Array dims are (kx, ky, kz), reduced axis FIRST**: PF spectral shape (N/2+1, N, N),
  Julia column-major so kx is the fastest index. Physical dims are (x, y, z), origin at
  the first grid point, x_i = (i−1)·L/N.
- **Index↔wavenumber** (1-based Julia index `i`): reduced axis kx = i−1 ∈ 0..N/2; full
  axes κ = i−1 for i−1 ≤ N/2 else i−1−N (standard FFT order). Hermitian partners inside
  the kx=0 plane are stored explicitly.
- **Sign + normalization**: forward is unnormalized Σ u e^{−iκ·x} (cos(m·x+φ) lands at +m
  with phase **+φ**, magnitude N³/2); the inverse carries the 1/N³. Same convention as
  TurTLE/FFTW — no conjugation or rescaling in the converter.
- **Dictionary to TurTLE**: TurTLE dataset [ky][kz][kx][comp] (C order, kx reduced) ↔ PF
  `[i_kx, j_ky, k_kz]` — per-axis index conventions IDENTICAL (0- vs 1-based aside), only
  the axis ORDER permutes: (kx,ky,kz) ↔ [ky,kz,kx]. Vector component order (x,y,z) on
  both sides — to be re-pinned by the converter's round-trip witness.

## Same-IC protocol — REVERSED by the owner (2026-08-28)

**Owner ruling: BOTH codes take the warm-up state from a TurTLE run.** TurTLE warms up
(256³ Hou–Li per the table above), continues natively from its own checkpoint; IT imports
the checkpoint: read `vorticity/complex/<iter>`, permute per the dictionary above, recover
û = iκ×ω̂/|κ|² (inverse curl; ω̂ is solenoidal from TurTLE's own projection), zero mode
zero. The TurTLE→IT converter + round-trip witness is POSTPONED (owner, 2026-08-28) — do
not build it until asked. The subsection below records the original IT→TurTLE direction
for reference (still correct mechanics for the reverse map).

### (superseded direction) Warm up in IT, export, inject into TurTLE:

- TurTLE generates a random IC ONLY if `vorticity/complex/0` is absent from
  `<simname>_checkpoint_0.h5`. Supply the dataset and it uses it — its own test does exactly this
  (tests/test_vorticity_equation.py:299: `f['vorticity/complex/0'] = data`).
- Dataset path `/vorticity/complex/<iteration>` (hdf5_tools.cpp:618). Layout: complex128,
  **(ny, nz, nx/2+1, 3)** — FFTW convention, slowest→fastest = y, z, x (TurTLE/tools.py docstring);
  PF stores (N/2+1, N, N, 3) reduced-axis-first. So the converter is: ω̂ = i κ×û (curl), an axis
  permutation, h5py write.
- On read TurTLE low-passes, projects div-free, and SYMMETRIZES (vorticity_equation.hpp:150–153),
  so the injected field need not be perfectly Hermitian — but inject the exact intended field
  anyway; the sanitization is a safety net, not a channel.

## TurTLE build: DONE (2026-08-28, Aiporetne) — version 8.2.1

The clone `inspiration/dns/turtle` is now checked out at tag **8.2.1** (= current upstream
master 8ad5402d, 2026-07-23; owner-requested upgrade from the 7.0.4 snapshot). 8.2.1 is
physics-identical to 7.0.4: the 8.x major bump is the scikit-build/pytest overhaul; only
four `cpp/` files changed, none solver code — the dealias_type trap verification carries
over unchanged. One upstream fix of note for the PARTICLE leg: 7.0.5's "prevent
inconsistent hdf5-meta in particle output" is now included. Built, installed, and
validated (tutorial 32³ NSVE + `pytest -m basic`: 14/14) in the fleet-shared
`inspiration/dns/turtle-deploy/` (Dropbox-synced; Enteropia only needs the same apt
packages). **Read `inspiration/dns/turtle-deploy/README.md`** for usage, the two live
deviations (the quoted-HINTS patch to the installed `_code.py` — an upstream
spaces-in-path bug — and the tags fetch), and the rebuild recipe. Work-list item 5 is now
only "run from the injected IC".

## NOT yet built (was queued when the instrument work interceded) — the home session's work list

1. ~~PF axis-convention check~~ **DONE 2026-08-28** — see the VERIFIED section above.
2. **The TurTLE→IT IC converter** (direction reversed by the owner: read TurTLE's
   `vorticity/complex/<iter>`, permute, inverse-curl to û) with a round-trip witness.
   **POSTPONED (owner, 2026-08-28) — do not build until asked.**
3. **The TurTLE warm-up run**: 256³ Hou–Li per the table (both codes start from its
   checkpoint); then IT's leg from the imported IC, recording E(κ), ε, u′, Re_λ, skewness.
4. **`docs/src/validation.md`**: the comparison page — physics setup, both parameter files, the
   transfer recipe, reproduction instructions, results table (marked awaiting the TurTLE leg, not
   silently empty). The owner wants the results VISIBLE on the docs page and REPRODUCIBLE from it.
5. TurTLE side: build, run from the injected IC, fill the table.

## Standing context worth knowing

- Fleet finding (2026-08-26): Aiporetne ≥ Enteropia for DNS — ±0.5% F32, 15.6% faster F64, 24 GB.
  The "fleet's fastest card = Enteropia" line in its CLAUDE.md is stale for this workload.
- The instrument freeze binds (fdeba74): no .claude/commands changes inside a scoring round.
- E8 (vorticity formulation) is on OPEN-ITEMS as a future feature — not part of this comparison.

## CPU performance head-to-head (2026-08-28, owner-requested; CORRECTED same day)

**First numbers RETRACTED (owner-caught)**: the original comparison used TurTLE's production-leg
means (0.289 s/step) as reference — but those legs ran while this session was building docs and
running test suites on the same cores, while IT's bench ran on a quieter box. Unequal noise
floors inflated the gap to a claimed 1.17×.

**Clean protocol** (short dedicated runs, strictly sequential, idle box, no session activity
during timing; first 50 steps of each discarded): TurTLE `cpubench` 400 steps via
`cpubench_driver.py`; IT via `it_cpu_bench.jl` (300 timed steps, identical checksum across
runs). Same 128³ F64 point, same handoff, same sampling cadence, i7-12700K:

- TurTLE (8 MPI × 2 OMP): **0.262 s/step**
- IT (16 Julia+FFTW threads): **0.248 s/step** → IT ≈ **1.06× faster**, not 1.17×.

Planner: ESTIMATE vs MEASURE Δ −0.5% at F64/16t (PF's mis-planning is F32-specific; a F32 CPU
bench is where MEASURE should earn ~2×). Structural notes stand: IT shared-memory (no MPI slab
transposes) vs TurTLE's cluster-scalable MPI; TurTLE's figure includes its niter_part HDF5
writes. Context: IT GPU 0.0144 s/step ≈ 17× its own CPU.

## Third comparison: IFLowStorageRK4 + adaptive step (owner-directed, 2026-08-29)

Same handoff, same 10⁴ particles, same ConstantPower forcing as the first pair; IT runs
`IFLowStorageRK4` (decision 85) under the ADAPTIVE CFL controller instead of the fixed matched
dt. 6,739 steps at mean dt 0.00546 (2.73× the fixed 2e-3; the fixed value was conservative —
chosen for matching, not stability), wall 174 s vs the fixed-dt IT leg's 265 s = 1.52× faster
for the same 36.8 t.u. RESULTS: statistical identity — ρ_u within 5e-6…1e-5 through the decay;
k/ε track at 1e-6–1e-5 rel through t ≈ 5 (truncation-seeded ~6e-7 at t = 1: different tableaux
at different steps — vs 1e-12 for the matched pair, a clean seed ladder), window ε̄ within 0.2%,
k̄ within 3%. Files: `gbgit_rk4adaptive_reference_data.h5` (irregular t grid = τ grid;
self-describing attrs), overlay `comparison_overlay_rk4.png`, leg script `it_leg_rk4.jl`.
PUBLISHED (owner-directed 2026-08-31): the page's "Robustness across integrators" section,
scripts in `validation/` (`it_leg_rk4.jl`, `overlay_plots_rk4.py`), overlay in `docs/src/assets/`,
and the h5 as the sixth release asset (sha256 1629764125ab00230d9a6d32fe710242075bb57264aea828113a0fe258094ca9).

**CPU head-to-head ADDENDUM (2026-08-30)**: after PF's weighted_inner CPU fix (their 26c76205,
IT bump in the same-day commit), the clean IT step is 0.202 s (was 0.248) — IT ≈ **1.30× faster
than TurTLE** on the i7 (was 1.06×). weighted_inner itself: 19.2 → 1.08 ms at -t8 (17.8×);
bench checksum bit-identical.

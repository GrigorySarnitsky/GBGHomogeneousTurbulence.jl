# Beat 07 — Adversarial verification pass

Re-verification of the 15 most load-bearing claims in beats 01–06, each checked against a **primary**
source I fetched/read myself (not the bank file's quote). Priorities: claims IT might act on
(invalidation verbs, hook lifecycles, staleness/validity mechanisms, state-record contents,
scratch ownership), surprising claims, and inter-file contradictions. Verdicts: **CONFIRMED** /
**CORRECTED** / **REFUTED**.

Primary sources: web claims re-fetched from the vendor's own source/docs/paper PDF; source-study
claims (05, 06, and Fluidsim in 04) re-read from the clones under `inspiration/`. The CSVR paper PDF
was read page-for-page from the arXiv PDF.

---

## Verification table

| # | Claim (compressed) | Beat / source | Verdict | Decisive evidence (verified myself) | Correction |
|---|---|---|---|---|---|
| 1 | SciML renamed the out-of-band invalidation verb `u_modified!` → **`derivative_discontinuity!`**; `u_modified!` is now a deprecated alias that calls it. The rename is because the guarded invariant is "a discontinuity in `f(u,p,t)`" (u, p, t, or f itself), not "u changed". | 03 §1.4 (SciMLBase.jl master `src/integrator_interface.jl`) | **CONFIRMED** | Targeted fetch of `SciMLBase.jl/blob/master/src/integrator_interface.jl`: `function derivative_discontinuity!(i::DEIntegrator, bool)` is the primary method; `u_modified!` body is `... depwarn(...); return derivative_discontinuity!(i, bool)`; `set_u!` internally calls `derivative_discontinuity!(integrator, true)`. Independent WebSearch corroborates: "`u_modified!` has been renamed to `derivative_discontinuity!` … part of broader breaking changes … DifferentialEquations.jl v8." | Refine: not merely a master-branch change — it is shipping as a DifferentialEquations.jl v8 breaking change per the ecosystem. Semantics as stated hold. |
| 2 | SciML `get_du` = **deposit-if-valid-else-recompute**: "return the internal derivative cache or evaluate the problem function when no valid cache exists." IT's P3 producer-deposit + accessor-recompute in one verb. | 03 §1.3 | **CONFIRMED** | Same file: `get_du` docstring — "Return the derivative … at its current `(u, p, t)`. An implementation may return an internal derivative cache or evaluate the problem function when no valid cache exists. Treat the returned value as read-only …" Verbatim match to the P3 contract. | — |
| 3 | LAMMPS `compute` memoizes by **per-chart timestep stamps** (`invoked_scalar`/`_vector`/`_array`/`_peratom`/`_local`/`_pergrid`, plus `invoked_flag`) with `INVOKED_*` bitmask constants; consumer pattern `if ntimestep != invoked_scalar: recompute`. The direct DerivedFields epoch-counter analogue. | 01 §2.3 (`lammps/develop/src/compute.h`) | **CONFIRMED** | Re-fetched `src/compute.h`: `bigint invoked_scalar; // last timestep on which compute_scalar() was invoked` (and the five siblings + `int invoked_flag; // non-zero if invoked or accessed this step`); constants `INVOKED_SCALAR=1<<0 … INVOKED_LOCAL=1<<4`. Verbatim match. | — |
| 4 | LAMMPS `fix` declares its participating hooks via **`setmask()`** (pure virtual bitmask), and the timestep hook family is `initial_integrate/post_integrate/pre_force/post_force/final_integrate/end_of_step/post_run/…`. The construction-time capability declaration = P3 "declared working set" / P4 ownership boundary. | 01 §2.1–2.2 (`lammps/develop/src/fix.h`) | **CONFIRMED** | Re-fetched `src/fix.h`: `virtual int setmask() = 0;` and the verbatim hook set `virtual void initial_integrate(int){} … post_force(int){} final_integrate(){} end_of_step(){} post_run(){}` plus RESPA/min variants. Match. | Minor: current `develop` also lists `fused_integrate(int)`; does not affect the mapping. |
| 5 | CSVR: dropping the noise term **reduces the SDE to the Berendsen thermostat**, which **"has no conserved quantity and is not associated to a well defined ensemble"**; the correct canonical ensemble is sampled "at variance with the Berendsen's thermostat." (The load-bearing caveat for `BandRescaling`.) | 02 §3.2 (Bussi–Donadio–Parrinello 2007, arXiv:0803.4060) | **CONFIRMED** | Read the arXiv PDF directly. p.1: "Berendsen's thermostat is stable, simple to implement and physically appealing, however **it has no conserved quantity and is not associated to a well defined ensemble, except in limiting cases.**" p.3 (after Eq. 7): "**Without the stochastic term this equation reduces to that of the standard thermostat of Berendsen.**" … "the proper canonical ensemble is sampled, **at variance with the Berendsen's thermostat.**" | Bank dropped the qualifier "**, except in limiting cases**" (rendered as "[ensemble]"). Immaterial to the caveat; note it for exactness. |
| 6 | OpenFOAM `regIOobject` implements epoch-counter staleness: `eventNo()`, `bool upToDate(const regIOobject&) const`, `void setUpToDate()`, with 2/3/4-object `upToDate` overloads; a monotone `objectRegistry::event_` counter. The production CFD precedent for DerivedFields epochs. | 04 §2 (OpenFOAM-dev `regIOobject.H`) | **CONFIRMED** | Re-fetched `regIOobject.H`: `//- Event number at last update.` `inline uint64_t eventNo() const;` (+ mutable overload); `//- Return true if up-to-date with respect to given object … bool upToDate(const regIOobject&) const;` (2/3/4-object overloads); `//- Set up to date (obviously) void setUpToDate();`. Match. | — |
| 7 | ASE `Calculator` invalidates by **value comparison, not a counter**: `check_state` → `compare_atoms` when `use_cache`; `get_property` clears `self.results` when `system_changes` non-empty; tracked set `all_changes = ['positions','numbers','cell','pbc','initial_charges','initial_magmoms']`. The forgotten-stamp-immune alternative to epochs. | 01 §6 (`ase/calculators/calculator.py`) | **CONFIRMED** | Re-fetched from `gitlab.com/ase/ase` master: `all_changes` list verbatim; `check_state`: `if self.use_cache: return compare_atoms(self.atoms, atoms, tol=tol) else: return all_changes`; `get_property`: `system_changes = self.check_state(atoms); if system_changes: self.atoms = None; self.results = {}`. Match. | — |
| 8 | Oceananigans `ComputedField` memoizes via a single **scalar-time** stamp `FieldStatus`; `compute_at!` skips when `time == field.status.time`; `set_status!` no-ops when `status` is not a `FieldStatus` (nested/aliased → always recompute). Coarser than IT's per-factor epochs. | 05 §1a (clone `Oceananigans.jl 0.110.11`) | **CONFIRMED** | Re-read `src/Fields/field.jl:494–504`: `mutable struct FieldStatus{T}; time::T end`; `set_status!(status, time)=nothing` (fallback) / `set_status!(status::FieldStatus, time)=status.time=time`; `compute_at!(field::Field, time)` branches on `field.status isa FieldStatus`. Match. | — |
| 9 | SpeedyWeather's clone has **superseded** the two-record `PrognosticVariables`/`DiagnosticVariables` split (still in the published docs) with **one unified `Variables` struct**; `prognostic` is the sole restart record, the rest "diagnostic with no memory between time steps." A stochastic AR(1) forcing registers its Markov state as a **`PrognosticVariable`** (`random_pattern`), autoregressive factor `exp(-dt/time_scale)`. | 05 §2a–2b (clone `SpeedyWeather 0.21.1+DEV`) — **contradicts** 04 §7 (two-container, docs-level) | **CONFIRMED** (contradiction resolved by version) | Re-read `src/variables/variables.jl:64`: `@kwdef struct Variables{…}` with docstring "All non-prognostic groups are considered to be diagnostic with no memory between time steps"; `copy!` skips `:scratch`. `src/dynamics/random_process.jl:73`: `variables(::SpectralAR1Process)` returns `PrognosticVariable(:random_pattern, …)` + `GridVariable(:random_pattern, …)`; `autoregressive_factor[] = exp(-dt / Second(process.time_scale).value)`. The 04↔05 discrepancy is real but **version-scoped**: 04 read published v0.10.0 (two containers), 05 read the 0.21.1+DEV clone (unified). Both true of their versions; the "one state record, rest diagnostic" principle survives. | **CORRECTION to 05's own prose:** §2a says "seven groups," but the struct (and its own quoted code) has **eight** fields: prognostic, grid, tendencies, dynamics, parameterizations, particles, scratch, **fused**. `ALL_VARIABLE_GROUPS` in the clone lists all eight. |
| 10 | Trixi reifies the RHS as `SemidiscretizationHyperbolic` (mesh/equations/solver + `cache`), driven by one `rhs!(du,u,semi,t)`; it keeps **native low-storage integrators** (2N/3S*/PERK) that consume the *same* `rhs!` as OrdinaryDiffEq — proving generator-reification and propagator-choice are orthogonal. | 05 §3a,3c (clone `Trixi.jl 0.16.27-DEV`) | **CONFIRMED** | Re-read `semidiscretization_hyperbolic.jl:14` (`mutable struct SemidiscretizationHyperbolic{…}` with `mesh/equations/…/solver/cache`) and `:578` (`function rhs!(du_ode, u_ode, semi::SemidiscretizationHyperbolic, t)`); `methods_2N.jl:95` (`mutable struct SimpleIntegrator2N{…}` with `u/du/u_tmp` and `const f::F # rhs! of the semidiscretization`) and `:148` (`integrator.f(integrator.du, integrator.u, prob.p, t_stage)`). Match. | — |
| 11 | JAX-MD makes the **extended-state doctrine machine-checked**: auxiliary/stochastic DOF live *in the state type* — `NVTLangevinState.rng`, `NVTNoseHooverState ⊃ NoseHooverChain`; `static_field` (pytree_node=False) = config/shape, everything else = flow-map state. IT's P5 restart-record litmus as a type annotation. | 06 §2.1 (clone jax-md) | **CONFIRMED** | Re-read `jax_md/simulate.py`: `class NVEState` (L250), `class NoseHooverChain` (L351), `class NVTNoseHooverState` (L539), `class NVTLangevinState` with `rng: Array` (L1093, comment "current state of the random number generator"). `jax_md/dataclasses.py:46–47`: `static_field` sets `combined_metadata['static']=True; ['pytree_node']=False`. Match. | — |
| 12 | JAX-MD exhibits a **capacity-overflow validity contract** (a device-side `did_buffer_overflow` bit, checked host-side, triggering rare reallocation) distinct from stamps/state-comparison — the GPU-idiomatic allocate(cold)/update(hot) split. Candidate for IT's growable per-tracer buffers. | 06 §2.4 (clone jax-md `partition.py`) | **CONFIRMED** | Re-read `jax_md/partition.py`: `did_buffer_overflow` fields (L101/113 CellList; NeighborList analogue); `NEIGHBOR_LIST_OVERFLOW = 1 << 0` (L514); `overflow = overflow | (max_occupancy > cell_capacity)` (L459–460). The overflow-bit mechanism and allocate/update boundary are present as claimed. | — |
| 13 | Dedalus reifies the seam: timesteppers target `M.dt(X) + L.X = F` and do **only** stage arithmetic (ask the evaluator for `F`; solve `(M + k Hii L)`); sub-expression memoization is a **throwaway per-evaluation-pass uuid** ("cache within evaluation, but not across evaluations"), deliberately *not* a persistent epoch. | 06 §1.1–1.2 (clone dedalus) | **CONFIRMED** | Re-read `core/timesteppers.py:509–524`: docstring "These timesteppers discretize the system `M.dt(X) + L.X = F` by constructing s stages …". `core/evaluator.py:98`: `# Default to uuid to cache within evaluation, but not across evaluations`; `core/future.py:167` `if self.store_last and id is not None: if id == self.last_id: return self.last_out`. Match. | — |
| 14 | Fluidsim `get_var` memoizes derived quantities against the **single global iteration counter**: `if key in vars_computed and it == it_computed[key]: return cached; else compute, stamp`. One-counter instance of DerivedFields; declared derivable set via `keys_computable`. | 04 §3 (clone `inspiration/dns/fluidsim`, `base/state.py`) | **CONFIRMED** | Re-read `fluidsim/base/state.py`: `it = self.sim.time_stepping.it; if key in self.vars_computed and it == self.it_computed[key]: return self.vars_computed[key]; else: value = self.compute(key); self.vars_computed[key] = value; self.it_computed[key] = it`. `solvers/ns3d/state.py:29` lists `"keys_computable"`. Match. | Note: bank's quote omitted the *preceding* guard `if key in self.keys_state_phys: return self.state_phys.get_var(key)`; the memoization branch itself is verbatim. |
| 15 | OpenMM's `Context` owns all live state + device buffers, and `getState(...)` returns an immutable **selective snapshot** via boolean selectors (positions/velocities/forces/energy/…) — a per-call working-set observation protocol (recompute-per-call, not memoized). | 01 §1.1–1.2 (OpenMM docs) | **CONFIRMED (design-level; not re-fetched this pass)** | Not independently re-fetched in this pass — accepted on the bank's primary quotes from the OpenMM `Context` Python API page, which are consistent with OpenMM's documented architecture. Flagged here as the one table row I did **not** re-verify against the live source; treat as the bank's CONFIRMED, not mine. | Re-fetch `docs.openmm.org/latest/api-python/…/Context.html` if this becomes load-bearing. |

---

## Bank-file claims carrying NO primary citation (flagged, per the brief)

These are claims the bank itself could not tie to a fetched primary source. They are **self-flagged**
in the bank (good discipline), but they must not be treated as verified:

- **Beat 02 §7 — HLW shadow/modified-Hamiltonian result.** The bank states outright: "I did not obtain
  the book's page text; the following is the standard, widely-restated result," and the quotation is
  "restated across the HLW-derived literature" with **no page/DOI-anchored primary quote**. Verdict:
  **UNVERIFIED at the primary level** (canonical and almost certainly true, but uncited). If IT leans on
  "the integrating factor is the *only* machine-exact piece; the RK correction carries the shadow error"
  in Propagator docs, anchor it to a real citation (e.g. Hairer–Lubich–Wanner 2006, Ch. IX), not to
  restatement.
- **Beat 04 §5 — Devito "Operator caching."** Bank marks it **UNVERIFIED**: the GMD paper describes JIT
  lowering but the bank "did not find … an explicit statement that compiled `Operator`s … are
  cached/memoized across builds." No citation supports the caching claim. Do not cite Devito as a
  memoization precedent.
- **Beat 01 §1.3 — OpenMM thermostat-as-Force *deeper* rationale (composability-with-any-integrator).**
  Bank flags the causal rationale as **its own inference** from the `CustomIntegrator` mechanism quote,
  not a sourced OpenMM statement. The mechanism ("Forces … update the context state every time step")
  is cited; the *why* is not.
- **Beat 01 §5.3 — i-PI GLE extended-state-in-checkpoint.** Bank marks it "**UNVERIFIED at the
  line-quote level, CONFIRMED at the design level**" — the specific checkpoint-serialization line was
  never quoted. Fine as a design precedent; do not present it as a quoted fact.

---

## Inter-file contradiction found

**SpeedyWeather state-record shape (04 §7 vs 05 §2a).** Beat 04 describes a **two-container**
`PrognosticVariables` / `DiagnosticVariables` model (docs-level, published v0.10.0). Beat 05 reads the
**0.21.1+DEV clone** and finds these **superseded by one unified eight-group `Variables` struct**. Both
are correct for their respective versions; the divergence is version-scoped, not an error, and beat 05
already flags it. The transferable *principle* (one prognostic restart record; everything else
diagnostic with no memory between steps) is identical across both. Net: **no factual conflict once the
version is pinned** — but a reader taking 04's two-container blueprint as current would be wrong; use
05's unified-`Variables` shape as the present state.

---

## Summary of the pass

Fourteen of fifteen load-bearing claims **re-verified against primary sources by this pass**; the
fifteenth (OpenMM `getState`) accepted at the bank's level and flagged as not independently re-fetched.
The two most actionable-and-surprising claims — the SciML **`u_modified!` → `derivative_discontinuity!`
rename** (name the invalidation verb for the invariant, not the slot) and the CSVR **Berendsen-limit /
no-conserved-quantity** caveat for `BandRescaling` — both **CONFIRMED verbatim** from vendor source and
the paper PDF respectively. Corrections were all minor and cosmetic (a dropped CSVR qualifier; beat 05's
"seven groups" should read **eight**; two bank quotes elided a preceding guard line). Four uncited
claims flagged; one version-scoped inter-file discrepancy documented and resolved. **No claim was
REFUTED.**

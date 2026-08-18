# `.claude/` — local working artifacts (GBGIsotropicTurbulence)

Untracked working notes (not committed). This index exists so a future session sees at a glance
what is **live** (pending work — act only when the user says) versus **archived** (done or
superseded — do **not** act on it). If you find a task-looking document, check here first before
assuming it is current.

## Status — the piles are worked off

Both files were **piles**: the user found problems by reading, reported them, I collected them here and
touched no `src`/`docs` file until told to fix. See [[docstrings-are-the-steering-surface]]. The
**documentation fix pass ran 2026-07-13** — commits `e56583a` (src docstrings + ARCHITECTURE/notation
prose) and `2e12afc` (map pages + api-page grouping), both green (load + tests + docs build).

**LIVE — doc-review panel round 2 (11 hats, ran 2026-07-15).** `doc-review/` now holds a **fresh**
11-expert RENDERED-docs re-audit (the round-3 fix pass rebuilt the docs; the 8-hat round-1 panel moved to
`doc-review-round1/`). The 8 original hats plus three the user asked for — **software-architect**
(senior-Julia design, sees Architecture), **structure-consistency** (docstring-shape uniformity,
Architecture withheld), **latex-typesetter**. Sequential, collect-only; each hat banked `NN-<key>.md`,
consolidated in `doc-review/00-SUMMARY.md` + an Artifact. **66 findings: 2 blocker, 6 major, 28 minor, 30
nit**; physics core / dealias band / time-integration / main citations re-verified clean; 3 false positives
recorded. Every Tier-1/2 finding re-verified against current `src/`+built HTML. Top: **F01** stale `f(sim)`
observable docs (5 hats — code removed the forms, docs still advertise → `MethodError`); **F02**
`allocate_buffers` `+ `→bullet render break (5 hats, HTML-confirmed); **F03** front-door forcing default
`BandRescaling(:total)` vs `NoForcing()` (`Generator.jl:53` wrong vs `SimulationRun.jl:154`); **F04**
`Li2008` G/C_ε length overload; **F07** decision-log ordinals vs unordered §11; **F08** Pope2000 factory-not-subtype.
**Act only when the user says fix.**

**DONE — round 3 (executed 2026-07-14, commits `a3a523c`…`08c2c4d`; full suite green, Docs CI green +
deployed).** Stage 1 code (defaults→front-door, `element_type`, `step!`→`State`, per-scheme buffers), the
observable-off-`Simulation` correction (M8 reverted — observables are functions of the state), stage 2
docs (§1–§14, P1–P4, §4 citations + `/check-docs` policy), stage 3 `ARCHITECTURE` (decision 28, `Generator`
roadmap, exact-alloc invariant). Only `return-type annotations` (nit) deliberately left. Originally:
**round 3 (opened 2026-07-14):** `docstring-review-round3.md` collects a fresh user read-through
of the **rendered** docs, after the 8-hat panel fix pass (commits `90c9829`, `3e6c5e7`). Collect-only —
act only when the user says fix. (The round-1 machine panel now sits in `doc-review-round1/`; its fix pass was
**RE-AUDITED 2026-07-14** by 6 independent agents — see `panel-reaudit.md` — which found it **not** fully
worked off: 2 laundered, 4 partial, 10 still-open, 1 false-positive. Those fed the round-3 fix list; the
still-open remainder is re-surfaced and superseded by the round-2 panel above.)

### `docstring-review-round2.md` — WORKED OFF
A **fresh** read of the docs after the fix pass + rename. Collected §1–§19, then fixed them in three
commits: `fd93722` (module-map bullets, MZ bounded to the developer docs, the `target` forcing rename +
field-aware behavior, the constructor-first type-docstring structure), `1039f3b` (Propagator/`step!` +
remaining #29/#18 + doc pages), and the **InterLinks commit** (§4 cross-package clickable `@extref` links via
`DocumenterInterLinks` — Base/CUDA/AMDGPU/PF inventories, the Julia types role-pinned `:jl:type:`; §11
`Phenomenology` made clickable through the *fully-qualified* `@ref GBGIsotropicTurbulence.Phenomenology`, since
a bare `@ref` to a sibling submodule does not resolve). Deferred by decision: §27 (minor) and D3. Round-1's
piles below stay a reusable reference — their defect-classes and cold-read probes recur.

### `docstring-review-pile.md`
Problems found reading the **docstrings / doc pages**. Two tracks in one file:
- **Documentation problems** §1–§31 — **FIXED** (`e56583a` + `2e12afc`), each re-verified against the
  post-refactor code first (the refactor had already absorbed several). The two once-held items are now
  done too (`1ad1eca`): doc-#10's kwarg rename (`energy`→`kinetic_energy`, `variance`→`scalar_variance`
  *everywhere* — the user chose "qualified everywhere"; observables were already qualified; `StochasticOU`'s
  `variance` left untouched, being the OU forcing variance not the scalar variance) and doc-#9's `CLAUDE.md`
  "symbol of −∇²" line (**removed** the example — doc #9 gave −∇² a clean statement, so it was a poor
  "no clean formula exists" example; the integrating-factor example stays). **Deferred (minor):** doc-#27
  (a BandRescaling total-vs-resolved-energy clarification).
- **Design problems** D1–D12 — structural/API/naming questions, *not* docstrings. Status (this
  supersedes the per-entry "collected" notes in the pile):
  - **DONE:** **D1 / D2** (state reified as `ResolvedFields`, single source of truth; the step scratch
    dissolved from `FieldBuffers` → `IntegratorBuffers` in `Propagator`; observables made thin readers of
    the state — `f029cd0`); D4 (`Physics` → `FlowConditions` into `Generator`, `4e2c0bd`); D9 (archive OU
    `StochasticOU`, `92f5c2d`); D5, D7, D8, D10 (Hou–Li auto strength; scalar `spectrum`; `velocity_vorticity!`
    split into `velocity_to_physical!` + `vorticity_to_physical!`; `ForcingSpec` → `DeferredForcing` —
    `0f9cee5`); **D11** (removed `default_integrator` — `recommended_cfl` takes the integrator explicitly, so
    there is no `default_anything`; `Simulation` inlines `IFLowStorageRK3()` as its kwarg default — `42a7017`).
  - **Roadmapped** (ARCHITECTURE §7 "Deliberately deferred", `42a7017`): D6 (broaden `DealiasingStrategy` to
    own the de-aliased nonlinear-product assembly, so 3/2-padding, phase-shift, and the skew-symmetric
    momentum form all fit), D12 (a temporal-accuracy step control distinct from the stability CFL).
  - **Postponed:** D3 (explicit-arg vs `kwargs` principle — the recommendation stands: name what you
    consume and can default, forward the rest; ties to doc-problem #16).
  - **Net:** the design track is closed — every D-item is done, roadmapped, or postponed. The **only live
    work is the documentation fix pass** (docstring §1–§31 + the architecture-review-pile prose edits).
- A **"Cross-cutting directives"** section sits between the two tracks.

### `architecture-review-pile.md`
The 12 problems the user found reading the `docs/ARCHITECTURE.md` rewrite. **All resolved:**
- **Closed earlier** (`4e2c0bd`, decision 23): #7 (forcing methods → verb-first), #8 (`Physics` →
  `FlowConditions`), #11 (stateful-forcing state homes in a `modeled` slot — deferred), #12 (open-systems
  framing = a §8 sub-lens, no new types).
- **Verified done at pass time:** re-checking the current `ARCHITECTURE.md` found the rewrite had already
  absorbed #1 (CloudPhysics linked to its docs site), #3 (name only the default dealiasing), #4 (no
  `\texttt` left; the set-notation braces gone), #5 (`IntegratorBuffers` sized to the run), #6 (the
  coordinate-free convention is in §10), #9 (statistics the sole `Float64` computational exception), #10
  (invariant 8 is denotation, not identity), and #2 at its flagged line — the whole-doc #2 sweep was
  clean. Only **#8-doc** ("follows Pope's conventions" → "standard usage; see Pope") needed applying,
  done in `e56583a` (with the notation.md twin).

## Post-refactor name map (commit `4e2c0bd`, 2026-07-12)

The piles were written **before** the refactor and use the old names. Translate when reading them:

| Pile says (old) | Now |
|---|---|
| module `SimulationState` | split → module `SimulationDomain` (the frame) + module `State` (the field) |
| module `Dynamics` | module `Generator` |
| module `TimeIntegration` | module `Propagator` |
| the domain **type** `SimulationDomain` | type `FixedDomain` (module keeps the name; a sheared frame is `ShearedDomain`, deferred) |
| `Physics` | `FlowConditions` (now lives in `Generator`) |
| `forcing_rate!` / `forcing_source!` | `set_forcing_rate!` / `add_forcing_source!` |

## Archived — done or superseded (do NOT act on these)

In `archive/` (see `archive/README.md`): the physics-first redesign proposal and the ARCHITECTURE.md
rewrite blueprint (both realized in the rewrite `4ca8ef2` + refactor `4e2c0bd`), an earlier draft of
the Alloy model (superseded by the committed `docs/architecture.als`), and the stale
`sorted-painting-ritchie.md` plan (its reports are a subset of `docstring-review-pile.md`).

Note: `docs/architecture.als` (committed) is the canonical Alloy structural model. Two plan files in
the global `~/.claude/plans/` belong to **other** projects (GBGStreamingStatistics, GBGPeriodicFields),
not this one.

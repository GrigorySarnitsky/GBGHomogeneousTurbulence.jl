# Fix audit — batch 9–16

Auditing `52ada56..HEAD` against the pile at
`.claude/doc-review/00-checkdocs-2026-08-24-findings.md`.

---

## 9
**Owner's ask (as recorded in the pile):** "`velocity_at_particles` docstring used ``(M, 3)`` with
M unbound." CLAIM: glossed "(``M`` the tracer count)".

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** `src/Cache.jl:262` now reads: "current epoch — the ``(M, 3)`` array (``M`` the tracer
count) of the velocity sampled at the position each tracer occupies at that instant". Diff confirms
the gloss was inserted at exactly the flagged clause (`git diff 52ada56..HEAD -- src/Cache.jl`).
Checked the class: `M` also appears unglossed at `Particles.jl:634` and in three `docs/src/decisions.md`
sites — but `docs/src/notation.md:39` already binds ``M`` package-wide ("the number of tracer
particles"), and the doc policy states explicitly that "a docstring introduces a symbol on first use
and need not repeat the convention" once the glossary carries it. So the other sites are not
instances of the same defect; this is not a LINE-ONLY case.

---

## 10
**Owner's ask:** Duplicate-linked targets (link-once-per-docstring rule), 5 named sites: Cache
`particles_modified!` linked `deposit!` twice; Forcing `set_forcing_rate!` linked
`uses_steady_linear_rate` twice; VarianceController linked `VarianceRescaling` twice; Observables
`integral_scale` linked `energy_spectrum` twice; Particles `advect!` linked `Heun` twice. CLAIM: each
second link demoted to backticks; dupref reports 0.

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** Verified all five docstrings by direct inspection of the current source and the diff:
- `src/Cache.jl` `particles_modified!`: `[`deposit!`](@ref …)` appears once (line ~411); the earlier
  mention was demoted to bare `` `deposit!(cache, tracers, u)` `` (diff: `- [`deposit!`](@ref
  GBGIsotropicTurbulence.Propagator.deposit!)`(cache, tracers, u)`` / `+ `deposit!(cache, tracers,
  u)``).
- `src/Forcing.jl` `set_forcing_rate!`: `uses_steady_linear_rate` demoted at line 190 (diff: `-
  [`uses_steady_linear_rate`](@ref)` / `+ `uses_steady_linear_rate``), the earlier mention at line
  185 stays linked.
- `src/Forcing.jl` `VarianceController`: `VarianceRescaling` demoted (diff: `-
  [`VarianceRescaling`](@ref)` / `+ `VarianceRescaling``).
- `src/Observables.jl` `integral_scale`: `energy_spectrum` demoted (diff: `-
  [`energy_spectrum`](@ref)` / `+ `energy_spectrum``), its earlier mention (the function's own
  definition line) stays linked.
- `src/Particles.jl` `advect!`: only one `[`Heun`](@ref)` remains linked; the newly-added
  AdamsBashforth section's mention of Heun is bare `` `Heun` `` — confirming the fix pass caught its
  own newly-introduced duplicate, as the pile notes.

---

## 11
**Owner's ask:** Abutting code-span/math-span pairs in `observables_cache.md:331-332`
("`history_depth` ``> 1``" and "`history_depth` ``- 1``"). CLAIM: reworded to "above 1" / "minus
one". The two ARCHITECTURE hits (``\nu = 0`` next to `IFHeun`; ``256^{3}`` next to `PhaseShift`) are
DISMISSED as the documented false-positive class.

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** `docs/src/observables_cache.md:331-332` now reads "with `history_depth` above 1 it
keeps a bounded ring of **past** velocity samples — `history_depth` minus one further ``M\times3``
arrays beyond the current slot" — both math spans removed, no code/math abutment remains. For the
two dismissals: `.claude/commands/check-docs.md:187-190` states the battery's own triage rule
verbatim — "plain adjacency of two unrelated things (a grid size next to a strategy name) is not" a
hit — which is a **literal, pre-existing textual match** for `docs/ARCHITECTURE.md:1447`'s
"``256^{3}`` `PhaseShift` run" (grid size next to strategy name) and a parallel case for line 731's
"``\nu = 0`` `IFHeun`" (a condition next to a scheme name, not "an argument name followed by the
symbol it denotes"). This is a codebase-defined mechanical rule applied correctly, not an
assistant-invented "by design" excuse — so it is not LAUNDERED.

---

## 12
**Owner's ask:** Argument coverage: `restart!(scheme, buffers)` never documented `scheme`;
`unwrapped_positions(tracers)` never documented `tracers`. CLAIM: both bound in prose; argcov
reports 0.

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** `src/Particles.jl` `restart!` docstring now opens "Discard whatever history `buffers`
holds for the particle integration scheme `scheme`, so the next [`advect!`](@ref) starts *that
scheme* from scratch" (diff: `- Discard whatever history \`buffers\` holds, so the next
[\`advect!\`](@ref) starts the scheme from scratch.` / `+ … holds for the particle integration
scheme \`scheme\`, so the next … starts that scheme from scratch.`). `unwrapped_positions`
docstring now opens "The **unwrapped** positions of the tracer set `tracers`, as a …" (diff: `- The
**unwrapped** tracer positions, as a` / `+ The **unwrapped** positions of the tracer set
\`tracers\`, as a`). Both arguments are now bound in prose exactly where the pile located the gap.

---

## 13
**Owner's ask:** Eight cross-module first mentions unlinked (xlink dry run). CLAIM: `APPLY=1`
auto-linked all eight; diff reviewed.

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** Re-ran the mechanical instrument at HEAD: `julia --project -e 'include(".claude/commands/check-docs/xlink.jl")'`
→ `FOUND 0 cross-module first mentions`. The script itself is byte-identical to its state before the
fix pass (`git diff 52ada56..HEAD -- .claude/commands/check-docs/xlink.jl` is empty) — it was
pre-existing tooling, not rewritten to pass trivially. Spot-checked several of the newly-linked
targets in the diff (`Simulation` in `Particles.jl`, `Tracers` in `Cache.jl`, `ResolvedFields` in
`Generator.jl`) — all are genuine defining-module-qualified `@ref`s to a different module, matching
the script's own selection logic (own-module names and already-linked names are excluded).

---

## 14
**Owner's ask:** `signature_fidelity.jl` reported 30 phantom asymmetries — all ten persistence
stubs, whose methods live in the unloaded HDF5 extension. CLAIM: instrument taught the class (empty
method table → "EXTENSION-HOMED — skipped"); now CLEAN over 97 bindings.

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** Re-ran the instrument at HEAD: `julia --project --startup-file=no
.claude/commands/check-docs/signature_fidelity.jl` → exactly ten `EXTENSION-HOMED (no methods
loaded) — skipped` lines (`read_domain`, `read_forcing`, `read_simulation`, `read_state`,
`read_tracers`, `write_domain`, `write_forcing`, `write_simulation`, `write_state`,
`write_tracers`), followed by `signature fidelity: CLEAN over 97 displayed bindings` — matching the
claim's numbers exactly. The diff confirms the instrument itself was taught the class (a new
`isempty(methods(f))` branch added in `defined_sets`, with a `#` comment explaining the weak-dependency
extension case), rather than the underlying persistence docstrings being papered over — the right
surface (the checker, which had a real blind spot) was fixed, not the flagged instances individually.

---

## 15
**Owner's ask:** `allocate_buffers` docstring said "One generic covers all three" — only two forms
exist since decision 70. CLAIM: now "covers both".

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** `src/Propagator.jl:168` now reads "…whose sample history it integrates over. One
generic covers both because it is one concept…" (diff: `- … One generic covers all three because it
is` / `+ … One generic covers both because it is`). Cross-checked against `docs/ARCHITECTURE.md:2208`
(decision 70: "One particle buffers type: `MultistepBuffers` is folded into…") and
`docs/ARCHITECTURE.md:2219` ("the two-argument form died") — confirms the docstring now correctly
describes exactly two forms (`allocate_buffers(scheme, domain; scalar)` and `allocate_buffers(scheme,
tracers, cache)`), matching the current signature block shown at the top of the same docstring.

---

## 16
**Owner's ask:** `advect!`'s shared docstring gave Heun's formula but no AdamsBashforth section; the
multistep update existed only in a non-rendered `#` comment. CLAIM: an "Under AdamsBashforth"
display-math section added (weighted sum over deposited samples, variable-step weights, bootstrap
note), and `AdamsBashforth`'s docstring now delegates "the update formula is given with `advect!`".

**VERDICT: HONORED**

**Question failed:** none.

**Evidence:** `src/Particles.jl`'s `advect!` docstring now carries an "Under
[`AdamsBashforth`](@ref)" section with the display formula
``\boldsymbol{X} \leftarrow \boldsymbol{X} + \sum_{j=0}^{K-1} b_j \boldsymbol{u}(t_{n-j},
\boldsymbol{X}(t_{n-j}))``, plus prose on the variable-step weights and the bootstrap note
("The first ``K-1`` pushes have no history yet and are taken under `Heun`; `velocity_end` feeds only
those bootstrap pushes"). Verified against the implementation at `src/Particles.jl:452-508`: the
`b[1]` weight multiplies `cache.velocity_at_particles` (the ``j=0`` sample) and `b[j+1]` multiplies
`past[j]` for `j = 1..K-1`, matching the formula's indexing; the `if cache.history_filled < K - 1`
branch calls `advect!(Heun(), …, velocity_end, …)` exactly for the bootstrap pushes, confirming the
`velocity_end`-only-for-bootstrap claim is literally true of the code, not merely plausible. The
`AdamsBashforth` type docstring (`src/Particles.jl:383-384`) now reads "…the trade is one stored
array per extra order against one interpolation per step; the update formula is given with
[`advect!`](@ref)." — the correct home/delegation direction (the in-place verb keeps the formula, the
type docstring links out), consistent with the corpus's `f`/`f!` one-home rule. The new caveat note
("The start-of-step velocity is read, never recomputed") still sits as the last substantive block of
the docstring, so this addition did not reintroduce the caveat-placement defect closed elsewhere in
the same pass (finding 30).

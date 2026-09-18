# Fix audit — findings 41–46 (check-docs 2026-08-24 pile)

Diff audited: `52ada56..HEAD` (commits `7abb434`, `c587b30`).

---

## Finding 41

**Owner's verbatim ask (pile text):** "observables_cache.md:419's FixedDomain construction line
was 137 columns. CLAIM: wrapped with a hanging indent."

**VERDICT: ADJACENT**
**Question failed: IMPLEMENTATION**

The line was split (`git diff` confirms: one 137-column line became two lines at
`docs/src/observables_cache.md:419-420`), so the right *kind* of repair (hanging-indent wrap) was
attempted. But the replacement is not actually correct against the corpus's own bound for this
exact defect class: the continuation line is **90 columns**, still over the 88-column ceiling that
this very fix pass enforces one finding later (finding 42's own claim: "in-fence lines now ≤ 88").

Measured directly against the current file (`python3` character count, not bytes):

```
419: domain = FixedDomain(; grid_points_per_axis = 64, side_length = 2π,      (67 cols)
420:                      dealiasing = TwoThirds(), element_type = Float64, array_type = Array)  (90 cols)
```

The continuation indent (21 spaces) also does not land under the first argument
(`grid_points_per_axis` starts at column 24, i.e. 23 spaces in), so it isn't even the
"hanging indent under the first argument" the house rule (CLAUDE.md silent-rendering rule (d))
calls for — a cosmetic miss layered on top of the substantive one. The horizontal-scroll defect
the finding exists to close is still present, just shorter.

---

## Finding 42

**Owner's verbatim ask (pile text):** "index.md quick-start julia block carried comment lines at
89-99 columns. CLAIM: initially skipped by the fix pass (caught while building this pile); comments
rewrapped, in-fence lines now ≤ 88."

**VERDICT: LINE-ONLY**
**Question failed: STRATEGY (line, not class)**

The claim is true as stated: every line inside `docs/src/index.md`'s quick-start `julia` fence
(lines 35-56) is now ≤ 88 columns — verified directly (max is line 53 at exactly 88). The named
instance is genuinely fixed, cleanly, with no information lost in the rewrap.

But the underlying class — a comment (or bare statement) inside a `julia` code fence in the docs
corpus exceeding 88 columns, the exact "no horizontal scroll" violation this fix targets — survives
untouched elsewhere, in files this commit range never touched (confirmed:
`git diff 52ada56..HEAD --stat` for these three files returns nothing):

- `docs/src/architecture.md:61` (99 cols): `# Observe and advance. The callback fires after every
  iteration (and once at the start); it records`
- `docs/src/api/Particles.md:81` (101 cols): `velocity_at_particles(sim.cache)
  # u(tₙ, X(tₙ)) — the Lagrangian sample, a checked read`
- `docs/src/phenomenology.md:20` (98 cols): `fp = FlowParameters(viscosity = 1e-3, dissipation =
  0.5, rms_velocity = 1.0, integral_scale = 1.0)`

Each is a code-fence line in `docs/src/` over the same 88-column bound this exact fix pass adopted
and applied only to `index.md`. The pile's own framing for finding 42 ("caught while building this
pile" — i.e. discovered by re-scanning rather than by design) signals the scan that surfaced the
`index.md` instance was not re-run corpus-wide before closing the finding.

---

## Finding 43

**Owner's verbatim ask (pile text):** "DISMISSED: reuse of ``K`` for the Grönwall Lipschitz constant
beside AdamsBashforth{K} — locally bound, standard usage, no house-glyph conflict."

**VERDICT: LAUNDERED**
**Question failed: STRATEGY**

This is a self-authored dismissal — nothing in the diff or the pile shows the owner adjudicating
this specific closure — and the reasoning it gives answers a narrower question than the one raised.
The finding's own title names the actual objection: reuse of `K` for the Lipschitz constant *beside*
`AdamsBashforth{K}`. Verified in `src/Particles.jl`: the `!!! warning` admonition using
`` ``K`` `` as the Lipschitz constant (lines 365-367, "a flow with Lipschitz constant ``K``... Grönwall
bounds the trajectory error by ``\delta(\mathrm{e}^{Kt} - 1)/K``") sits directly inside the docstring
attached to `struct AdamsBashforth{K} <: AbstractParticleIntegrator end` (line 386) — where `K` is
the struct's own type parameter (the order). This is exactly the local, same-object collision the
finding names.

The dismissal answers "is `K` a **house-reserved glyph**?" (no — confirmed against CLAUDE.md's
notation table and `docs/src/notation.md`, neither lists `K`) rather than the finding's actual
question, "does this docstring reuse one symbol for two concepts?" — which CLAUDE.md's doc-edit
checklist states independently of house-glyph status ("Notation — one symbol per concept, one
concept per symbol"). Mitigating fact, for the record: the rendered HTML signature block for
`AdamsBashforth` shows only `AdamsBashforth(; order = 4)` (verified in `docs/build/api/Particles/`)
— the type parameter `{K}` never appears in the rendered page next to the Lipschitz `K`, so the
collision is source-level, not reader-facing. That mitigating fact belongs in an escalation to the
owner, not in a self-declared close; the pile records no such owner ruling.

---

## Finding 44

**Owner's verbatim ask (pile text):** "DISMISSED: notation.md's Code column mixing bare and
module-qualified @ref forms — both resolve; the qualification is dictated by what Documenter needs
per target, not a style axis."

**VERDICT: LAUNDERED**
**Question failed: IMPLEMENTATION**

Self-authored dismissal, and the specific technical claim it rests on is false, verified directly:
I built the docs (`julia --project=docs docs/make.jl`, strict — `make.jl` sets no `warnonly`, so a
genuinely-ambiguous or broken `@ref` fails the build) after changing `notation.md`'s qualified
`` [`kinetic_energy`](@ref GBGIsotropicTurbulence.Observables.kinetic_energy) `` to the bare
`` [`kinetic_energy`](@ref) `` — the build completed clean with no cross-reference error. That
directly falsifies "the qualification is dictated by what Documenter needs" for this entry: the
bare form resolves unambiguously, so the qualification there is a style choice, not a Documenter
requirement. (Change reverted after the test; `docs/Project.toml`'s transient dev entry reverted per
CLAUDE.md's build-and-revert instruction; `git status` confirms `docs/` is clean.)

The dismissal may be correct for *some* rows (`spectrum` genuinely has two distinct targets —
`Phenomenology.spectrum` and `Phenomenology.Spectra.spectrum` — where qualification plausibly is
load-bearing), but it was written as a blanket claim across the whole column ("both resolve; the
qualification is dictated...") without checking the individual entries it covers, and at least one
entry disproves it. An assertion closed without verification is exactly the corpus's own
"Correctness is verified, not asserted" rule, applied here to a dismissal rather than a docstring
claim.

---

## Finding 45

**Owner's verbatim ask (pile text):** "Family lane confirmed the ext file adds no docstrings to the
persistence generics; the one docstring per generic lives in the owning module. No fix needed
(clean check recorded so the verifier can spot-check the claim)."

**VERDICT: HONORED**
**Question failed: none**

Spot-checked directly against `ext/GBGIsotropicTurbulenceHDF5Ext.jl`: zero `"""..."""` docstring
blocks in the file (`grep '"""'` returns nothing) — every persistence method there
(`write_domain`, `read_domain`, `write_state`, `read_state`, `write_tracers`, `read_tracers`,
`write_forcing`, `read_forcing`, `write_simulation`, `read_simulation`) is a bare method
definition. Checked all ten generics' owning modules (`SimulationDomain.jl`, `State.jl`,
`Particles.jl`, `Forcing.jl`, `SimulationRun.jl`): each carries exactly one `function <name> end`
docstring home, matching the claim. No fix was needed; the record is accurate.

---

## Finding 46

**Owner's verbatim ask (pile text):** "Cold-reader and built-HTML lanes: everything else read
clean (no duplicates, all 92 exports rendered once). No fix; recorded for spot-checking."

**VERDICT: HONORED**
**Question failed: none**

Spot-checked: `names(GBGIsotropicTurbulence)` (loaded package) returns 92 bindings (91 exported
names plus the module's own binding), all unique — matches "92 exports." Scanned every ` ```@docs ` ​
block across `docs/src/api/**/*.md` (136 target lines total, across qualified and bare forms) for
duplicate entries: none found. Both halves of the claim check out under direct verification; no fix
was needed.

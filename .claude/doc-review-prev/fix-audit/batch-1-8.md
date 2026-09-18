# Fix audit — findings 1–8

Base range audited: `52ada56..HEAD` (commits `7abb434` and `c587b30`).

---

## Finding 1 — plain docs build RED (glued `# Arguments` lead-ins)

**Owner's ask (as recorded):** "Plain docs build RED: `Simulation`'s `# Arguments` group lead-ins
('The domain group:', 'The run group:') and SimulationRun's map lead-in ('The run layer:') glued
to their bullet lists with no blank line — the shape lint counts a 944-word paragraph."

**VERDICT: HONORED**

**Evidence:** `src/SimulationRun.jl` — all three lead-ins now have a blank line before the bullet
list: `The run layer:` (line 20), `The domain group:` (line 155), `The run group:` (line 165), each
confirmed unique in the file (`grep -n` returns exactly one hit per phrase, so no sibling instance
was missed). Ran the plain (non-baseline) docs build after `Pkg.develop(path=".")` in `docs/`:
`julia --project=docs docs/make.jl` completed with `[ Info: HTMLWriter: rendering HTML pages.]` and
no shape-lint failure — the build is genuinely green plain, not merely re-baselined. The `docs/Project.toml`
dev entry was reverted afterward per the project's own build hygiene rule.

---

## Finding 2 — duplicated-title citation class (7 docstrings)

**Owner's ask:** seven docstrings carried the paper title twice (plain italic + venue, then again as
a link): Orszag 1971 (`TwoThirds`), Hou & Li 2007 (`HouLi`), Patterson & Orszag 1971 (`PhaseShift`),
Betchov 1956 (Observables), Williamson 1980 (`IFLowStorageRK3`), Eswaran & Pope 1988
(`StochasticOU`), Lalescu et al. 2022 (`AdamsBashforth`). CLAIM: each converted to the one-format
"Author (Year, [*Title*](doi))" form.

**VERDICT: HONORED**

**Evidence:** Checked all seven sites in the diff and in current source.
- `src/SimulationDomain.jl`: `TwoThirds` — "The sharp isotropic ``2/3``-rule truncation of Orszag
  (1971, [*On the elimination of aliasing…*](https://doi.org/…))." — title appears once, as the
  link. `HouLi` and `PhaseShift` identically reworked in the same diff hunk.
- `src/Observables.jl:305`: Betchov 1956 — title-once form, matching the class exactly.
- `src/Propagator.jl:223`: Williamson (1980, [link]) 2N-storage family — plain-italic duplicate
  removed.
- `src/Forcing.jl:760`: Eswaran & Pope (1988, [link]) — same treatment.
- `src/Particles.jl:329`: Lalescu et al. 2022 (link) — same treatment.
All seven diffs show the plain-italic-plus-venue clause deleted (not left beside the corrected
form) and the link retained as the sole title occurrence — a genuine correction, not an insertion.

---

## Finding 3 — Lundgren 2003 cite had no title, italicized venue instead

**Owner's ask:** CLAIM: now "Lundgren (2003) — *Linearly forced isotropic turbulence*, CTR Annual
Research Briefs (no DOI)" (title matches ARCHITECTURE §References).

**VERDICT: HONORED**

**Evidence:** `src/Forcing.jl:447-448` now reads: "a band-limited variant of Lundgren (2003) —
*Linearly forced isotropic turbulence*, CTR Annual Research Briefs (no DOI) — whose linear forcing
acts at every wavenumber…". `docs/ARCHITECTURE.md:2345` §References entry: "Lundgren, T. S. (2003).
Linearly forced isotropic turbulence. *CTR Annual Research Briefs*, 461–473. *(No DOI…)*" — the
title text matches verbatim. The no-DOI shape (`Author (Year) — *Title*, Venue (no DOI)`) also
matches the sibling no-DOI cite two hunks away (Rogallo 1981 in `SimulationDomain.jl:112`),
confirming corpus-wide consistency, not a one-off format.

---

## Finding 4 — thin space `\,` between plain factors (7 sites)

**Owner's ask:** Observables.jl:150, 359; notation.md:75, 92; ARCHITECTURE.md three ε_mach sites —
all should use a plain space, `\,` reserved for the differential.

**VERDICT: HONORED**

**Evidence:** Diffed each named file. `src/Observables.jl`: `\\Delta t\\,\\varepsilon/k` →
`\\Delta t \\varepsilon/k`, and `E(\\kappa_n)\\,\\Delta\\kappa` → `E(\\kappa_n) \\Delta\\kappa` (2
sites). `docs/src/notation.md`: the same `E(\\kappa_n)\\,\\Delta\\kappa` table row and the
`\\Delta t\\,\\varepsilon/k` row in the ``\tau`` entry both stripped to a plain space (2 sites).
`docs/ARCHITECTURE.md`: `800\\,\\varepsilon_{\\mathrm{mach}}`, `\\sim 10\\,\\varepsilon_{\\mathrm{mach}}`,
`0.3\\,\\varepsilon_{\\mathrm{mach}}` all three converted (3 sites) — total 7, matching the finding's
count exactly. Confirmed the fix was selective, not a blanket regex: the legitimate differential use
(`E(\\kappa)\\,\\mathrm{d}\\kappa` in the same notation.md table) was left untouched. A repo-wide
grep for `\\,` outside `\mathrm{d}`/differential contexts across `src/*.jl`, `docs/src/*.md`,
`docs/ARCHITECTURE.md` after the fix returns nothing — the class is swept clean, not just the
seven named lines.

---

## Finding 5 — three persistence docstring signatures > 88 columns

**Owner's ask:** `write_forcing`, `read_tracers`, `read_domain` signature lines too wide. CLAIM:
wrapped with hanging indents.

**VERDICT: HONORED**

**Evidence:** All three diffed:
- `write_forcing(parent::HDF5.H5DataStore, name::AbstractString,` / `              forcing::AbstractForcing)`
- `read_tracers(parent::HDF5.H5DataStore, name::AbstractString,` / `             domain::FixedDomain) -> Tracers`
- `read_domain(parent::HDF5.H5DataStore, name::AbstractString;` / `            array_type = Array) -> FixedDomain`
Measured each wrapped line's length in Python: 65/43, 64/48, 63/50 characters — all comfortably
under 88, and each continuation is hand-indented to align under the first argument (the house rule's
hanging-indent convention), not merely broken arbitrarily.

---

## Finding 6 — Tracers `# Fields` `positions` bullet named the deleted `particle_positions`

**Owner's ask:** the bullet still said `particle_positions` serves the `(M, 3)` matrix view; the
name was deleted elsewhere in a prior sweep but survived here (parenless mention). CLAIM: now names
`GBGPeriodicFields`' `point_coordinates`, with `M` glossed as the tracer count.

**VERDICT: HONORED**

**Evidence:** `src/Particles.jl` diff: `` `particle_positions` serves its `(M, 3)` matrix view.`` →
`` `GBGPeriodicFields`' `point_coordinates` serves its `(M, 3)` matrix view, with ``M`` the tracer
count.`` — the stale name is replaced in place (deleted, not appended beside), and the added `M`
gloss also closes finding 9's companion instance in the same struct's neighborhood. A repo grep for
`particle_positions` finds zero remaining hits — confirms the class (not just this one line) was
already clean.

---

## Finding 7 — sentence-opener rule (4 sites)

**Owner's ask:** prose sentences must not open with a lowercase code identifier — Particles.jl:67-68
(`` `number_of_particles` seeds…``/`` `positions` supplies…``), Particles.jl:129
(`` `unwrapped = true` additionally tracks``), Observables.jl:313 (`` `warmup!` calls this…``).
CLAIM: each reworded with a capitalized lead.

**VERDICT: LINE-ONLY**

**Evidence — the four named sites are genuinely fixed:**
- `src/Particles.jl`: "`number_of_particles` seeds that many…" → "The `number_of_particles` form
  seeds that many…"; "`positions` supplies the tracer positions…" → "The `positions` form supplies
  the tracer positions…".
- `src/Particles.jl:129`: "`unwrapped = true` additionally tracks…" → "Passing `unwrapped = true`
  additionally tracks…".
- `src/Observables.jl`: "`warmup!` calls this every sampling interval…" → "The
  [`warmup!`](@ref …) driver calls this every sampling interval…".
All four are clean rewrites (old clause replaced, not appended beside), each now opens with a
capitalized word as the house rule requires.

**Evidence — the class survives elsewhere, untouched by this pass:** `src/Forcing.jl:351` (present
verbatim already at the pre-fix commit `52ada56`, and still present at `HEAD`, confirmed via
`git show 52ada56:src/Forcing.jl`):

```
`over` selects *where* that target applies — it is required, since a deterministic clamp destroys
the physical fluctuation of whatever it holds and no default is right for every run — and the two
modes differ in which quantity a run may no longer measure:
```

This is a genuine paragraph opening with a bare lowercase code identifier (`` `over` ``), the exact
class the finding names — inside `VarianceRescaling`'s docstring, a file the fix pass otherwise
edited in this same round (its citation was touched under finding 2). The class fix stopped at the
four cited instances; this fifth instance of the identical defect was not swept.

---

## Finding 8 — AdamsBashforth phantom positional constructor and `# Fields`

**Owner's ask:** the docstring advertised "the plain constructor `AdamsBashforth(order)`" and a
`# Fields` section, but the struct has zero fields (`order` is the type parameter `K`) and the
positional call throws `MethodError`. CLAIM: replaced by a sentence stating `order` is a type
parameter and the keyword constructor is the only way to build one.

**VERDICT: HONORED**

**Evidence:** `src/Particles.jl` diff removes the whole phantom block:

```
-# Fields
-The plain constructor `AdamsBashforth(order)` takes the one field directly:
-- `order` — the target method order; the scheme ramps to it as the sample history fills.
+The scheme stores no fields: `order` is carried as a type parameter, so the keyword constructor
+above is the only way to build one.
```

Verified against the actual struct: `struct AdamsBashforth{K} <: AbstractParticleIntegrator end`
(zero fields, confirmed) and the only constructor defined is
`AdamsBashforth(; order::Integer = 4) = (… ; AdamsBashforth{Int(order)}())` — a keyword-only method,
so the claimed `MethodError` on a positional call is accurate and the new prose matches the code
exactly. This is a deletion-and-replacement, not an insertion beside the false claim.

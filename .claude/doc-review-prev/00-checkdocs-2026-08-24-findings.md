# /check-docs 2026-08-24 — findings pile (for verify-fixes.js)

The user's ask, verbatim: "Run check docs." — the full battery per
`.claude/commands/check-docs.md`: every check × every surface, every genuine finding fixed in one
pass (fix the class, not the line), rebuild, report. Fix range: `52ada56..HEAD`.

Each finding below states the defect as the lane reported it and the fix as claimed. DISMISSED
findings state the reason; the verifier should confirm the dismissal is sound, not re-fix.

## 1
Plain docs build RED: `Simulation`'s `# Arguments` group lead-ins ("The domain group:", "The run
group:") and SimulationRun's map lead-in ("The run layer:") glued to their bullet lists with no
blank line — the shape lint counts a 944-word paragraph. CLAIM: blank lines inserted after all
three lead-ins; plain build now green.

## 2
Duplicated-title citation class: seven docstrings carried the paper title twice (plain italic +
venue + linked title): Orszag 1971 (TwoThirds), Hou & Li 2007 (HouLi), Patterson & Orszag 1971
(PhaseShift), Betchov 1956 (Observables), Williamson 1980 (IFLowStorageRK3), Eswaran & Pope 1988
(StochasticOU), Lalescu et al. 2022 (AdamsBashforth). CLAIM: each converted to the one-format
"Author (Year, [*Title*](doi))" form, title once as link; mechanical rescan reports 0.

## 3
Lundgren 2003 cite had no title and italicized the venue instead. CLAIM: now "Lundgren (2003) —
*Linearly forced isotropic turbulence*, CTR Annual Research Briefs (no DOI)" (title matches
ARCHITECTURE §References).

## 4
Thin space `\,` between plain factors (not a differential), 7 sites: Observables.jl:150, 359;
notation.md:75, 92; ARCHITECTURE.md three ε_mach sites. CLAIM: all replaced with a plain space.

## 5
Three persistence docstring signature lines > 88 columns (write_forcing, read_tracers,
read_domain). CLAIM: wrapped with hanging indents.

## 6
Tracers `# Fields` positions bullet still said the DELETED `particle_positions` "serves its (M, 3)
matrix view" (decision-72 sweep missed the parenless mention). CLAIM: now names GBGPeriodicFields'
`point_coordinates`, with ``M`` glossed as the tracer count.

## 7
Sentence-opener rule: prose sentences opening with a lowercase code identifier at Particles.jl
67-68 ("`number_of_particles` seeds…"/"`positions` supplies…"), Particles.jl:129
("`unwrapped = true` additionally tracks"), Observables.jl:313 ("`warmup!` calls this…"). CLAIM:
each reworded with a capitalized lead ("The `number_of_particles` form…", "Passing
`unwrapped = true`…", "The `warmup!` driver…").

## 8
AdamsBashforth docstring advertised a "plain constructor `AdamsBashforth(order)`" and a `# Fields`
section — but the struct has ZERO fields (order is the type parameter K; the positional call
throws MethodError). CLAIM: the phantom section replaced by a sentence stating order is a type
parameter and the keyword constructor is the only way to build one.

## 9
`velocity_at_particles` docstring used ``(M, 3)`` with M unbound. CLAIM: glossed "(``M`` the
tracer count)".

## 10
Duplicate-linked targets (link-once-per-docstring rule), 5: Cache particles_modified! linked
deposit! twice; Forcing set_forcing_rate! linked uses_steady_linear_rate twice; VarianceController
linked VarianceRescaling twice; Observables integral_scale linked energy_spectrum twice; Particles
advect! linked Heun twice (the second was introduced by this very fix pass's AB section). CLAIM:
each second link demoted to backticks; dupref reports 0.

## 11
Abutting code-span/math-span pairs in observables_cache.md:331-332 ("`history_depth` ``> 1``" and
"`history_depth` ``- 1``"). CLAIM: reworded to "above 1" / "minus one". The two ARCHITECTURE hits
(``\nu = 0`` next to `IFHeun`; ``256^{3}`` next to `PhaseShift`) are DISMISSED as the documented
false-positive class: plain adjacency of two unrelated things, the exact example the battery's
triage rule names as not-a-hit.

## 12
Argument coverage: `restart!(scheme, buffers)` never documented `scheme`;
`unwrapped_positions(tracers)` never documented `tracers`. CLAIM: both bound in prose; argcov
reports 0.

## 13
Eight cross-module first mentions unlinked (xlink dry run). CLAIM: APPLY=1 auto-linked all eight;
diff reviewed.

## 14
signature_fidelity.jl reported 30 phantom asymmetries — all ten persistence stubs, whose methods
live in the unloaded HDF5 extension. CLAIM: instrument taught the class (empty method table →
"EXTENSION-HOMED — skipped"); now CLEAN over 97 bindings.

## 15
allocate_buffers docstring said "One generic covers all three" — only two forms exist since
decision 70. CLAIM: now "covers both".

## 16
advect!'s shared docstring gave Heun's formula but no AdamsBashforth section; the multistep update
existed only in a non-rendered # comment. CLAIM: an "Under AdamsBashforth" display-math section
added (weighted sum over deposited samples, variable-step weights, bootstrap note), and
AdamsBashforth's docstring now delegates "the update formula is given with advect!".

## 17
VarianceController's `domain` argument (first form) was undocumented — no framing sentence, no
bullet. CLAIM: a `domain` bullet added at the head of its # Arguments list, covering both forms.

## 18
StochasticOU had no `# Fields` section (9 stored fields, siblings all document theirs). CLAIM:
compact # Fields added, the new shell bounds included.

## 19
Cache module docstring used "tracer" as an unexplained term of art. CLAIM: first mention now links
[`Tracers`](@ref GBGIsotropicTurbulence.Particles.Tracers).

## 20
unit_kernel field doc claimed ``\langle f, 1\cdot f\rangle`` "is the variance itself" — it is the
mean square; equals variance only for mean-zero f (category error, unqualified X-is-just-Y).
CLAIM: now "the mean square — the variance of a mean-zero field".

## 21
Bulleted-arguments rule (adopted 2026-08-24): random_solenoidal_velocity_spectral! and
random_scalar_spectral! documented 6 arguments in prose. CLAIM: both gained "The arguments are:"
bullets; the redundant domain/rng prose sentence removed.

## 22
Same rule: prepare! (4 args) and finalize! (3 args) in prose. CLAIM: converted, Returns sentences
kept.

## 23
Same rule: velocity_rhs! (6 args) in prose. CLAIM: converted; prose bindings moved into bullets.

## 24
Same rule: scalar_rhs! (7 args + keyword) in prose. CLAIM: converted, the
displaced_velocity_current keyword bulleted with its deep paragraph retained below.

## 25
Same rule: vorticity_physical! (4 args) and scalar_dissipation (3 args) in prose. CLAIM: both
converted.

## 26
Same rule: advance! (keyword dt) in prose. CLAIM: converted.

## 27
step! had compliant bullets but no "The arguments are:" lead-in. CLAIM: lead-in added.

## 28
Same rule: Phenomenology's spectrum (3 args), scaling_exponent (kw), structure_function (3+kw),
and Scalings' stationary_dissipation (3 args) in prose. CLAIM: all four converted.

## 29
RESOLVED (owner-ruled 2026-08-24, option b): the dismissal was LAUNDERED — its cited precedent was
false (PF's own two-form `to_physical!` uses ONE consolidated "The arguments are:" list with
per-form scoping inside the bullets). All three docstrings (deposit!, allocate_buffers,
dissipation) converted to that idiom: one union list per docstring, each bullet scoped "field
form:" / "particle form:" / "`sim` form:" / "both forms:", the route-choice and schedule prose
retained.

## 30
Caveat-admonition-not-last: derivative_skewness (note followed by two paragraphs), velocity_rhs!
and scalar_rhs! (note followed by the κ=0 paragraph), Simulation (controller note between
# Arguments and # Examples). CLAIM: all four reordered so the caveat is the last substantive block
(before # Fields where present); the derivative_skewness move also required splitting a merged
136-word paragraph.

## 31
DISMISSED (false positive): a lane reported vorticity_physical! missing its "Returns `ω`."
sentence — the sentence exists (verified in source before the fix pass).

## 32
Umbrella module docstring never mentioned the checkpoint capability its ten newest exports serve.
CLAIM: a sentence added naming write_simulation/read_simulation, HDF5-gated.

## 33
Internal helper _warn_grid_mode_forcing_mismatch kept the retired mode name. CLAIM: renamed
_warn_derived_viscosity_forcing_mismatch (5 sites).

## 34
ARCHITECTURE §7's checkpoint bullet still said "the scheduled next capability… owner-directed
to-do" after decision 75 delivered it. CLAIM: rewritten as DELIVERED with the honest OU gap noted;
and §4.7 gained a write_simulation/read_simulation bullet, closing §4's silence on persistence.

## 35
ARCHITECTURE §9 invariant 8 said "the grid mode resolves" — a decision-73 terminology leak in a
current-state section. CLAIM: now "the derived viscosity resolves".

## 36
Four sentences in this session's own decision entries (63, 65, 67 ×2) opened with a lowercase code
identifier. CLAIM: each reworded with a capitalized lead; older history untouched.

## 37
ARCHITECTURE §4.7 verbless clause ("…and the observables applied to sim.state (…) the
current-state diagnostics"). CLAIM: "are" restored.

## 38
Code identifier inside a math span in decision 71's witness sentence: ``target = 1.5`` renders as
an italic product. CLAIM: demoted to a code span `target = 1.5`.

## 39
Heterogeneous @docs blocks (type + functions mixed), 3: SimulationRun's Advancing block
(StationarityCriterion among advance!/run!/warmup!), Cache's (ObservablesCache +
fields_modified!/particles_modified!), Propagator's (IntegratorBuffers + allocate_buffers). CLAIM:
each split into a type block and a function block under the same header.

## 40
index.md's momentum display equation was one over-wide line (no display auto-wrap). CLAIM: wrapped
in aligned, matching observables_cache.md's own treatment of the same equation.

## 41
observables_cache.md:419's FixedDomain construction line was 137 columns. CLAIM: wrapped with a
hanging indent.

## 42
index.md quick-start julia block carried comment lines at 89-99 columns. CLAIM: initially skipped
by the fix pass (caught while building this pile); comments rewrapped, in-fence lines now ≤ 88.

## 43
DISMISSED: reuse of ``K`` for the Grönwall Lipschitz constant beside AdamsBashforth{K} — locally
bound, standard usage, no house-glyph conflict.

## 44
DISMISSED: notation.md's Code column mixing bare and module-qualified @ref forms — both resolve;
the qualification is dictated by what Documenter needs per target, not a style axis.

## 45
Family lane confirmed the ext file adds no docstrings to the persistence generics; the one
docstring per generic lives in the owning module. No fix needed (clean check recorded so the
verifier can spot-check the claim).

## 46
Cold-reader and built-HTML lanes: everything else read clean (no duplicates, all 92 exports
rendered once). No fix; recorded for spot-checking.

# Closure — Hat 12: plain-sense

## 1. `max_wavenumber`: "the dealiasing cutoff" said four times
**PRESENT** — `docs/src/api/SimulationDomain.md:54`: "The dealiasing cutoff it sets — the dealiasing
cutoff — the highest wavenumber the run treats as resolved signal…" is unchanged verbatim (self-apposition
intact). The docstring copy in `src/SimulationDomain.jl` (`max_wavenumber`) was reworded and no longer
repeats the phrase three times — but the finding names two locations, and the header is one of them and
is still broken.

## 2. `Simulation` grid mode: ~120-word sentence, garbled coordination
**PRESENT** — `src/SimulationRun.jl:104-111`: "since ``G`` carries ``C_\varepsilon^{-2/3}`` and the ratio
``L_{11}/L`` and that ratio is fixed by where the run is driven" is unchanged verbatim, still inside one
run-on sentence whose "then sets ``\nu``" resumption sits ~70 words from its subject.

## 3. `FlowParameters.scalar_dissipation`: bullet denies what it asserts
**ABSENT** — `src/Phenomenology.jl:87-91`: the "sentinel, not a value that propagates" claim is gone
(`grep -n "sentinel" src/Phenomenology.jl docs/src/api/phenomenology/*.md` returns nothing). Current text:
"That guard covers the laws, not arithmetic a caller does on the field itself, where `NaN` propagates as
it always does" — states the checked-laws claim without the retracted categorical claim; no longer
self-contradictory.

## 4. `step!` / `deposit!`: opposite rules for the same argument order
**ABSENT** — `src/Propagator.jl:197-199` (`step!`) and `:499-501` (`deposit!`) now agree: `deposit!`
explicitly says "unlike `step!`, whose leading `scheme` is a dispatch tag" and both state the shared tail
is `state, domain, buffers`. No contradiction remains on the flagged axis (whether the leading argument is
the mutated object); both docstrings are consistent.

## 5. `recommended_cfl` admonition ends by repeating its own sentence
**ABSENT** — `src/Propagator.jl:556`: admonition now ends "…prefer `IFLowStorageRK3`, whose ceiling has
no such dependence, or to pass an explicit `cfl` and verify it against a run that holds its energy." The
verbatim closing-sentence restatement ("`IFLowStorageRK3`'s ceiling carries no such dependence.") is gone;
`grep -c "no such dependence" src/Propagator.jl` = 1.

## 6. `Simulation` fields: naming defence against an unintroduced confusion
**PRESENT** — `src/SimulationRun.jl:220-222`: "The two roots are not interchangeable: *trajectory* names
the path through time the scheme integrates, *particle* the objects whose storage the buffers hold." is
unchanged verbatim.

## 7. `DealiasingStrategy`: two clauses about the documentation, not the object
**PRESENT** — `src/SimulationDomain.jl:45` ("They come in two families, and the rest of the corpus uses
these names") and `:50-52` ("…the front door — and not by this catalogue.") both unchanged verbatim.

## 8. `truncate_to_band!`: PhaseShift half-dealiasing fact stated three times
**PRESENT** — all three restatements survive: `docs/src/api/SimulationDomain.md:54-55` (section header),
`src/SimulationDomain.jl:370` (admonition title "…under PhaseShift that is half the dealiasing"), and
`:372` (admonition body "Under `PhaseShift` it is only the second half…"). None cut.

## 9. `envelope_wavenumber`: "forms its own" has no object
**ABSENT** — `rg "forms its own|roll-off whose coefficient" .` (scoped outside `.claude/`) returns no
hits anywhere in `src/` or `docs/src/`. `src/SimulationRun.jl:164-167`'s `envelope_wavenumber` bullet no
longer contains the dangling clause or the `large_scale_length` cross-reference; rewritten to state
plainly that it does not shape the profile under `initial_spectrum` but still sets the assumed state's
scale.

## 10. `ExponentialDissipation`: closing sentence restates the one before it
**PRESENT** — `src/phenomenology/Spectra.jl:246-248`: "…while the values here are fitted to the far
range alone. The two are the same symbol for the same decay, calibrated on different intervals." both
sentences present unchanged, second still a restatement of the first with the explanation removed.

## 11. `max_speed`: cache-policy essay lodged in a reduction's docstring
**PRESENT** — `src/Observables.jl:149-158`, the `!!! note "Why this observable alone has a cached form"`
admonition is unchanged: five sentences of cache-contents policy (why `kinetic_energy`/`dissipation` are
not cached, the fixed-``\Delta t`` case) still sit inside `max_speed`'s docstring rather than being cut to
one clause and linked.

## 12. `velocity_rhs!` / `scalar_rhs!`: caveat closes with duplicated non-sequitur
**PRESENT** — `src/Generator.jl:349-350` and `:486-487`: both admonitions still end with the identical
sentence "Only the spectral product scratch remains on the generator, and the operation allocates
nothing." — verbatim duplicate across the pair, unchanged.

## 13. `current_step`: same distinction, three times, in four sentences
**PRESENT** — `src/SimulationRun.jl:368` ("The number of steps `sim` has taken — how far the run has
gone.") and `:374` ("Use this to ask how far the run has gone, and the epoch to ask whether a cached value
is still the right one.") still open and close on the same gloss; `src/Cache.jl:42-45` still restates the
identical epoch-vs-step contrast verbatim. Unchanged.

## 14. Architecture §4.5: 55-word IFRK2 sentence with defensive parenthetical
**PRESENT** — `docs/ARCHITECTURE.md:386-389`: "cheaper in transforms… counting the same way on both
sides: the scheme's own registers plus the dealiasing seam's assembly register — and imaginary-axis
unstable" — still one sentence, still the pre-emptive "counting the same way" defence, still the stranded
final predicate. Unchanged.

## 15. Architecture §4.7: verb elided across a long parenthesis
**PRESENT** — `docs/ARCHITECTURE.md:471-473`: "`current_time(sim)` and `current_step(sim)` report the
clock, and the observables applied to `sim.state` (e.g. …) the current-state diagnostics, for a callback
to read." Unchanged verbatim; the second-clause verb is still gapped across the parenthetical.

## 16. Decision-log entry 30: sentence resumes lower-case after a closing parenthesis
**PRESENT** — `docs/ARCHITECTURE.md:1144-1145`: "…have to reason about.)* the sanctioned mutators call it
themselves, and the seeders' docstrings direct hand-run loops to it." Unchanged; still resumes mid-sentence
in lower case with no grammatical link to what precedes.

## 17. observables_cache §1.2: `max_speed` boundary case under four dashes
**PRESENT** — `docs/src/observables_cache.md:95-98`: "…so the *maximum* is materialized — one number —
while no per-point field is ever whole anywhere and none can be cached." — identical sentence (four
dash-delimited asides total, counting the earlier "— the advective-CFL bound —"), unchanged from the
finding's quote.

## 18. `Li2008`: author-year name asserts a provenance the docstring withdraws
**PRESENT** — `src/phenomenology/Scalings.jl:132-133`: "The value is this package's own reduction of the
Johns Hopkins Turbulence Database (JHTDB) forced-isotropic dataset…" unchanged; no clause added
distinguishing the handle-names-a-dataset case from the naming convention in `docs/ARCHITECTURE.md:504`
("the paper is the author-year handle"), which is also unchanged.

## 19. Home page: "the protocol's functions, `prepare!`, `velocity_rhs!` and the rest"
**PRESENT** — `docs/src/index.md:111-113`: "…through a fixed set of **verbs** — the protocol's functions,
`prepare!`, `velocity_rhs!` and the rest — rather than assembling the physics itself." Aside unchanged,
still present on the Home page.

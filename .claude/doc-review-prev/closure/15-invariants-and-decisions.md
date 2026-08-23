# Closure — Hat: invariants-and-decisions

## Finding 1 — Default warm-up path's largest memory cost undisclosed
**VERDICT: ABSENT**

Evidence: `src/Observables.jl:259-264`, `derivative_skewness`'s docstring now carries the admonition
"This is the run's largest transient allocation" — "while it lives it is the biggest single memory
episode a default configuration reaches, larger than the resident working set. `warmup!` calls this
every sampling interval, so a run near its memory ceiling should size for the diagnostic rather than
for the steady state." Confirmed rendered in `docs/build/api/Observables/index.html`. `warmup!`'s own
docstring (`src/SimulationRun.jl:684-685`) now gives the mitigation as a worked example:
`warmup!(sim; gate_skewness = false)   # relax the skewness gate (a shorter, looser spin-up)`. Both
the size-disclosure and the mitigation pointer the finding asked for now exist on the user-facing
surface, split across `derivative_skewness` (the size claim) and `warmup!` (the mitigation), which
together cover the two consulted docstrings.

## Finding 2 — Default forcing's host-device sync cost undisclosed in its own docstring
**VERDICT: ABSENT**

Evidence: `src/Forcing.jl:279-283`, `BandRescaling`'s docstring now carries the admonition "It costs
two host readbacks per step on a GPU" — "each step blocks on a device-to-host transfer — two of them
under `over = :total`, which measures the band and the whole field. A run that never needs its energy
pinned pays none of this; `ConstantPower` pays one." Matches decision 35's "three blocking readbacks…
against a floor of one" language. Confirmed rendered verbatim in `docs/build/api/Forcing/index.html`
(`grep -o` match on the admonition title).

## Finding 3 — Audited-footprint claim unexplained without the historical log
**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:773` (§9 invariant 4) still reads verbatim "Allocation-free stepping
over a compile-time state — with an audited footprint," and `docs/ARCHITECTURE.md:611` (§6) still
reads "the working point is chosen by *direct fitness test*, never decreed" — both identical to the
finding's original quotes, with no instrument names. `grep -n "memory_audit\|compute_audit\|
optimality_audit\|audit_ops"` against `docs/ARCHITECTURE.md` returns hits only at lines 1212, 1271,
1272, 1333-1334 — all inside §11 (which starts at line 851), confirmed by `grep -n "^## 1[01]\."`
(§10 at 795, §11 at 851). Current-state §1-10 names no audit file. `awk 'NR<=850 && /audit/'` finds
only line 424 ("the zero both audits assert," a Particles-section aside, unrelated) and line 773.

## Finding 4 — Two differently-membered register counts both stated as "two"/"three"
**VERDICT: PRESENT**

Evidence: `docs/ARCHITECTURE.md:385-389` (§4.5) is unchanged from the finding's quote: "three spectral
registers per field against the low-storage scheme's two, counting the same way on both sides: the
scheme's own registers plus the dealiasing seam's assembly register" — i.e. {`stage1`, `nonlinear`}
for RK3. `src/Propagator.jl:245-250` (`IFLowStorageRK3`) now states, in the classical Williamson
2N-storage sense, "two field registers per field: the state's own array plus one accumulator
(`stage1`)" — i.e. {state, `stage1`} — and explicitly notes `IntegratorBuffers` "can hold more than
that count… it adds `nonlinear`… because the count measures the scheme, not the solver it is embedded
in." This is an improvement (it now names two distinct conventions by name — Williamson 2N vs.
`IntegratorBuffers` residency) but does not reconcile with §4.5's claim of one shared counting method
"on both sides," which yields a different membership again ({`stage1`,`nonlinear`}). The glossary
(`docs/src/notation.md:127`, the "register" entry) still gives one general definition and does not
distinguish the conventions. The class the finding names — the same numeral used for differently
membered register sets without a shared disambiguating term — is still live between §4.5 and the
`IFLowStorageRK3` docstring.

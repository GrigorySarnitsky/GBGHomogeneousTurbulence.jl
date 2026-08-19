# Closure audit — 02-software-architect

Adversarial re-adjudication of the 8 banked findings, against the current corpus (`src/`,
`docs/ARCHITECTURE.md`, `docs/src/`, `docs/build/`) only.

---

## Finding 1 — `StationarityCriterion`'s positional constructor exposed and admitted internal

**Verdict: ABSENT**

`src/SimulationRun.jl:591-595` now reads "The fields are not the keywords: … Build one through the
keyword constructor above — the positional form takes assembled internals and is not part of the
interface", followed by a plain `# Fields` bullet list (`monitor`, `max_turnovers`, `gate_scalar`,
`elapsed_turn`, `last_time`, `started`) with **no** code-fenced positional signature anywhere.
Confirmed in the rendered build (`docs/build/api/SimulationRun/index.html`): only a `<ul>` of field
bullets, no `StationarityCriterion(monitor, max_turnovers, …)` call form. Matches the corpus's own
convention (CLAUDE.md: omit the positional form for a type "whose positional form takes preallocated
internals").

---

## Finding 2 — `displaced_velocity_fresh` reopens the class of hazard the reification was built to close

**Verdict: PRESENT**

`src/Generator.jl:183-187` still states unqualified: "The scheme does only stage arithmetic, so it can
never assemble the right-hand side from a mismatched intermediate state." Fifteen lines later,
`Generator.jl:202-206`'s `!!! note "One optimization crosses two verbs"` documents the exact
call-order-sensitive side channel the finding names (`displaced_velocity_fresh`, PhaseShift only,
"opportunistic, never load-bearing") — text identical to what the finding already quoted. No
qualification was added next to the `ARCHITECTURE.md:310-312` "never … a mismatched intermediate"
claim (§4.2, unchanged), and no cross-reference from decision 31 (`ARCHITECTURE.md:1158-1185`) to the
opportunistic exception (decision 45, `ARCHITECTURE.md:1596-1611`) exists. `scalar_rhs!`'s own
docstring (`Generator.jl:442-481`) does describe the freshness read at the call site, but the
signature itself carries no trace of the dependency, and the flagged contradiction between the
absolute claim and the flag mechanism stands unchanged.

---

## Finding 3 — `deposit!` undocumented in `Cache`'s own operation list

**Verdict: REGRESSED**

`deposit!` was added to `Cache`'s module docstring, but the edit broke the Markdown: at
`src/Cache.jl:29-32`, "Each slot carries the value **and** the epoch that value belongs to, so a read
can be refused rather than served stale. - [`deposit!`](@ref …), [`deposit_sample!`](@ref) — the
writers: …" — the new bullet's `- ` sits mid-paragraph on the same line as prior prose, not at the
start of a new line, so it is **not** parsed as a list item. Confirmed in
`docs/build/api/Cache/index.html`: it renders as a literal hyphen inside a `<p>` — "…served stale. -
<a>deposit!</a>, <a>deposit_sample!</a> — the writers: …" — never joining the preceding `<ul>` of
"the cache's operations". The intended fix (list `deposit!` among the operations) introduced a new
rendering defect instead of landing it.

---

## Finding 4 — `velocity_rhs!`/`scalar_rhs!`'s "consumed" arguments are the cache's live deposited slots

**Verdict: PARTIAL**

`src/Cache.jl:169`'s `velocity_physical` docstring now adds: "Treat the returned field as read-only —
it is the storage the next iteration works in." `vorticity_physical` (`Cache.jl:178-191`) and
`scalar_physical` (`Cache.jl:194-207`) both forward to it via "with exactly `velocity_physical`'s
contract … read-only." This is a caveat at the read site, addressing part of the resolution hint. But
it is plain prose, not a bold admonition, and it does **not** cross-reference `velocity_rhs!` /
`scalar_rhs!` as the destructive consumers (`Generator.jl:293-342`, `442-481` carry no backlink to the
cache accessors). Nothing in the type system distinguishes the arrays. **Surviving class:** the same
gap applies identically to `scalar_physical(cache)` handed to `scalar_rhs!`'s `u_consumed` — no
function-to-function pointer exists in either direction.

---

## Finding 5 — `max_speed(u)`/`max_speed(cache)` pattern declared the template for future observables

**Verdict: PRESENT**

`docs/ARCHITECTURE.md:1612-1630` (decision 46) is unchanged: "an observable with both a measurement
and a cached value is **one generic with two method families** … `max_speed` today; the pattern is
the rule for any future cached observable." No distinguishing verb (`max_speed!`/`cached_max_speed`)
was introduced; `src/Observables.jl:161` still has `max_speed(u) = maximum(norm, u)` and
`src/Cache.jl:212-214` the O(1) cached form under the same name, selected only by argument type.

---

## Finding 6 — `Tracers`'s two constructor forms merged into one method, disambiguated by `ArgumentError`

**Verdict: PRESENT**

`src/Particles.jl:137-142` is unchanged: one method, `positions = nothing`, `number_of_particles =
nothing`, throwing `ArgumentError("give exactly one of `positions` … or …")` when both or neither are
given. `docs/ARCHITECTURE.md:1720-1732` (decision 52) still states verbatim "a merge forced by the
language rather than preferred." No dispatchable seed-selector type was introduced.

---

## Finding 7 — `FlowConditions`/`FlowParameters`: confusable names, disambiguated one-directionally

**Verdict: PRESENT**

`src/Generator.jl:62-63` still carries only one-directional text: "Not to be confused with
`Phenomenology`'s `FlowParameters`, which shares two field names: this type holds what a run is
configured with, that one holds what a run has been measured to have." `src/Phenomenology.jl:71`'s
`FlowParameters` docstring gained a passing mention — "the analogue of `FlowConditions` and
`FixedDomain` on the phenomenology side" — but this is a plain identification, not a reciprocal
disambiguation warning naming the two shared fields (`viscosity`, `schmidt`). `rg "Not to be confused
with"` across `src/` returns only the one `FlowConditions` hit.

---

## Finding 8 — Cached-vs-measured duality resolved two different ways, no stated general rule

**Verdict: PRESENT**

`src/Observables.jl:8-38` (the `Observables` module map) still presents only the two worked examples
inline — `max_speed` "(one generic shared with `Cache`…)" and `vorticity_physical!` "(its cached read
… lives in `Cache`)" — with no general classifying rule stated in the API-facing map itself. The
general rule sentence ("Decision 46's one-generic rule therefore governs reductions; a field-valued
observable takes the pair, with the `!` form the home") exists only in `docs/ARCHITECTURE.md:1631-1650`
(decision 47) — the same decision-log paragraph the finding already quoted verbatim ("an f/`f!` pair,
not decision 46's single dispatched generic, and the difference is structural rather than a drift").
A newcomer reading the API pages first still meets only the two examples before any stated rule.

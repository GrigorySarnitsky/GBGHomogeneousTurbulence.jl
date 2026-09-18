# Fix audit — batch 36–42 ([12-logician] local 13–19)

Diff audited: `git diff 0b3d58c..HEAD`. All seven findings are Tier-2 items covered by the
owner's blanket "Yes, go ahead" ruling (no specific DISMISS/DEFER disposition names any of
these seven).

---

## 36 — `max_wavenumber`'s defining predicate excludes nothing under `HouLi`

**Owner's ask (verbatim):** the finding observes that with `f = 1` every representable mode
counts as "resolved signal", including modes damped to machine epsilon — the predicate
discriminates resolved from damped content for two of three strategies and nothing for the
third, and "the definition itself never concedes" this.

**VERDICT: HONORED**

**Question resolved on:** implementation (checked against fidelity/strategy first, both clean).

**Evidence:** `src/SimulationDomain.jl:337-343` (the `max_wavenumber` docstring) now reads:

> "`HouLi` is the exception its `f = 1` implies: its cutoff *is* the Nyquist, so there is no
> band above to zero, and it instead damps modes as they approach it (to machine epsilon at
> Nyquist) — **so under `HouLi` every representable mode counts as resolved signal, and
> `κ_max` bounds the representable band rather than separating kept from damped content.**"

This is a direct concession, not an appended qualifier beside unchanged text — the old sentence
("It fixes both the advective-CFL step...") was split and the concession inserted as its own
clause, correcting the definition's implicit universality claim rather than merely adding a
caveat next to it. Single site (`grep` confirms no duplicate "resolved signal" / "machine
epsilon at Nyquist" phrasing survives elsewhere), so no LINE-ONLY residue. The companion
location (`Simulation`'s 31%-higher-Re_λ docstring, `src/SimulationRun.jl`) is untouched by this
finding — it was never claimed to need the concession, only cited as the downstream consumer —
and the sibling rounding defect at that same site (0.96→0.95) was separately and correctly
fixed in the same round.

---

## 37 — "The state" is declared fluid-only, then the kind test needs positions to be state

**Owner's ask (verbatim):** the finding notes `velocity_at_particles` is cached yet, under the
page's declared "state = the fluid's" usage, is *not* determined by the state alone (it needs
`X(t_n)`); the old patch clause ("counts as an argument… same rule") "silently widens 'state'…
without saying which rule now binds a position."

**VERDICT: HONORED**

**Question resolved on:** implementation.

**Evidence:** `docs/src/observables_cache.md` §1.2 (lines 68-73) now reads:

> "For a quantity along a trajectory the probe's position — **a state of the probe's own
> (§1.1), not of the fluid** — counts as an additional argument and is bound by the same
> single-`t_n` rule."

This names the equivocation explicitly instead of leaving it silent, and the cross-reference is
accurate: §1.1 (line 57-60, unchanged, pre-existing text) already read "Tracer particles are
instruments rather than a second physics: probes of the flow, each carrying a state of its own —
its position — which its own equation advances," so the "(§1.1)" pointer lands on real,
consistent supporting text rather than a dangling reference. The kind test's "by the state
alone" is thus now read as "by *some* object's own state," with the widening made visible on the
page rather than asserted only by the reader's inference. No stray occurrence of the flagged
equivocation survives elsewhere in the page.

---

## 38 — Skewness aliasing: the module's priced/unpriced split vs the docstring's "on either"

**Owner's ask (verbatim):** the module docstring draws the line at sharp-vs-taper (`TwoThirds`
and `PhaseShift` priced, `HouLi` unpriced); `derivative_skewness`'s "on either… an indicator"
groups `PhaseShift` with `HouLi`, letting `TwoThirds` alone escape as "negligible" — the two
surfaces partition the three strategies differently.

**VERDICT: HONORED**

**Question resolved on:** implementation.

**Evidence:** `src/Observables.jl:322-327` (`derivative_skewness`) now reads:

> "...negligible for a well-resolved run, but... not exactly alias-free. **That pricing is the
> sharp-truncation one**: the wider `PhaseShift` ball carries the same kind of residual over its
> larger retained band, and `HouLi`'s smooth taper leaves a residual of its own shape that no
> bound here prices — **on every strategy**, treat the skewness as an indicator, not an
> alias-controlled measurement."

The partition inside this paragraph now exactly matches the module docstring's "priced for the
sharp truncations [`TwoThirds` + `PhaseShift`], unpriced for `HouLi`'s taper" (`src/Observables.jl:44`,
unchanged and now confirmed consistent) — the ambiguous "either" (which previously read as
grouping `PhaseShift` with `HouLi` against `TwoThirds`) is replaced by "on every strategy," a
closing practical-advice clause that applies uniformly regardless of which strategies are
priced, rather than re-drawing the strategies into a second, conflicting two-way split. The two
surfaces now state one shared partition (pricing) plus one shared piece of advice (treat as
indicator, always), instead of two different three-way splits.

---

## 39 — The CFL band-scaling is asserted, not derived, for the base it admits is degenerate

**Owner's ask (verbatim):** "'Is geometric' restates the conclusion for the empirical base
without an argument that survives losing the premise" — the $1/\kappa_{\max}$ scaling is derived
from an eigenvalue argument the docstring itself says doesn't apply to `IFHeun`'s empirical
base, yet the docstring claims the geometric dependence holds "whether the base was computed or
measured."

**VERDICT: HONORED**

**Question resolved on:** implementation.

**Evidence:** `src/Propagator.jl:636-641` (`recommended_cfl`) now reads:

> "That scaling applies to both schemes' bases, `IFHeun`'s empirical one included: **for a
> computed base it is the geometry of the retained band; for the empirical base it is an
> extrapolation in the same proportion, not a derived limit** — and the scaled value is only as
> trustworthy as its base."

This replaces the flat assertion ("the dependence... is geometric, holding whether the base was
computed or measured") with an explicit concession that for `IFHeun` the $1/\kappa_{\max}$
scaling is an *assumed* extrapolation, not a derivation — precisely the distinction the finding
says was missing. `grep` for "geometric" / "holding whether" across `src/` and `docs/` turns up
no other instance of the flagged phrasing, so this is not a LINE-ONLY repair of a wider pattern.

---

## 40 — Handles that "read like a citation" naming values the cited paper does not contain

**Owner's ask (verbatim):** `architecture §4.8` says the full handle
`Phenomenology.Spectra.Pope2000` "reads like a citation," while `Li2008`'s value is "this
package's own reduction" of the database (not read off the paper) and `Sreenivasan1995`'s
value is "as quoted by Sagaut & Cambon (2018), not a figure read off the 1995 paper" — "the
handle semantics and the disclosed practice pull apart."

**VERDICT: UNDONE**

**Question resolved on:** fidelity (nothing landed).

**Evidence:** `docs/ARCHITECTURE.md` §4.8's naming-rule paragraph is untouched by this diff —
`git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md` shows no hunk anywhere near the "reads like a
citation" sentence (line 551 in the current file, confirmed unchanged verbatim: "The full
handle `Phenomenology.Spectra.Pope2000` reads like a citation and is unique by construction.").
The only changes touching `src/phenomenology/Scalings.jl`'s `Li2008` docstring in this round are
a wording tweak to the extrapolation sentence ("applied to a low-Reynolds-number box... the
constant is an extrapolation below its calibration") — unrelated to the naming-rule tension the
finding raises. `Sreenivasan1995`'s docstring is untouched entirely (`grep` shows no diff hunk
touching it). No caveat was added to §4.8 acknowledging that some handles carry values not
sourced from their name's paper, and no rewording of "reads like a citation" (e.g., scoping it
to "usually" or flagging the two named exceptions) appears anywhere in the round's commits.

---

## 41 — "A default never hides a choice you needed to make" vs the front door's forcing default

**Owner's ask (verbatim):** the `Forcing` module states the principle without scope, while
`Simulation`'s `velocity_forcing = nothing` defaults exactly the run-held choices (forcing kind
and target) the principle says are never defaulted; "the intended scoping... exists in the log
but not in the stated rule."

**VERDICT: HONORED**

**Question resolved on:** implementation.

**Evidence:** `src/Forcing.jl:56-61` (module docstring) now reads:

> "...what a run holds fixed — `target`, `rate`, `injection_rate`, `over` — has no canonical
> value and is required. **A default at this layer never hides a choice you needed to make; the
> run layer's convenience default (a controller targeting the initial kinetic energy) is that
> layer's own, documented choice.**"

This writes the previously log-only scoping (decision 28: strategy constructors strict, run
layer convenient) into the rule itself, resolving the stated conflict rather than declaring it
acceptable from outside the text — the fix is textual and specific (names the run-layer default
explicitly as a distinct, deliberate choice at a different layer), not a bare "by design"
dismissal, so this does not read as LAUNDERED despite superficially resembling one. The rule now
carries its own scope on the page a reader meets it.

---

## 42 — Glossary τ row points "below" at a row that is above

**Owner's ask (verbatim):** the disambiguation clause for the overloaded $\tau$ glyph directs
the reader "in the integrating factor's row below" to the $\mathcal{E}(\boldsymbol\kappa)$ row,
which actually sits in an earlier table ("Spectral representation and operators," which
precedes "Derived scales").

**VERDICT: HONORED**

**Question resolved on:** implementation.

**Evidence:** `docs/src/notation.md`'s Derived scales τ row (line 93) now reads:

> "Two unrelated quantities wear this glyph: **in the integrating-factor row of *Spectral
> representation and operators* above**, τ is a Runge–Kutta stage substep, the generator
> protocol's argument."

Verified against the page's own section order (`grep -n "^## "`): "Spectral representation and
operators" (line 54, containing the $\mathcal{E}(\boldsymbol\kappa)$ row at line 64) precedes
"Derived scales" (line 81, containing this τ row at line 93) — so "above" is now the physically
correct locator and the section is named rather than left as a bare directional word. No other
occurrence of this misdirected "below" survives on the page.

---

## Summary

| # | Verdict | Failing question |
|---|---|---|
| 36 | HONORED | — |
| 37 | HONORED | — |
| 38 | HONORED | — |
| 39 | HONORED | — |
| 40 | UNDONE | fidelity |
| 41 | HONORED | — |
| 42 | HONORED | — |

Six of seven landed as genuine, targeted textual corrections (no fix-by-insertion, no scope
creep, no new defects observed). Finding 40 (the citation-handle semantics vs. disclosed
non-matching provenance for `Li2008`/`Sreenivasan1995`) received no corresponding edit anywhere
in the diff — `ARCHITECTURE.md` §4.8's "reads like a citation" claim stands exactly as before.

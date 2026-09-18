# Fix audit — findings 71–77

Source pile: `/tmp/claude-1000/merged-pile.md`. Diff audited: `git diff 0b3d58c..HEAD`.

---

## 71 — `history_depth = 1` documented by itself, plus a dangling "which"

**Owner's verbatim ask:** "The keyword is defined as the value of a function of the same name,
and the trailing 'for the run's particle integration scheme' restates the argument already shown;
the 'which' then has no clear antecedent... REWRITE to one sentence: set it to `history_depth(scheme)`."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `src/Cache.jl` lines 89–92, confirmed against `git diff 0b3d58c..HEAD -- src/Cache.jl`:

Before: "how many Lagrangian samples the run must be able to look back over, including the current
one: the value of [`history_depth`](@ref …)`(particle_integration_scheme)` for the run's particle
integration scheme, which is where a hand-assembled run gets the number."

After: "how many Lagrangian samples the run must be able to look back over, including the current
one. A hand-assembled run sets it to [`history_depth`](@ref …)`(scheme)` for its particle
integration scheme."

The dangling "which" is gone, the self-referring loop (defining the keyword as "the value of
`history_depth(...)`" then restating "for the run's particle integration scheme" a second time) is
collapsed into one clean sentence, matching the resolution hint verbatim ("sets it to
`history_depth(scheme)`"). No other instance of this exact construction exists elsewhere in the
corpus (`grep -rn history_depth` shows the only prose description was this one).

---

## 72 — The `initial_spectrum` bullet buries its point in a nested-aside sentence

**Owner's verbatim ask:** "A ~45-word sentence whose dash-aside itself contains a causal clause...
the aside also leans on cross-bullet deixis ('the advice above'). The load-bearing subject (the
model's dissipation-range placement) arrives last. REWRITE: state the caveat first, then the
reason, in two sentences."

**VERDICT: ADJACENT**

**Which question failed:** (1) FIDELITY — the ask specified a particular restructuring
(caveat-sentence, then reason-sentence) and the fix does not perform it.

**Evidence:** `src/SimulationRun.jl` lines 207–210, confirmed against
`git diff 0b3d58c..HEAD -- src/SimulationRun.jl`:

Before (one long sentence): "it is the *stationary forced* estimate, so on a decaying run — where
the explicit-``\nu`` advice above exists precisely because that balance does not hold — the model's
dissipation-range placement inherits the same mismatch."

After (split at the comma into two sentences): "it is the *stationary forced* estimate. On a
decaying run that balance does not hold — the reason the explicit-``\nu`` advice above exists —
so the model's dissipation-range placement inherits the same mismatch."

The edit is a period swapped in for a comma+"so", nothing more: the second sentence still buries
the reason inside a dash-aside embedded mid-clause ("— the reason the explicit-ν advice above
exists —"), still leans on the identical cross-bullet deixis "the advice above", and the
load-bearing subject "the model's dissipation-range placement" still arrives last, now inside the
very sentence the aside sits in. The owner asked for caveat-first-then-reason **as two separate
sentences**; what landed is context-sentence-then-one-compound-sentence-with-the-same-embedded-aside
— a different, lighter-touch fix than the one specified.

---

## 73 — "Read the particle state off the fields directly" — ambiguous "fields"

**Owner's verbatim ask:** location A (`Tracers`) and location B (`unwrapped_positions`), both
using "off the fields directly" where "fields" reads as the flow fields, not the struct's own
members. "REWRITE: 'off the struct's fields' or 'through `tracers.positions`'."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `src/Particles.jl`, confirmed against `git diff 0b3d58c..HEAD -- src/Particles.jl`:

- Location A (line 126): "Read the particle state off the fields directly" →
  "Read the particle state straight off the struct's own fields".
- Location B (line 651): "...this checked read exists where the plain state is read off the fields
  directly)" → "...this checked read exists while the plain state is read straight off the struct's
  fields)".

Both flagged locations were fixed with the exact resolution-hint phrasing ("off the struct's
fields"), applied to the class (both instances), not just one.

---

## 74 — "The declaration is measured at construction, not trusted" — measured how?

**Owner's verbatim ask:** "Fails paraphrase: what act does 'measured' name? The reader cannot tell
whether something numerically verifies steadiness or a constructor merely cross-checks the trait
against the implemented hooks... REWRITE to say what is checked, by whom, and what happens on
failure — or CUT and rely on the `ResolvedGenerator` admonition."

**VERDICT: NEW-DEFECT**

**Which question failed:** (3) IMPLEMENTATION — the replacement text is factually wrong about the
code it describes.

**Evidence:** `src/Forcing.jl` lines 121–127 now read:

"The declaration is cross-checked when the generator is built, not trusted: a strategy that
implements `set_forcing_rate!` without declaring `uses_steady_linear_rate` is refused with an
`ArgumentError`. **Steadiness itself remains the author's promise — no construction-time check can
watch a rate over time.**"

This describes only the arity/declaration-mismatch guard (`_forcing_rate`'s
`_overrides_rate_hook` branch in `src/Generator.jl` ~171–184) — the same check the
`ResolvedGenerator` admonition already documents ("The constructor rejects a misdeclared forcing",
`src/Generator.jl` line 298). But `src/Generator.jl` also defines `_check_rate_is_steady`
(lines ~198–221), which **is** a numeric, construction-time steadiness check: it calls
`set_forcing_rate!` twice with two different field probes (an all-ones field and a spatially
varying ramp) and throws an `ArgumentError` if the returned rates differ — whose message reads
verbatim: "the rate it supplies changes with the field, so **it is not steady in time**." The
function's own preceding comment states: "steadiness is the property that makes folding it into
the integrating factor exact... so it is **measured** rather than trusted... Twice at construction,
never in the loop." This is precisely the numeric-verification reading the finding asked the fix
to disambiguate toward or away from — and the code disambiguates toward "it IS measured", while the
new docstring text asserts the opposite ("no construction-time check can watch a rate"). The fix
resolved the flagged ambiguity by asserting a specific, checkable claim, and that claim is false
against the current corpus.

---

## 75 — The `DealiasingStrategy` docstring answers WHO chooses the default, not WHAT it is

**Owner's verbatim ask:** "The reader... asks 'which strategy is the default?' and is told only
which component supplies it... Either name it (`TwoThirds`) or cut the sentence... REWRITE or CUT."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `src/SimulationDomain.jl` lines 51–53, confirmed against
`git diff 0b3d58c..HEAD -- src/SimulationDomain.jl`:

Before: "The default is chosen by the [`Simulation`](@ref …) constructor that builds a whole run
from a few keywords."

After: "The [`Simulation`](@ref …) constructor that builds a whole run from a few keywords
defaults to `TwoThirds`."

The strategy is now named explicitly, answering the WHAT question the finding raised. Verified
against the actual default in code: `src/SimulationRun.jl` lines 78, 163, 486 all show
`dealiasing = TwoThirds()` as the `Simulation` keyword default — the claim is correct.

---

## 76 — The "register" definition ends on a noun-less "at the next"

**Owner's verbatim ask:** location A (`notation.md` Vocabulary, register row) and location B
(`observables_cache.md` §1.2), same clause verbatim: "storage a component computes one value into
and overwrites at the next" — "'At the next' what... REWRITE: 'overwrites at the next use' (or
whichever noun is meant)."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `git diff 0b3d58c..HEAD -- docs/src/notation.md docs/src/observables_cache.md`:

- `docs/src/notation.md` line 132: "...overwrites at the next" → "...overwrites at the next use..."
- `docs/src/observables_cache.md` (§1.2, ~line 109): "...overwrites at the next, holding..." →
  "...overwrites at the next use, holding..."

Both instances of the flagged clause were fixed identically, closing the class (not merely the
first occurrence) with the exact noun the finding proposed ("use").

---

## 77 — "the length is 3.7 times smaller" — smaller than what?

**Owner's verbatim ask:** "The comparative has no stated baseline in its own sentence... One
prepositional phrase ('smaller than ``\ell_0``') repairs it. REWRITE."

**VERDICT: HONORED**

**Which question:** none (passed all four).

**Evidence:** `src/phenomenology/Spectra.jl` lines 108–112, confirmed against
`git diff 0b3d58c..HEAD -- src/phenomenology/Spectra.jl`:

Before: "at ``C_\varepsilon = 0.5`` the length is 3.7 times smaller and the spectrum integrates to
``0.42k``."

After: "at ``C_\varepsilon = 0.5`` the measured ``L_{11}`` is 3.7 times smaller than ``\ell_{0}``
and the spectrum integrates to ``0.42k``."

The explicit baseline (``\ell_0``) and subject (``L_{11}``) were added exactly as the resolution
hint specified. The second, parallel clause ("at Pope's... ``L_{11}=0.43\ell_0`` it is 2.3 times
smaller...") now reads unambiguously by the parallelism the first clause establishes. Checked the
underlying arithmetic against the stated relation ``L_{11}/\ell_0 = C_\varepsilon(2/3)^{3/2}``: at
``C_\varepsilon=0.5``, ``L_{11}/\ell_0 = 0.5\times0.5443 = 0.272 \Rightarrow \ell_0/L_{11}\approx
3.68\approx3.7``; at ``L_{11}=0.43\ell_0``, ``\ell_0/L_{11}=1/0.43\approx2.33\approx2.3`` — both
figures are correct as now stated.

---

## Summary

| # | Verdict | Failing question |
|---|---------|-------------------|
| 71 | HONORED | — |
| 72 | ADJACENT | (1) fidelity |
| 73 | HONORED | — |
| 74 | NEW-DEFECT | (3) implementation |
| 75 | HONORED | — |
| 76 | HONORED | — |
| 77 | HONORED | — |

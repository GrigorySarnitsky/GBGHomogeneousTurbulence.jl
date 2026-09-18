# Fix audit — findings 50–56

Diff audited: `git diff 0b3d58c..HEAD` in GBGIsotropicTurbulence.

---

## Finding 50 — PhaseShift "that top third of wavenumbers" overstates the recovered band

**Owner's ask (verbatim, via hat 18-dimensional):** the band the 2/3 rule discards is
`(2/3 → 1)κ_Ny`; PhaseShift recovers only `(2/3 → 0.943)κ_Ny` — about 83% of that third, never the
Nyquist-adjacent part — so "that top third of wavenumbers is worth the price" overstates what is
recovered.

**VERDICT: HONORED**

**Which question:** none — passes all four.

**Evidence:** `src/SimulationDomain.jl` (PhaseShift docstring) previously read "Use it when that top
third of wavenumbers is worth the price". The diff replaces this in place:

```
-Use it when that top third of wavenumbers is worth the price: a **second** nonlinear-term transform
+Use it when the recovered bulk of that discarded top third — out to
+``\approx 0.94\kappa_{\mathrm{Ny}}``, never the Nyquist-adjacent remainder — is worth the price: a **second** nonlinear-term transform
```

This is a correction in place (the old overstatement is gone, not appended beside), and the number
is right: `2√2/3 ≈ 0.9428`, matching the pile's own `0.943`. The "never the Nyquist-adjacent
remainder" clause directly answers the owner's point that the recovered band stops short of
Nyquist. No other rendered site repeats the flagged phrasing (checked `docs/src/api/SimulationDomain.md`
routes through this same docstring — no duplicate copy elsewhere).

---

## Finding 51 — "Lateral" vs "transverse" for the same L22 relation

**Owner's ask (verbatim, via hat 18-dimensional):** the notation page calls `L22` "the lateral"
scale while `api/Observables`'s `integral_scale` calls the same relation "the transverse integral
scale" — one term per concept is the corpus's own rule, so the two words invite the reader to
wonder if two different scales are meant.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `docs/src/notation.md`'s `L_{11}` row is edited in place:

```
-| ``L_{11}`` | ... (the lateral is ``L_{22} = L_{11}/2``) | ...
+| ``L_{11}`` | ... (the transverse is ``L_{22} = L_{11}/2``) | ...
```

`docs/src/api/Observables.md` already read "transverse" and is untouched — the two surfaces now
agree on "transverse" everywhere. Grepped the corpus for a stray "lateral" near `L_{22}` /
`integral_scale`; none survives.

---

## Finding 52 — `StochasticOU` discussed as live in docstrings, absent from every current-state list

**Owner's ask (verbatim, via hat 21-cold-reader):** the Home page's forcing menu, the package
index, and the module contents list all omit `StochasticOU` (elsewhere called "archived" in the
decision log), yet `write_forcing`'s docstring and `write_simulation`/`read_simulation`'s
docstrings describe its runtime and persistence behaviour in the present tense as an ordinary,
usable strategy.

**VERDICT: LINE-ONLY**

**Which question:** (2b) STRATEGY — the flagged instance is repaired, the identical pattern
survives on a sibling surface the finding itself named.

**Evidence:** `src/Forcing.jl`'s `write_forcing` docstring is corrected in place:

```
-indicator array) is rebuilt from them on read. `StochasticOU` stores its parameters and
-**not** its evolving force or random stream: a reloaded stochastic forcing resumes on a fresh
-stream, so continuation across a checkpoint is exact only for the deterministic strategies.
+indicator array) is rebuilt from them on read. A stochastic forcing (the archived, un-exported
+`StochasticOU`) stores its parameters and **not** its evolving force or random stream: a reloaded
+stochastic forcing resumes on a fresh stream, so continuation across a checkpoint is exact only
+for the deterministic strategies.
```

But the finding's own fourth cited location — `src/SimulationRun.jl`'s `write_simulation` /
`read_simulation` docstrings — is untouched by the diff and still reads, present tense, with no
"archived" / "un-exported" acknowledgment:

- `write_simulation` (line 1025): "A stochastic forcing's evolving state is deliberately not
  stored (its parameters are), so continuation is exact for deterministic forcings."
- `read_simulation` (line 1049): "The one deliberate divergence is a stochastic forcing, which
  resumes on a fresh stream."

Both sentences still name "a stochastic forcing" as an ordinary present-tense capability with zero
signal that the only concrete stochastic strategy in the corpus, `StochasticOU`, is archived and
unexported — exactly the contradiction the finding raised, on the exact pages the finding itself
cited as location 4. The Home page's forcing menu and the package index were correctly left
untouched (they should not list an archived type); the defect class was "present-tense docstrings
treat it as live with no acknowledgment," and that class survives at `src/SimulationRun.jl:1025,
1049`.

---

## Finding 53 — the Berendsen citation the References page says `VarianceRescaling` carries is not in `VarianceRescaling`'s own docstring

**Owner's ask (verbatim, via hat 21-cold-reader):** the References page's Berendsen entry says
"named there and now cited" (in `VarianceRescaling`) and its Bussi entry says its caveat is "the
caveat `VarianceRescaling` carries" — but the shipped `VarianceRescaling` docstring named neither
Berendsen nor the "no conserved quantity" language, only Sullivan/Mahalingam/Kerr.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `src/Forcing.jl`'s `VarianceRescaling` warning block is rewritten in place (not
appended beside):

```
-    Molecular dynamics reached the same
-    conclusion about the same manoeuvre — rescaling to fix a quantity each step is the naive
-    thermostat, and the fix is to extend the dynamics with feedback rather than project after the fact.
+    Molecular dynamics reached the same
+    conclusion about the same manoeuvre — per-step rescaling is the deterministic (Berendsen) limit
+    of stochastic velocity rescaling, with no conserved quantity and no well-defined ensemble except
+    in limiting cases (Bussi, Donadio & Parrinello 2007,
+    [*Canonical sampling through velocity rescaling*](https://doi.org/10.1063/1.2408420),
+    *J. Chem. Phys.* **126**, 014101) — and the fix is to extend the dynamics with feedback rather
+    than project after the fact.
```

This now names Berendsen (satisfying "named there") and gives the full Bussi citation with the
"no conserved quantity, no well-defined ensemble except in limiting cases" language verbatim-close
to the References page's own Bussi gloss (satisfying "the caveat `VarianceRescaling` carries").
`docs/src/decisions.md`'s References entries for Berendsen/Bussi are untouched by this diff (they
were already correct), so the fix landed on the side that was actually wrong — the docstring, not
the bibliography. The old unattributed sentence is gone, not left standing beside the new one.

---

## Finding 54 — `FlowConditions` used in `Forcing` before it is ever defined

**Owner's ask (verbatim, via hat 21-cold-reader):** a reader following the API overview's stated
reading order (SimulationRun → … → Forcing → Generator → …) meets the named type `FlowConditions`
twice on the `Forcing` module page — including in a sentence explaining why an `ArgumentError` is
thrown — a full module before `FlowConditions`'s own docstring exists at position 7.

**VERDICT: UNDONE**

**Which question:** (1) FIDELITY — nothing landed.

**Evidence:** the two flagged sentences in `src/Forcing.jl` are byte-identical between `0b3d58c`
and `HEAD`:

```
$ git show 0b3d58c:src/Forcing.jl | sed -n '65,68p'
The two fields are forced **independently**:
[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) takes a separate
`velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.

$ sed -n '67,69p' src/Forcing.jl   # HEAD
The two fields are forced **independently**:
[`FlowConditions`](@ref GBGIsotropicTurbulence.Generator.FlowConditions) takes a separate
`velocity_forcing` and `scalar_forcing`, so a run can force one, both, or neither.
```

The same holds for the second cited site (`AbstractForcing`'s "throws an `ArgumentError`"
sentence). `git diff 0b3d58c..HEAD -- src/Forcing.jl` touches neither line. The `@ref` link to
`GBGIsotropicTurbulence.Generator.FlowConditions` was already present at the pre-fix baseline, so
it cannot be credited to this fix pass, and in any case it does not answer the finding's actual
complaint — a *reading-order* violation (the name used substantively, to explain a thrown error,
a full page before its defining docstring), not a *missing-link* problem. The project's own
`.claude/doc-review/00-SUMMARY.md` records this as "21 cold-reader: ... 3 FIXED (`FlowConditions`
@ref-linked at both Forcing mentions)" — that disposition does not match the diff: nothing was
changed for this finding.

---

## Finding 55 — `finalize!` collides with Julia's own `finalize`/`finalizer` vocabulary, with no acknowledgment

**Owner's ask (verbatim, via hat 21-cold-reader):** `finalize!`'s docstring gets no equivalent
acknowledgment of the false-cognate risk that the decision log gave `integrator`, so the same class
of first-encounter misreading (GC-triggered cleanup vs "apply the post-step forcing projection")
goes unflagged.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `src/Generator.jl`'s `finalize!` docstring gains a new closing sentence, appended
after the existing description (there was no incorrect clause to delete here — the ask was for an
*added* disclaimer, matching the `integrator` precedent, so this is the correct kind of repair):

```
 after its final stage, so everything that follows the step — the diagnostics, the derived
-observables, the tracer advance — sees the forced end-of-step fields.
+observables, the tracer advance — sees the forced end-of-step fields. The name is this protocol's
+step-closing verb, unrelated to `Base.finalize`, Julia's garbage-collection finalizer vocabulary.
```

This explicitly names `Base.finalize` and disclaims the GC-finalizer reading, mirroring the
decision log's treatment of the `integrator` false cognate that the finding cited as precedent.
Checked for other rendered `finalize!` sites (the module contents one-liner at line 29, the
`step!`-adjacent mention at line 285): both are short pointer mentions, consistent with the house
rule that a caveat lives at the operation's own docstring, not repeated at every mention.

---

## Finding 56 — `ScalarBuffers` is described but never given its own definition site

**Owner's ask (verbatim, via hat 21-cold-reader):** `ScalarBuffers` is named and its field layout
described in prose inside `IntegratorBuffers`'s Fields section, but has no own docstring block, no
`## ScalarBuffers` heading, and no package-index entry, so a reader cannot look it up the way every
other named type can.

**VERDICT: HONORED**

**Which question:** none.

**Evidence:** `src/Propagator.jl`'s `IntegratorBuffers` Fields entry for `scalar` is edited in
place to say explicitly that this is the type's only description:

```
-- `scalar` — a `ScalarBuffers` for the passive scalar ``\varphi`` when `scalar = true`, else `nothing`;
+- `scalar` — a `ScalarBuffers` (an internal record; this entry is its full description) for the
+  passive scalar ``\varphi`` when `scalar = true`, else `nothing`;
```

`ScalarBuffers` remains unexported (confirmed: no `export ScalarBuffers` in `src/Propagator.jl`),
consistent with `CLAUDE.md`'s own documented convention that a type whose positional form takes
preallocated internals (the docstring names `IntegratorBuffers` itself as an example) is
deliberately not given a separate constructor-first docstring, to avoid inviting a caller to
assemble the machinery by hand. `ScalarBuffers` is exactly that shape — a nested nothing-when-unused
nested buffer bundle. The fix does not add an index entry (it cannot, without an exported docstring),
but it does resolve the reader-facing complaint: the one paragraph that describes `ScalarBuffers` now
says outright that it is the complete, deliberate description, rather than leaving a cold reader to
wonder whether documentation exists elsewhere and was simply missed. No owner-authored ruling
specific to this item was found in `.claude/`, but the disposition is not a bare "by design"
assertion invented for this finding — it applies an already-recorded, pre-existing house convention
to a type that fits it.

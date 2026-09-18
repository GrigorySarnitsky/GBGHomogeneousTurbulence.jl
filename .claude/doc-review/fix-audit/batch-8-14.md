# Fix audit — batch 8–14

Audited against `git diff 0b3d58c..HEAD` and the current corpus
(`src/`, `docs/`, `CLAUDE.md`) in
`/home/grigory/Dropbox/Research and Teach/Isotropic Turbulence/GBGIsotropicTurbulence`.

---

## 8 — no demonstrated validation numbers or performance data anywhere

**Owner's verbatim ask (finding text):** "nowhere in the rendered docs is there a single
demonstrated result from an actual run of this code — no measured `C_K`, `Re_λ`, or spectrum
plotted against a model law, and no wall-clock/throughput number for any grid size on any
backend."

**VERDICT: HONORED**

**Which question failed:** none — this is the one finding in the batch where the correct
action was *not* to edit prose.

**Evidence:** The merged pile's header records the owner's actual ruling: "DEFER to the owner:
demonstrated validation numbers, PF's verbatim in-place-steer sentence" — i.e. the owner
authorized escalation rather than an edit. `00-SUMMARY.md:23` records "3 ESCALATED to owner
(demonstrated validation / performance numbers are a docs-scope decision, not an edit)" and
line 69 lists it under "Open for the owner: free-b-3 (demonstrated validation numbers)". I
grepped the diff for fabricated evidence (`git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md |
grep -i "measured\|benchmark\|throughput\|wall-clock\|C_K\|Re_λ ="`) and found no invented
numbers were inserted to paper over the gap — the finding remains genuinely open, as the owner
directed. A finding that names a scope decision correctly deferred to the owner, and left
verifiably undecided rather than laundered shut, is the honored outcome.

---

## 9 — `kinetic_energy` and `scalar_variance` name both a setting and a measurement

**Owner's verbatim ask (finding text):** identifies that `kinetic_energy`/`scalar_variance`
serve as both `Simulation` keyword-argument names (a setting) and `Observables` function names
(a measurement), calling it a clarity cost for a reader skimming a snippet with both uses
nearby.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** The pile's own OWNER RULINGS header states as ground truth: "the owner ruled 'Yes,
go ahead.' over a plan that enumerated ... DISMISS ... the kinetic_energy keyword/observable
dual use (deliberate symmetry) ... Those dismissals are owner-sanctioned, not assistant-authored."
`00-SUMMARY.md:24` records "4 DISMISSED (deliberate symmetry: the keyword names the quantity
the observable measures)". Since the pile records this as an *owner* decision, not an
assistant declaration, it is not LAUNDERED under the rubric's own test ("A close is only
legitimate if the OWNER decided it"). Confirmed no code/doc changes were made under this
finding: `git diff 0b3d58c..HEAD -- src/Observables.jl src/SimulationRun.jl | grep
"kinetic_energy\|scalar_variance"` shows only an unrelated import addition
(`kinetic_energy_and_dissipation`) — the dual-use naming itself is untouched, consistent with
"dismissed, not silently reworded".

---

## 10 — `valid_Reλ` is advisory-only, so `Lundgren2002` can silently return an unphysical sign

**Owner's verbatim ask (finding text):** flags that `structure_function(Lundgren2002(), r, fp;
order = 3)` at `Re_λ` below ~34 silently returns a physically nonsensical (wrong-sign) value
because `valid_Reλ` is "deliberately unenforced everywhere in `Phenomenology`", with no warning
or error, unlike the rest of the package's guard-heavy style.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** Same OWNER RULINGS header: "DISMISS ... valid_Reλ advisory-by-design (documented
in place) ... Those dismissals are owner-sanctioned, not assistant-authored."
`00-SUMMARY.md:25` records "5 DISMISSED (`valid_Reλ` advisory by design, stated in `Reference`
and Lundgren's caveat)". `git diff 0b3d58c..HEAD -- src/phenomenology/StructureFunctions.jl
src/Phenomenology.jl | grep "valid_Reλ"` returns nothing — no code or docstring touched. The
current source (`src/Phenomenology.jl:188`) still reads "it is advisory: a comparison that opts
in reads it, nothing enforces it" verbatim as quoted in the finding, confirming the dismissal
did not quietly reword the disclosure away.

---

## 11 — the decision log's prose density works against it as documentation

**Owner's verbatim ask (finding text):** several `ARCHITECTURE.md §11` entries (the 2026-07
"observation layer" and "memory audit" entries) run 300–500+ words as a single paragraph with
deeply nested parentheticals, "exactly the 'a passage you had to read three times' reaction this
review is watching for."

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** OWNER RULINGS header: "DISMISS ... the decision-log register/density complaints
(deliberate append-only ledger) ... Those dismissals are owner-sanctioned, not
assistant-authored." `00-SUMMARY.md:19-20` (the free-reader-a local-3 sibling finding, same
disposition applied here per `00-SUMMARY.md:26`, "6 DISMISSED (as a-3)") records: "3 DISMISSED
(the decision log is a deliberate append-only ledger; its audience is recorded in CLAUDE.md)."
Checked the two named entries directly: `docs/ARCHITECTURE.md:1206` ("30. (2026-07) The
observation layer...") and `:1288` ("33. (2026-07) The memory audit..."). Neither hunk range
appears in `git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md` — the entries are byte-for-byte
untouched, confirming the dismissal was not accompanied by a stealth rewrite.

---

## 12 — inconsistent leading-semicolon style across `FixedDomain(...)` call examples

**Owner's verbatim ask (finding text):** every worked `FixedDomain(...)` example leads with `;`
except the one on the Forcing page's `DeferredForcing`/`VarianceRescaling` example
(`domain = FixedDomain(grid_points_per_axis = 64, ...)`, no leading `;`).

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `00-SUMMARY.md:27` records "7 FIXED (the one semicolon-less `FixedDomain`
example)." Diff confirms the exact site:
`git diff 0b3d58c..HEAD -- src/Forcing.jl` shows
`-domain = FixedDomain(grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(),`
`+domain = FixedDomain(; grid_points_per_axis = 64, side_length = 2π, dealiasing = TwoThirds(),`
— a genuine correction, not an appended duplicate. Class-swept, not line-only: a corpus-wide
grep for every `= FixedDomain(` call site (`docs/src/observables_cache.md:425`,
`src/Forcing.jl:170`, `src/SimulationDomain.jl:179,182`, `src/SimulationRun.jl:260`) shows all
five now open with `FixedDomain(; grid_points_per_axis = ...)`, so no sibling instance was left
behind.

---

## 13 — "front door" used outside its own sanctioned scope

**Owner's verbatim ask (source: CLAUDE.md, owner-ruled 2026-08-24, quoted by the finding):**
"`Simulation` may be called *the front door* only in its own description — its docstring and
its own api-page/§4.7 sections, where the term is introduced — and every other surface names
`Simulation` explicitly... an alias lives where it is defined, nowhere else." The finding
flags `ARCHITECTURE.md §7` using "front door" live, unqualified, outside that sanctioned scope.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `00-SUMMARY.md:28` records "1 FIXED (§7 names the constructor)". Confirmed in
`git diff 0b3d58c..HEAD -- docs/ARCHITECTURE.md`:
`-...neither the domain nor the `Simulation` front` / `-door exposes an override.` →
`+...neither the domain nor the `Simulation`` / `+constructor exposes an override.` — the
flagged clause is corrected in place (the alias replaced by "constructor"), not appended beside
the old text. A corpus-wide sweep for every remaining "front door" occurrence
(`grep -rn "front door" docs/src/ docs/ARCHITECTURE.md src/ CLAUDE.md`) shows every surviving
instance sits either in `§4.7`'s own heading ("### 4.7 `SimulationRun` — the front door",
sanctioned), in `docs/src/decisions.md` / `ARCHITECTURE.md §11` (the decision-log history,
sanctioned as history per CLAUDE.md's own parenthetical), in `CLAUDE.md`'s own policy sentence
(defining the rule), or in one un-rendered `#` comment (`src/SimulationRun.jl:624`, "so the
front door checks it for every scheme") which is neither a "page" (the finding's own location
scope) nor rendered documentation, and was not touched by this diff either way — outside the
finding's stated surface. The notation-page glossary row was also widened in the same pass to
name the §4.7 "wider entry-point sense" explicitly (`docs/src/notation.md:135`), closing the
ambiguity the finding raised about which sense governs §4.7's heading, rather than leaving that
row silent on it.

---

## 14 — a directional cross-reference error: "below" should be "above"

**Owner's verbatim ask (finding text):** the τ row in notation.md's "Derived scales" section
points to "the integrating factor's row below", but that row (in "Spectral representation and
operators") is textually *earlier* in the page, i.e. above, not below.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `00-SUMMARY.md:28-29` records "2 FIXED (τ row names the table above)". Confirmed
in `git diff 0b3d58c..HEAD -- docs/src/notation.md`:
`-...in the integrating factor's row below, \tau is a Runge–Kutta stage substep...` →
`+...in the integrating-factor row of *Spectral representation and operators* above, \tau is a
Runge–Kutta stage substep...` — the wrong directional word is replaced (not appended beside),
and the fix goes further than minimally required by naming the actual section instead of a bare
"above"/"below", removing the ambiguity that produced the original error. Verified the
direction is now factually correct: `grep -n "^## " docs/src/notation.md` shows "Spectral
representation and operators" at line 54 and "Derived scales" (home of the τ row) at line 81 —
54 < 81, so "above" is correct.

---

### Batch summary

All seven findings in this batch (8–14) verify as **HONORED**. Three (9, 10, 11) are
owner-ruled dismissals rather than edits — confirmed legitimate because the pile's own
OWNER RULINGS header attributes the "DISMISS" decision to the owner ("Yes, go ahead" over a
plan that named these specific dispositions), not to the assistant, and because the flagged
text in each case is verifiably untouched (no stealth reword masquerading as a fix). One (8) is
an owner-ruled deferral, verified genuinely still open with no fabricated numbers inserted to
paper over the gap. Three (12, 13, 14) are genuine text corrections, each verified to replace
(not append beside) the flagged clause, each swept across its full class of sibling instances,
and each factually correct against the surrounding document structure or corpus.

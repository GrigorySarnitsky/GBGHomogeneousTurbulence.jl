# Fix audit — batch 15–21

Diff audited: `git diff 0b3d58c..HEAD` (commits `752149e`, `5a6157f`, `2d981f8`, `4a03de9`).
Pile: `/tmp/claude-1000/merged-pile.md`, findings 15–21.

---

## Finding 15 — Forcing module's "run-specific, no default" list omits `injection_rate`

**Owner's verbatim ask (via the panel):** the module docstring's keyword list — *"what a run holds
fixed — `target`, `rate`, `over` — has no canonical value and is required"* — never names
`ConstantPower`'s own required, run-specific keyword `injection_rate`.

**VERDICT: HONORED**

**Evidence:** `src/Forcing.jl:59` now reads *"a run holds fixed — `target`, `rate`,
`injection_rate`, `over` — has no canonical value and is required."* `injection_rate` is inserted
into the enumeration itself (not appended as a caveat beside the old sentence), so the list is now
exhaustive over the four strategies as the surrounding "does the value come from the method, or
from this run?" framing promises. The neighbouring sentence was also reworded ("A default at this
layer never hides…") to fold in a `VarianceController` clarification, which is in scope of the same
paragraph and not a separate unrequested change.

---

## Finding 16 — "Re = 1/ν" vs "2π/ν" phrasing needs a second read every time it appears

**Owner's verbatim ask:** *"Worth a rewrite (e.g., 'with length measured in units of
u'/(rate)...') the next time this passage is touched, purely for a first-time reader's sake — I had
to stop and do the algebra myself the first time I hit it, even though it is correct every time."*

**VERDICT: UNDONE**

**Evidence:** The three cited locations are byte-for-byte unchanged across the whole
`0b3d58c..HEAD` diff:
- `docs/ARCHITECTURE.md:248` still reads `` u' = L = 1``; ``2\pi/\nu`` on the shipped defaults,
  where ``L = 2\pi``) `` — identical to the quoted text.
- `src/Generator.jl:55` still reads `with the box in units where ``u' = L = 1`` this is
  ``\mathrm{Re} = 1/\nu``…` — identical.
- `docs/src/notation.md:49` still carries "the same construction verbatim a third time" the finding
  described, unchanged.

`git log 0b3d58c..HEAD --format="%s%n%b"` contains no mention of Reynolds-number phrasing, and no
`.claude/` disposition file records this as deliberately deferred or owner-ruled out of scope. The
finding was explicitly conditional ("the next time this passage is touched") rather than a mandate,
but nothing in the fix pass shows it was even considered — it is simply absent from the diff.

---

## Finding 17 — Notation-page operator glyphs list PF names without the mutating `!`

**Owner's verbatim ask (via the panel):** the Spectral-representation-and-operators table lists
`curl`, `divergence`, `to_spectral`, `to_physical`, `convolve`, `helmholtz_projection` — the
allocating names — while every other surface (architecture §5, the decision log, the generator
docstrings) uses the bang form for the same functions; low confidence this might be an intentional,
unstated convention, but "nothing on the page states that reading."

**VERDICT: HONORED**

**Evidence:** `docs/src/notation.md:5-6` now opens with: *"An operation family is listed once, by
its allocating name; the in-place sibling appends `!` (`curl` / `curl!`)."* The table's own entries
(`docs/src/notation.md:61-65`) were left as the allocating names — which is exactly what the finding
flagged as "likely deliberate ... but nothing on the page states that reading." The fix supplies the
missing statement rather than renaming the table (which would have duplicated the catalogue-family
convention CLAUDE.md already sanctions). Cross-checked that every listed operation genuinely has a
documented `!` sibling in the corpus (`to_physical!`, `curl!` / `divergence!` in ARCHITECTURE §5,
`helmholtz_projection!` in the decision log), so the added sentence is not itself a false claim.

---

## Finding 18 — Pao's hypothesis mis-stated as "constant spectral flux through the dissipation range"

**Owner's verbatim ask:** *"'The spectral energy flux stays constant' is the opposite of the
mechanism: constant flux means zero dissipation and no roll-off... resolution_hint: say 'the
hypothesis that the cascade timescale (flux per unit spectral energy) retains its inertial-range
form through the dissipation range.'"*

**VERDICT: HONORED**

**Evidence:** `src/phenomenology/Spectra.jl`:
- `PaoDissipation` docstring now reads: *"from the hypothesis that the cascade timescale — the
  spectral flux per unit spectral energy — retains its inertial-range form through the dissipation
  range, so the flux decays there as viscosity drains it"* — matching the resolution hint almost
  verbatim, and its `# Fields` entry for `α` follows suit ("the cascade-timescale hypothesis").
- `Pao1965` docstring's *"constant-spectral-flux hypothesis"* → *"constant-cascade-timescale
  hypothesis"*.
Both flagged locations were corrected (not merely appended to), and `grep -rn "constant.spectral.flux"
src/ docs/` returns nothing — no surviving instance of the false phrasing anywhere in the corpus.

---

## Finding 19 — `scalar_rhs!` contradicts itself on the κ = 0 mode

**Owner's verbatim ask:** *"The 'only to roundoff' rationale is the velocity's situation ... pasted
onto the scalar, where it appears false. ... resolution_hint: keep the pin if wanted for uniformity,
but attribute the roundoff residual to the velocity route only; for the divergence form state that
iκ·(·) vanishes identically at κ = 0."*

**VERDICT: LINE-ONLY**

**Evidence:** The primary flagged docstring is fixed correctly: `src/Generator.jl` (`scalar_rhs!`)
now reads *"The advective term's κ = 0 mode is zero exactly by construction — the divergence
multiplier iκ vanishes identically at κ = 0 — and the assembly pins it anyway, for uniformity with
the velocity route, whose product mean is only roundoff-small."* This is exactly the resolution
hint's requested attribution split.

But the finding named a third location carrying "the same roundoff claim for the scalar":
`docs/ARCHITECTURE.md`, decision 60 (the κ = 0 pin entry, ~line 2028-2043), which still reads: *"the
mean mode is exactly conserved by the continuous equations
(⟨u×ω⟩ = 0 ... ⟨∇·(uφ)⟩ = 0), but discretely the identity holds only to roundoff"* — unchanged by the
diff, and still asserting "roundoff" for the scalar divergence identity, the exact claim finding 19
says is false. `docs/src/observables_cache.md:273` ("holds the κ = 0 tendency at zero") was left
alone but is not itself false (no roundoff claim there), so it is not part of the surviving
class. The decision log entry is: the flagged class (roundoff misattributed to the scalar route)
survives verbatim on a rendered docs page the finding explicitly cited as a location.

---

## Finding 20 — "The spectral field" / "the spectral state" — field-vs-representation category error

**Owner's verbatim ask:** *"'a scalar field in spectral representation' [is the corpus's own
correct form] ... the N̂ bullets and the two 'spectral state' phrasings are the residual instances
of the conflation the house rule bans. resolution_hint: 'the field in spectral representation
receiving …'; 'recovered … from the state's spectral representation.'"*

**VERDICT: HONORED**

**Evidence:** All four cited instances corrected to the exact resolution-hint wording:
- `src/Generator.jl`, `velocity_rhs!` and `scalar_rhs!` `N̂` bullets: *"the spectral field
  receiving"* → *"the field in spectral representation receiving."*
- `src/Observables.jl:20-21` (module docstring `vorticity_physical!` entry): *"the spectral
  state"* → *"the state's spectral representation."*
- `docs/src/api/Observables.md:54` ("Vorticity recovery" section): same correction, *"from the
  state's spectral representation."*
`grep -rn "spectral field\b" src/ docs/` and `grep -rn "spectral state" src/*.jl docs/src/*.md
docs/ARCHITECTURE.md` confirm no surviving instance of either banned phrase outside plain `#`
comments (`src/GBGIsotropicTurbulence.jl:20`, `src/SimulationRun.jl:3` — internal, non-rendered
comments, not part of the user-facing docs surface the finding audited) and one unrelated prose use
in the decision log ("the spectral state" as a noun for "what was stored," decision-log context,
not a docstring formula).

---

## Finding 21 — `ModelSpectrum` calls the roll-off length "L" where the glossary reserves L for the box side

**Owner's verbatim ask:** *"The formula uses ℓ, the glossary binds ℓ to exactly this quantity and
states 'never the box side L'... resolution_hint: replace '$L$' with '$\ell$' in that sentence."*

**VERDICT: HONORED**

**Evidence:** `src/phenomenology/Spectra.jl:310`: *"which reads ``\varepsilon`` and the roll-off's
own length ``\ell``"* — `L` replaced by `\ell` exactly as the resolution hint asked, and the
surrounding sentence ("see `large_scale_length` — `L_{11}` for most forms...") is otherwise
untouched, so no unrelated rewrite. Checked the rest of the `ModelSpectrum` docstring for
consistency: the displayed formula already used `f_L(\kappa \ell)` (glyph `L` names the *roll-off
function* `f_L`, a different object from the *length*, which is correctly disambiguated from the
box side everywhere else in the same docstring) — no other stray `$L$`-for-length instance remains
in the docstring.

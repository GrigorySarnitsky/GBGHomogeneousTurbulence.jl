# Closure — Hat 03: Free-eyed reader C

## Finding 1 — `⟨θ²⟩` vs `⟨φ²⟩` contradiction

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md:489` (§2 walkthrough) now reads
`` \langle\varphi^2\rangle `` must settle too; the decision-log entry (line ~944, decision 13)
also reads `` \langle\varphi^2\rangle `` must flatten too. `rg --glob '!.claude/**' -n
'theta|\\theta' docs/ARCHITECTURE.md docs/src/ src/` returns only the explicit ban statement
(`docs/ARCHITECTURE.md:838`) and the notation-glossary entry documenting the ban
(`docs/src/notation.md:32`) — no stray `\theta` remains anywhere in the corpus.

---

## Finding 2 — Rogallo cited as both 1981 and 1984

**VERDICT: ABSENT**

Evidence: `rg --glob '!.claude/**' -n 'Rogallo' src/ docs/ARCHITECTURE.md docs/src/` shows every
citation as 1981, including the `PhaseShift`/domain docstring at `src/SimulationDomain.jl:114`
(`Rogallo (1981) — Numerical experiments in homogeneous turbulence, NASA TM-81315`), matching
`docs/ARCHITECTURE.md:1144` and the §References entry at `docs/ARCHITECTURE.md:2110`. A
corpus-wide search for `1984` turns up only unrelated citations (Nosé, Berendsen, Qian) — none
Rogallo.

---

## Finding 3 — "summationorder" glued word

**VERDICT: ABSENT**

Evidence: source at `docs/ARCHITECTURE.md:632` reads `*summation order*` with the space intact.
Checked the rendered build too: `grep -o '.\{40\}summation.\{40\}'
docs/build/architecture/index.html` returns `"...bought there by <em>summation order</em>, not by
a wider accumulator..."` — renders as two words, correctly emphasized.

---

## Finding 4 — `unit_kernel` missing from ARCHITECTURE.md §4.1

**VERDICT: ABSENT**

Evidence: `docs/ARCHITECTURE.md` §4.1 (lines 184–188) now explicitly lists `unit_kernel` in its
walkthrough of the per-mode symbols on the frame: "...the constant-1 `unit_kernel` in the same
lazy form, so a plain variance can join a fused multi-weight reduction (decision 63); and the
dealias kernel..." — sitting directly between the squared-wavenumber kernel and the dealias
kernel, exactly where the finding said it was missing.

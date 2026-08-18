# Panel review — DNS practitioner / GPU performance hat

Scope: numerical methods (rotational form, exact per-mode integrating factor, dealiasing bands,
IFRK2 / IFLowStorageRK3, the deposit-driven cache schedule and its transform accounting, particle
push, forcing) and performance claims (allocation-free hot loop, in-place, GPU-agnostic storage,
minimal footprint, CFL scaling, the "2× transforms" cost of `PhaseShift`).

**Overall verdict.** This is an unusually tightly cross-checked document. I re-derived the
dealiasing-band arithmetic (`2/3` vs `√2/3·N` vs `2√2/3·κ_Ny`, all three consistent and mutually
convertible), the transform-count table in `observables_cache` §2.3 (18/9, 21/18, 36/18, 42/36 —
every entry reconciles exactly with the RK3 3-stage assembly recipe stated two paragraphs above
it, and with the decision-log's "RK3 51→42 c2r / RK2 34→28 c2r" post-fix numbers), the CFL
constants (`C_CFL ≲ 0.83` from `y_s=√3` and `κ_max Δx = 2π/3`, rounds correctly to the stated
`0.5`), the Williamson RK3 coefficients (`A,B,d` match the standard "RKW3" case-7 set, `d` sums to
1), the IFRK2 stability polynomial (`|R(iy)|² = 1+y⁴/4`, correctly unstable on the imaginary axis),
the memory-ledger byte counts (322.5 MiB / 256³ frame reconciles exactly to a mix of one real and
two complex-container `N²(N/2+1)` arrays; 384 MiB per physical vector; 768 MiB for two of them),
and the `κ_p/√2` shell-peak / `Re_λ ∼ N^{2/3}` / Yaglom `-2/3 ε_φ` derivations. None of these
turned up an error. The remaining findings are narrower — one substantive framing tension, and two
minor/nit clarity points.

---

## Finding 1 — "Float64 is the production precision" sits oddly for a GPU-primary, consumer-GPU-targeted code

**Type:** performance
**Severity:** minor
**Confidence:** medium

**Locations:**
- ARCHITECTURE §6: "Both precisions are supported equally, with no privileged default. `Float32`
  is the development and desktop precision; `Float64` is the production precision."
- Same section, two sentences later: "the working point is chosen by direct fitness test, never
  decreed."
- `SimulationRun.Simulation` docstring: `element_type = Float64` is the front-door default.

**Description:** The document is explicit elsewhere that precision is "a studied axis…chosen by
direct fitness test, never decreed," yet in the same breath it hands out a normative label —
"`Float64` is the production precision" — before any such study is described as having been run.
For a package whose stated primary target is the GPU (Home page, invariant 4), this framing cuts
against common GPU-DNS practice: on non-datacenter cards (the class this package's own front-door
default and this reviewer's own fleet run on) FP64 throughput is typically 1/32–1/64 of FP32, so
defaulting new users toward "the production precision" being double is a real throughput
concession that the doc does not weigh against the GPU-primary charter. This is not a
self-contradiction inside the rendered text (the sentence is consistent with itself), but it reads
as pre-judging the fitness-test outcome the same section says has not been decreed, and a reader
skimming only the labeled recommendation could pick the more expensive default on exactly the
hardware this package is built for.

**Contradicts:** (soft, framing-level) "no privileged default" / "chosen by direct fitness
test, never decreed" (ARCHITECTURE §6) vs. "`Float64` is the production precision" (same section,
same paragraph).

---

## Finding 2 — The §2.3 transform-count table's scheme scope is stated once, two paragraphs before the table, not at the table itself

**Type:** clarity
**Severity:** minor
**Confidence:** medium

**Locations:**
- `observables_cache` §2: "One configuration fixes the system: a mask dealiasing rule…, **a
  three-stage scheme**, the default rescaling velocity forcing, an adaptive timestep."
- `observables_cache` §2.3 table: `TwoThirds, HouLi | 18 inverse, 9 forward | 21 inverse, 18
  forward` / `PhaseShift | 36 inverse, 18 forward | 42 inverse, 36 forward` — no scheme name in the
  table or its immediately surrounding prose.

**Description:** The transform counts are correct for `IFLowStorageRK3`'s three stages (I
reconstructed them independently from the per-evaluation recipe given just above the table: 6
inverse + 3 forward per velocity evaluation, ×3 stages = 18/9; +1 inverse/+3 forward per stage for
the scalar = 21/18; `PhaseShift` doubles each = 36/18, 42/36 — all match). But the "three-stage
scheme" qualifier that makes these numbers scheme-specific appears only once, in §2's opening
sentence, and is not repeated at the table or in the paragraph that walks through the recipe
immediately before it. Recomputing the same recipe for `IFRK2`'s two stages gives materially
different counts (a reader who trusts the decision log's "RK2 34→28 c2r" figure would find no
route from the rendered table alone to that smaller number). A reader who jumps straight to the
table — a plausible use pattern for a reference page — could reasonably take it as scheme-agnostic.

**Resolution hint:** repeat "(for the three-stage scheme)" in the table's caption or column header.

---

## Finding 3 — `IFLowStorageRK3`'s headline "two field registers per field" sits next to a three-array `IntegratorBuffers` field list

**Type:** clarity
**Severity:** nit
**Confidence:** low

**Locations:**
- `Propagator.IFLowStorageRK3` docstring: "…two field registers per field: the state's own array
  plus one accumulator (`stage1`; the raw-assembly register `nonlinear` is the dealiasing seam's
  addition, not the scheme's)."
- `Propagator.IntegratorBuffers` Fields: `stage1` — "allocated by every scheme"; `nonlinear` — "the
  assembled right-hand side; `IFLowStorageRK3` only, else `nothing`."

**Description:** The docstring already anticipates and answers this, so I list it at low
confidence: a reader who takes "two field registers per field" as the actual resident GPU footprint
(rather than Williamson's classical accounting, which conventionally excludes the transient
right-hand-side buffer any explicit RK scheme needs) will find a third field-sized array
(`nonlinear`) genuinely resident and counted in the memory-audit ledger (per ARCHITECTURE's decision
log, "the scalar's transient registers (`copy`/`nonlinear`/factor could share one slot)" treats
`nonlinear` as a real, distinct buffer). This matches how the term is conventionally used in the
spectral-DNS literature (Rai–Moin/Spalart–Moser–Rogers-style RK3 implementations also need a
transient RHS array outside the "2N" count), so this is very likely *not* a defect — flagging only
because the parenthetical explaining the attribution is easy to skim past on a first read of the
headline claim.

---

## Not flagged (verified correct, noted for the record)

- `PhaseShift` band: `κ_max = (√2/3)N·(2π/L) = (2√2/3)κ_Ny ≈ 0.94κ_Ny`, a factor `√2` wider radius
  than `TwoThirds`'s `(2/3)κ_Ny`, `(√2)³ ≈ 2.8×` the retained-sphere mode count, at exactly `2×` the
  transforms for both velocity and scalar (post the same-stage `u_shifted` reuse fix) — consistent
  across ARCHITECTURE, `notation`, `observables_cache`, `Generator`, `Observables`, and
  `SimulationDomain`.
- Transform table cross-checked against the decision log's pre-/post-fix c2r counts for both RK3
  (51→42) and RK2 (34→28, reconstructed from the two-stage recipe).
- CFL derivation (`C_CFL ≲ y_s/(κ_max Δx)`, `κ_max Δx = fπ`) reproduces the stated `0.83`/`0.5`
  (RK3) figures exactly.
- Williamson RK3 coefficients, IFRK2 stability polynomial, Heun endpoint formula (verified against
  the integrating-factor substitution by hand), `κ_p/√2` shell-peak derivation, `ConstantPower`'s
  `A = target/(2E_band)`, and the frame/physical-vector byte counts (322.5 MiB, 384 MiB, 768 MiB,
  2.3 GiB) all reconcile exactly.

# Beat 02 — MD theory (the formalisms that dictate architecture) vs. IT's five design problems

Research date 2026-07-18. Beat: the **theory** of organizing MD-like dynamics — not engines, the
formalisms. The Liouville-operator / Trotter-factorization picture (Tuckerman–Berne–Martyna 1992);
extended-system thermostats (Martyna–Tuckerman–Tobias–Klein 1996); stochastic thermostats and the
splitting alphabet (Bussi–Donadio–Parrinello CSVR 2007; Leimkuhler–Matthews BAOAB); constraint
projections (SHAKE / RATTLE); and backward-error / shadow-Hamiltonian theory (Hairer–Lubich–Wanner).

The MD dictionary maps onto IT's Mori–Zwanzig reading: **state** = phase point ``\Gamma=\{x,p\}``;
**generator** = the Liouville operator ``\mathrm{i}L`` (the RHS as a vector field / first-order
differential operator); **propagator** = ``\mathrm e^{\mathrm iLt}`` and its factorization = the
integrator; **forcing** = thermostats / barostats / constraints; **observables** = phase functions.
IT's exact viscous integrating factor ``\mathrm e^{-\nu\kappa^2\,\mathrm dt}`` is the field-theory twin of
an **exactly solved subflow** (an "interaction-picture" / "``O``-type" factor).

Every claim is verified against a primary source (the paper's own text, extracted from the PDF) with the
decisive line quoted. Seeded leads from the prompt are marked **CONFIRMED** or **REFUTED**. Where I
could not verify, I mark **UNVERIFIED**.

The headline result for IT's design review: **the MD-theory canon does not cut the primitive at
generator-vs-propagator. It cuts it at a factorization of the propagator into named subflows, each tied
to an additive piece of the generator, each carrying its own exactly-or-approximately-solved flow map.**
That is a direct verdict on P1, and it also predicts the *shape* of IT's four-hook Forcing protocol.

---

## 1. Tuckerman–Berne–Martyna 1992 — the Liouville/Trotter formalism (P1, P5)

Tuckerman, Berne, Martyna, "Reversible multiple time scale molecular dynamics," *J. Chem. Phys.*
**97**(3), 1990–2001 (1 Aug 1992). Text extracted from the Berne-group scan
(`columbia.edu/cu/chemistry/groups/berne/papers/jcp_97_1990_1992.pdf`).

### 1.1 The generator is a differential operator; the propagator is its exponential (P1)

The Liouville operator is defined (their Eq. 2.1) as the first-order vector field generating the flow:

> "The Liouville operator L for a system of f degrees of freedom is defined in Cartesian coordinates
> as … iL = {…,H}" — the Poisson bracket with the Hamiltonian.

> "The classical propagator is then U(t) = e^{iLt}" (Eq. 2.2), and "the state of the system at time t is
> given by Γ(t) = U(t)Γ(0)" (Eq. 2.3).

This is *exactly* IT's Mori–Zwanzig reading made literal: the **generator** is the RHS as an operator,
the **propagator** is `exp(generator · dt)`. IT names them; MD theory writes them as one algebraic
object and then *factorizes* it — the crucial move.

### 1.2 The primitive cut is a factorization into subflows, NOT generator-vs-propagator (P1)

The formalism's central act is to **split the generator additively** and Trotter-factorize the
exponential (Eqs. 2.4–2.6):

> "we will decompose the Liouville operator L into two parts such that iL = iL₁ + iL₂."

> "For this decomposition the Trotter theorem yields
> e^{i(L₁+L₂)Δt} = e^{iL₁(Δt/2)} e^{iL₂Δt} e^{iL₁(Δt/2)} + O(Δt³)" (Eq. 2.5).

> "Because the three factors … are separately unitary … any integrator based on this Trotter
> factorization will be reversible." (following Eq. 2.6)

Each factor is a subflow that is **solved exactly** by the shift property (Eq. 2.16):

> "e^{c ∂/∂q} f(q) = f(q + c), where c is independent of q."

So the architecture the formalism *dictates* is: **name the additive pieces of the generator; each piece
is an exactly-integrable subflow (a translation in some coordinate); the propagator is a symmetric
product of these subflow exponentials.** There is no free-standing "propagator object" that
hand-assembles the RHS — the propagator *is* the ordered list of subflow letters, and the "RHS" only
ever appears already partitioned into the pieces each subflow consumes.

**Verdict on P1.** The absent Generator/Propagator seam in IT is the absence of exactly this
partition. In MD theory the scheme never "hand-assembles the RHS": the RHS is presented *pre-split* as
`{iL₁, iL₂, …}` and the scheme is pure letter arithmetic (`e^{iL₁ h/2} e^{iL₂ h} e^{iL₁ h/2}`). IT's
proposed `ResolvedGenerator` with a `rhs!/factor!/prepare!/finalize!` protocol is the field-theory
realization of this partition — provided the protocol exposes the pieces as *named subflows*, not as one
monolithic `rhs!`. The theory's warning is sharper than "add a seam": it says the seam is a *partition
of the generator into exactly-solved and correction pieces*, and the scheme should see only the
partition, never re-derive it. IT's silent 3rd→1st-order scalar bug (a stage reading a mid-update
velocity) is the signature failure of hand-assembly: in the Trotter picture each subflow reads a
well-defined intermediate state `Γ_a[Δt/2; Γ(0)]` (their Eqs. 2.7–2.11, the serial application), and a
subflow that reads the wrong intermediate is a *malformed factorization*, immediately visible as a
broken letter string.

### 1.3 Velocity Verlet AND position Verlet from the *choice* of split (P1, P5)

The single most transferable fact for IT: **the same generator, split two ways, gives two different
integrators — and the "exactly-solved" piece is a design choice.** With

> "iL₁ = ẋ ∂/∂x, iL₂ = F(x) ∂/∂p … This leads to … the velocity Verlet algorithm" (Eqs. 2.14–2.17),

versus the *reversed* assignment

> "we can generate another reversible algorithm by taking iL₁ = ẋ ∂/∂x, iL₂ = F(x) ∂/∂p" with the
> force half-steps outermost — "This is an entirely new reversible integrator which we name the
> **position Verlet** integrator." (Eqs. 2.21–2.22)

**CONFIRMED (seeded lead): the primitive is a factorization into named subflows, not a
generator-vs-propagator dichotomy.** The generator is fixed; what varies (and defines the scheme) is the
partition and the ordering of subflow letters. This is precisely IT's situation: the viscous term is the
naturally "exactly solvable" piece (`exp(-νκ²dt)` is a shift in the interaction picture), and the
nonlinear + forcing terms are the "correction" pieces evaluated at stage points. Which pieces go into
the exact factor vs the stage arithmetic is a *scheme* decision, and the theory says it must be made
explicitly and once, at the factorization, not re-improvised inside each `step!`.

### 1.4 rRESPA — multiple time-stepping *is* a nested factorization (P1, P4)

The generator is split by **force range/stiffness** and the propagator nested (Eqs. 3.1–3.8):

> "F(x) = F_s(x) + F_l(x)" (short + long range, Eq. 3.1), giving
> "iL = ẋ ∂/∂x + F_s(x) ∂/∂p + F_l(x) ∂/∂p" (Eq. 3.4).

> "G_RESPA(Δt) = e^{(Δt/2)F_l ∂/∂p} [ e^{(δt/2)F_s ∂/∂p} e^{δt ẋ ∂/∂x} e^{(δt/2)F_s ∂/∂p} ]^n
> e^{(Δt/2)F_l ∂/∂p}, where δt = Δt/n" (Eqs. 3.6–3.7).

> "one long range force evaluation and n short range force evaluations will be required in a large time
> step Δt … no more work required for this reversible propagator than for the … nonreversible RESPA."
> (after Eq. 3.7)

The architectural lesson for P4 (scratch ownership) and P1: **the outer, slow, expensive piece
(`F_l`, the analogue of IT's long-range forcing / low-mode injection) is factored to the *outside* and
touched once per macro-step; the inner cheap stiff piece runs many sub-steps.** rRESPA is the exact
theoretical precedent for IT folding a *linear* forcing rate into the (exact) integrating factor while a
*nonlinear/expensive* forcing source is added per stage — the two forcing hooks `set_forcing_rate!` and
`add_forcing_source!` are the field-theory image of rRESPA's `F_l`-outer / `F_s`-inner split. The theory
says: put the exactly-solvable/stiff part in the exact subflow, the rest as an additive correction —
which is **one generator term seen at two resolutions**, not two independent mechanisms (see §6).

---

## 2. Martyna–Tuckerman–Tobias–Klein 1996 — extended systems (P4, P5)

Martyna, Tuckerman, Tobias, Klein, "Explicit reversible integrators for extended systems dynamics,"
*Mol. Phys.* **87**(5), 1117–1157 (1996). Text extracted from
`aiichironakano.github.io/phys516/Martyna-Integrator-MolPhys96.pdf`.

### 2.1 Thermostat variables ENTER the phase space with their own equations of motion (P5)

**CONFIRMED (seeded lead).** The Nosé–Hoover-chain thermostat variables ``\eta_j`` and their conjugate
momenta ``p_{\eta_j}`` are genuine phase-space coordinates with their own EOM (their Eq. 1):

> "There are M thermostats η_j with masses Q_j and momenta p_{η_j}."

The dynamics has a **conserved quantity that includes the thermostat variables** (Eq. 2):

> "The conserved quantity for the MTK dynamics is
> H' = Σ pᵢ²/2mᵢ + Σ p_{η_j}²/2Q_j + φ(r) + N_f kT η₁ + kT Σ η_j."

**Mapping to P5.** This is the *phase-space extension* doctrine: a thermostat is not a post-hoc
correction, it is **extra coordinates in Γ with their own generator terms**, and the honest invariant is
`H'`, the *extended* energy, not `H`. IT's P5 reads the whole `Simulation` as a skew-product tower
(time → OU noise → fields → particles). MTTK96 is the canonical precedent: the extended variables live
*in* the restart record (you cannot restart an NHC run without the current `{η_j, p_{η_j}}`), exactly as
IT's P5 argues a stochastic forcing's internal state is a **Markovian-surrogate slot that belongs to the
state record** (litmus: the flow map needs it). The scalar `N_f kT η₁ + kT Σ η_j` term in `H'` is the
"logbook" bookkeeping — the accumulated thermostat work — that makes the extended system conservative.

### 2.2 The thermostat is an OUTER symmetric wrap in the factorization (P1, P4)

The extended propagator is a **nested Trotter factorization with the thermostat on the outside** (Eq. 26):

> "exp(iLΔt) = exp(iL_NHC Δt/2) exp(iL₁ Δt/2) exp(iL₂ Δt) exp(iL₁ Δt/2) exp(iL_NHC Δt/2) + O(Δt³),
> where L₁ and L₂ retain their previous definitions, and iL_NHC = iL − iL₁ − iL₂ consists of the rest of
> the terms in iL."

So the thermostat is (a) a state extension, (b) a generator term `iL_NHC = iL − iL₁ − iL₂`, and (c) a
**propagator letter wrapped symmetrically around the core Verlet update**. Its own factorization is
itself recursively split (Eq. 28), and may carry a *multiple-timestep* inner loop and even a higher-order
Suzuki–Yoshida decomposition (Eq. 29):

> "a multiple time step, n_c > 1, approach has been used. For typical simulations n_c can be taken to be
> one. However, if the frequency associated with the Nosé–Hoover chain is high … n_c must be taken rather
> large."

### 2.3 The thermostat's only coupling to velocities is a multiplicative scale (P4, P5)

Decisive for IT's `apply_forcing!` (post-step rescale) understanding (their §4, around the NHC
implementation):

> "The only coupling of the particle velocities to the thermostat variables occurs through … G₁.
> Therefore, a velocity scaling factor can be accumulated and applied to … the velocity-Verlet step in
> the usual way."

**Mapping to P4 (scratch ownership).** The NHC integrator owns *its own* variables and scratch
(`{η_j, p_{η_j}}`, the accumulated scale factor); it does **not** reach into the core integrator's
registers — it multiplies the momenta at the boundary. This is exactly IT's P4 proposal: forcings own
their scratch; the integrator owns only the stage registers; the coupling is at well-defined boundaries
(a source term, a rate, a post-step scale). MTTK96 is a primary-source endorsement of P4's ownership
split against IT's current "forcing receives the integrator's whole buffer bundle" footgun. A forcing
that reaches into `buffers.velocity_physical` is the analogue of a thermostat routine reaching into the
Verlet position registers — which MTTK96 never does.

---

## 3. Bussi–Donadio–Parrinello 2007 — stochastic velocity rescaling / CSVR (P4, P5)

Bussi, Donadio, Parrinello, "Canonical sampling through velocity rescaling," *J. Chem. Phys.* **126**,
014101 (2007). Text extracted from the arXiv version (`arXiv:0803.4060`).

### 3.1 The rescale as a stochastic differential equation on the kinetic energy (P5)

The thermostat is written as an auxiliary SDE for the total kinetic energy `K` (their Eq. 7):

> "dK = (K̄ − K) dt/τ + 2 √(K K̄ / N_f) dW/√τ."

Here `K̄` is the target, `τ` the coupling time, `dW` a Wiener increment. The velocities are then
rescaled by `α = √(K_new/K_old)`.

### 3.2 The deterministic limit IS Berendsen — and Berendsen has no conserved quantity (P5)

**CONFIRMED (seeded lead), and this is the single most important warning for IT's `BandRescaling`.**
Dropping the noise term recovers deterministic clamp-to-target rescaling:

> "Without the stochastic term this equation reduces to that of the standard thermostat of Berendsen."
> (after Eq. 7)

And the paper is explicit that deterministic rescaling is *broken as sampling*:

> "Berendsen's thermostat is stable, simple to implement and physically appealing, however it has **no
> conserved quantity and is not associated to a well defined [ensemble]**." (§I)

> "Once the equilibrium is reached the proper canonical ensemble is sampled, **at variance with the
> Berendsen's thermostat**." (after Eq. 7)

**Mapping to P5 / IT's `BandRescaling`.** IT's `BandRescaling` holds a band's (or the total) energy
fixed by a **deterministic post-step rescale** — structurally, Berendsen with `τ → 0` (instantaneous
clamp). CSVR's result is the precise statement of "the known artifacts of clamping measured quantities"
in IT's memory: a deterministic clamp **suppresses the physical fluctuations** of the clamped quantity
and admits **no conserved bookkeeping**. This is a fitness caveat IT should document on `BandRescaling`,
and CSVR is the sanctioned upgrade (add the stochastic term → correct fluctuations + a conserved
"effective energy"). It also validates IT's memory rule *"never clamp what you measure."*

### 3.3 The "effective energy" — conservation bookkeeping for a stochastic thermostat (P5)

CSVR restores a conserved quantity by **accumulating the thermostat's work** (their Eq. 15):

> "H̃(t) = H(t) − ∫₀ᵗ (K̄ − K(t'))dt'/τ − 2∫₀ᵗ √(K(t')K̄/N_f) dW(t')/√τ … the last two terms come from
> the integration of Eq. (7) along the trajectory."

> "Since only the changes due to the velocity Verlet steps are accumulated into H̃, this quantity is
> almost constant. On the other hand, H has the proper distribution." (Fig. 1 caption)

**Mapping to P5 (the logbook / state doctrine).** `H̃` is exactly a **logbook quantity**: it is not
needed by the flow map (the dynamics runs without it) but it is the *running accumulator of injected
energy* that lets you audit the integrator. IT's P5 litmus ("what the flow map needs" → state record;
everything else → cache or logbook) has a clean instance here: the OU forcing's internal state is
state-record (flow map needs it, §2.1 analogue); a running "energy injected by forcing" accumulator is
logbook (audit only). CSVR is the primary precedent for **both** categories coexisting in one thermostat.

---

## 4. Leimkuhler–Matthews BAOAB — the splitting alphabet (P1, P4)

Leimkuhler & Matthews, *Molecular Dynamics* (Springer, 2015) and "Rational construction of stochastic
numerical methods for molecular sampling" (*Appl. Math. Res. eXpress* 2013); the operator definitions
below are quoted from Leimkuhler, Matthews & collaborators, "…" (`arXiv:1711.01310`, the PAdL/melts
review) which restates the BAOAB construction verbatim.

### 4.1 The vector field is split into named, exactly-solvable letters (P1)

**CONFIRMED (seeded lead).** The Langevin vector field is split three ways (their Eq. 3):

> "d[q; p] = [m⁻¹p; 0]dt (**A**) + [0; −∇_q U]dt (**B**) + [0; −γ(p − mu)dt + σm^{1/2}dW] (**O**)
> … in such a way that each piece can be solved 'exactly'."

The **A** letter is the position drift (a translation), **B** the momentum kick from the force, **O** the
Ornstein–Uhlenbeck friction+noise. The `O`-part is solved **exactly** by an exponential update (Eq. 5):

> "p(t) = mu + (p(0) − mu) e^{−γt} + σ √( m(1 − e^{−2γt}) / 2γ ) R," R i.i.d. standard normal.

The scheme is then a **string of letters** — a symmetric Trotter product (Eq. 6):

> "e^{hL̂_BAOAB} = e^{(h/2)L_B} e^{(h/2)L_A} e^{hL_O} e^{(h/2)L_A} e^{(h/2)L_B}."

> "only one force calculation is required at each step for BAOAB."

### 4.2 The taxonomy discipline (P1, P4)

The whole family is named by its letter string: `BAOAB`, `ABOBA`, `OBABO`, `BAOA`, etc. — each a
different ordering of the *same* exactly-solvable subflows. This is a **taxonomy discipline**: a scheme's
identity is its factorization word, and every letter is a self-contained, independently-tested subflow
that owns exactly its own coordinates.

**Mapping to IT (P1, P4).** IT's `O` letter already exists — it *is* the integrating factor
`exp(-νκ²dt)`, the exact linear subflow (Leimkuhler–Matthews' `O` is `exp(-γt)` on momenta; IT's is
`exp(-νκ²dt)` on modes; both are the exact solution of the linear/damping part). The lesson is
structural: **IT's Propagator should be expressible as a word over named subflows**
(`factor`/`nonlinear-stage`/`forcing-source`/`project`), each owning its scratch (P4), and a new scheme
should be a new word, not a new hand-assembled `step!`. This is the strongest positive template for P1:
BAOAB shows a whole zoo of integrators as re-orderings of four exact/approximate subflows, with the RHS
never re-assembled — the state each letter reads and writes is fixed by the letter, so the scalar-bug
class (§1.2) cannot arise.

---

## 5. SHAKE / RATTLE — constraint projection (P1, P4, P5)

Ryckaert, Ciccotti, Berendsen, *J. Comput. Phys.* **23**, 327 (1977) (SHAKE); Andersen, "Rattle: a
'velocity' version of the SHAKE algorithm," *J. Comput. Phys.* **52**, 24–34 (1983). Text extracted from
a scan of Andersen 1983 (`matsci.org/uploads/short-url/nKcViXGFFSVgEDvCfYhFnR0C2kS.pdf`).

### 5.1 The constraint manifold and its tangent-space (velocity) condition (P1)

The holonomic constraint defines a manifold; RATTLE enforces both the position constraint **and its time
derivative** — the velocity condition that keeps the velocity in the manifold's tangent space (their Eqs.
A1–A2):

> "the constraint is expressed as σ_{ij}(r) = |rᵢ − rⱼ|² − d_{ij}² = 0." (Eq. A1)

> "The time derivatives of the constraint equations give constraints on the velocities, namely
> [ṙᵢ(t) − ṙⱼ(t)] · [rᵢ(t) − rⱼ(t)] = 0." (Eq. A2)

The correction is a Lagrange-multiplier force **orthogonal to the manifold**, chosen so the corrected
velocity is perpendicular to the bond vector (from Appendix C):

> "We want to choose k so that ṙ − ṙ' is perpendicular to r_a(t + h)."

This is a **projection onto the tangent space of the constraint manifold** — algebraic, not differential:
it is *not* a term in `iL`; it is applied *after* the unconstrained update.

### 5.2 The two-stage structure: unconstrained update, then project (P1)

RATTLE deliberately uses **different multipliers for the position stage and the velocity stage** (their
§II):

> "There is no need that the same approximation for g be used in the position equation as in the velocity
> equation." — position stage (Eq. 2.7) projects `r(t+h)` onto σ = 0; a **separate** velocity stage (Eq.
> 2.8) projects `ṙ(t+h)` onto σ̇ = 0.

**Mapping to P1 / IT's Leray projection and `apply_forcing!`.** IT's incompressibility is a constraint of
exactly this kind: the velocity must lie on the divergence-free manifold, i.e. `κ · û = 0` in spectral
representation, enforced by the **Leray projection** `ℙ = I − κκ/κ²` — the spectral image of RATTLE's
"velocity perpendicular to the constraint gradient." And IT's `apply_forcing!` (the post-step
`BandRescaling`) is structurally a **manifold projection applied after the unconstrained stage arithmetic
finishes** — the same "unconstrained update, then project" two-phase pattern RATTLE codifies. The theory
says a post-step projection is a *legitimate and distinct* mechanism (it is genuinely not a generator
term), which **validates IT keeping `apply_forcing!` as a separate hook** rather than trying to fold every
forcing into the RHS. See §6 for why this is the *one* hook the theory says is irreducibly separate.

---

## 6. What the theory predicts for IT's four-hook Forcing protocol (P4, P1)

This is the deliverable's central question: **is four the right number, and is the hook set exactly what
the theory predicts?** Assemble the taxonomy from §§1–5. Every thermostat/constraint class lands in one
of four architectural roles:

| Role | MD-theory mechanism | Primary source | IT hook |
|---|---|---|---|
| (a) **State extension** — a Markovian surrogate variable with its own EOM, in the restart record | NHC variables `{η_j, p_{η_j}}` (Eq. 1–2); CSVR auxiliary `K`-SDE (Eq. 7) | MTTK96; Bussi 2007 | `prepare_forcing!` (advance OU internal state) |
| (b) **Generator term (nonlinear / additive correction)** — an additive piece of `iL` evaluated at a stage | rRESPA `F_s`/`F_l ∂/∂p` (Eq. 3.4); BAOAB `B` = force kick | TBM92; Leimkuhler–Matthews | `add_forcing_source!` (additive per-stage source) |
| (c) **Exact linear subflow** — a stiff/linear piece folded into an exactly-solved factor | BAOAB `O` = `exp(-γt)` (Eq. 5); rRESPA outer `F_l` factor; the interaction picture | Leimkuhler–Matthews; TBM92 | `set_forcing_rate!` (linear rate folded into integrating factor) |
| (d) **Post-step projection** — an algebraic projection onto a manifold, applied after the update | RATTLE velocity projection (Eq. A2); CSVR/Berendsen rescale | Andersen 1983; Bussi 2007 | `apply_forcing!` (post-step projection/rescale) |

**So four is the theoretically correct *number of roles* — the taxonomy has exactly four cells, and IT's
four hooks occupy exactly those four cells.** This is a strong, verified endorsement of the hook *set*:
IT independently rediscovered the (state-extension / generator-term / exact-subflow / projection) quartet
that the MD canon converged on across TBM92, MTTK96, Bussi, and RATTLE.

**But the theory also flags a subtlety IT should be explicit about.** In the rigorous formalism, roles
(a), (b), (c) are **not four independent mechanisms** — they are *views of one generator term*, split by
what is exactly solvable:

- A thermostat is **one** object. It (a) extends the phase space, which (b) adds a term `iL_thermo` to
  the generator, which (c) becomes a propagator letter `exp(iL_thermo · h)`. MTTK96's `iL_NHC = iL − iL₁
  − iL₂` is literally "the generator term of the state extension, realized as a propagator letter." (a),
  (b), (c) are the *same* thermostat seen as coordinates, as an operator term, and as a factor.
- rRESPA (§1.4) shows (b) and (c) are the **same force** at two resolutions: `F_l` folded into the outer
  exact factor, `F_s` added as inner stage corrections — *one* generator term, partitioned by stiffness.

The consequence for IT: `set_forcing_rate!` (c) and `add_forcing_source!` (b) are, in the theory, **two
representations of one generator term** — the linear-in-field part routed to the exact factor, the
nonlinear/remainder routed to a stage source. That is the rRESPA `F_l`/`F_s` split, and it is *correct*
to expose both — but IT should document that they are **not two forcings, they are two channels of one
forcing's generator term**, and a single strategy legitimately uses both (as `StochasticOU` does: it
`prepare_forcing!`-advances its state and `add_forcing_source!`-injects it — roles (a)+(b) — while a
future exact-OU upgrade would move the linear damping into role (c)). The genuinely *separate* mechanism
is (d): a projection is **not** a generator term (RATTLE's projection is algebraic, applied after the
flow), so `apply_forcing!` is the one hook that is irreducibly its own thing.

**Refinement the theory suggests (not a defect, a sharpening).** The four hooks are better understood as
**one lifecycle** — advance-state (a) → contribute-generator-term, exact-part (c) and remainder-part (b)
→ project (d) — than as four peer callbacks. This is IT's own P5 "Gauss–Seidel sweep per step" read of
the skew-product tower, and it matches the Trotter *ordering* discipline: the letters have a fixed order
(`prepare` before the stages that consume the prepared state; `project` after). A forcing that implements
(b) but reads state that only (a) produces has an *ordering* contract, exactly as a Trotter word fixes
which intermediate each letter reads (§1.2). Making that ordering explicit in the protocol is the
forcing-side analogue of the P1 fix.

---

## 7. Backward-error / shadow-Hamiltonian theory — why the exact factor is exact (P1, P5)

Hairer, Lubich, Wanner, *Geometric Numerical Integration: Structure-Preserving Algorithms for ODEs*
(Springer Series in Comp. Math. 31, 2nd ed. 2006). Verified via the SIAM/Acta-Numerica secondary
literature (I did not obtain the book's page text; the following is the standard, widely-restated result,
marked accordingly).

**CONFIRMED (as canonical result, secondary sources).** A symmetric/symplectic integrator's discrete
trajectory lies *exactly* on the flow of a **modified ("shadow") Hamiltonian** `H̃ = H + O(h^p)`, given
by an asymptotic series in the step size; this is why such integrators show **no secular energy drift**.
From the backward-error literature:

> "the discrete time steps of a k-th order symmetric symplectic integrator exactly fall onto the flow for
> some modified Hamiltonian, given by an even, asymptotic expansion with respect to the integrator step
> size" (restated across the HLW-derived literature; e.g. the modified-energy analyses).

**Mapping to IT (P1, P5).** Two consequences:

1. **IT's integrating factor is the *one* piece that is exact to machine precision, not just to the
   scheme's order.** `exp(-νκ²dt)` is the closed-form solution of the linear subflow — it carries *no*
   shadow-Hamiltonian error. Everything else (the nonlinear stage arithmetic) carries the modified-energy
   error of the RK scheme. This is worth stating in the Propagator docs: the split is
   `exact-linear-subflow ∘ order-p-nonlinear-correction`, and only the correction has backward error.
   This is the theoretical content of IT's "the integrating factor is a spectral multiplier, say so
   briefly rather than forcing a physical formula" — it is an *exact* subflow, not an approximation.

2. **The conserved quantity is the extended/shadow one, not the naive one.** MTTK96's `H'` and CSVR's
   `H̃` are both instances: the honest invariant of a forced/thermostatted run is the *extended* energy
   (physical energy + injected-work bookkeeping), and backward-error theory says even *that* is only
   conserved up to the scheme's shadow error. IT's P5 doctrine (state record vs cache vs logbook) is the
   architectural expression of this: the logbook should carry the injected-energy accumulator so the run
   is auditable the way MTTK96/CSVR make theirs auditable.

---

## Transferable ideas for IT (ranked)

1. **The primitive is a factorization into named subflows, not generator-vs-propagator (P1).** TBM92 §1.2
   and BAOAB §4: the scheme is a *word* over exactly/approximately-solved subflows; the RHS is never
   re-assembled inside `step!` — it is presented pre-partitioned. IT's `ResolvedGenerator` should expose
   the *partition* (exact-factor piece, nonlinear-stage piece, forcing channels), and a scheme should be
   letter arithmetic over that partition. This is the deepest lesson and directly targets the scalar bug.

2. **Four hooks = the four theoretical roles, and the mapping is exact (P4).** §6's table: state-extension
   (`prepare_forcing!`), generator-term-remainder (`add_forcing_source!`), exact-linear-subflow
   (`set_forcing_rate!`), post-step-projection (`apply_forcing!`) are precisely the (a/b/c/d) cells of the
   MTTK96 + rRESPA + RATTLE + CSVR taxonomy. Keep four — but document that (b)+(c) are two channels of one
   generator term (rRESPA `F_s`/`F_l`) and (d) is the one irreducibly separate mechanism (an algebraic
   projection, not a generator term).

3. **Deterministic clamp-rescale is Berendsen; it has no conserved quantity and kills fluctuations (P5).**
   CSVR §3.2, verbatim: "reduces to that of … Berendsen … no conserved quantity … not associated to a
   well defined [ensemble]." Document this fitness caveat on `BandRescaling`; the sanctioned upgrade is a
   stochastic rescale (CSVR) plus an **effective-energy accumulator** (Eq. 15) in the logbook.

4. **Extended/stochastic-forcing internal state belongs in the restart record (P5).** MTTK96 Eq. 1–2:
   thermostat variables are phase-space coordinates with their own EOM; you cannot restart without them.
   IT's OU-forcing state is the same — a Markovian surrogate slot in the state record, not a cache. The
   flow-map litmus (P5) gives the identical verdict.

5. **The exact factor is the only machine-exact piece; everything else carries shadow-Hamiltonian error
   (P1/P5).** HLW §7. Say in the Propagator docs that the integrating factor is exact and the RK
   correction is order-`p`; carry an injected-energy accumulator in the logbook so a forced run is
   auditable (the MTTK96 `H'` / CSVR `H̃` pattern).

6. **The outer, slow, expensive piece is factored outside and touched once per macro-step (P4).** rRESPA
   Eq. 3.7: `F_l` outside, `F_s`-Verlet inner loop, "no more work than the nonreversible RESPA." IT's
   low-mode/expensive forcing should be an outer factor; forcings own their own scratch (MTTK96: the
   thermostat never touches the Verlet registers) — the primary-source endorsement of P4.

7. **A scheme's identity is its factorization word — build a taxonomy, not a pile of `step!`s (P1).**
   BAOAB/ABOBA/OBABO §4.2. IT's Propagator zoo (RKW3, etc.) should read as words over
   `{factor, nonlinear-stage, forcing-source, project}`, so adding a scheme is choosing a word.

---

## Where IT's proposal differs from this beat's practice — risk or justified deviation?

- **IT splits Forcing into four peer hooks; the theory sees one lifecycle with a fixed order.** Roles
  (a)/(b)/(c) are three views of one generator term (MTTK96 `iL_NHC = iL − iL₁ − iL₂`); the theory would
  make the *ordering* (prepare → contribute → project) part of the protocol. **Risk: mild.** IT's flat
  four-hook interface is fine so long as the ordering contract is documented (a `prepare_forcing!` that
  produces state a later `add_forcing_source!` consumes has the same "which intermediate does this letter
  read" contract as a Trotter word). Left implicit, it is the forcing-side twin of the P1 scalar bug.
  **Recommendation:** state the lifecycle order in `AbstractForcing`'s docstring; note that (b)+(c) are
  one generator term at two resolutions.

- **IT's `BandRescaling` is a deterministic clamp; the theory says that is Berendsen and is
  ensemble-broken.** **Risk: real but bounded — for warm-up/spin-up it is defensible; as a stationary
  sampler it is not.** Justified *iff* documented as a spin-up/energy-holding tool, not a physically
  faithful stationary forcing (IT's warm-up research already prefers a Bassenne-style controller and
  "never clamp what you measure"). CSVR is the drop-in upgrade if faithful fluctuations are wanted.

- **IT folds only the *viscous* term into the exact factor; MD theory folds *any* linear/stiff piece
  (including linear forcing, thermostat damping).** IT's `set_forcing_rate!` already generalizes this
  (linear forcing → `A(κ) − D|κ|²` in the factor), which is **exactly** the rRESPA/interaction-picture
  move. **Not a deviation — a correct generalization**, verified against rRESPA Eq. 3.4–3.7 and BAOAB's
  `O`-letter. The only gap: a future *exact-OU* forcing would move OU damping from role (a)/(b) into role
  (c), which the current hook set already supports.

- **IT proposes a `finalize!` in the Generator protocol (P1); the theory has no separate "finalize"** —
  the closest analogue is the *outer* half-factor of a symmetric Trotter word (`exp(iL₁ Δt/2)` at the
  end, MTTK96 Eq. 26) and the RATTLE velocity-projection second stage. **Not a risk:** `finalize!` is the
  natural home for the trailing half-step / post-step projection that the symmetric factorization *does*
  have; the theory endorses a trailing subflow, it just doesn't call it "finalize."

- **IT treats particles as a separate fiber with their own accuracy contract (P5); MD theory would call
  this an operator-split subsystem in the skew-product.** Consistent with the tracer literature (TurTLE
  is AB4 operator-split for particles, per IT's own memory) and with MTTK96's independent thermostat
  chains. **Justified deviation / non-deviation:** the skew-product tower (time → noise → fields →
  particles) advanced by a Gauss–Seidel sweep *is* the extended-system + Trotter picture applied to a
  hierarchy; IT's reading is the correct generalization, not a departure.

**Net:** IT's architecture is unusually close to what the MD-theory canon prescribes. The Forcing hook
*count and roles* are exactly right (a rediscovery of the four-cell taxonomy); the two live cautions are
(1) make the forcing lifecycle *order* explicit, and (2) document `BandRescaling` as a Berendsen-class
deterministic clamp with the CSVR upgrade path. The P1 seam is precisely the "present the RHS
pre-partitioned into named subflows" discipline that TBM92/BAOAB codify.

---

## Sources

Primary (text extracted from the paper PDF and quoted above):

- M. Tuckerman, B. J. Berne, G. J. Martyna, "Reversible multiple time scale molecular dynamics," *J.
  Chem. Phys.* **97**(3), 1990–2001 (1992). doi:10.1063/1.463137. PDF:
  `columbia.edu/cu/chemistry/groups/berne/papers/jcp_97_1990_1992.pdf` (Berne group scan). Eqs. 2.1–2.6
  (Liouville/Trotter), 2.14–2.22 (velocity & position Verlet), 3.1–3.8 (rRESPA).
- G. J. Martyna, M. E. Tuckerman, D. J. Tobias, M. L. Klein, "Explicit reversible integrators for extended
  systems dynamics," *Mol. Phys.* **87**(5), 1117–1157 (1996). doi:10.1080/00268979600100761. PDF:
  `aiichironakano.github.io/phys516/Martyna-Integrator-MolPhys96.pdf`. Eqs. 1–2 (NHC EOM & `H'`), 24–29
  (Liouville split & Trotter factorization); §4 velocity-scaling accumulation.
- G. Bussi, D. Donadio, M. Parrinello, "Canonical sampling through velocity rescaling," *J. Chem. Phys.*
  **126**, 014101 (2007). arXiv:0803.4060. Eqs. 4–7 (rescale SDE, Berendsen limit), Eq. 15 & Fig. 1
  (effective energy `H̃`); §I (Berendsen has no conserved quantity).
- H. C. Andersen, "Rattle: a 'velocity' version of the SHAKE algorithm for molecular dynamics
  calculations," *J. Comput. Phys.* **52**, 24–34 (1983). PDF:
  `matsci.org/uploads/short-url/nKcViXGFFSVgEDvCfYhFnR0C2kS.pdf`. Eqs. 2.5–2.8 (two-stage
  position/velocity constraint), A1–A2 (constraint & velocity-tangent condition), App. C (velocity ⟂
  bond vector). J.-P. Ryckaert, G. Ciccotti, H. J. C. Berendsen, *J. Comput. Phys.* **23**, 327 (1977)
  (SHAKE, cited by Andersen 1983).
- B. Leimkuhler, C. Matthews, "Rational construction of stochastic numerical methods for molecular
  sampling," *Appl. Math. Res. eXpress* 2013, 34–56; and *Molecular Dynamics* (Springer, 2015). BAOAB
  operator definitions quoted from the restatement in arXiv:1711.01310 (Leimkuhler–Matthews et al., PAdL /
  polymer-melts review), Eqs. 3–6 (A/B/O split, exact `O`, BAOAB word).
- E. Hairer, C. Lubich, G. Wanner, *Geometric Numerical Integration* (Springer, 2nd ed. 2006). Backward-
  error / modified-(shadow-)Hamiltonian result stated from the canonical secondary literature (SIAM J.
  Numer. Anal. backward-error analysis; Acta Numerica 2003 Störmer–Verlet article) — **not** verified
  against the book's page text (marked in §7).

IT source cross-checks (verified against the repository):

- `src/Forcing.jl` — the four hooks confirmed verbatim: `set_forcing_rate!` (lines 4, 22, 214, 244 —
  "a per-mode rate A(k) … folded into the integrating factor"), `add_forcing_source!` (lines 25, 111,
  322), `prepare_forcing!` (lines 24, 101, 302), `apply_forcing!` (lines 8, 23, 176 — `BandRescaling`).
  `StochasticOU` uses `prepare_forcing!` + `add_forcing_source!` (roles a+b); `BandRescaling` uses
  `apply_forcing!` (role d); `Linear`/`ConstantPower` use `set_forcing_rate!` (role c).

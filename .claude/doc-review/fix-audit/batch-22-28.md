# Fix audit — batch 22–28

## 22 — Notation page: τ row points to "the integrating factor's row below", but that row is above

**Owner's verbatim ask (via panel finding, resolution_hint):** `"in the integrating factor's row above"`.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `docs/src/notation.md:93` now reads: "in the integrating-factor row of *Spectral
representation and operators* above, ``\tau`` is a Runge–Kutta stage substep". The page's section
order confirms the direction is now correct: "Spectral representation and operators" is at line 54
(carrying the ``\mathcal{E}(\boldsymbol{\kappa})`` row) and "Derived scales" (the τ row) is at line 81
— strictly below, so "above" is now the true direction. The fix also names the section explicitly
("of *Spectral representation and operators*"), which is stronger than the bare directional word the
finding flagged and removes ambiguity about which row is meant. A corpus-wide check
(`grep -rn "row below\|row above" docs/src src/*.jl`) turns up only this row and one unrelated,
correctly-directed use in `observables_cache.md:365` ("the row above", genuinely above) — no sibling
instance of the same misdirection survives.

---

## 23 — Obukhov–Corrsin "no factor-of-two conversion" claim argues from the dissipation convention alone

**Owner's verbatim ask (resolution_hint):** "verify Sreenivasan 1996's E_θ normalization; if
consistent, extend the parenthetical to certify both halves of the convention."

**VERDICT: INSERTED**

**Which question failed:** STRATEGY (2a, fix-by-insertion).

**Evidence:** `src/phenomenology/Spectra.jl` (diff vs 0b3d58c) still asserts, unqualified, that the
constant "pairs directly with this package's full-variance ``\varepsilon_\varphi``
(`scalar_dissipation`) with no factor-of-two conversion" — the exact clause the finding flagged is
untouched — and now has a parenthetical appended beside it: "(the constant is invariant so long as a
source scales its scalar spectrum and its dissipation together — both double or both halve — so only
a mixed-convention quote would shift it by two)." This restates the *general logical condition* under
which the claim would fail (which the finding's own description already spelled out — "the constant
is invariant only when the spectrum normalization and the dissipation convention flip together") but
never states whether Sreenivasan (1996)'s actual ``E_\theta`` convention satisfies that condition. No
source-side check was performed: `git log -p` over the touched range shows only this one clause change,
with no accompanying verification note, no citation of Sreenivasan's normalization, and no update to
the ``valid_Re_\lambda`` / provenance record. The finding's severity/confidence were minor/low, but the
resolution_hint was explicit and binary (verify, then extend if consistent) — a hedge that flags the
general risk without resolving it, appended beside the original unqualified claim, is exactly the
fix-by-insertion pattern: the flagged assertion still stands, with qualifying prose added around it
rather than the assertion being corrected, softened to reflect actual uncertainty, or verified true.

---

## 24 — Scalar mean conservation asserted exact and only-to-roundoff in one docstring

**Owner's verbatim ask:** the docstring must not assert both "conserves the scalar mean exactly ...
the divergence has no κ=0 component" and "holds discretely only to roundoff" in the same docstring.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Generator.jl` (diff): the false clause is deleted, not merely amended alongside —
"The advective term's ``\kappa = 0`` mode is zeroed exactly (``\langle\nabla\cdot(\boldsymbol{u}\varphi)\rangle
= 0`` holds discretely only to roundoff, and the mean of ``\varphi`` has no diffusive damping)" became
"The advective term's ``\kappa = 0`` mode is zero exactly by construction — the divergence multiplier
``\mathrm{i}\boldsymbol{\kappa}`` vanishes identically at ``\boldsymbol{\kappa} = \boldsymbol{0}`` —
and the assembly pins it anyway, for uniformity with the velocity route, whose product mean is only
roundoff-small; the mean of ``\varphi`` has no diffusive damping." This is now internally consistent
with the earlier paragraph in the same docstring ("The conservative form conserves the scalar mean
exactly: the divergence has no ``\boldsymbol{\kappa}=\boldsymbol{0}`` component", `Generator.jl:645`,
unchanged and correct) and with `observables_cache.md:273`'s independent claim. The corrected physics
is verifiable against the code: the divergence operator ``\mathrm{i}\boldsymbol{\kappa}\cdot(\cdot)``
is identically zero at ``\boldsymbol{\kappa}=0`` regardless of floating-point roundoff — this is exact
by construction, unlike the velocity route's rotational-form product mean, which genuinely is only
roundoff-small (a real asymmetry between the two routes, now correctly attributed). No stray instance
of the retracted "only to roundoff" scalar-mean claim remains in the corpus.

---

## 25 — "Holds the present instant only" contradicted by the Lagrangian sample history

**Owner's verbatim ask:** resolve the contradiction between the blanket "present instant only, no
history" claim and the cache's documented `velocity_at_particles_history`.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** Both flagged locations were corrected to name the exception rather than deny it.
`src/SimulationRun.jl:25`: "It holds the present instant — plus the one bounded look-back a multistep
particle scheme needs, the cache's Lagrangian sample history — and past instants otherwise exist only
in what an observation recorded as the run advanced." `docs/ARCHITECTURE.md:474`: "A `Simulation`
value bundles what one iteration advances and reads — the present instant (the one bounded look-back
is the cache's Lagrangian sample history, which a multistep particle scheme needs): ...". Both surfaces
the finding cited now state the same qualified claim; a corpus grep for "present instant" / "no
history" surfaces no other absolute (unqualified) claim of the kind flagged. This is a genuine
correction (the false universal replaced by an accurate, scoped one), not an appended disclaimer next
to a false claim left standing.

---

## 26 — "The declaration is measured at construction, not trusted" — an unfalsifiable check

**Owner's verbatim ask:** state plainly what the construction-time guard can and cannot verify
(it cannot refute a false `uses_steady_linear_rate = true` declaration; it only catches the reverse
misdeclaration).

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `src/Forcing.jl:124-127` (diff vs 0b3d58c): "The declaration is measured at construction,
not trusted." became "The declaration is cross-checked when the generator is built, not trusted: a
strategy that implements `set_forcing_rate!` without declaring `uses_steady_linear_rate` is refused
with an `ArgumentError`. Steadiness itself remains the author's promise — no construction-time check
can watch a rate over time." This directly states the scope the finding demanded: the check catches
only the one-directional misdeclaration (hook present, trait absent), and explicitly disclaims any
capacity to verify temporal steadiness — matching the finding's own diagnosis almost verbatim ("the
only guard the docs describe catches the reverse misdeclaration ... no construction-time inspection
can measure [steadiness]"). The rewrite replaces the overclaiming sentence in place (not appended
beside it); a corpus grep confirms this is the sole instance of the phrase.

---

## 27 — The hand-run loop has no documented way to advance the particles epoch without destroying the history

**Owner's verbatim ask:** a legitimate hand-driven `advect!` must be able to advance the particles
epoch without discarding the Lagrangian sample history the multistep scheme needs — the finding
diagnosed both the `AdamsBashforth` case (cannot advance epoch and keep history) and the frozen-counter
case (no epoch verb on the public `advect!` path).

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** This was fixed at the code level, not by reprose. `src/Particles.jl`:
`advect!(::Heun, ...)` now ends with `advance_particles_epoch!(buffers.cache)` (comment: "The push
announces itself (decision 76): the positions changed, so the particles counter moves ... This keeps
the two-epoch guard live on a hand-run loop, not only under `advance!`"). `advect!(::AdamsBashforth{K},
...)` calls `advance_particles_epoch!(cache)` directly on its mature branch and delegates to
`advect!(Heun(), ...)` — which now self-advances — on its bootstrap branch (comment: "the bootstrap
branch announced through Heun's push"); its trailing history-shift loop runs unconditionally after
either branch, so the sample history is preserved in the same call that advances the epoch. This
matches the commit log (`2d981f87`, "T8, option (a)"): "`advect!` now advances the particles epoch
itself at the end of every push ... The run layer's separate call is gone." Checked
`src/SimulationRun.jl` / `src/Cache.jl`: no redundant separate epoch-advance call remains in the run
layer's tracer-advance path; `particles_modified!` still owns the out-of-band (history-clearing)
announcement, distinct from the in-push announcement. The docstring for `advect!` (`Particles.jl`
~567-569) states the new behavior plainly: "Every push also advances the cache's particles counter —
the push announces itself ... A hand-run loop therefore gets the same staleness protection as a run."
Both consequences the finding named are resolved: the epoch now advances on every `advect!` call
regardless of scheme, and the history is not discarded by that advance.

---

## 28 — Who makes the seeding deposit — "when the cache is built" vs the `Simulation` constructor

**Owner's verbatim ask:** correct the design page's claim that "a deposit seeding the initial state is
made when the cache is built" (the cache constructor takes no state and cannot deposit) to attribute
the seeding deposit to the `Simulation` constructor, consistent with the API docs.

**VERDICT: HONORED**

**Which question failed:** none.

**Evidence:** `docs/src/observables_cache.md:148-149` (diff vs 0b3d58c): "the first because a deposit
seeding the initial state is made when the cache is built" became "the first because the `Simulation`
constructor makes a deposit seeding the initial state as it builds the run" — now consistent with
`api/Propagator.md`'s "the `Simulation` constructor makes the seeding deposits" and with the
`ObservablesCache(domain; scalar = false, ...)` signature the finding cites as proof the cache alone
cannot hold the seed. A corpus grep for "when the cache is built" / "cache is built" turns up two other
hits, both unrelated to the seeding-deposit claim (`Observables.jl:200` and
`observables_cache.md:120` describe the fixed *deposit schedule*, not who performs the seed; `git log`
confirms these were untouched and remain correct as written) — no sibling instance of the misattributed
seeding claim survives.

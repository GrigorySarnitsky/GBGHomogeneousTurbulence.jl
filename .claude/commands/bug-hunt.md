# /bug-hunt — the CODE instrument

`/check-docs` and `/check-consistency` audit **prose**: the first deterministically against the
source, the second by reading the rendered site as a physicist would. Neither one asks whether the
code is *correct*. A docstring can be flawless about a function that returns the wrong number, and
both instruments will pass it.

`/bug-hunt` is the third instrument and it audits the **code**. Fan a panel of lanes across `src/`,
each with a distinct defect lens, and report what would actually go wrong.

## The one design rule

> **A static claim about code is a hypothesis. The only admissible evidence is a program that fails.**

Everything below follows from that sentence, and it is not a stylistic preference — it is the
correction for a failure mode this project has now measured in two other instruments. An agent
reading code and reporting what "looks wrong" produces fluent, confident, unfalsifiable prose. In a
documentation instrument that costs a wasted read. Here it costs a **fix pass on working code**, which
is strictly worse than the bug it imagined: the tree gets edited, the suite still passes, and nobody
can tell afterwards whether anything was ever wrong.

So the hunt is **static** and the confirmation is **dynamic**. Every candidate must be reduced to a
**witness** — a self-contained `@testset` that asserts the CORRECT behaviour and is therefore observed
to FAIL on the current tree.

* A candidate whose witness **passes** is not a bug. It is discarded, however good the argument was.
* A candidate for which **no witness can be written** is not actionable. It is reported separately as
  a latent hazard and is not fixed.
* A witness that **fails** *is* the finding. It is also — unchanged — the regression test the fix must
  flip, and the file that gets promoted into `test/` when the fix lands.

This inverts the usual economics of a review: the expensive step is *proving* the defect, not
describing it, and nothing reaches the fixer that has not already been demonstrated. It also means the
instrument verifies its own fixes **without an agent**: `witnesses.jl pass` is a program exiting
non-zero, not an opinion.

## The two classes that escape the witness rule

They are handled explicitly rather than smuggled through as if they had been proven.

**Architecture / maintainability** — duplication, divergent copies of one rule, a leaked abstraction, a
`CLAUDE.md` invariant broken in code. No test can fail on these. Their evidence standard is **two or
more quoted locations a reader can diff**, plus the stated consequence: what a maintainer must change
in both places, and what breaks if they change only one. A single site with no second location is not
a finding, and "it is untidy" is not a consequence. These are verified after the fix by
`verify-fixes.js`, whose job is to catch the **RELOCATED** verdict — a duplicate moved to a new file
reads exactly like a fix in a diff and exactly like a defect in the tree.

**API semantics** — any claim about what `Base` or a dependency does. This is precisely where a model
is confidently wrong from memory, so the standard is **both**: the official documentation fetched and
quoted **with its URL** (`docs.julialang.org`, or the package's own docs), *and* a witness that runs.
Memory is not evidence and is not accepted as any part of the chain.

## The lanes

Ten: **two free** and **eight by class**. The split matters more than the classes do.

The eight class lanes are cut by defect class rather than by file, because a class is what an agent
can hold in its head and a file is not — a per-file split makes every cross-module defect invisible
to everyone at once.

But a list of classes is a *hypothesis about where bugs live*, and a defect outside all eight is
invisible to all eight **by construction**, with the run still reporting `complete: true`. That is the
"never narrow a reviewer's brief" failure, rebuilt one level down. So two lanes get **no class list at
all** — only a starting point, so that two free readers do not open the same file first. Their brief
is to find what is wrong with the code, and they are told in as many words that if they catch
themselves working a checklist they should go back to reading.

| Lane | Hunts |
|------|-------|
| `free-hot-path` | **no class list.** Reads one complete iteration end to end from `advance!`, following every call into whatever module it lands in |
| `free-modules` | **no class list.** Picks the two or three files it judges most likely to be wrong and reads them whole |
| `aliasing-and-mutation` | shared buffers, a caller's array written without contract, a missing (or gratuitous) copy, `!` functions writing a non-leading argument |
| `numerics-and-types` | `Float32`/`Float64` genericity, untyped literals promoting, a normalization applied twice or never, a tolerance that is absolute where it must be relative, division by a possible zero |
| `api-contracts` | calls whose correctness rests on a Base or PF/SS semantic detail — always filed `api-semantics`, never trusted from memory |
| `gpu-and-hot-loop` | scalar indexing of a device array, an allocation inside `step!`/`deposit!`/`advect!`, a host–device sync in the per-step path |
| `edge-cases` | the corners of the configuration space: zero tracers, `NoForcing`, an empty band, odd or tiny `N`, a non-2π box, `Float32`, the first iteration |
| `state-machine` | the cache's epoch/staleness machine and the iteration's ordering contract — a slot read before it was set, an order depended on but not enforced |
| `architecture` | one rule implemented twice, a repeated literal, a near-duplicate pair, dead code, a leaked abstraction, an invariant broken in code |
| `test-critic` | what the suite does **not** pin: a documented guarantee with no test, a branch nothing exercises, a test that would pass if the function were wrong |

`test-critic` earns its place by producing witnessable candidates: "this claim is unpinned, and here is
the call that exposes it" is exactly a witness plan. The `Float32` genericity claim was found false on
three consecutive documentation rounds — each fix verified only against the functions that round's
finding happened to name — and was finally killed by pinning the *claim* over every observable. That
is this lane's whole thesis.

## Cost mode

**Economy is the default.** The **class lanes** run cheap (Sonnet); the **two free lanes are anchors**
and stay at session strength in every mode, exactly as `/check-consistency` anchors its two physics
hats. The reason is the same one: a cheap lane's *false positive* is caught downstream by the
reproducer, but its *false negative* has no verifier anywhere — a bug nobody raises is never
reproduced — and the free lanes are both the ones doing open-ended judgement (where a cheap model is
weakest) and the ones covering what the class list omits. Pass `strength: "full"` to lift the class
lanes too.

**On the reproduction stage.** It also runs at session strength, but the argument for that is weaker
than it first appears and is recorded honestly here: `witnesses.jl fail` re-runs every witness
mechanically, so a reproducer that *misreports* a result is already caught by a program. What the
gate cannot catch is a reproducer that gives up too early (a false NOT-REPRODUCED) or one that writes
a witness asserting the wrong thing — and the second happened twice on round 1 **at full strength**.
If reproduction is ever economized, that is the exposure to weigh, not misreporting.

## Run it

```
Workflow({ scriptPath: ".claude/commands/bug-hunt/hunt.js",
           args: { repo: "$REPO", pile: "$REPO/.claude/bug-hunt", strength: "economy" } })
```

## Run the hunt ONCE; loop the VERIFIER

**The instrument runs once. What loops is the verification of that run's findings.** This is the same
bound `/check-docs` and `/check-consistency` carry: the panel runs once, `verify.js` adjudicates the
*banked* findings, and the loop is verify → fix → verify until closure plateaus. Neither re-runs
itself as a termination condition.

**This was got wrong here first, and the correction matters more than the original rule.** The closure
gate used to demand a follow-up hunt confirming *nothing new*. No sibling instrument does that, and it
cannot terminate while the code is being edited, because each round's fixes seed the next round's
findings — measured across five rounds: **20, 9, 17, 21, 17**. A rule that makes "finished"
permanently false is a bad rule, not a strict one. Worse, it licensed unbounded edits to *code*,
which is a different risk from unbounded edits to prose: the doc instruments only ever rewrite
documentation, while this one changes how the package computes.

So the finding set is **fixed by one hunt**, and every finding leaves it in one of three states:

| state | how it is established |
|---|---|
| **fixed** | its witness flips — `witnesses.jl pass`, a program, not a judgement |
| **refuted** | shown not to be a defect, with the measurement recorded at the site |
| **escalated** | a design decision, named to the user, its witness deliberately NOT filed into `test/` so nothing reads green over it |

A finding in none of those is a **dropped** finding, and `finished.py` fails on the arithmetic.

**Four verifiers, because the witness gate cannot cover everything:**

1. `witnesses.jl pass` — mechanical, covers every confirmed runtime and api-semantics finding.
2. `verify-fixes.js` — the architecture class, which has no witness by nature. It hunts the
   **RELOCATED** verdict: a duplicate moved to a new file reads as a fix in a diff and as a defect in
   the tree.
3. `dismissals.js` — **the findings that were never confirmed.** `NOT-REPRODUCED` and `NOT-A-DEFECT`
   are judgement calls that get *filed*, so nothing revisits them; under a one-hunt design a wrong
   dismissal is simply lost. Round 1 dismissed the `particle_velocities` two-epoch check as "correct
   on the current tree" — a **blocker** — and `_base_cfl`'s fallback as "sanctioned by the contract",
   also wrong. Both surfaced only because a later hunt happened to re-raise them, which under this
   design would not happen. It defaults to **UNSAFE**.

4. **`/audit-changes`** — **the edits themselves**, which no witness covers, and which is now a
   STANDALONE INSTRUMENT rather than a phase of this one. A witness exists only for a defect the hunt
   *found*, so a regression introduced by a *fix* is invisible to the gate: measured here, the witness
   set reported `NEWLY BROKEN = 0` while two regressions were live and confirmed by hand. The question
   it asks — was this change proportionate? — is orthogonal to how the edits arose, which is why it
   was lifted out: it applies equally to a `/check-docs` sweep, a `/check-consistency` fix round, or a
   change made by hand. Its lens set was settled by adversarial attack rather than by taste, and it
   carries its own disposition gate. See `.claude/commands/audit-changes.md`.

The verifier loop terminates because the finding set is finite. Run it until every finding is in one
of the three states above; that is the whole of "closed".

Then, in order:

```bash
# 1. Every confirmed witness must FAIL on the untouched tree. A witness that passes is a phantom
#    bug and the finding is withdrawn — this is the gate that keeps invented defects out.
julia --project .claude/commands/bug-hunt/witnesses.jl fail

# 2. …fix…  (main thread, full strength, never economized)

# 3. Every witness must now PASS. This is the fix verifier for the runtime and api-semantics
#    classes, and it is a program, not a reviewer.
julia --project .claude/commands/bug-hunt/witnesses.jl pass

# 4. The architecture class, which has no witness, is audited by agent — hunting RELOCATED.
Workflow({ scriptPath: ".claude/commands/bug-hunt/verify-fixes.js",
           args: { repo: "$REPO", findings: [...] } })

# 5. Promote every passing witness into test/ and run the suite.
julia --project -e 'using Pkg; Pkg.test()'

# 6. Audit the DISMISSALS — the findings the hunt did not confirm. Not optional: a filed
#    dismissal is never revisited, and two of round 1's were wrong (one a blocker).
Workflow({ scriptPath: ".claude/commands/bug-hunt/dismissals.js", args: { repo, dismissals: [...] } })

# 7. AUDIT THE EDITS — mandatory, and it is `/audit-changes`, a separate instrument. A witness
#    exists only for a defect the hunt FOUND, so a regression introduced by a FIX is invisible to
#    the gate. Run it over this hunt's diff and answer every serious finding; its own gate refuses
#    to close on an unanswered one, or on an audit that no longer describes the tree.
git diff <base>..HEAD -- src test docs > /tmp/changes.diff
Workflow({ scriptPath: ".claude/commands/audit-changes/audit.js", args: {...} })
python3 .claude/commands/audit-changes/gate.py

# 8. Ask whether the work is finished. Exit 0 means yes; non-zero names what is not.
python3 .claude/commands/bug-hunt/finished.py
```

## Discipline

- **Collect-only during the hunt.** The lanes never edit. A lane that "quietly fixes while it is here"
  destroys the before-state its own witness needs.
- **A witness asserts the RIGHT behaviour, never merely exhibits the wrong one.** The difference only
  shows up later: the first is a regression test, the second is a snapshot of a bug that will pass
  again the moment the bug returns in a different form.
- **Never weaken an assertion until it fails.** That proves persistence, not a defect. If the witness
  passes, the verdict is NOT-REPRODUCED and the candidate dies.
- **Witness filenames collide across rounds** — every round starts its numbering at `01-<lane>-01`,
  so a bulk copy into `test/regressions/` silently OVERWRITES an earlier round's regression test with
  a new, still-failing one. The earlier test is then gone and the suite fails for a reason that looks
  like the new fix. Promote by explicit path, never `cp witnesses/*.jl`, and prefix the round.
- **Promote a witness only AFTER its fix lands.** A witness is a *failing* program until then, so
  copying the whole directory into `test/regressions/` at the end of a round drags every still-open
  finding into the suite and turns it red — which looks like a broken fix and is really a broken
  promotion. Promote per finding, as each one closes.
- **A witness must locate files with `pkgdir`**, never by counting `..` hops. It is authored under
  `.claude/bug-hunt/witnesses/` and *promoted* into `test/regressions/`, so a path counted from its
  original depth resolves outside the repository the moment it moves — and the failure lands in the
  suite, not in the gate. Walking up to the first `Project.toml` is *also* wrong: `test/` carries one
  of its own, so the walk stops a level early.
- **A broken witness is evidence of nothing** — in *either* direction. `witnesses.jl` reports BROKEN
  separately from FAIL for exactly this reason: counting a load error as a proven bug is how a phantom
  gets promoted.
- **An empty run is never a success.** No witnesses found, no findings passed to the verifier, a dead
  lane — each exits non-zero or is logged as an anomaly with `complete: false`. Three separate
  instruments in this project have shipped a silent-success path; the tally is not to be read as a
  clean sweep while an anomaly stands.
- **Don't launder a finding as "by design."** Fix it, or escalate it to the user with the trade-off.
- **A flagged instance is a sample of a class.** Fix the class — and then *re-measure*, because a class
  claimed swept but not re-verified is an instance fix wearing a class's name.

## Output

- `.claude/bug-hunt/witnesses/*.jl` — the executable findings. Untracked while open; promoted into
  `test/` when their fix lands.
- The workflow's returned object — the per-lane tally, the confirmed findings, and `complete`.
- **Tracked** (the instrument, not its output): this file and `.claude/commands/bug-hunt/`.

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
```

## Discipline

- **Collect-only during the hunt.** The lanes never edit. A lane that "quietly fixes while it is here"
  destroys the before-state its own witness needs.
- **A witness asserts the RIGHT behaviour, never merely exhibits the wrong one.** The difference only
  shows up later: the first is a regression test, the second is a snapshot of a bug that will pass
  again the moment the bug returns in a different form.
- **Never weaken an assertion until it fails.** That proves persistence, not a defect. If the witness
  passes, the verdict is NOT-REPRODUCED and the candidate dies.
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

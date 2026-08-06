# /check-consistency — the fresh-eyed multi-hat RENDERED-docs panel

Fire an expert panel of fresh-eyed agents at the **rendered** documentation and collect every
internal-consistency and expert-instinct defect they find. This is the **judgment-level** counterpart to
`/check-docs`: where `/check-docs` runs a *deterministic* battery (greps, build lints, the
argument-coverage sweep) against the **source**, `/check-consistency` reads the **rendered site as a
reader would** and hunts what a grep cannot — a quantity defined two ways across pages, a physics or
category error, a normalization that disagrees between two formulas, a structure/design smell, an
unreachable citation, a cold-read gap.

Each hat is a **fresh agent** that reads ONLY the reader-text manuscript (no `src/`, no `CLAUDE.md`, no
memory — it judges the docs as written, from its own expertise) and banks its findings to a file. **One
exception:** the `latex-typesetter` hat also reads the authored **source** (`src/`, `docs/`) and the
**`CLAUDE.md`** house rulebook — typesetting idiom lives in the source markup, not the rendered output,
and the house style it enforces is defined there. The panel is **collect-only**: it never edits `src/`
or `docs/`; you act only when the user says fix. It runs **sequentially**, so a token-out loses at most
the current hat; the hat order is **priority** (most critical first).

## What it catches — and what it does not

Catches: cross-page contradictions, physics/dimensional/category errors, method disagreements, design and
API smells in the *documented* interface, structure non-uniformity, citation gaps/overclaims, and
self-containedness ("cold read") failures. These need judgment and cross-referencing.

Does **not** reliably catch: mechanical, pattern-matchable idioms — `\mathbf`, bare-index `\partial_i`,
formula-in-backticks, an unbraced `\boldsymbol u`. A hat that *reads* the TeX may not *flag* these (a
panel once read a `\,` overuse and waved it through). **Those belong to `/check-docs`'s deterministic
scans** (several are build-enforced) — do not lean on the panel for them. (The `latex-typesetter` hat now
comes closest: it reads the authored **source** against the `CLAUDE.md` rulebook, so it is a real
judgment-level backstop — but `/check-docs` stays the enforcement, and the hat is told to spend its
effort on the context calls a grep cannot make.)

## The panel (11 hats)

Substrate **FULL** = every rendered page incl. the design docs; **SITEONLY** = the design docs — the
Architecture page and the observables-cache page — withheld, so the two no-design-doc hats judge
self-containedness and structure without the design docs as a crutch.

| # | Hat | Lens | Substrate |
|---|-----|------|-----------|
| 1 | `consistency-matrix` | the spine — matrix every recurring entity (quantity, symbol, formula, constant, method, docstring shape) and diff it across all pages | FULL |
| 2 | `software-architect` | the *documented* design as a senior Julia dev — signatures, dispatch, `f`/`f!`, decomposition, single-source-of-truth, decision-log soundness | FULL |
| 3 | `turbulence-theoretician` | every physical definition / law / dimensionless constant / derived scale vs established theory *and* itself — **and the category/type-error class** (a field vs its representation, a rate vs its time-integral, an operator vs its parameter, a density vs an energy) | FULL |
| 4 | `dns-practitioner` | numerical methods + performance claims; the dealias band and the transform counts stated consistently everywhere | FULL |
| 5 | `structure-consistency` | infer the implicit docstring template, then flag every outlier against it | SITEONLY |
| 6 | `latex-typesetter` | every formula's TeX idiom, judged against the **`CLAUDE.md`** house rulebook and reading the authored **source** (not just the rendered output) | FULL + source + CLAUDE.md |
| 7 | `api-user` | build/drive the library from the docs alone — arg coverage, return shapes/representations, the checked-read contract, exported-vs-documented agreement | FULL |
| 8 | `dimensional` | dimensional consistency + every normalization factor correct *and* identical across pages | FULL |
| 9 | `citations-integrity` | consistent author-year, inline↔References matching, no inaccessible source, no overclaim | FULL |
| 10 | `style-editor` | internal uniformity (majority style) **+** the raw built HTML for silent-render failures | FULL + raw HTML |
| 11 | `cold-reader` | a first-year grad student's top-to-bottom cold read — undefined symbols/terms (a *boundary*, a *deposit*, a *stamp*, an *epoch*), self-containedness | SITEONLY |

The hats live in `.claude/commands/check-consistency/panel.js` (their personas are the source of truth;
this table is the map). The physics pair sits adjacent by design — `turbulence-theoretician` (the
physical laws and the category/type errors) with `dimensional` (the factors) — the first catching the
structurally-false-but-plausible sentence, the second the concrete normalization slip. Scale the panel
to the ask: the full 11-hat run is the "thorough audit" (tens of minutes; cost per the modes below);
for a quick check, run a subset.

## Cost modes (mirrors `/check-docs` — ported from PF 2026-08-06)

**Economy is the DEFAULT.** Nine of the eleven hats run on the cheap scan model (Sonnet); the two
physics hats — `turbulence-theoretician` and `dimensional` — are **anchors** that always run at the
session's full-strength model. The asymmetry is deliberate: a cheap hat's *false positive* is caught
downstream (the discipline already verifies every Tier-1/2 finding against `src/` and the built HTML in
the main thread, at full strength), but a *false negative* — a subtle category error or a
plausible-but-wrong factor read past — has no downstream verifier, and those two hats exist precisely
for that class. The other nine lenses are enumerative or rule-anchored (matrix-diffing, template
outliers, arg coverage, citations, style, the written house-rulebook typesetting, the cold read) — the
kind of narrow evidence-cited scan the cheap lanes are strong at — and the panel's cross-hat redundancy
means the anchors' domains overlap most of what a cheap hat could miss. Net: roughly a 3–4× panel-cost
cut for a little extra false-positive noise, absorbed by the verification step. **Never economized:**
the main-thread verification, the consolidation/ranking, and any later fix pass. **Full strength**
(every hat at the session model) runs only on explicit request: pass `strength: "full"` in the
Workflow args.

## Run it

Let `$SCRATCH` be this session's scratchpad and `$REPO` the repo root (absolute). The large, ephemeral
manuscripts go in `$SCRATCH`; the findings pile is the repo's `.claude/doc-review/`.

1. **Build the docs fresh** — the panel reads the *rendered* output, so it must be current, and the two
   build lints must be clean first:
   ```bash
   julia --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd()))' >/dev/null 2>&1
   julia --project=docs docs/make.jl > /tmp/build.log 2>&1; echo $?   # REQUIRE exit 0
   # (verify by EXIT CODE, never by grepping the output — a lint failure prints `ERROR:`, not `┌ Error`)
   git checkout -- docs/Project.toml           # revert the transient dev entry (Project.toml ALONE)
   ```
2. **Consolidate** the built HTML into the two reader-text manuscripts (needs `beautifulsoup4`):
   ```bash
   python3 .claude/commands/check-consistency/consolidate.py docs/build \
       "$SCRATCH/manuscript-full.md" "$SCRATCH/manuscript-siteonly.md"
   ```
   Confirm the reported page count matches the site and no page is empty.
3. **Archive** any prior findings so a re-run starts clean (keep the last round for diffing):
   ```bash
   if [ -n "$(ls -A .claude/doc-review 2>/dev/null)" ]; then
     rm -rf .claude/doc-review-prev && mv .claude/doc-review .claude/doc-review-prev
   fi
   mkdir -p .claude/doc-review
   ```
4. **Run the panel** — a background `Workflow` on the companion script, sequential, collect-only. Pass
   **absolute** paths (each hat `Read`s them):
   ```
   Workflow({ scriptPath: ".claude/commands/check-consistency/panel.js",
              args: { full:        "$SCRATCH/manuscript-full.md",
                      siteonly:    "$SCRATCH/manuscript-siteonly.md",
                      rawhtml:     "$REPO/docs/build",
                      pile:        "$REPO/.claude/doc-review",
                      adjudicated: "$REPO/.claude/doc-review-adjudicated.md",
                      strength:    "economy" } })   # the default; "full" only on explicit request
   ```
   **The hats are otherwise BLIND to prior rounds, and that is the design** — fresh eyes are the whole
   instrument (a fresh round once caught a mathematically false sentence the previous round's *fix
   pass* had introduced). The one exception is `adjudicated`, injected into every hat's preamble:
   findings settled as **not** defects (manuscript-extraction artifacts, user-closed design decisions).
   Nothing merely *fixed* belongs in that file — re-flagging a bad fix is exactly what the panel is
   for. PF measured the cost of omitting it: 4 of a round's 87 findings were re-litigation of settled
   material, including one hat's **top-ranked** finding.
   Each hat banks `.claude/doc-review/NN-<key>.md` and returns a structured findings object; you are
   notified when the workflow completes.
5. **Consolidate the findings** into `.claude/doc-review/00-SUMMARY.md` **and an Artifact dashboard**:
   read every `NN-*.md`, **dedup** (cluster cross-hat — a defect found by many hats is a strong signal),
   **rank** by severity × corroboration, and record which batteries came back **clean** and which are
   confirmed **false positives**.

## Discipline (the hard-won rules — follow them)

- **Collect-only.** The panel proposes; the user disposes. Do not touch `src/` or `docs/` during a panel
  run, and do not "quietly fix while I'm here."
- **Verify before you trust — a rendered-text read is not ground truth.** Before reporting any Tier-1/2
  finding, confirm it against the **current `src/`** and the **built HTML** (quote the decisive line).
  Rendered-text reads have produced *false* blockers: a decision log that renders `<ol>` misread as
  unnumbered; a grep-escaping slip that "found" zero of something that was plentiful. Re-check the crux,
  do not relay it raw.
- **Judgment, not mechanics.** See "what it does not catch" — route mechanical idioms to `/check-docs`.
- **Don't launder a flagged smell.** Never close a finding by declaring it "by design" / "for symmetry" /
  "it's convenient". Fix it, or escalate it to the user with the trade-off — the user decides. (The
  genuine by-design absences — the forthcoming statistics, the recorded deferrals of §7 — are stated in
  the docs; a hat is told not to flag those as gaps.)
- **Record dispositions and false positives** in `00-SUMMARY.md` (a short block at the top): what was
  fixed, escalated, left-with-a-first-principle-reason, and confirmed-not-a-defect — and move the
  settled **non-defects** into `.claude/doc-review-adjudicated.md`, the only file a future round is
  shown.
- **A flagged instance is a sample of a class** — when you do fix (later, on the user's word), fix the
  class across every surface, not just the quoted line.
- **The per-hat files are the work list; `00-SUMMARY.md` is a reading aid.** The consolidated summary is
  written **for the user** — deduplicated, ranked, scannable — and consolidation is *lossy by design*,
  which is exactly what makes it readable. So a fix pass **must be driven from the banked `NN-*.md`
  files**, enumerating every finding in every hat and closing it by number; the summary is never the
  input. (PF proved the point twice in one run: a hat's 20 findings folded into a single parenthetical
  in the summary, 19 of them silently surviving the fix pass; and a finding filed **major / high
  confidence** relayed by the summary as "soft", which was false.) **A severity in the summary never
  overrides the hat's own** — re-read the hat before downgrading anything. Report closure **per hat and
  per finding number** ("06: 20/20 closed"), so the count is auditable against the banked files rather
  than against the summary's clusters.
- **Bounded output per hat.** Each hat is capped at its ~25 most significant findings with tight quotes
  (the preamble enforces it): the banked file and the returned object mirror each other, so an unbounded
  dump doubles on output and can overrun the output-token cap (it killed two PF hats once). A hat that
  would exceed the cap is being insufficiently selective, not thorough — 15 sharp findings beat 50
  padded ones. A killed hat is simply re-run standalone (same persona, the cap in its prompt) to fill
  its `NN-<key>.md` gap; the other hats' banked files are untouched.

## Output

- `.claude/doc-review/NN-<key>.md` — one file per hat (the raw banked findings).
- `.claude/doc-review/00-SUMMARY.md` — the consolidated, deduplicated, ranked report with dispositions,
  the verified-clean batteries, and the confirmed false positives.
- An **Artifact** dashboard (filterable by severity/surface) for the user to scan.
- `.claude/doc-review-prev/` — the previous round, kept for diffing.

The findings **piles** — `.claude/doc-review/` and `.claude/doc-review-prev/` — are untracked working
notes, regenerated every run (never commit them; stage tracked files with `git add -u`, never `-A`).
**Tracked**, because they are the instrument rather than its output: this command file, the
`check-consistency/` scripts, and `.claude/doc-review-adjudicated.md` — the do-not-re-flag list
`panel.js` injects into every hat, which has to survive a re-run and reach the other machine.

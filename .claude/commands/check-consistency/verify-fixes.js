// VERIFY-FIXES — the second adversarial auditor. Where verify.js audits a STATE, this audits an ACT.
//
// Args: { pile, repo, range, strength }
//   pile     — absolute path to the findings pile (a doc-reading pile, or a banked hat file)
//   repo     — the repo root
//   range    — the git range holding the fix pass, e.g. "9b3ecdd..HEAD"
//   strength — 'economy' (DEFAULT) | 'full'
//
// THE DELIBERATE INVERSION OF verify.js
//
//   verify.js  audits a STATE — "does this defect exist now?" — and is therefore BLIND to the diff.
//              Showing it the fixer's report would let it grade homework against its own answer key.
//   THIS one   audits an ACT — "was this repaired well?" — and therefore MUST see the diff, plus the
//              user's verbatim words as ground truth, because the repair itself is the object under
//              review. A fix can leave the corpus in a state verify.js calls ABSENT and still be a
//              bad fix: done by insertion, done to the line and not the class, done in a docstring
//              when the defect was in the code, or done correctly on the wrong instruction.
//
// The four questions, and the failure each exists to catch (all four are RECORDED failures of this
// project, not hypotheticals — see CLAUDE.md "Known weaknesses" and the round-1/round-2 piles):
//   FIDELITY       — did the user's actual ask land, everywhere it applies?
//   STRATEGY       — right KIND of repair? (fix-by-insertion; line-not-class; docstring patch over a
//                    code defect; a caveat where a rename was asked for)
//   IMPLEMENTATION — is the replacement text actually correct? A fix can honor the instruction
//                    perfectly and still be false — formula, category/type, cold read, house notation.
//   SCOPE          — anything changed that was not asked for; or a flagged term carried through a
//                    rewrite because it was not the literal flagged word.
export const meta = {
  name: 'check-consistency-verify-fixes',
  description: 'Adversarial audit of HOW findings were fixed — fidelity, strategy, implementation, scope (sees the diff and the user\'s verbatim words)',
  phases: [ { title: 'Audit fixes' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
const PILE = A.pile
const REPO = A.repo
// Same guard as verify.js (PF, 2026-08-27): a finding the owner settled as NOT a defect was
// deliberately not fixed, so an auditor that has not seen the list grades it UNDONE — the one
// verdict indistinguishable from real neglect.
const ADJUDICATED = A.adjudicated || `${A.repo}/.claude/doc-review-adjudicated.md`
const RANGE = A.range
// Findings are adjudicated in batches so each auditor holds a workable slice; batches are ranges of
// finding numbers in the pile.
//
// `batches` is REQUIRED, and used to default to the round-2 read's [[1,7]…[36,42]]. That default was
// a silent truncation waiting to happen: pointed at a 114-finding pile it would audit findings 1-42,
// report a healthy tally over six batches, and never mention the 72 it skipped. A caller who knows
// the pile size must state it, so the coverage is a decision rather than a leftover.
const BATCHES = A.batches
if (!Array.isArray(BATCHES) || !BATCHES.length) {
  throw new Error('`batches` is required: pass e.g. [[1,7],[8,14],…] covering EVERY finding in the pile. ' +
                  'Count them first (`grep -cE "^#{2,3} +(Finding )?[0-9]+" <pile>`) — an unstated range silently drops the tail.')
}
const covered = BATCHES.reduce((n, b) => n + (b[1] - b[0] + 1), 0)
log(`auditing findings ${BATCHES[0][0]}-${BATCHES[BATCHES.length - 1][1]} in ${BATCHES.length} batches (${covered} findings)`)

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    batch: { type: 'string' },
    audits: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        finding: { type: 'string' },
        user_ask: { type: 'string', description: "the user's verbatim instruction, abbreviated" },
        verdict: { type: 'string', enum: ['HONORED', 'ADJACENT', 'INSERTED', 'LINE-ONLY', 'NEW-DEFECT', 'SCOPE-CREEP', 'UNDONE', 'LAUNDERED'] },
        question: { type: 'string', enum: ['fidelity', 'strategy', 'implementation', 'scope', 'none'], description: 'which of the four questions the verdict answers; "none" for HONORED' },
        evidence: { type: 'string', description: 'file:line + the decisive quote from the CURRENT source, and from the diff where the act matters' },
        class_surfaces: { type: 'array', items: { type: 'string' },
          description: 'EVERY surface the finding\'s own text names or implies as carrying the same class, each with whether it was swept and the file:line that shows it. Enumerate from the FINDING, not from the diff and not from memory. Empty is a LINE-ONLY verdict, never HONORED.' },
      },
      required: ['finding', 'user_ask', 'verdict', 'question', 'evidence', 'class_surfaces'],
    } },
  },
  required: ['batch', 'audits'],
}

// HONORED IS EARNED BY ENUMERATION, NOT BY A STORY (PF's addition, ported 2026-08-27). PF raised
// this while porting the instrument, and it lands on IT's own worst measured failure: eleven of
// thirteen deficiencies in one round were LINE-ONLY — the flagged site fixed, the class alive on
// surfaces the finding had ALREADY NAMED. An auditor asked "was the class swept?" will accept a
// plausible account, because a plausible account is what a fix pass produces. So the verdict now
// requires the auditor to LIST the other surfaces and say what happened at each; an empty list is
// demoted to LINE-ONLY by rule rather than judged. The enumeration comes from the finding's text —
// the surfaces it named are the ones that must be checked — never from the diff, which shows only
// where someone already looked.
const PREAMBLE = `You are an ADVERSARIAL FIX AUDITOR for GBGIsotropicTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence.

The package owner read the rendered documentation and reported defects in their own words. An assistant then fixed them. YOU AUDIT THE FIXES. Your allegiance is to the owner, not to the assistant: assume the fix is deficient until its evidence convinces you otherwise.

You have three things:
  1. THE PILE — the findings, each carrying the owner's VERBATIM words. Those words are GROUND TRUTH. Where the owner stated a preference ("I prefer X", "make them all named", "just omit this", "drop it"), that preference is the specification, not a suggestion the assistant was free to reinterpret.
  2. THE DIFF — the fix pass itself: \`git diff ${RANGE}\` and \`git log ${RANGE}\` in ${REPO}. Read it. The ACT is what you are auditing, so how the text changed matters as much as what it now says.
  3. THE CURRENT CORPUS — ${REPO}/src/*.jl, ${REPO}/docs/, and the house rulebook ${REPO}/CLAUDE.md.

FOR EACH FINDING IN YOUR BATCH, ask FOUR questions in order, and stop at the first failure:

  (1) FIDELITY — did the owner's actual ask land, and land EVERYWHERE it applies? A rename applied to
      the quoted line but not to the other call sites, the docs, the tests, and the prose is not
      fidelity. A synonym is not the name they chose.
  (2) STRATEGY — was the right KIND of repair chosen? Three specific failures to hunt:
      (a) FIX BY INSERTION — the flagged text is still there, with correct text APPENDED beside it.
          A repair must CORRECT or DELETE the flagged clause. This is the assistant's single most
          frequent recorded failure; look for it every time.
      (b) LINE, NOT CLASS — the flagged instance is fixed and the same defect survives elsewhere.
          A flagged instance is a SAMPLE OF A CLASS. Search for the other instances yourself.
      (c) WRONG SURFACE — a docstring reworded to explain away a defect that lives in the CODE
          (a misleading name papered over with a caveat; an argument order excused rather than fixed).
  (3) IMPLEMENTATION — is the replacement text CORRECT? A fix can honor the instruction exactly and
      still be wrong: a formula that no longer matches the source, a category/type error (a field vs
      its representation, a rate vs its time-integral, an operator vs its parameter), a broken or
      dangling cross-reference, a term introduced that is itself undefined, house notation violated.
      Verify formulas against the code — do not accept a plausible one.
  (4) SCOPE — was anything changed that the owner did not ask for? And, the subtle one: was a flagged
      TERM carried through a rewrite because it was not the literal flagged word? (A sentence rewritten
      to fix "boundary" while quietly keeping "stamped" is a scope failure, not a success.)

VERDICTS — HONORED is the ONLY verdict that requires evidence; every other verdict you may assert on
the strength of a quote, and you should prefer them when in doubt:
  HONORED     — the ask landed, by the right means, correctly, without creep. Cite what you checked,
                AND fill \`class_surfaces\`: enumerate from the FINDING'S OWN TEXT every other surface
                carrying the same class, and say for each whether it was swept, with a file:line.
                An empty \`class_surfaces\` is LINE-ONLY by rule — not a judgement call. This is the
                measured failure mode: eleven of thirteen deficiencies in one round were LINE-ONLY,
                on surfaces the finding had already named. HONORED is earned by enumeration, never
                by a plausible account of a sweep.
  ADJACENT    — something was done, but not what was asked (a synonym, a partial reading, a different fix).
  INSERTED    — repaired by appending; the flagged text survives.
  LINE-ONLY   — the instance is fixed, the class is alive. Name the surviving sites.
  NEW-DEFECT  — the fix introduced a fresh defect. Describe the new one.
  SCOPE-CREEP — unasked changes, or a flagged term carried through a rewrite.
  UNDONE      — nothing was done.
  LAUNDERED   — the finding was closed by DECLARING it acceptable ("by design", "for symmetry", "for
                consistency", "already recorded", "deliberate tradeoff") rather than fixed or escalated.

BEFORE grading anything UNDONE, check ${ADJUDICATED} — the owner's list of findings ruled NOT to be
defects. A finding on that list was deliberately left alone; grading it UNDONE is the one verdict
that looks identical to real neglect, and acting on it sends the next pass to edit something already
settled. Note the asymmetry: nothing merely FIXED is listed there, so absence from it proves nothing.
                A close is only legitimate if the OWNER decided it — the pile records the owner's words,
                so check them. An assistant-authored dismissal is LAUNDERED, however reasonable it reads.

Do not propose fixes. Do not rank. Do not soften. One audit entry per finding in your batch — every
finding, including the ones that look obviously fine.`

phase('Audit fixes')

const results = await pipeline(
  BATCHES,
  (b, _orig, i) => agent(
    `${PREAMBLE}

THE PILE (read it; your batch is findings ${b[0]}–${b[1]}, and you must return one audit entry for EACH):
  ${PILE}

THE DIFF: run \`git -C "${REPO}" log --stat ${RANGE}\` and \`git -C "${REPO}" diff ${RANGE}\` (use \`-- <path>\` to scope it when the whole diff is large).

When you are done, FIRST use the Write tool to save your audit as readable markdown to:
  ${REPO}/.claude/doc-review/fix-audit/batch-${b[0]}-${b[1]}.md
(one section per finding: number / the owner's verbatim ask / VERDICT / which question failed / evidence). THEN return the structured object with batch="${b[0]}-${b[1]}".`,
    { label: `fix-audit:${b[0]}-${b[1]}`, phase: 'Audit fixes', schema: SCHEMA, agentType: 'general-purpose',
      ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })
)

// A dead batch must not vanish: log against the range this loop ASSIGNED, never the agent's own
// self-reported `batch` string, and count the shortfall against what the range asked for.
const all = []
const anomalies = []
for (let i = 0; i < BATCHES.length; i++) {
  const b = BATCHES[i]
  const want = b[1] - b[0] + 1
  const r = results[i]
  if (!r) { anomalies.push(`${b[0]}-${b[1]}: DEAD — no result`); log(`batch ${b[0]}-${b[1]}: DEAD`); continue }
  const got = (r.audits || []).length
  if (got === 0) anomalies.push(`${b[0]}-${b[1]}: EMPTY — zero audits returned`)
  else if (got < want) anomalies.push(`${b[0]}-${b[1]}: SHORT — ${got} of ${want}`)
  log(`batch ${b[0]}-${b[1]}: ${got}/${want} audited`)
  all.push(r)
}

// MECHANICAL DEMOTION — the script applies it, not the auditor (2026-08-27).
// The preamble told the auditor "an empty `class_surfaces` is LINE-ONLY BY RULE — not a judgement
// call", and then nothing applied it: the tally below counted whatever verdict came back. That is
// this repository's own recorded weakness — writing the rule instead of building the check — in the
// script whose entire purpose is catching a fixer who did the same thing. It was found by following
// a PF report about a DIFFERENT defect in PF's demotion, which is the third time the cross-check has
// surfaced something neither of us was looking for.
//
// The predicate is EMPTINESS, deliberately, and that is the whole of it. PF's demotion matched a
// fixed vocabulary and a `file:line` shape, and demoted ten sound answers out of thirteen for
// writing "lines 195, 273" or "nothing to sweep". A rule that cries wolf fails in the other
// direction — the next reader who finds ten of thirteen demotions spurious stops reading demotions
// at all. An empty array is a structural fact about the response and cannot be misread; anything
// that parses the CONTENT of those strings would be re-introducing PF's bug here.
// Falsified in both directions before landing (no JS runtime on this host, so the predicate was
// evaluated directly against five cases):
//   honored + one surface named          -> kept HONORED
//   honored + empty array                -> demoted
//   honored + field absent               -> demoted
//   honored + "ARCHITECTURE.md (lines 195, 273) — nothing to sweep"  -> kept HONORED
//     (that is verbatim the phrasing PF's content-matching demotion rejected; it must pass here)
//   UNDONE + empty array                 -> left UNDONE, never touched
let demoted = 0
for (const r of all) for (const a of (r.audits || [])) {
  if (a.verdict === 'HONORED' && !(Array.isArray(a.class_surfaces) && a.class_surfaces.length)) {
    a.verdict = 'LINE-ONLY'
    a.evidence = `[DEMOTED BY SCRIPT: HONORED claimed with no enumerated class surface] ${a.evidence || ''}`
    demoted++
  }
}

const tally = {}
for (const r of all) for (const a of (r.audits || [])) tally[a.verdict] = (tally[a.verdict] || 0) + 1
log(`TOTAL: ${JSON.stringify(tally)}`)
if (demoted) {
  log(`   ${demoted} HONORED → LINE-ONLY by script (no class surface enumerated). Counted separately`)
  log(`   so the mechanical share of the demotions is visible rather than folded into the auditors'.`)
}
if (anomalies.length) {
  log(`!! ${anomalies.length} ANOMALY(S) — THE TALLY IS INCOMPLETE, DO NOT READ IT AS A FIX-QUALITY RATE:`)
  for (const a of anomalies) log(`   !! ${a}`)
}
return { tally, demoted_by_script: demoted, anomalies, batches: BATCHES, complete: anomalies.length === 0, results: all }

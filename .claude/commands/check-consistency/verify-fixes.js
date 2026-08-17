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
const RANGE = A.range
// Findings are adjudicated in batches so each auditor holds a workable slice; batches are ranges of
// finding numbers in the pile. Passed in, or defaulted to the round-2 read's 42.
const BATCHES = A.batches || [[1, 7], [8, 14], [15, 21], [22, 28], [29, 35], [36, 42]]

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
      },
      required: ['finding', 'user_ask', 'verdict', 'question', 'evidence'],
    } },
  },
  required: ['batch', 'audits'],
}

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
  HONORED     — the ask landed, by the right means, correctly, without creep. Cite what you checked.
  ADJACENT    — something was done, but not what was asked (a synonym, a partial reading, a different fix).
  INSERTED    — repaired by appending; the flagged text survives.
  LINE-ONLY   — the instance is fixed, the class is alive. Name the surviving sites.
  NEW-DEFECT  — the fix introduced a fresh defect. Describe the new one.
  SCOPE-CREEP — unasked changes, or a flagged term carried through a rewrite.
  UNDONE      — nothing was done.
  LAUNDERED   — the finding was closed by DECLARING it acceptable ("by design", "for symmetry", "for
                consistency", "already recorded", "deliberate tradeoff") rather than fixed or escalated.
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

const all = results.filter(Boolean)
const tally = {}
for (const r of all) for (const a of (r.audits || [])) tally[a.verdict] = (tally[a.verdict] || 0) + 1
for (const r of all) log(`batch ${r.batch}: ${(r.audits || []).length} audited`)
log(`TOTAL: ${JSON.stringify(tally)}`)
return { tally, results: all }

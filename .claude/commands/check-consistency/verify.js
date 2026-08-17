// /check-consistency VERIFY — the closure audit. The MANDATORY final phase of a panel round: it
// answers, per banked finding, whether the defect exists in the corpus RIGHT NOW.
//
// Args (absolute paths): { pile, repo, strength }
//   pile     — .claude/doc-review (the banked NN-<key>.md hat files; verdicts land in pile/closure/)
//   repo     — the repo root (the verifier reads src/, docs/, docs/build)
//   strength — 'economy' (DEFAULT, every verifier on the cheap model) | 'full'
//
// THE DESIGN RULE THAT MAKES THIS AN INSTRUMENT RATHER THAN A RUBBER STAMP:
//
// (1) The verifier is BLIND to the fix pass. It never sees the diff, the commit message, the
//     summary, or any claim about what was fixed — it sees the FINDING (which describes a defect)
//     and the CURRENT corpus, and answers "does this defect exist now?". A verifier handed the
//     fixer's report grades the homework against its own answer key; that is decision 37's lesson
//     (a bound that consumes the assumption it should test certifies nothing).
// (2) The DEFAULT VERDICT IS "PRESENT". A verdict of ABSENT or NOT-A-DEFECT is admissible only with
//     the enumerated search behind it. This makes the cheap model's failure mode SAFE: a lazy agent
//     returns "still broken", which costs a re-check, rather than "all clear", which is the failure
//     that has no downstream verifier. That inversion is what licenses the economy lane here.
// (3) PARTIAL exists because the recorded failure is not "fix wrong" but "fix the LINE, not the
//     CLASS" — round-1 finding 4a was applied to one constructor and never swept.
// (4) REGRESSED exists because a fix pass has demonstrably introduced new defects before (a PF round
//     caught a mathematically false sentence written by the previous round's fix pass).
export const meta = {
  name: 'check-consistency-verify',
  description: 'Adversarial closure audit: per banked finding, does the defect still exist in the corpus? (blind to the fix pass)',
  phases: [ { title: 'Verify' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
const PILE = A.pile
const REPO = A.repo

// The hat files, in the panel's own order. A verifier is spawned per file.
const HATS = [
  '01-consistency-matrix', '02-software-architect', '03-turbulence-theoretician',
  '04-dns-practitioner', '05-structure-consistency', '06-latex-typesetter',
  '07-api-user', '08-dimensional', '09-citations-integrity', '10-style-editor',
  '11-cold-reader',
]

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    hat: { type: 'string' },
    verdicts: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        finding: { type: 'string', description: 'the finding number as banked, e.g. "3" or "Finding 3"' },
        title: { type: 'string', description: 'the banked finding title, abbreviated' },
        verdict: { type: 'string', enum: ['PRESENT', 'PARTIAL', 'REGRESSED', 'ABSENT', 'NOT-A-DEFECT'] },
        evidence: { type: 'string', description: 'file:line + the decisive quote. For PRESENT/PARTIAL/REGRESSED: where the defect lives now. For ABSENT/NOT-A-DEFECT: the searches run and what they returned.' },
        surviving_class: { type: 'string', description: 'PARTIAL only: the other sites where the class is alive' },
      },
      required: ['finding', 'title', 'verdict', 'evidence'],
    } },
  },
  required: ['hat', 'verdicts'],
}

const PREAMBLE = `You are an ADVERSARIAL CLOSURE AUDITOR for GBGIsotropicTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence (velocity field and passive scalar on a triple-periodic box, integrating-factor time-stepping, pluggable forcing and dealiasing, a deposit-driven observables cache, Lagrangian tracers).

Some time ago an expert panel audited this package's documentation and banked its findings. A fix pass then ran. YOUR JOB IS NOT TO REVIEW THE FIX PASS — you are deliberately not shown it, and you must not go looking for it (do NOT read git log, git diff, commit messages, 00-SUMMARY.md, or any other hat's file). Your job is to answer ONE question per banked finding, from the CURRENT corpus alone:

    ** DOES THE DEFECT THIS FINDING DESCRIBES EXIST IN THE CORPUS RIGHT NOW? **

That question is answerable without any knowledge of what happened in between, and answering it that way is the entire point: a verifier that reads the fixer's report is grading homework against its own answer key.

VERDICTS — the DEFAULT IS "PRESENT". You must actively earn anything else:
- PRESENT      — the defect is still there. Quote file:line.
- PARTIAL      — fixed at the exact line the finding quoted, but the CLASS is alive elsewhere. This is the single most important verdict you can return: the recorded failure mode of this package is fixing the flagged instance and not sweeping the class. Whenever a finding describes something that could recur, SEARCH FOR OTHER INSTANCES before you accept a fix. List them in surviving_class.
- REGRESSED    — the area was changed and the change introduced a NEW defect (a false statement, a broken link, a dangling reference, a formula that no longer matches the code). Report the new defect, not the old one.
- ABSENT       — genuinely gone. ADMISSIBLE ONLY WITH EVIDENCE: state the searches you ran (the greps, the spellings and synonyms you tried, the files you read) and that they came back empty. "I looked and it seems fine" is NOT evidence and you must return PRESENT instead.
- NOT-A-DEFECT — the original finding was itself wrong (a misreading of the rendered manuscript, a claim false against the source). ADMISSIBLE ONLY WITH EVIDENCE, quoting the source line that refutes it.

If you cannot establish a verdict with evidence in reasonable effort, return PRESENT. That is the correct, safe answer — an unverified "fixed" is the exact failure this audit exists to prevent, and a false PRESENT merely costs a downstream re-check.

HOW TO WORK:
- Read your banked hat file FIRST, in full. Enumerate EVERY finding in it by number. You must return a verdict for EVERY ONE — no skipping, no merging, no "the rest look fine".
- The findings quote the RENDERED text. Ground truth is the SOURCE: the docstrings in ${REPO}/src/*.jl, the pages in ${REPO}/docs/src/, and ${REPO}/docs/ARCHITECTURE.md. The rendered build is at ${REPO}/docs/build (read it when the finding is about rendering — a dead link, a formula rendering as literal text, a table falling back to pipes).
- ${REPO}/CLAUDE.md is the house rulebook. Consult it when a finding turns on house style, naming, or documentation policy — it tells you what the corpus is SUPPOSED to look like.
- Note that names may have CHANGED since the finding was written. A finding about \`velocity_factor\` may now concern a renamed binding. Follow the concept, not the string: a defect that moved to a new name is PRESENT, not ABSENT.
- Use grep/ripgrep aggressively. A single Read of one file is almost never enough to justify ABSENT.

OUTPUT DISCIPLINE: one verdict per banked finding, evidence <= 60 words each. Do not editorialize, do not propose fixes, do not rank. You are an instrument, not a reviewer.`

phase('Verify')

const results = await pipeline(
  HATS,
  (hat) => agent(
    `${PREAMBLE}

YOUR BANKED HAT FILE (read it first, in full — it holds the findings you must adjudicate):
  ${PILE}/${hat}.md

When you are done, FIRST use the Write tool to save your verdicts as readable markdown to:
  ${PILE}/closure/${hat}.md
(a title line naming the hat, then one section per finding: number / title / VERDICT / evidence / surviving-class). THEN return the structured object with hat="${hat}".`,
    { label: `verify:${hat}`, phase: 'Verify', schema: SCHEMA, agentType: 'general-purpose',
      ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })
)

const all = results.filter(Boolean)
const tally = {}
for (const r of all) for (const v of (r.verdicts || [])) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (const r of all) {
  const c = {}
  for (const v of (r.verdicts || [])) c[v.verdict] = (c[v.verdict] || 0) + 1
  log(`${r.hat}: ${(r.verdicts || []).length} adjudicated — ${JSON.stringify(c)}`)
}
log(`TOTAL: ${JSON.stringify(tally)}`)
return { tally, results: all }

// THE DISMISSAL AUDIT — the half of the verifier the witness gate cannot cover.
//
// `witnesses.jl pass` proves that every CONFIRMED finding of a hunt was fixed. It says nothing about
// the findings that were never confirmed. Those verdicts — NOT-REPRODUCED, NOT-A-DEFECT — are
// judgement calls made by one agent under time pressure, and they are FILED, so nothing revisits
// them. Under a one-hunt design (which is the design: the instrument runs once, the verifier loops
// over its findings) a wrong dismissal is simply lost.
//
// This session measured the cost. Round 1 dismissed two candidates:
//
//   * "`Cache.particle_velocities`' two-epoch check is correct on the current tree — a test-coverage
//     gap, not a runtime defect."  It was a BLOCKER: the read checked one of the two epochs, so an
//     announced reposition — the exact mutation the two-counter design exists to catch — was the one
//     the read could not see, and `advance!`'s opening guard could never fire.
//   * "`_base_cfl`'s `::AbstractIntegrator` default is sanctioned by the supertype contract."  Its
//     sibling `allocate_buffers` HARD-ERRORS for an unknown scheme while this returned 0.3 silently,
//     and 0.3 sits ABOVE `IFRK2`'s 0.25, so a new scheme with a tighter limit was handed too large a
//     timestep from a constant appearing in no docstring.
//
// Both surfaced only because a LATER hunt happened to re-raise them. With no later hunt, nothing
// would have. So the dismissals need an auditor, and it is the same shape as the doc instruments':
// it re-examines what was reported, and does not go looking for anything new.
//
// THE DEFAULT VERDICT IS "UNSAFE". An auditor that cannot show the dismissal was right returns
// UNSAFE, because the asymmetry is real — a wrongly-dismissed defect is silent and permanent, while
// a wrongly-upheld one costs one more look.
//
// Args: { repo, dismissals: [{title, file, line, mechanism, verdict, observed}] }
export const meta = {
  name: 'bug-hunt-dismissals',
  description: 'Re-examine every finding a hunt dismissed, defaulting to "the dismissal is unsafe"',
  phases: [{ title: 'Audit dismissals' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const ITEMS = A.dismissals || []
if (!REPO) throw new Error('needs { repo }')
if (!ITEMS.length) throw new Error('needs a non-empty dismissals array — an empty audit is not a clean one')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    verdict: { type: 'string', enum: ['DISMISSAL-SOUND', 'UNSAFE', 'DISMISSAL-WRONG'] },
    evidence: { type: 'string', description: 'quoted lines from the CURRENT tree that settle it, <= 70 words' },
    what_would_bite: { type: 'string', description: 'if UNSAFE or WRONG: the concrete call/input that misbehaves' },
  },
  required: ['title', 'verdict', 'evidence'],
}

phase('Audit dismissals')

const out = await parallel(ITEMS.map((d, i) => () => agent(
`A defect hunt raised this candidate and then DISMISSED it. You are re-examining the dismissal. You
are not the agent who made it and you owe it nothing.

  claim:      ${d.title}
  location:   ${d.file || '?'}${d.line ? ':' + d.line : ''}
  mechanism:  ${d.mechanism || '(not recorded)'}
  verdict:    ${d.verdict}
  reasoning:  ${d.observed || '(not recorded)'}

Read the CURRENT tree at ${REPO}. Decide:

  DISMISSAL-SOUND — the claim is genuinely not a defect, and you can show why from the code. Quote
                    the lines that settle it.
  UNSAFE          — you cannot establish that it is not a defect. THIS IS YOUR DEFAULT.
  DISMISSAL-WRONG — it IS a defect. Name the call and input that misbehaves.

WHY THE DEFAULT IS UNSAFE. A wrongly-dismissed defect is silent and permanent — nothing revisits a
filed dismissal. A wrongly-upheld one costs one more look. So "I could not confirm it is fine" is
reported as UNSAFE, not waved through.

TWO DISMISSAL SHAPES THAT WERE WRONG BEFORE, both from this instrument's own history:

  * "correct on the current tree — a test-coverage gap, not a runtime defect." Check the claim
    itself, not whether a test exists. One such dismissal hid a blocker.
  * "sanctioned by the contract / deliberate by design." A recorded arrangement is not evidence it is
    right. If a sibling operation handles the same situation differently, that asymmetry is the
    finding, and "it is documented" does not answer it.

Do not hunt for anything else. Your scope is this claim.`,
  { label: `dismissal:${(d.title || '?').slice(0, 34)}`, phase: 'Audit dismissals',
    schema: SCHEMA, agentType: 'general-purpose' })
  .then(v => ({ ...v, index: i + 1 }))))

const verdicts = out.filter(Boolean)
const dead = ITEMS.length - verdicts.length
const tally = {}
for (const v of verdicts) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (const v of verdicts) log(`${String(v.index).padStart(2, '0')}  ${v.verdict.padEnd(16)} ${v.title.slice(0, 80)}`)
log(`TALLY: ${JSON.stringify(tally)}`)
if (dead) log(`!! ${dead} auditor(s) DIED — that many dismissals are UNAUDITED, not upheld`)

const reopened = verdicts.filter(v => v.verdict !== 'DISMISSAL-SOUND')
if (reopened.length) {
  log(`!! ${reopened.length} dismissal(s) DO NOT HOLD — these go back on the finding list:`)
  for (const v of reopened) log(`   !! [${v.verdict}] ${v.title} — ${v.what_would_bite || v.evidence}`)
}
return { tally, verdicts, reopened, dead, complete: dead === 0 }

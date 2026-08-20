// The ARCHITECTURE-class fix verifier. The runtime and api-semantics classes need no agent at all —
// their witnesses re-run mechanically (`witnesses.jl pass`), and a program exiting non-zero is a
// stronger verdict than any reviewer. This script covers only what no program can check: whether an
// architecture finding was actually resolved, or merely relocated, renamed, or declared acceptable.
//
// It sees the fix (unlike the doc instruments' blind verifier) because the question here is about an
// ACT: did this diff eliminate the duplication, or move it? That is only answerable against the diff.
//
// THE DEFAULT VERDICT IS THE UNFAVOURABLE ONE. An auditor with no evidence returns ABSENT, never
// "probably fine" — the cheap-lane laziness must fail safe, which is the rule the doc instruments
// paid for twice.
//
// Args: { repo, findings: [{title, file, second_location, mechanism, claimed_fix}], strength }
export const meta = {
  name: 'bug-hunt-verify-fixes',
  description: 'Audit whether each architecture-class fix eliminated the defect or merely relocated it',
  phases: [{ title: 'Audit' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const FINDINGS = A.findings || []
if (!REPO) throw new Error('needs { repo }')
if (!FINDINGS.length) throw new Error('needs a non-empty findings array — an empty audit must not report success')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    verdict: { type: 'string', enum: ['FIXED', 'RELOCATED', 'PARTIAL', 'ABSENT', 'NOT-A-DEFECT'] },
    evidence: { type: 'string', description: 'the decisive quoted lines from the CURRENT tree, <= 70 words' },
    residue: { type: 'string', description: 'if not FIXED: exactly what still stands, with file:line' },
  },
  required: ['title', 'verdict', 'evidence'],
}

phase('Audit')

const out = await parallel(FINDINGS.map((f, i) => () => agent(
`You are auditing ONE claimed fix to an architecture defect in GBGIsotropicTurbulence at ${REPO}. You are not the person who made it and you owe it no benefit of the doubt.

  finding:      ${f.title}
  location:     ${f.file}${f.second_location ? '   and   ' + f.second_location : ''}
  mechanism:    ${f.mechanism}
  claimed fix:  ${f.claimed_fix || '(unstated — establish from the tree what was done)'}

READ THE CURRENT TREE, not the diff summary you were handed. Then decide between:

  FIXED        — the defect is gone. For a duplication that means ONE definition remains and every
                 former site reaches it; quote the single definition and at least one call site.
  RELOCATED    — the shape changed but the defect survives: the duplicate moved to a new file, the
                 literal became a differently-spelled literal, the two copies became two wrappers
                 around two bodies. THIS IS THE VERDICT THE INSTRUMENT EXISTS TO CATCH, because a
                 relocation reads exactly like a fix in a diff and exactly like a defect in the tree.
  PARTIAL      — one of the two sites was swept, the other stands. Name the one that stands.
  ABSENT       — you cannot find evidence the defect was addressed at all. THIS IS YOUR DEFAULT: if
                 the evidence is not in your hands, return ABSENT rather than assuming competence.
  NOT-A-DEFECT — on reading both sites, the original finding was wrong (the two blocks differ for a
                 real reason). Say what the reason is.

Do NOT accept a comment, a docstring, or a decision-log entry as a fix: prose asserting that two
copies are intentionally parallel leaves two copies that can drift. The test is what a maintainer
would have to edit, and in how many places.

Quote from the tree. An assertion with no quoted line is worth ABSENT.`,
  { label: `audit:${(f.title || 'finding').slice(0, 34)}`, phase: 'Audit', schema: SCHEMA,
    agentType: 'general-purpose', ...(A.strength === 'full' ? {} : {}) })
  .then(v => ({ ...v, index: i + 1 }))))

const verdicts = out.filter(Boolean)
const dead = FINDINGS.length - verdicts.length
const tally = {}
for (const v of verdicts) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (const v of verdicts) log(`${String(v.index).padStart(2, '0')}  ${v.verdict.padEnd(13)} ${v.title}`)
log(`TALLY: ${JSON.stringify(tally)}`)
if (dead) log(`!! ${dead} auditor(s) DIED — that many findings are UNVERIFIED, not clean`)

const open = verdicts.filter(v => !['FIXED', 'NOT-A-DEFECT'].includes(v.verdict))
if (open.length) { log(`!! ${open.length} STILL OPEN:`); for (const v of open) log(`   !! [${v.verdict}] ${v.title} — ${v.residue || v.evidence}`) }

return { tally, verdicts, dead, complete: dead === 0, open }

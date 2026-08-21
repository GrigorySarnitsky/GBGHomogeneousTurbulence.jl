// ADVERSARIAL ATTACK ON THE EDIT-AUDIT'S LENS DESIGN.
//
// The edit audit exists because a witness-based defect hunt cannot see the damage its own fixes do.
// But the audit is itself a LIST OF LENSES someone wrote down, and this project has already measured
// what a written list does: eight hand-specified hunt lanes reported `complete: true` over their own
// blind spot, and two unconstrained readers then found nine defects the eight could not see. The
// audit's list is newer and shorter. There is no reason to think it is better.
//
// So this attacks the DESIGN, not the code. The question is not "is the audit useful" — it is:
//
//     WHAT KIND OF HARMFUL EDIT PASSES ALL SEVEN LENSES?
//
// AN ATTACK WITHOUT A CONCRETE EVADING EXAMPLE IS NOT AN ATTACK. "The taxonomy may be incomplete" is
// worthless; "here is an edit, here is why each of the seven lanes waves it through" is a proof. The
// strongest possible result is an existence proof of a blind spot, and that is what is being asked
// for.
//
// The panel is deliberately not all software people. A logician tests whether the partition is
// exhaustive as a partition; a philosopher tests whether the audit's central predicates mean
// anything stable; a red-teamer tries to walk an edit straight past all of them.
//
// Args: { repo, design }
export const meta = {
  name: 'attack-audit-design',
  description: 'Adversarial attack on the edit-audit lens set: what harmful edit passes all seven lenses?',
  phases: [{ title: 'Attack' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const { repo: REPO, design: DESIGN } = A
if (!REPO || !DESIGN) throw new Error('needs { repo, design }')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    role: { type: 'string' },
    verdict: { type: 'string', enum: ['SOUND', 'GAPS'] },
    gaps: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        severity: { type: 'string', enum: ['fatal', 'serious', 'worth-fixing'] },
        gap: { type: 'string', description: 'the blind spot, stated as a KIND of edit' },
        evading_example: { type: 'string',
                           description: 'a CONCRETE edit to this package that is harmful and passes all seven lenses. Required.' },
        why_each_lane_misses: { type: 'string', description: 'lane by lane, why it does not fire' },
        proposed_lens: { type: 'string', description: 'the lens that would catch it, or "no lens — needs a different mechanism"' },
      },
      required: ['severity', 'gap', 'evading_example', 'why_each_lane_misses', 'proposed_lens'] } },
  },
  required: ['role', 'verdict', 'gaps'],
}

const PREAMBLE = `You are attacking the DESIGN of an automated code-edit audit — not the code it audits.

CONTEXT. An automated defect hunt made 605 inserted and 129 deleted lines across 11 source files of a
Julia pseudospectral turbulence solver (${REPO}). The agent that made those edits was also the agent
that found the defects and reported the results. An "edit audit" was then built to check whether the
edits were justified and whether they silently changed behaviour. That audit's lens set is below,
verbatim.

WHY THIS ATTACK EXISTS. The same project already measured what a hand-written list of lenses does:
in the defect hunt, eight hand-specified lanes reported themselves COMPLETE while missing an entire
class, and two unconstrained readers then found nine defects the eight could not see — four of them
regressions introduced by the hunt's own fixes. The audit's lens set is newer, shorter, and written
by the same author. Assume it is inadequate and find out how.

THE DESIGN UNDER ATTACK:

${DESIGN}

YOUR OUTPUT MUST CONTAIN CONCRETE EVADING EXAMPLES. A gap asserted in the abstract ("the taxonomy may
not be exhaustive", "there could be emergent effects") is worth nothing here. What is worth something
is: *here is a specific edit someone could make to this package, it is harmful, and here is why each
of the seven lenses individually fails to fire on it.* Walk the lanes one at a time and show each one
missing. If you cannot construct such an example for a gap you suspect, say so plainly rather than
padding — a short honest attack beats a long speculative one.

Say SOUND if you genuinely cannot break it. That verdict is permitted and will be believed.`

const ROLES = [
  { key: 'logician', anchor: true, brief: `You are a LOGICIAN. Treat the lens set as a proposed partition of a space and test it AS a partition. Is the space itself well-defined — what is the set of all possible harmful edits, and under what relation are the lenses a cover of it? Attack on structure: (a) DUALS — for each lens, does its logical dual have a lane? The set has "over-rejection" (an edit that newly REJECTS valid input); where is the lane for an edit that newly ACCEPTS input that was previously and rightly refused? (b) QUANTIFIERS — the audit's question is scoped to "input that was previously valid"; what harmful edits fall outside that quantifier entirely? (c) COMPOSITION — each lens judges edits one at a time; what harm exists only in the CONJUNCTION of two individually-innocent edits? (d) NEGATIVE SPACE — every lens examines something PRESENT in the diff; what about the harmful ABSENCE of an edit, or a deletion whose trace is gone? (e) OVERLAP vs GAP — where two lenses both plausibly own something, does it fall between them?` },

  { key: 'philosopher', anchor: true, brief: `You are a PHILOSOPHER working on epistemology and philosophy of science. Attack the audit's CONCEPTS, not its coverage. (a) THE BASELINE PROBLEM — the audit treats prior behaviour as the norm and flags "silent change" against it, but the prior behaviour may itself have been wrong; on what grounds is the status quo normative, and what false positives and false negatives does that assumption generate? (This project's own rulebook warns "legacy is not evidence of correctness" — the audit may have inverted that into a principle.) (b) "JUSTIFIED" — justified relative to WHAT? the defect? the author's intent? the package's purpose? the user's ability to check? These come apart; show a case where they disagree and the audit gives the wrong answer. (c) INDEPENDENCE — the auditors are the same kind of agent, with the same training and dispositions, as the author. In what sense is this independent, and what failure would be invisible to ALL of them at once? (d) FALSIFIABILITY — how would anyone discover that the audit had missed something? If there is no such route, what is the audit's output actually evidence of? (e) WHOSE STANDPOINT — the user of this package reads the API documentation and NOT the code; does "justified" indexed to a reader-who-cannot-read-the-code differ from what these lenses measure?` },

  { key: 'red-team', anchor: true, brief: `You are a RED-TEAMER and your job is purely constructive: WRITE THE EDITS THAT GET THROUGH. Produce as many concrete, harmful, plausible edits to this package as you can that pass all seven lenses. Read the actual source at ${REPO}/src to make them realistic — a plausible edit is one an agent fixing a real defect might genuinely make. Fruitful directions to try, though do not be limited to them: an edit that is individually proportionate but changes a documented DEFAULT; an edit that preserves every value but changes WHEN something is evaluated; an edit that is correct on CPU and wrong on a device backend; an edit that only misbehaves on the second call, or after a specific sequence; an edit that changes error-path behaviour rather than success-path; an edit that is right for the tested precision and wrong for the other; an edit that quietly widens what a function accepts. For each, walk the seven lanes and show each one missing.` },

  { key: 'measurement', brief: `You are a MEASUREMENT and EVALUATION specialist. Attack the audit's EVIDENCE STANDARD rather than its categories. What does a lane's CLEAN verdict actually license anyone to conclude? The lanes are asked for their "8 most substantial findings" — what does a cap do to a lens that should have reported thirty? The severity labels are self-assigned by the same agent that reports the finding — what does that do to a downstream reader triaging by severity? The audit ran ONCE over one diff; what is its false-negative rate and how would anyone estimate it? Is there any measurement here that could come back and say "the audit was wrong", and if not, what would have to be built for that to be possible? Propose the specific instrument, not the aspiration.` },
]

phase('Attack')
const results = await parallel(ROLES.map(r => () => agent(
  `${PREAMBLE}\n\nYOUR ROLE: ${r.key}\n\n${r.brief}\n\nReturn the structured object with role="${r.key}".`,
  { label: `attack:${r.key}`, phase: 'Attack', schema: SCHEMA, agentType: 'general-purpose',
    ...(r.anchor ? {} : { model: 'sonnet' }) })))

const done = results.filter(Boolean)
const dead = ROLES.length - done.length
const gaps = done.flatMap(r => (r.gaps || []).map(g => ({ ...g, role: r.role })))
const bySeverity = {}
for (const g of gaps) bySeverity[g.severity] = (bySeverity[g.severity] || 0) + 1
for (const r of done) log(`${r.role}: ${r.verdict} (${(r.gaps || []).length} gap(s))`)
log(`TOTAL: ${JSON.stringify(bySeverity)}`)
for (const g of gaps.filter(g => g.severity === 'fatal')) log(`   FATAL [${g.role}] ${g.gap}`)
if (dead) log(`!! ${dead} attacker(s) DIED — that angle is UNTESTED, not sound`)
return { bySeverity, gaps, dead, complete: dead === 0 }

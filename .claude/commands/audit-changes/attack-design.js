// ADVERSARIAL ATTACK ON AN INSTRUMENT'S LENS DESIGN. Generalized 2026-08-22 over the `subject` arg;
// the defaults reproduce the edit-audit framing it was written for, so existing callers are unchanged.
//
// The edit audit exists because a witness-based defect hunt cannot see the damage its own fixes do.
// But the audit is itself a LIST OF LENSES someone wrote down, and this project has already measured
// what a written list does: eight hand-specified hunt lanes reported `complete: true` over their own
// blind spot, and two unconstrained readers then found nine defects the eight could not see. The
// audit's list is newer and shorter. There is no reason to think it is better.
//
// So this attacks the DESIGN, not the code. The question is not "is the audit useful" — it is:
//
//     WHAT KIND OF DEFECT PASSES EVERY LANE?
//
// AN ATTACK WITHOUT A CONCRETE EVADING EXAMPLE IS NOT AN ATTACK. "The taxonomy may be incomplete" is
// worthless; "here is an edit, here is why each of the seven lanes waves it through" is a proof. The
// strongest possible result is an existence proof of a blind spot, and that is what is being asked
// for.
//
// The panel is deliberately not all software people. A logician tests whether the partition is
// exhaustive as a partition; a philosopher tests whether the audit's central predicates mean
// anything stable; a counterexample hunter tries to walk an edit straight past all of them.
//
// Args: { repo, design, subject? } — subject = { object, defect, defects, lanes, context, directions,
//                                                 standpoint, source }, each optional.
// ON THE NAME. This lane was called `red-team` until 2026-08-22, and the term was borrowed without
// checking that the analogy held. It does not. A red team models an ADVERSARY WITH INTENT — someone
// who wants in and will use whatever works — and that licenses exotic scenarios. There is no
// adversary here: nobody is sneaking bad edits past this audit. The realistic failure is a
// well-intentioned fix that is simply too wide. So the useful constraint is the OPPOSITE of a red
// team's: the edit must be one an agent fixing a real defect might GENUINELY MAKE. The lane's actual
// job is to produce a counterexample to a universal coverage claim, which is what it is now called.
export const meta = {
  name: 'attack-audit-design',
  description: 'Adversarial attack on ANY instrument\'s lens set: what defect passes every lane?',
  phases: [{ title: 'Attack' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const { repo: REPO } = A
// `design` inlines the lens set into the prompt; `designPath` names a file for the attacker to Read
// instead. A workflow script has no filesystem access, but its agents do — and a large design
// (the docs panel's 23 personas run to 36 kB) is better read than interpolated.
const DESIGN = A.design
  ? A.design
  : (A.designPath
      ? `The design is too large to inline. READ IT FIRST, in full, with the Read tool:\n    ${A.designPath}\nEverything below refers to the lens set in that file.`
      : null)
if (!REPO || !DESIGN) throw new Error('needs { repo, design | designPath }')

// THE SUBJECT BLOCK generalizes this attacker over instruments. It was hardwired to the edit audit
// until 2026-08-22, while the /audit-changes command file already claimed "any instrument's lane list
// should have to survive it" — a universal claim its own code did not support. The defaults preserve
// the edit-audit framing exactly, so an existing invocation is unaffected.
const S = A.subject || {}
const OBJECT     = S.object   || 'a code edit'
const DEFECT     = S.defect   || 'a harmful edit'
const DEFECTS    = S.defects  || 'harmful edits'
const LANES      = S.lanes    || 'seven lenses'
const CONTEXT    = S.context  || `An automated defect hunt made 605 inserted and 129 deleted lines across 11 source files of a
Julia pseudospectral turbulence solver (${REPO}). The agent that made those edits was also the agent
that found the defects and reported the results. An "edit audit" was then built to check whether the
edits were justified and whether they silently changed behaviour. That audit's lens set is below,
verbatim.`
const DIRECTIONS = S.directions || `an edit that is individually proportionate but changes a documented DEFAULT; an edit that preserves every value but changes WHEN something is evaluated; an edit that is correct on CPU and wrong on a device backend; an edit that only misbehaves on the second call, or after a specific sequence; an edit that changes error-path behaviour rather than success-path; an edit that is right for the tested precision and wrong for the other; an edit that quietly widens what a function accepts`
const STANDPOINT = S.standpoint || `the user of this package reads the API documentation and NOT the code`
const SOURCE     = S.source   || `${REPO}/src`

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    role: { type: 'string' },
    verdict: { type: 'string', enum: ['SOUND', 'GAPS'] },
    gaps: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        severity: { type: 'string', enum: ['fatal', 'serious', 'worth-fixing'] },
        gap: { type: 'string', description: 'the blind spot, stated as a KIND of defect the instrument cannot see' },
        evading_example: { type: 'string',
                           description: 'a CONCRETE instance, real for this package, that is harmful and passes EVERY lane. Required.' },
        why_each_lane_misses: { type: 'string', description: 'lane by lane, why it does not fire' },
        proposed_lens: { type: 'string', description: 'the lens that would catch it, or "no lens — needs a different mechanism"' },
      },
      required: ['severity', 'gap', 'evading_example', 'why_each_lane_misses', 'proposed_lens'] } },
  },
  required: ['role', 'verdict', 'gaps'],
}

const PREAMBLE = `You are attacking the DESIGN of an automated review instrument — not the thing it reviews. The instrument's object is ${OBJECT}.

CONTEXT. ${CONTEXT}

WHY THIS ATTACK EXISTS. The same project already measured what a hand-written list of lenses does:
in the defect hunt, eight hand-specified lanes reported themselves COMPLETE while missing an entire
class, and two unconstrained readers then found nine defects the eight could not see — four of them
regressions introduced by the hunt's own fixes. This lens set was written by the same author as the
thing it audits, and its additions were justified by that author's own reasoning. Assume it is
inadequate and find out how.

THE DESIGN UNDER ATTACK:

${DESIGN}

YOUR OUTPUT MUST CONTAIN CONCRETE EVADING EXAMPLES. A gap asserted in the abstract ("the taxonomy may
not be exhaustive", "there could be emergent effects") is worth nothing here. What is worth something
is: *here is a specific instance in this package, it is harmful, and here is why each lane
individually fails to fire on it.* Walk the lanes one at a time and show each one missing. If you cannot construct such an example for a gap you suspect, say so plainly rather than
padding — a short honest attack beats a long speculative one.

Say SOUND if you genuinely cannot break it. That verdict is permitted and will be believed.`

const ROLES = [
  { key: 'logician', anchor: true, brief: `You are a LOGICIAN. Treat the lens set as a proposed partition of a space and test it AS a partition. Is the space itself well-defined — what is the set of all possible ${DEFECTS} for this instrument's object (${OBJECT}), and under what relation are the lenses a cover of it? Attack on structure: (a) DUALS — for each lens, does its logical dual have a lane? For example, if some lane detects a thing WRONGLY PRESENT, is there a lane for the same thing WRONGLY ABSENT? Name each dual and say whether it is covered. (b) QUANTIFIERS — find the scope restriction the instrument's own question carries, state it, and name what falls outside that quantifier entirely. (c) COMPOSITION — each lens judges items one at a time; what harm exists only in the CONJUNCTION of two individually-innocent ones? (d) NEGATIVE SPACE — every lens examines something PRESENT in the material; what about a harmful ABSENCE, which leaves no trace to read? (e) OVERLAP vs GAP — where two lenses both plausibly own something, does it fall between them?` },

  { key: 'philosopher', anchor: true, brief: `You are a PHILOSOPHER working on epistemology and philosophy of science. Attack the audit's CONCEPTS, not its coverage. (a) THE BASELINE PROBLEM — the audit treats prior behaviour as the norm and flags "silent change" against it, but the prior behaviour may itself have been wrong; on what grounds is the status quo normative, and what false positives and false negatives does that assumption generate? (This project's own rulebook warns "legacy is not evidence of correctness" — the audit may have inverted that into a principle.) (b) "JUSTIFIED" — justified relative to WHAT? the defect? the author's intent? the package's purpose? the user's ability to check? These come apart; show a case where they disagree and the audit gives the wrong answer. (c) INDEPENDENCE — the auditors are the same kind of agent, with the same training and dispositions, as the author. In what sense is this independent, and what failure would be invisible to ALL of them at once? (d) FALSIFIABILITY — how would anyone discover that the audit had missed something? If there is no such route, what is the audit's output actually evidence of? (e) WHOSE STANDPOINT — ${STANDPOINT}; does the instrument's central predicate, indexed to THAT reader, differ from what these lenses actually measure?` },

  { key: 'counterexample', anchor: true, brief: `You are a COUNTEREXAMPLE HUNTER. The panel is testing a universal claim — "these lenses catch ${DEFECTS}" — and your job is to falsify it: WRITE THE INSTANCES THAT GET THROUGH. Produce as many concrete, harmful, plausible instances in this package as you can that pass EVERY lane. Read the real material at ${SOURCE} to make them realistic — a plausible instance is one that a competent author would genuinely produce, not one contrived to evade. Fruitful directions to try, though do not be limited to them: ${DIRECTIONS}. For each, walk EVERY lane and show each one missing.` },

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

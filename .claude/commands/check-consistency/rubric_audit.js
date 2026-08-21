// THE RUBRIC AUDIT — the user's task of 2026-08-17: "for each finding in this pile, ask WHICH HAT
// SHOULD HAVE CAUGHT IT, AND WHY DIDN'T IT?"
//
// The naive way to answer that is to read the findings, read the personas, and judge. That cannot
// work: my judgement about what a rubric should catch is the same judgement that wrote the rubric,
// so it will confidently report that each hat covers its own findings. The measured version of this
// exact failure is on record — eight /bug-hunt lanes reported `complete: true` over their own blind
// spot, and two unconstrained lanes then found nine defects the eight could not see.
//
// So the audit borrows /bug-hunt's rule:
//
//     A CLAIM THAT "HAT X SHOULD HAVE CAUGHT FINDING Y" IS A HYPOTHESIS. THE ONLY ADMISSIBLE
//     EVIDENCE IS RUNNING HAT X'S PERSONA, BLIND, ON THE TEXT WHERE Y LIVES, AND SEEING WHETHER Y
//     COMES OUT.
//
// Two controls make it capable of failing:
//
//   * THE PERSONA IS VERBATIM, lifted from panel.js. A paraphrase would test my summary of the
//     rubric rather than the rubric.
//   * THE SUBSTRATE IS UNCONTAMINATED. A hat sees only the passage as it stood at the baseline
//     commit — never the title, never the critique. `rubric_prep.py` writes the two into disjoint
//     directories and asserts no finding's own words leak into its substrate.
//
// The scorer is a separate agent that never ran the hat, sees both sides, and DEFAULTS TO MISSED.
// "The hat said something vaguely nearby" is not catching the defect.
//
// Args: { repo, base }   base = the rubric-audit directory (absolute)
export const meta = {
  name: 'rubric-audit',
  description: 'Test, blind, whether each panel hat’s own rubric produces the findings the user found',
  phases: [{ title: 'Assign' }, { title: 'Blind run' }, { title: 'Score' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo, BASE = A.base
if (!REPO || !BASE) throw new Error('needs { repo, base }')
const HATS = A.hats            // [{key, persona}]
const INDEX = A.index          // [{id, title, locations}]
if (!HATS?.length || !INDEX?.length) throw new Error('needs { hats, index } — an empty audit is not a clean one')

const ASSIGN_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { assignments: { type: 'array', items: {
    type: 'object', additionalProperties: false,
    properties: {
      id: { type: 'integer' },
      hats: { type: 'array', items: { type: 'string' },
              description: 'the 1-2 hat keys whose OWN STATED RUBRIC covers this defect. [] if none does.' },
      why: { type: 'string', description: 'quote the clause of the persona that covers it, or say why none does. <= 40 words.' },
    }, required: ['id', 'hats', 'why'] } } },
  required: ['assignments'],
}

const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { findings: { type: 'array', items: {
    type: 'object', additionalProperties: false,
    properties: {
      where: { type: 'string', description: 'file and roughly where in the excerpt' },
      defect: { type: 'string', description: 'what is wrong, in your own words' },
    }, required: ['where', 'defect'] } } },
  required: ['findings'],
}

const SCORE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    id: { type: 'integer' },
    verdict: { type: 'string', enum: ['CAUGHT', 'MISSED', 'PARTIAL'] },
    evidence: { type: 'string', description: 'the hat’s own words that match the defect, or "nothing reported on this" — <= 40 words' },
  }, required: ['id', 'verdict', 'evidence'],
}

// ── 1. ASSIGN. This agent MAY see the findings: it is not the one under test. ────────────────────
phase('Assign')
const personaList = HATS.map(h => `### ${h.key}\n${h.persona.slice(0, 1100)}`).join('\n\n')
const CHUNK = 9
const chunks = []
for (let i = 0; i < INDEX.length; i += CHUNK) chunks.push(INDEX.slice(i, i + CHUNK))

const assigned = (await parallel(chunks.map((chunk, ci) => () => agent(
`You are mapping DEFECTS onto the RUBRICS that should have caught them, for a panel of documentation
hats. Below are the panel's personas, verbatim. For each finding, read its full entry at
${BASE}/defect/<id>.md (zero-padded, e.g. 07 → 07.md) and decide which hat's OWN STATED RUBRIC covers
that defect.

Judge the persona AS WRITTEN. The question is not "which hat is nearest in topic" but "does this
persona's text instruct a reader to look for this class of thing?" If none of them does, answer with
an EMPTY list — that is the finding this audit exists to produce, and a forced assignment destroys it.
Quote the clause you relied on.

PERSONAS:
${personaList}

FINDINGS IN YOUR CHUNK: ${chunk.map(f => `${f.id} (${f.title.slice(0, 90)})`).join('; ')}`,
  { label: `assign:${ci + 1}`, phase: 'Assign', schema: ASSIGN_SCHEMA, agentType: 'general-purpose' })))
).filter(Boolean).flatMap(r => r.assignments)

const byHat = {}
const unassigned = []
for (const a of assigned) {
  if (!a.hats?.length) { unassigned.push(a); continue }
  for (const h of a.hats) (byHat[h] ||= []).push(a.id)
}
log(`assigned ${assigned.length} findings; ${unassigned.length} covered by NO persona`)
for (const u of unassigned) log(`   no rubric covers #${u.id}: ${u.why}`)

// ── 2. BLIND RUN + 3. SCORE, pipelined per hat. ─────────────────────────────────────────────────
phase('Blind run')
const hatKeys = Object.keys(byHat)
const results = await pipeline(
  hatKeys,
  (key) => {
    const persona = HATS.find(h => h.key === key).persona
    const ids = byHat[key]
    return agent(`${persona}

YOUR SUBSTRATE is a set of passages from a Julia turbulence package's documentation and source, held
in these files — read every one:
${ids.map(i => `${BASE}/substrate/${String(i).padStart(2, '0')}.txt`).join('\n')}

Apply your lens and REPORT EVERY DEFECT YOU FIND. Be specific about where and what. These are
excerpts, so ignore anything that is merely cut off at an edge; judge what is present.`,
      { label: `blind:${key}`, phase: 'Blind run', schema: REPORT_SCHEMA, agentType: 'general-purpose' })
      .then(r => ({ key, ids, reported: r?.findings || [] }))
  },
  (run) => {
    if (!run) return null
    const listing = run.reported.map((f, i) => `${i + 1}. [${f.where}] ${f.defect}`).join('\n') || '(reported nothing)'
    return parallel(run.ids.map(id => () => agent(
`You are scoring whether a documentation reviewer, working blind, found ONE specific known defect.

THE KNOWN DEFECT is described at ${BASE}/defect/${String(id).padStart(2, '0')}.md — read it.

WHAT THE REVIEWER REPORTED, having seen only the passage and never the defect description:
${listing}

Did the reviewer report THIS defect?

  CAUGHT  — one of its items is this defect: same passage, same thing wrong with it.
  PARTIAL — it noticed the passage and something adjacent, but not the defect itself.
  MISSED  — nothing in the list is this defect.

DEFAULT TO MISSED. The point of this exercise is to find rubric gaps, so a generous reading destroys
the measurement. Topical proximity is not catching it: "this sentence is unclear" does not catch "this
sentence states a false quantifier". Being in the right file is not catching it.`,
      { label: `score:${run.key}-${id}`, phase: 'Score', schema: SCORE_SCHEMA, agentType: 'general-purpose' })
      .then(v => ({ ...v, id, hat: run.key })))) 
  },
)

const scores = results.filter(Boolean).flat().filter(Boolean)
const best = {}
for (const s of scores) {
  const rank = { CAUGHT: 2, PARTIAL: 1, MISSED: 0 }
  if (!best[s.id] || rank[s.verdict] > rank[best[s.id].verdict]) best[s.id] = s
}
const tally = { CAUGHT: 0, PARTIAL: 0, MISSED: 0 }
for (const id of Object.keys(best)) tally[best[id].verdict]++
log(`BEST-OF verdicts across assigned hats: ${JSON.stringify(tally)}`)
log(`plus ${unassigned.length} findings NO persona claimed at all`)
const gaps = Object.values(best).filter(s => s.verdict !== 'CAUGHT')
for (const g of gaps) log(`   GAP  #${g.id} [${g.hat}] ${g.verdict}: ${g.evidence}`)

return { tally, unassigned, gaps, scores, byHat,
         complete: hatKeys.length > 0 && scores.length > 0 }

// SEVERITY RE-RATE — the blind recalibration pass (attack round C10, 2026-08-23).
//
// THE PROBLEM: severity and confidence are asserted exactly once, by the same interested agent
// that produced the finding, and nothing downstream re-examines them — the consolidation ranks by
// them, the fix pass orders by them, and a mis-rated finding steers both. Structurally identical
// to rubric_audit's blind-run design: strip the self-assigned rating, show a fresh agent only the
// evidence, and compare.
//
// Args: { items_path, count } — items_path is a JSON file {"items": [{id, text}]} whose text
// blocks carry NO severity/confidence lines (the caller strips them; this script trusts the
// caller's blinding). Each rating agent Reads the file itself and takes its own item — a workflow
// script has no filesystem, its agents do. Returns one rating per item; the comparison against the
// hats' self-ratings happens in the main thread, which knows the originals.
export const meta = {
  name: 'check-consistency-severity-recheck',
  description: 'Blind re-rating of sampled panel findings: fresh agents rate severity from the evidence alone',
  phases: [{ title: 'Re-rate' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const PATH = A.items_path
const COUNT = A.count
if (!PATH || !COUNT) throw new Error('needs { items_path, count }')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    id: { type: 'string' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor', 'nit'] },
    reason: { type: 'string', description: 'one sentence: what the rating turns on' },
  },
  required: ['id', 'severity', 'reason'],
}

const SCALE = `Severity scale (the panel's own):
- blocker — wrong or misleading: a reader acting on this text gets a wrong result or wrong belief
  about the physics, the API, or a cost.
- major — a real defect a reader will plausibly hit: a contradiction between surfaces, a stale
  quantified claim, a missing load-bearing statement.
- minor — real but unlikely to mislead: localized wording, a gap with nearby correction, drift on
  a secondary surface.
- nit — cosmetic or judgment-flavored.
Rate what the EVIDENCE supports, not what the prose's tone suggests.`

phase('Re-rate')
const out = await parallel(Array.from({ length: COUNT }, (_, i) => () => agent(
`You are re-rating the severity of ONE documentation-review finding for a pseudospectral DNS
package. You did not produce the finding and owe its author nothing. You see only the finding's
evidence — no self-assigned rating, no fix status.

First: Read the JSON file at ${PATH}. Take items[${i}] (0-based). Rate THAT finding only.

${SCALE}

Return {id: <the item's own id>, severity, reason}.`,
  { label: `rate:item-${i}`, schema: SCHEMA, model: 'sonnet' })))

return out.filter(Boolean)

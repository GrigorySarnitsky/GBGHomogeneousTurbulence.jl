// /audit-changes — WERE THESE EDITS JUSTIFIED, AND DID THEY SILENTLY CHANGE BEHAVIOUR?
//
// A standalone instrument, and the question it asks is orthogonal to how the edits arose. It applies
// to a defect hunt's fix pass, a documentation sweep, a review round, or a change made by hand. The
// other instruments here look at CODE; this one looks at CHANGES TO CODE, which is a different object
// with different failure modes — an edit can be a correct fix and still be wider than the defect
// required, and neither the code nor the fix looks wrong in isolation.
//
// It earns its place empirically. Run over five rounds of automated defect fixing, it found what no
// defect hunt could: a convenience method that threw on the exact call its own docstring described; a
// forcing amplitude that lost its only bound when a floor was removed for a good reason; a timestep
// ceiling that was, on inspection, a statement about which UNITS the caller had chosen. A hunt looks
// for defects in code. None of those are defects in code — they are defects in edits.
//
// WHY IT HAS NO ADVERSARIAL VERIFIER OF ITS OWN, unlike the doc instruments. Their verifier exists
// because "is this finding fixed?" is a judgement and judgements get quietly dropped. This one already
// contains its mechanical anchor: the `executing` lane RUNS things. A second adversarial layer
// auditing the auditor is where the regress starts and the grounding stops. What it has instead is a
// DISPOSITION GATE (every serious finding must be answered, and a stale audit is refused) and a
// reusable DESIGN ATTACKER — see attack-design.js, which found eleven fatal gaps in an earlier version
// of the lane set below.
//
// Args: { repo, diff, base, head, claims?, kind? }
//   diff   — path to the diff under audit
//   base   — the commit the norm is read at (NOT head: see the preamble)
//   claims — optional path to the author's commit messages, for the claim-versus-edit lane
//   kind   — 'code' | 'prose' | 'both' (default: both)
export const meta = {
  name: 'audit-edits',
  description: 'Independent audit of the code the bug hunt changed: justified, or silent behaviour change?',
  phases: [{ title: 'Audit' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const { repo: REPO, diff: DIFF, claims: CLAIMS, base: BASE, head: HEAD, scale: SCALE } = A
const KIND = A.kind || 'both'
if (!REPO || !DIFF || !BASE) throw new Error('needs { repo, diff, base }')
if (!['code', 'prose', 'both'].includes(KIND)) throw new Error(`kind must be code|prose|both, got ${KIND}`)

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    lane: { type: 'string' },
    verdict: { type: 'string', enum: ['CLEAN', 'CONCERNS'],
               description: 'CLEAN only if you found nothing in your lens worth the user reading' },
    checked: { type: 'array', items: { type: 'string' },
               description: 'REQUIRED, and required especially when CLEAN: what you actually examined, item by item (the specific hunks, names, guards or calls). A CLEAN verdict with an empty or vague `checked` list is indistinguishable from a lane that did nothing, and will be read as such.' },
    candidates_found: { type: 'integer',
                        description: 'how many candidates you found in total BEFORE the reporting cap. If this exceeds the number you report, the cap is hiding findings and the reader must know.' },
    findings: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        severity: { type: 'string', enum: ['serious', 'notable', 'minor'] },
        title: { type: 'string' },
        file: { type: 'string' },
        before: { type: 'string', description: 'what the code did BEFORE, quoted from the diff' },
        after: { type: 'string', description: 'what it does NOW, quoted' },
        why_it_matters: { type: 'string', description: 'who is affected and how — concrete, not abstract' },
        justified: { type: 'string', enum: ['yes', 'no', 'unclear'],
                     description: 'was this change warranted by a defect, or is it wider than the defect required?' },
      },
      required: ['severity', 'title', 'file', 'before', 'after', 'why_it_matters', 'justified'] } },
  },
  required: ['lane', 'verdict', 'checked', 'candidates_found', 'findings'],
}

const PREAMBLE = `You are auditing a large set of edits to GBGIsotropicTurbulence, a Julia pseudospectral DNS of homogeneous isotropic turbulence. The edits were made by an automated defect hunt over five rounds: 605 lines inserted, 129 deleted, across 11 source files.

THE DIFF: ${DIFF}   (base ${BASE} → head ${HEAD || 'HEAD'}) — src/, test/ AND docs/
THE CODE: ${REPO}/src   — read the current files, not only the diff
THE RULEBOOK: ${REPO}/CLAUDE.md — its "Core invariants" section states what the package promises

PIN THE NORM AT BASE, NOT AT HEAD. The docstrings, comments and tests you would naturally treat as
the standard were themselves EDITED in the window you are auditing — the audited party rewrote the
description of the thing you are auditing. So when you need to know what the package PROMISED, read
it at the base commit:  git show ${BASE}:src/<file>  ...and compare. A contract quietly rewritten to
match a changed behaviour is the defect, not the baseline.

THE ORACLE IS PART OF THE CHANGE SET. \`test/\` is in this diff. A fix that also edited the test that
would have caught it, or a frozen audit ledger that was re-baselined in the same commit, is exactly
the shape that certifies itself. Treat every test/ and ledger change as a claim to be checked, never
as the standard.

YOUR QUESTION IS NOT "what is wrong with this code". It is:

    WAS EACH CHANGE JUSTIFIED, AND DID IT SILENTLY ALTER WHAT THE PACKAGE DOES FOR INPUT THAT WAS
    PREVIOUSLY VALID?

An edit is a problem for this audit if it is WIDER than the defect it claims to fix, if it changes a
computed result, if it rejects usage that used to work, or if it alters a public contract — even when
the underlying fix was correct. "The fix was right" does not settle "the change was proportionate".

READ THE CODE FIRST AND FORM YOUR VERDICT BEFORE reading any commit message. The author's commit
messages are at ${CLAIMS}; they are the author's CLAIMS about these edits, not evidence about them.
The author was the finder, the fixer and the reporter of this work, so the claims are exactly what an
independent audit exists to check.

AUDIT ONLY. Do not edit, create or delete any file in ${REPO}. Report; do not repair.

Quote the before and after from the diff for every finding — an assertion with no quoted line is not
a finding. Report CLEAN honestly if your lens turns up nothing; a padded list is worse than a short
one. Cap: your 8 most substantial findings.`

// LENS DESIGN — deliberately the OPPOSITE balance to the hunt's, and for a measured reason.
//
// In the HUNT, a defect-class list bounds an unbounded search space (thousands of lines), so the
// classes ARE the limiting factor: eight class lanes reported complete over their own blind spot and
// two unconstrained readers then found nine defects at a third the cost. Free readers had to be the
// senior partner there.
//
// In an AUDIT the scope is a FINITE diff that every lane reads in full. A lens no longer restricts
// what an auditor SEES, only what it prioritises — so the blind-spot argument is weak, while the
// opposite argument is strong: the questions worth asking here are ones a general reader does not
// ask spontaneously. Measured on the first run, the two findings that no other lane produced were
// exactly the lens-specific ones — "does this validation foreclose the inviscid limit?" (which needs
// somebody to enumerate every added guard and interrogate each) and "does this commit message
// describe its own diff?" (which needs somebody to deliberately compare claim against edit).
//
// So: specific lenses lead, ONE free reader as insurance against this list being incomplete.
const LANES = [
  { key: 'free-reader', brief: `NO LIST. Read the diff and the current code and say what troubles you about these CHANGES. You are here because every other lane in this panel works from a list of concerns somebody wrote down, and a list is a hypothesis about where the problems are. Do not work through a checklist; if you catch yourself doing so, go back to reading. The one thing you are held to is the panel's question — was each change justified, and did it silently alter behaviour for input that previously worked — not "what else is wrong with this package".` },
  { key: 'executing', anchor: true, brief: `YOU RUN THINGS. Every other lane in this panel READS, and that is the flaw three independent attackers on this design converged on: the instrument these edits came from is founded on "a static claim about code is a hypothesis; the only admissible evidence is a program that fails", and its own audit was built entirely out of readers. So an edit justified by a MEASUREMENT written in a comment — "this allocates nothing", "this costs 2.9x", "the round trip closes", "measured 1.9x" — was certified by agents that read the comment.

Your job, in this order. (1) EVERY MEASUREMENT CLAIM the diff asserts, in a comment, a docstring or a commit message: re-run it. Write the Julia, run it, report the number you got beside the number claimed. (2) EVERY NEW ENTRY POINT the diff adds — a method, a keyword, an exported name, a changed return shape: write the call ITS OWN DOCUMENTATION describes and RUN it. A convenience method added in this window that throws on its documented call is a real class, found here before. (3) Any claim of the form "X and Y now agree", "the two branches coincide", "value unchanged": evaluate both sides and compare. Report numbers, not impressions. Use \`julia --project\` in the repository.` },

  { key: 'under-rejection', anchor: true, brief: `THE STRICT DUAL OF over-rejection, which the panel lacked. That lane enumerates guards the diff ADDS and asks if any is too strict. Nobody owns guards the diff REMOVES OR WEAKENS — and that is the direction that fails SILENTLY, since an over-strict guard throws in your face while a missing one returns a wrong number.

ENUMERATE, from the diff, every one of these that was deleted or loosened: a \`throw\`, an \`@assert\`, an early return, a ceiling or clamp, an equality test weakened to an inequality (\`==\` to \`>=\`), a concrete type annotation widened (to \`Any\`, to a supertype), a sentinel or floor removed, a conjunct dropped from a condition, a branch deleted. For EACH, construct the input that USED to be refused and show what the package computes for it now. Note the quantifier trap that hides this class: input that previously threw was not "previously valid", so the behaviour-change lane excludes it by construction.` },

  { key: 'backend-portability', brief: `CPU-IDENTICAL, DEVICE-BROKEN. This package is GPU-primary — storage is generic \`AbstractArray\`, and scalar indexing of a device array is forbidden — but every test in this repository runs on \`Array\`. So an edit can be bit-identical on CPU and broken on \`CuArray\`/\`ROCArray\` with nothing failing anywhere. No other lane owns this.

For each edited line ask whether it would execute unchanged on a device array. Look for: scalar indexing introduced (\`x[i]\`, \`first\`, \`getindex\` in a loop); a host-only function called on field storage (an RNG fill, a \`sort\`, a \`findfirst\`); a closure capturing a non-bitstype (a \`Type\`, a \`String\`, an abstract field) which a kernel launch rejects; a new host-device transfer or readback in the per-step path; \`Float64\` literals forcing a device kernel to double. Where the answer turns on which method a call dispatches to, say which package would have to provide it.` },

  { key: 'behaviour-change', anchor: true, brief: `SILENT BEHAVIOUR CHANGE. For input that was valid and worked BEFORE these edits, does the package now compute a different number, take a different branch, or produce a different result? Trace each edit that touches a computation — not a validation, a computation. Candidates to check specifically: the empty-band guard's test, the CFL timestep's ceiling, the integral-scale denominator, the forcing target factor's numeric type, the max-speed reduction, the epoch bookkeeping around deposits, the sample-history relocation. For each, decide whether an existing run's output changes and say by how much if you can.` },

  { key: 'over-rejection', anchor: true, brief: `NEWLY REJECTED USAGE. These edits added a large number of argument validations (viscosity, schmidt, cfl, kinetic_energy, scalar_variance, number_of_particles, forcing targets and variances, correlation time, κ_max_η, timestep sign, integrator order, buffer depth, scalar/state pairing). ENUMERATE THEM ALL from the diff, then for EACH ask: was that input previously valid and useful for something legitimate? A validation that rejects a genuine workflow is a regression dressed as a safety improvement — e.g. refusing zero viscosity forecloses an inviscid or Euler-limit study; refusing a zero-energy seed forecloses building a state incrementally. Judge each on whether a physicist could reasonably have been doing it.` },

  { key: 'public-contract', brief: `PUBLIC API AND CONTRACT. What changed in the surface a user depends on? Struct fields added or REMOVED, positional constructors whose arity changed, return values whose type changed, exports added or renamed, error types thrown where none were before. Check \`ModelSpectrum\`, \`step!\`, \`MultistepBuffers\`, \`ObservablesCache\`, and the epoch/announce verbs particularly. For each, state whether existing user code would break, and whether the break is announced anywhere a reader would see it.` },

  { key: 'numerics', brief: `NUMERICAL AND PHYSICAL CORRECTNESS of the changed lines. Do the edited formulas still compute what they claim? Check especially: the band-emptiness test and what it now admits or excludes; the CFL ceiling's dimensions and whether the bound is physically meaningful; the integral-scale sum after excluding a shell; the target factor as exact Int/Rational rather than floats; the retained-Nyquist cutoff expression; anything touching an epoch comparison that gates whether a value is served. Derive; do not assume the author's arithmetic.` },

  { key: 'invariants', brief: `THE PACKAGE'S OWN INVARIANTS, from CLAUDE.md: the hot loop is in-place and allocation-free over preallocated buffers; storage is generic AbstractArray with no scalar indexing of device arrays; minimal memory footprint trumps compute cost; physics stays thin. Did any edit add an allocation, a reduction, or a device-to-host readback to the per-step path? Did any add resident storage? Did any move work into the hot loop that was not there before? The frozen audit ledgers in test/ are the reference for what the step is supposed to cost.` },

  { key: 'claim-versus-edit', brief: `CLAIM AGAINST EDIT — you ARE to read ${CLAIMS} first, unlike the other lanes. For each commit message claim, find the corresponding hunk in the diff and check that the edit does what the claim says, no more and no less. Flag: edits present in the diff that no claim mentions (drive-by changes); claims that describe an edit not actually present; and claims whose scope is narrower than the edit made. This lane exists because the author was simultaneously the finder, fixer and reporter.` },
]

// PROSE lanes. A documentation sweep changes no behaviour, so the code lenses are vacuous on it —
// and a lane that cannot fire teaches the reader to discount CLEAN verdicts everywhere. What a prose
// diff CAN break is the contract: a docstring rewritten to match code it misdescribes, a caveat
// dropped, a guarantee quietly weakened, a rename swept through five surfaces and not the sixth.
const PROSE_LANES = [
  { key: 'contract-drift', anchor: true, brief: `A DOCSTRING IS A PROMISE. For every changed line of prose, check the promise against the CODE it describes — at HEAD for what the code does, and at the base commit for what the promise USED to be. Hunt the direction that hides: a claim edited to match behaviour that is itself wrong (the documentation bent to fit the code rather than the code fixed to fit the documentation), a caveat or warning deleted, a quantifier weakened ("always" to "usually", "never" to "rarely"), a guarantee that lost a condition it depended on. Quote the code line that settles each.` },
  { key: 'sweep-completeness', brief: `AN INCOMPLETE SWEEP. When one instance of a thing is edited, the others usually need it too — a renamed argument, a changed default, a retired term, a formula corrected in one docstring and not its \`f\`/\`f!\` twin. For every prose change in this diff, grep the whole corpus for the OTHER sites that state the same thing, and report the ones left behind. This is the single most common defect class in documentation edits, because the fixer sees the site they were pointed at and not the class.` },
  { key: 'reader-consequence', brief: `WHAT DOES A READER NOW BELIEVE THAT IS FALSE? Read the changed prose as its audience would — a physicist who reads the API documentation and NOT the source. For each edit ask what they would now do, expect, or conclude, and whether the code supports it. Flag prose that is technically true and practically misleading, an example that no longer runs, a signature that drifted from the implementation, and any place the docs now describe an intention rather than a behaviour.` },
]

const SELECTED = KIND === 'code'  ? LANES
               : KIND === 'prose' ? PROSE_LANES
               :                    [...LANES, ...PROSE_LANES]

phase('Audit')
const results = await parallel(SELECTED.map(lane => () => agent(
  `${PREAMBLE}\n\nYOUR LENS: ${lane.key}\n\n${lane.brief}\n\nReturn the structured object with lane="${lane.key}".`,
  { label: `audit:${lane.key}`, phase: 'Audit', schema: SCHEMA, agentType: 'general-purpose',
    ...(lane.anchor ? {} : { model: 'sonnet' }) })))

const done = results.filter(Boolean)
const dead = SELECTED.length - done.length
const all = done.flatMap(r => (r.findings || []).map(f => ({ ...f, lane: r.lane })))
const bySeverity = { serious: 0, notable: 0, minor: 0 }
for (const f of all) bySeverity[f.severity] = (bySeverity[f.severity] || 0) + 1
for (const r of done) log(`${r.lane}: ${r.verdict} (${(r.findings || []).length})`)
log(`TOTAL: ${JSON.stringify(bySeverity)}`)
for (const f of all.filter(f => f.severity === 'serious')) log(`   SERIOUS [${f.lane}] ${f.title}`)
if (dead) log(`!! ${dead} auditor(s) DIED — that lens is UNAUDITED, not clean`)
return { bySeverity, findings: all, dead, complete: dead === 0 }

// /bug-hunt — the CODE instrument, as against /check-docs and /check-consistency which audit prose.
//
// THE ONE DESIGN RULE, from which everything else follows:
//
//     A STATIC CLAIM ABOUT CODE IS A HYPOTHESIS. THE ONLY ADMISSIBLE EVIDENCE IS A PROGRAM THAT
//     FAILS.
//
// Reading code and reporting what "looks wrong" produces plausible, confident, unfalsifiable prose —
// the exact failure this project has measured repeatedly in its documentation instruments, and it is
// worse here, because a wrong bug report costs a fix pass on working code. So the hunt is static and
// the confirmation is dynamic: every candidate defect must be reduced to a WITNESS — a self-contained
// `@testset` asserting the CORRECT behaviour, which must be observed to FAIL on the current tree.
//
//   * A candidate whose witness passes is not a bug. It is discarded, whatever the argument for it.
//   * A candidate whose witness cannot be written is not actionable. It is discarded too.
//   * A witness that fails IS the finding. It is also, unchanged, the regression test the fix must
//     flip, and it is promoted into test/ when the fix lands.
//
// That inverts the usual economics: the expensive step is proving the bug, not describing it, and
// nothing reaches the fixer that has not already been demonstrated.
//
// TWO CLASSES ESCAPE THE WITNESS RULE, and are handled separately rather than smuggled through:
//
//   * ARCHITECTURE / MAINTAINABILITY (duplication, divergent copies, leaked abstraction, an invariant
//     of CLAUDE.md broken). These are not runtime defects and no test can fail on them. They demand a
//     different evidence standard: two or more quoted locations that a reader can diff, and a stated
//     consequence. A single-site "this is ugly" is not a finding.
//   * API-SEMANTICS claims ("`similar` does not preserve X", "`copyto!` requires Y"). Memory about
//     Base and third-party behaviour is exactly where a model is confidently wrong, so these need
//     BOTH: the official documentation fetched and quoted with its URL, AND a witness that runs.
//
// Args (absolute paths): { repo, pile, strength, lanes }
//   repo     — the repository root
//   pile     — where findings and witnesses are banked (.claude/bug-hunt)
//   strength — 'economy' (DEFAULT: hunt lanes on the cheap model, reproduction at full strength)
//              | 'full'  (everything at the session model)
//   lanes    — optional subset, by key or number, for re-running a dead lane
//   round    — the round number; prefixes every witness filename so a later round cannot overwrite
//              an earlier round's promoted regression test (measured: it did, and the suite then
//              failed for what looked like a bad fix)
//
// The reproduction stage is NEVER economized, in either mode. A cheap hunter that invents a
// candidate costs one reproduction that fails to reproduce; a cheap reproducer that mis-runs a
// witness corrupts the only evidence the instrument produces.
export const meta = {
  name: 'bug-hunt',
  description: 'Static hunt across the code, every candidate defect confirmed by a failing witness before it is reported',
  phases: [{ title: 'Hunt' }, { title: 'Reproduce' }],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const PILE = A.pile
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
// Witness filenames must not collide across rounds — see the slug instruction below.
const ROUND = A.round === undefined ? '' : `r${A.round}-`
if (!REPO || !PILE) throw new Error('bug-hunt needs { repo, pile } as absolute paths')

const CANDIDATE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    lane: { type: 'string' },
    files_read: { type: 'array', items: { type: 'string' },
                  description: 'every source file you actually opened — coverage is measured, not asserted' },
    candidates: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        kind: { type: 'string', enum: ['runtime', 'architecture', 'api-semantics'] },
        severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
        title: { type: 'string', description: 'one line, the defect not the location' },
        file: { type: 'string' },
        line: { type: 'integer' },
        mechanism: { type: 'string', description: 'WHY it is wrong — the causal chain, not a restatement' },
        witness_plan: { type: 'string',
                        description: 'runtime/api-semantics: the concrete call and the assertion that should hold but will not. architecture: the second location to diff against and the maintenance consequence.' },
        second_location: { type: 'string', description: 'architecture only: file:line of the divergent copy' },
      },
      required: ['kind', 'severity', 'title', 'file', 'line', 'mechanism', 'witness_plan'],
    } },
  },
  required: ['lane', 'files_read', 'candidates'],
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    title: { type: 'string' },
    verdict: { type: 'string', enum: ['REPRODUCED', 'NOT-REPRODUCED', 'WITNESS-WRONG', 'NO-WITNESS-POSSIBLE', 'EVIDENCED', 'NOT-A-DEFECT'] },
    witness_path: { type: 'string', description: 'REPRODUCED only: path of the banked .jl witness' },
    observed: { type: 'string', description: 'the actual output that proves it — a failing @test line, or the two quoted divergent blocks. <= 60 words.' },
    docs_url: { type: 'string', description: 'api-semantics only: the official page fetched, with the sentence it says' },
    severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
  },
  required: ['title', 'verdict', 'observed'],
}

// The free lanes' preamble. It carries the EVIDENCE discipline (which is what makes a finding
// admissible) and deliberately carries no taxonomy: naming classes here would recreate, one level
// down, exactly the blind spot these lanes exist to cover.
const FREE_PREAMBLE = `You are reading the code of GBGIsotropicTurbulence, a Julia pseudospectral DNS of homogeneous isotropic turbulence (velocity + passive scalar on a triple-periodic box, integrating-factor time stepping, pluggable forcing and dealiasing, a deposit-driven observables cache, Lagrangian tracers). GPU-primary: the time loop is in-place and allocation-free over preallocated buffers, storage is generic AbstractArray, and scalar indexing of device arrays is forbidden. The rulebook is ${REPO}/CLAUDE.md; the code is ${REPO}/src; the tests are ${REPO}/test.

YOUR BRIEF IS TO FIND WHAT IS WRONG WITH THIS CODE. That is the whole brief.

You are deliberately given NO list of defect classes to look for. Other lanes in this panel work from
such lists, and those lists are somebody's guess about where bugs live — so a defect that falls
outside every one of them is invisible to every one of them, and the run still reports success. You
are the lane that is supposed to catch what the guess missed. If you find yourself working through a
mental checklist, stop and read the actual code again: the finding that matters is usually the one
that has no category yet.

Read the source. Follow the data. Ask, of each thing you read, what would have to be true for it to
be correct, and then check whether it is.

WHAT MAKES A FINDING ADMISSIBLE. Every candidate you raise goes to a separate agent whose only job is
to write a program demonstrating it, and which discards anything that does not reproduce. So a
candidate is worth raising only if you can say what call, with what input, misbehaves — and how you
would know. Give that as the witness plan. If you cannot name one, do not raise it. One candidate you
can specify a failing call for beats five you cannot.

Classify each as "runtime" (a witness can be a failing @testset), "api-semantics" (your claim rests on
what Base or a dependency does — say so, and the reproducer will check the official documentation
rather than trusting memory), or "architecture" (no program can fail on it, so it needs a SECOND
location to diff against and a stated maintenance consequence).

Do not report style, naming, or documentation defects — other instruments own those.

Report files_read honestly; it is cross-checked against the tree.

Cap: your 6 most substantial candidates.`

const HUNT_PREAMBLE = `You are hunting DEFECTS IN THE CODE of GBGIsotropicTurbulence, a Julia pseudospectral DNS of homogeneous isotropic turbulence (velocity + passive scalar on a triple-periodic box, integrating-factor time stepping, pluggable forcing and dealiasing, a deposit-driven observables cache, Lagrangian tracers). GPU-primary: the time loop is in-place and allocation-free over preallocated buffers, storage is generic AbstractArray, and scalar indexing of device arrays is forbidden.

THE RULEBOOK IS ${REPO}/CLAUDE.md — read its "Core invariants" and "Style" sections first. THE CODE IS ${REPO}/src/*.jl and ${REPO}/src/phenomenology/*.jl. The tests are ${REPO}/test/*.jl and tell you what is already pinned.

YOU ARE PRODUCING HYPOTHESES, NOT VERDICTS. Every candidate you raise will be handed to a separate agent whose only job is to write a program that demonstrates it, and which discards anything that does not reproduce. So:

  * Do NOT report what merely looks unusual. Report what you can say will MISBEHAVE, and say with what input.
  * For every candidate, give a WITNESS PLAN: the concrete call, the input that triggers it, and the assertion that ought to hold but will not. If you cannot name one, do not raise the candidate.
  * Prefer one candidate you can specify a failing call for over five you cannot.
  * Do not report style, naming, or documentation defects. Other instruments own those, and a finding here that turns out to be prose wastes a reproduction slot.

THREE KINDS, and the kind decides the evidence:
  * "runtime"       — wrong values, wrong types, aliasing, mutation of a caller's data, an edge case that errors or silently misbehaves. Witness = a failing @testset.
  * "api-semantics"  — a claim about what Base or a dependency does. You are very likely to be wrong from memory here; say what you believe and the reproducer will check the official documentation AND run it.
  * "architecture"   — duplication, divergent copies of one rule, a leaked abstraction, an invariant of CLAUDE.md broken in the code. No test can fail on these, so they need a SECOND LOCATION to diff and a stated maintenance consequence. One site is not a finding.

Report your files_read honestly: it is cross-checked against the tree, and a lane that claims a sweep it did not do is worse than a lane that reports a narrow one.

Cap: your 6 most substantial candidates. Ranked by what would actually go wrong.`

// The FREE lanes. They exist because everything below them is a list I wrote, and a list is a
// hypothesis about where bugs live: a defect outside all eight classes is invisible to the class
// lanes BY CONSTRUCTION, and the run would still report complete. These get no class list at all —
// only a starting point, so that two free readers do not open the same file first. They are also the
// lanes whose failure mode is unrecoverable (a bug nobody raises is never reproduced), which is why
// they are the anchors that stay at full strength when the class lanes go cheap — the same asymmetry
// /check-consistency applies to its two physics hats, and which this instrument shipped without.
const FREE_LANES = [
  { key: 'free-hot-path', anchor: true, brief: `Start at \`SimulationRun.advance!\` and read ONE COMPLETE ITERATION end to end, following every call into whatever module it lands in — the generator's stages, the integrator, the deposit, the tracer push. Read the code, not the docstrings, and where a docstring makes a promise, check the code keeps it.` },
  { key: 'free-modules', anchor: true, brief: `Choose the two or three source files you judge most likely to be wrong — by size, by intricacy, by how much state they carry, by how little the suite exercises them — and READ THEM WHOLE, top to bottom. Say at the start which you chose and why.` },
]

const LANES = [
  { key: 'aliasing-and-mutation', brief: `Aliasing and unintended mutation. Which arrays are shared between owners? The observables cache borrows the tracer set's particle-velocities storage; the step takes cache slots as scratch mid-iteration; the generator forms products IN PLACE over an operand's array (\`ω_consumed\`, \`u_consumed\`). Hunt for: a caller's array mutated without that being part of the contract, two owners writing one buffer in an order that is not enforced, a \`!\` function whose non-leading argument is written, a copy that should exist and does not (or exists and need not). Trace the actual assignment sites, not the docstrings.` },

  { key: 'numerics-and-types', brief: `Numerical correctness and type behaviour. Hunt for: untyped literals promoting a Float32 computation to Float64; integer division or overflow; a tolerance that is absolute where it should be relative; division by a quantity that can be zero; \`≈\` with a default tolerance where the scale makes it meaningless; accumulation order that loses precision; a normalization (1/N, 2κ, the ½ in the kinetic energy, a Parseval factor) applied twice or not at all. The package is Float32/Float64 generic and that genericity is claimed in Observables' module docstring and pinned in test/validation.jl — check the claim holds wherever it is made.` },

  { key: 'api-contracts', brief: `Claims about Base and about GBGPeriodicFields / GBGStreamingStatistics. Hunt for calls whose CORRECTNESS DEPENDS on a semantic detail: does \`similar\` preserve the axes/backend you assume? does \`copyto!\` accept these shapes? does \`mod\` behave as you want at the negative boundary? does \`sum\`/\`maximum\` over a device array do what you think? does a PF operation alias its output with an input, or require them distinct? Do NOT trust your memory of any of these — mark them api-semantics so the reproducer fetches the official documentation and runs them.` },

  { key: 'gpu-and-hot-loop', brief: `The GPU-primary invariant and the allocation-free hot loop. Hunt for: scalar indexing of an array that may be a device array; an allocation inside \`step!\` / \`deposit!\` / \`advect!\` or anything they call; a host-device transfer (a \`sum\` to a scalar, an \`Array(...)\`, a comparison against a host number) inside the per-step path; a broadcast that materializes a temporary; \`Float64\` literals forcing a device kernel to double. Read the actual call chain of one iteration and say where the allocation or the sync happens.` },

  { key: 'edge-cases', brief: `Degenerate and boundary configurations, which are where a solver silently misbehaves. Hunt by ENUMERATING the configuration space and picking the corners: zero tracers; one tracer; a scalar-free run reaching a scalar path; \`NoForcing\`; a forcing band with no content; odd or very small N; \`side_length\` other than 2π; Float32; \`dt\` given explicitly versus adaptive; the first iteration (no history) and the seeding deposit; an out-of-band mutation without the announce. For each, name the call that goes wrong and how.` },

  { key: 'state-machine', brief: `The cache's epoch/staleness state machine and the iteration's ordering contract. Hunt for: a path that reads a slot whose epoch was not set; a producer that writes a slot without recording it; an ordering the code depends on but does not enforce (the tracer advance after the closing deposit; \`prepare!\` before the stages; \`record\` before \`deposit_sample!\`); a counter advanced twice or not at all; a state reachable by a documented public sequence that leaves the cache inconsistent. Follow \`advance!\` line by line and then try to break it from the public API.` },

  { key: 'architecture', brief: `Maintainability, as a code property rather than a taste. Hunt for: THE SAME RULE IMPLEMENTED TWICE (a formula, a coefficient, a band construction, a normalization) where the copies can drift — quote both; a constant repeated as a literal instead of being named once; a near-duplicate function pair differing in one line; dead code and unreachable branches; an abstraction leaked (a caller reaching through a type to internals it should not know); a CLAUDE.md invariant broken in code (physics reimplementing a field or statistics operation that belongs in PF/SS; a resident N³ buffer serving an M×3 need). Every finding needs two locations or an invariant quoted.` },

  { key: 'test-critic', brief: `What the suite does NOT pin, which is where a regression will land. Read test/*.jl against src/*.jl and hunt for: a documented guarantee with no test (search the docstrings for claims — "never", "exactly", "always", "in place", "returns the field's own element type"); a branch no test exercises (a scheme, a dealiasing strategy, a forcing, a code path behind a keyword); a test that would pass even if the function were wrong (asserts a type but not a value, or a value that is trivially true); a property tested only at the default configuration where the constant happens to be 1. Your candidates are "this claim is unpinned and here is the call that would expose it" — those ARE witnessable.` },
]

const ALL_LANES = [...FREE_LANES, ...LANES]
const selected = Array.isArray(A.lanes) && A.lanes.length
  ? ALL_LANES.filter((l, i) => A.lanes.some(x => l.key === String(x) || String(i + 1) === String(x)))
  : ALL_LANES
if (!selected.length) throw new Error(`lanes ${JSON.stringify(A.lanes)} matched none of: ${ALL_LANES.map(l => l.key).join(', ')}`)

// An anchor lane never drops to the cheap model, in any mode.
const laneModel = (lane) => (STRENGTH === 'economy' && !lane.anchor) ? { model: 'sonnet' } : {}

phase('Hunt')

// Each lane's candidates go straight into reproduction — no barrier, so a lane that finishes early
// starts proving while the slower lanes are still reading.
const results = await pipeline(
  selected,

  (lane) => agent(lane.anchor ? `${FREE_PREAMBLE}

WHERE TO START: ${lane.brief}

Return the structured object with lane="${lane.key}".` : `${HUNT_PREAMBLE}

YOUR LANE: ${lane.key}

${lane.brief}

Return the structured object with lane="${lane.key}".`,
    { label: `hunt:${lane.key}`, phase: 'Hunt', schema: CANDIDATE_SCHEMA, agentType: 'general-purpose',
      ...laneModel(lane) }),

  (found, lane) => {
    if (!found || !found.candidates || !found.candidates.length) return { lane: lane.key, verdicts: [], files_read: (found && found.files_read) || [] }
    return parallel(found.candidates.map((c, i) => () =>
      agent(`You are the REPRODUCER for one candidate defect in GBGIsotropicTurbulence (Julia, at ${REPO}). A hunter claims the following. Your job is NOT to agree with it.

  kind:      ${c.kind}
  severity:  ${c.severity}
  title:     ${c.title}
  location:  ${c.file}:${c.line}
  mechanism: ${c.mechanism}
  plan:      ${c.witness_plan}
  ${c.second_location ? 'second location: ' + c.second_location : ''}

THE DEFAULT VERDICT IS "NOT-REPRODUCED". You must earn anything else with evidence a third party could re-run. An unproven bug report costs a fix pass on working code, which is worse than a missed bug, so failing to reproduce is the SAFE outcome and you should return it whenever the evidence is not in your hands.

HOW TO PROVE IT, by kind:

* kind = "runtime" — Write a SELF-CONTAINED Julia file that asserts the CORRECT behaviour and therefore FAILS on the current tree. Use this shape:

      using Test, GBGIsotropicTurbulence     # plus whatever else it needs
      @testset "<the claim, as a sentence>" begin
        # minimal setup — small N, few tracers, fixed rng
        @test <what SHOULD hold>
      end

  Save it to ${PILE}/witnesses/<NN>-<slug>.jl, then RUN it — NOTE THE QUOTES, these paths contain
  spaces and an unquoted cd silently lands you in the wrong directory:
      cd "${REPO}" && julia --project --startup-file=no "${PILE}/witnesses/<NN>-<slug>.jl"
  Read the output. If everything PASSES, the hunter was wrong: verdict NOT-REPRODUCED — do not
  rescue the candidate by weakening the assertion until it fails, which proves nothing but your
  persistence.

  A FAILING TEST IS NECESSARY AND NOT SUFFICIENT, and this is the step most likely to be skipped.
  A witness can fail because the WITNESS is wrong: a test asserting a false identity fails on
  perfectly correct code, and adopting it aims a fix pass at working code — the exact harm the
  witness rule exists to prevent, arrived at by the route that feels most rigorous. So before
  returning REPRODUCED, DERIVE THE EXPECTED VALUE INDEPENDENTLY of the assertion you just wrote:
  from the documented contract, from an analytic case you can evaluate by hand, from a
  mathematical identity the operation must satisfy, or from a second route to the same quantity.
  State that derivation in `observed`. If the independent derivation agrees with the CODE rather
  than with your assertion, the verdict is WITNESS-WRONG — say what the correct expectation is and
  why the witness encoded a different one. That is a clean outcome, not a failure; it is also the
  only verdict that protects working code from a confident test.
  (The `api-semantics` branch below already works this way — official documentation must agree with
  the run before REPRODUCED. This paragraph extends the same requirement to `runtime`, where the
  oracle is a derivation rather than a document.)

  Keep the file: on REPRODUCED it becomes the regression test, so it must assert the RIGHT behaviour
  rather than merely exhibit the wrong one.

* kind = "api-semantics" — Do BOTH, in this order. (1) Fetch the OFFICIAL documentation for the
  function — docs.julialang.org for Base, the package's own docs for a dependency — and quote the
  sentence that settles it, with the URL. Your memory of Base semantics is not evidence and is
  frequently wrong. (2) Then write and run a witness as above. Verdict REPRODUCED only if the
  documentation and the run agree that the code is wrong.

* kind = "architecture" — No program can fail on this, so the evidence is textual and must be
  DIFFABLE: read BOTH locations, quote the two blocks, and state precisely what a maintainer would
  have to change in both places and what happens if they change only one. Verdict EVIDENCED if the
  duplication/divergence/violation is real and you have both quotes; NOT-A-DEFECT if the second site
  turns out to differ for a reason, or if there is no second site. Do not file an architecture
  finding whose consequence is "it is untidy".

If the claim is real but no program can distinguish it (a latent hazard nothing currently reaches),
return NO-WITNESS-POSSIBLE and say what would have to change for it to bite. That is an honest
outcome and is reported separately — it is not a bug.

Number your witness ${String(i + 1).padStart(2, '0')} within lane "${lane.key}", i.e. use the slug
"${ROUND}${lane.key}-${String(i + 1).padStart(2, '0')}". The round prefix is not decoration: every
round numbers its lanes from 01, so without it a later round's still-failing witness OVERWRITES an
earlier round's passing regression test of the same name — which destroys the older test and makes
the suite fail for what looks like a bad fix.

OUTPUT: the structured object. \`observed\` must contain the ACTUAL evidence — the failing @test line
as printed, or the two quoted blocks — not a description of it.`,
        { label: `repro:${lane.key}-${i + 1}`, phase: 'Reproduce', schema: VERDICT_SCHEMA, agentType: 'general-purpose' })
        .then(v => ({ ...v, lane: lane.key, candidate: c }))))
      .then(vs => ({ lane: lane.key, files_read: found.files_read || [], verdicts: vs.filter(Boolean) }))
  },
)

// ── Reporting. A lane that died must not read as a lane that found nothing. ──────────────────────
const anomalies = []
const all = []
for (let i = 0; i < selected.length; i++) {
  const r = results[i]
  if (!r) { anomalies.push(`${selected[i].key}: DEAD — no result`); continue }
  all.push(r)
}

const tally = {}
for (const r of all) for (const v of r.verdicts) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (const r of all) {
  const c = {}
  for (const v of r.verdicts) c[v.verdict] = (c[v.verdict] || 0) + 1
  log(`${r.lane}: ${r.verdicts.length} candidates → ${JSON.stringify(c)}  (${(r.files_read || []).length} files read)`)
}
log(`TOTAL: ${JSON.stringify(tally)}`)

const confirmed = all.flatMap(r => r.verdicts.filter(v => v.verdict === 'REPRODUCED' || v.verdict === 'EVIDENCED'))
log(`CONFIRMED (witnessed or evidenced): ${confirmed.length}`)
for (const v of confirmed) log(`   [${v.severity || '?'}] ${v.title}`)

if (anomalies.length) {
  log(`!! ${anomalies.length} ANOMALY(S) — the hunt is INCOMPLETE, do not read the tally as a clean sweep:`)
  for (const a of anomalies) log(`   !! ${a}`)
}

return {
  tally, anomalies, complete: anomalies.length === 0,
  lanes_run: selected.map(l => l.key),
  files_read: [...new Set(all.flatMap(r => r.files_read || []))],
  confirmed, results: all,
}

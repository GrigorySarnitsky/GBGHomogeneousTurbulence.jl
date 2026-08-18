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
//
// KEEP THIS LIST IN STEP WITH panel.js. The script cannot read the pile directory (no filesystem in
// a workflow script), so a hat added to the panel and NOT added here is banked, fixed, and never
// verified — silently, because the run still reports success over the hats it does know. That is
// exactly the accounting failure this instrument exists to catch: on 2026-08-18 the list still held
// the original 11 while the panel banked 15, leaving four hats' findings unaudited.
const ALL_HATS = [
  '01-consistency-matrix', '02-software-architect', '03-turbulence-theoretician',
  '04-dns-practitioner', '05-structure-consistency', '06-latex-typesetter',
  '07-api-user', '08-dimensional', '09-citations-integrity', '10-style-editor',
  '11-cold-reader', '12-plain-sense', '13-naming-policy', '14-doc-policy',
  '15-invariants-and-decisions',
]

// `hats` runs a SUBSET (by name or by numeric prefix). Its purpose is re-running the hats that died
// — the whole panel once came back rate-limited, 11 agents launched at once — so a retry need not
// re-pay for the verdicts already banked. Omit it to verify everything.
// Accept every spelling a caller actually uses: the banked name ('06-latex-typesetter'), the bare
// key the panel logs and a person says ('latex-typesetter'), and the number padded or not (6, '06').
const matches = (hat, sel) => {
  const x = String(sel)
  return hat === x || hat.endsWith('-' + x) || hat.startsWith(x.padStart(2, '0') + '-')
}
const HATS = Array.isArray(A.hats) && A.hats.length
  ? ALL_HATS.filter(h => A.hats.some(x => matches(h, x)))
  : ALL_HATS

// A selector that matches nothing would run zero agents and report a clean empty tally — the same
// silent-success shape as the stale hat list this argument was added to work around. Every selector
// must hit, not just one of them: `hats: ['12', 'cold-readr']` should fail, not quietly run one hat.
if (Array.isArray(A.hats) && A.hats.length) {
  const unmatched = A.hats.filter(x => !ALL_HATS.some(h => matches(h, x)))
  if (unmatched.length) {
    throw new Error(`hats selector(s) ${JSON.stringify(unmatched)} matched no hat. Known: ${ALL_HATS.join(', ')}`)
  }
}
if (!HATS.length) throw new Error('no hats selected')

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    hat: { type: 'string' },
    findings_in_file: { type: 'integer', description: 'how many findings the banked hat file contains, counted by enumerating it — NOT how many you adjudicated' },
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
  required: ['hat', 'findings_in_file', 'verdicts'],
}

const PREAMBLE = `You are an ADVERSARIAL CLOSURE AUDITOR for GBGIsotropicTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence (velocity field and passive scalar on a triple-periodic box, integrating-factor time-stepping, pluggable forcing and dealiasing, a deposit-driven observables cache, Lagrangian tracers).

Some time ago an expert panel audited this package's documentation and banked its findings. A fix pass then ran. YOUR JOB IS NOT TO REVIEW THE FIX PASS — you are deliberately not shown it, and you must not go looking for it.

BLINDNESS — THE ONE RULE THAT MAKES THIS AUDIT WORTH RUNNING. Read exactly ONE file under \`.claude/\`: your own banked hat file, named below. Everything else under \`.claude/\` is FORBIDDEN — every other hat's file, 00-SUMMARY.md, the fix-audit and doc-reading piles, and above all ANY \`closure\` directory (\`closure/\`, \`closure-r1/\`, \`closure-r2/\`, …), which hold PREVIOUS ROUNDS' VERDICTS ON THE FINDINGS YOU ARE ADJUDICATING RIGHT NOW. They are the answer key. Reading one — or letting one surface in a search result and using it — converts this audit into a copy of the last one, which is precisely the failure it exists to prevent. Also forbidden: git log, git diff, and commit messages.

THIS BITES THROUGH SEARCHES, NOT JUST READS. The findings pile lives INSIDE the repository, so a repo-wide grep sweeps the answer key into your results without your asking. Scope every search to the corpus under audit — \`src/\`, \`docs/src/\`, \`docs/ARCHITECTURE.md\`, \`docs/build/\`, \`CLAUDE.md\` — and never search \`.claude/\` (with ripgrep: \`rg --glob '!.claude/**'\`). If a forbidden file appears in output anyway, disregard its content and say so in your evidence rather than relying on it. Your job is to answer ONE question per banked finding, from the CURRENT corpus alone:

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
- Return \`findings_in_file\` = how many findings that file CONTAINS (the count you enumerated), independently of how many you managed to adjudicate. The two are cross-checked: reporting a count that matches your verdict list when it does not match the file defeats the check and is the one thing you must not do. If you genuinely cannot adjudicate one, return PRESENT for it with the reason as evidence — that is the safe verdict — rather than dropping it.
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

// ANOMALY DETECTION. A tally is only trustworthy if every hat actually ran and actually adjudicated
// its whole file, and until 2026-08-18 neither was checked — the script accepted whatever came back.
// The rule "a per-hat count of zero means a DEAD AGENT, not a clean hat" is implemented here rather
// than left to whoever reads the output, because a reader applying it by eye gets it wrong in BOTH
// directions: on 2026-08-18 an all-ABSENT hat was misread as a dead agent (the reader's own filter
// hid the verdicts), and the rate-limited run before it had eleven genuinely dead agents whose only
// signal was an empty tally. Neither judgement should be a human's to make from the output alone.
const anomalies = []
const all = []
for (let i = 0; i < HATS.length; i++) {
  const hat = HATS[i]
  const r = results[i]
  if (!r) { anomalies.push({ hat, kind: 'DEAD', detail: 'agent returned nothing (died, or was skipped)' }); continue }
  const n = (r.verdicts || []).length
  const expected = r.findings_in_file
  if (n === 0) anomalies.push({ hat, kind: 'EMPTY', detail: 'returned zero verdicts — a dead agent, not a clean hat' })
  else if (typeof expected === 'number' && n < expected) {
    anomalies.push({ hat, kind: 'INCOMPLETE', detail: `adjudicated ${n} of ${expected} banked findings` })
  }
  all.push(r)
}

const tally = {}
for (const r of all) for (const v of (r.verdicts || [])) tally[v.verdict] = (tally[v.verdict] || 0) + 1
for (let i = 0; i < HATS.length; i++) {
  const r = results[i]
  if (!r) { log(`[${i + 1}/${HATS.length}] ${HATS[i]}: DEAD — no result returned`); continue }
  const c = {}
  for (const v of (r.verdicts || [])) c[v.verdict] = (c[v.verdict] || 0) + 1
  const cov = typeof r.findings_in_file === 'number' ? `${(r.verdicts || []).length}/${r.findings_in_file}` : `${(r.verdicts || []).length}/?`
  log(`[${i + 1}/${HATS.length}] ${HATS[i]}: ${cov} adjudicated — ${JSON.stringify(c)}`)
}
log(`TOTAL: ${JSON.stringify(tally)}`)

// The headline the caller must not be able to miss. A run with anomalies has NOT verified what its
// tally appears to claim, and the tally must not be read as a closure rate until they are resolved.
if (anomalies.length) {
  log(`!! ${anomalies.length} ANOMALY(S) — THE TALLY IS INCOMPLETE, DO NOT READ IT AS A CLOSURE RATE:`)
  for (const a of anomalies) log(`   !! ${a.hat}: ${a.kind} — ${a.detail}`)
} else {
  log(`every hat ran and adjudicated its whole banked file (${HATS.length} hats)`)
}

// `hats_run` lets the caller check the closure/ directory against what was actually attempted:
// the agents are told to Write their verdict files, and nothing inside a workflow script can see
// the filesystem to confirm they did.
return { tally, anomalies, hats_run: HATS, complete: anomalies.length === 0, results: all }

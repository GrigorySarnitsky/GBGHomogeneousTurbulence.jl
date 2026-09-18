// /check-docs review lanes — the judgment half of the battery, fanned out per surface plus the two
// cross-cutting lanes the surface agents structurally cannot run.
//
// Args: { repo, strength }   strength: 'economy' (DEFAULT, Sonnet lanes) | 'full'
//
// The deterministic scans run in the main thread before this; these lanes carry checks 1-6 as
// POSITIVE procedures (enumerate, then verify each item) and check 7 / check 2's audience half in
// the family and cold-reader lanes. Collect-only: every finding is closed by the main thread, at
// full strength, in the same run.
export const meta = {
  name: 'check-docs-lanes',
  description: 'The judgment lanes of /check-docs: per-surface checks 1-6 plus the family and cold-reader lanes',
  phases: [ { title: 'Lanes' } ],
}

const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const REPO = A.repo
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    lane: { type: 'string' },
    findings: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        check: { type: 'string', enum: ['correct','self-contained','notation','formatted','current','cited','family','cold-read'] },
        severity: { type: 'string', enum: ['blocker','major','minor','nit'] },
        location: { type: 'string', description: 'file:line' },
        quote: { type: 'string', description: 'the decisive text, <= 25 words' },
        problem: { type: 'string' },
        fix: { type: 'string' },
      },
      required: ['check','severity','location','quote','problem','fix'],
    } },
  },
  required: ['lane','findings'],
}

const PREAMBLE = `You audit the documentation of GBGHomogeneousTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence (one velocity field and one passive scalar on a triple-periodic box, integrating-factor time-stepping, pluggable forcing and dealiasing, a deposit-driven observables cache, Lagrangian particle tracking).

THE RULEBOOK IS ${REPO}/CLAUDE.md — read its "Documentation policy", "Style" and "Doc-edit checklist" sections FIRST and treat them as authoritative. GROUND TRUTH IS ${REPO}/src — verify every claim against the code and quote the decisive line.

RUN EACH CHECK AS A POSITIVE PROCEDURE: enumerate the items, then verify each one. A defect that is absent-by-omission — an unbound symbol, a false-but-plausible formula, an argument that is never documented — does not announce itself on a read-through, so passive reading is NOT a check.

The checks:
1. CORRECT — every formula, normalization (the 1/N, the 2*varkappa, the 1/2 in the kinetic energy, Parseval/spectral factors), conservation or adjoint relation, and quantifier (exact/all/never) true and precise; the diagnostic consistent with the physical quantity it claims to measure; and free of CATEGORY/TYPE ERRORS — a field vs its representation, an operator vs its parameter, a rate vs its time-integral, a diagnostic scalar vs the field it reduces, a per-wavenumber density vs an energy. Type every object from the code.
2. SELF-CONTAINED — every symbol bound at first use (or in notation.md); every signature argument documented, enumerated FROM THE SIGNATURE; a term of art explained or linked.
3. NOTATION — one symbol per concept and one concept per symbol; the house glyphs (bold-italic vectors, the kappa/k/varkappa set, varphi, coordinate-subscripted partials, upright imaginary unit); math variables symbolic, storage descriptive.
4. FORMATTED — math is LaTeX never backticks; every code identifier backticked never bare; no code name inside a math span; no formula split across a math/code boundary.
5. CURRENT & COMPLETE — every claim matches the code's PRESENT state. A docstring that names only a SUBSET of what the code now provides is stale even if literally true. This corpus was just through a large rename (integrator->scheme, *_stamp->*_epoch, dealias!->truncate_to_band!, sample!->interpolate_at_particles!, Tracers' scheme->interpolation_scheme, velocity/scalar->*_spectral, cache slots->*_physical) and several signature changes, so weight this check heavily.
6. CITED — author-year consistent, matching the ARCHITECTURE.md References entry; no inaccessible source. The Phenomenology leaf is exempt (self-contained Reference values).

OUTPUT: report only GENUINE findings, each with file:line, the decisive quote (<= 25 words) and a concrete fix. Do NOT report style preferences, and do NOT report things the rulebook explicitly permits. Cap at your 20 most significant. If a surface is clean, return an empty findings list — that is a real and useful result.`

const lanes = [
  { key: 'architecture', substrate: `${REPO}/docs/ARCHITECTURE.md — every section AND its References list. NOTE: §11's decision log is APPEND-ONLY HISTORY; an old entry naming a superseded API records what was decided then, so only the current-state sections (§1-§10) must match today's code. Entries dated 2026-08 are recent and in scope for correctness.` },

  { key: 'src-core', substrate: `The docstrings in ${REPO}/src/SimulationDomain.jl, ${REPO}/src/State.jl, ${REPO}/src/Observables.jl and ${REPO}/src/Cache.jl (module AND function/type docstrings; plain # comments are NOT rendered and are exempt).` },

  { key: 'src-dynamics', substrate: `The docstrings in ${REPO}/src/Forcing.jl, ${REPO}/src/Generator.jl, ${REPO}/src/Propagator.jl and ${REPO}/src/Particles.jl (module AND function/type docstrings; plain # comments are exempt).` },

  { key: 'src-run', substrate: `The docstrings in ${REPO}/src/SimulationRun.jl and the umbrella ${REPO}/src/GBGHomogeneousTurbulence.jl (module AND function/type docstrings; plain # comments are exempt).` },

  { key: 'src-phenomenology', substrate: `The docstrings in ${REPO}/src/Phenomenology.jl and ${REPO}/src/phenomenology/*.jl (Spectra, StructureFunctions, Scalings). This is an extraction-bound leaf: it carries its own self-contained Reference values by design and is EXEMPT from the ARCHITECTURE References cross-check, so judge its citations for well-formedness and resolvability instead.` },

  { key: 'pages', substrate: `The hand-written pages ${REPO}/docs/src/index.md, notation.md, api.md, observables_cache.md and ${REPO}/docs/src/api/*.md plus ${REPO}/docs/src/api/phenomenology/*.md. Judge the hand-written prose and the @docs groupings; SKIP the @autodocs/@example/@repl/@index blocks themselves. Do NOT read docs/src/architecture.md — it is a generated copy.` },

  { key: 'family', persona: `YOUR LANE IS CHECK 7, WHICH NO PER-SURFACE AGENT CAN RUN because its grouping is relational rather than per-file. Enumerate every f / f! pair and every getter / set_...! pair across ${REPO}/src/*.jl, then verify for EACH pair: the two share ONE HOME for the formula (the in-place ! form owns it and is listed first), the other is a thin @ref-linking wrapper with NO second copy of the formula, and NO NOTATION DRIFTS across the pair (partial-derivative spelling, vector boldness, symbol choice). Report a pair whose formula is duplicated, whose home is the wrong member, or whose notation differs between the two.`,
    substrate: `${REPO}/src/*.jl and ${REPO}/src/phenomenology/*.jl` },

  { key: 'cold-reader', persona: `YOUR LANE IS CHECK 2's AUDIENCE HALF. You are a first-year turbulence graduate student — comfortable with Fourier methods and Julia, NEW to this package — reading the exported docstrings as a REPL user meets them (?name), with the design docs withheld. Flag every symbol, term of art, or package concept used before it is defined or never defined anywhere: an epoch, a slot, a deposit, an observation, an iteration vs a step vs a stage, a register, a scheme, an integrating factor. HUNT ESPECIALLY ORDINARY ENGLISH WORDS CARRYING PACKAGE-SPECIFIC MEANINGS — a register, an advance, a record, something armed, a front door — because they read as plain prose and never trip an undefined-symbol check: you understand the English and silently supply the wrong referent. Your read is ORDERED: report where you FIRST meet a term, since a gloss on a later page does not close a bare use on an earlier one. VERIFY each finding against the source before reporting: a term may be defined on the module docstring or a sibling method you did not open.`,
    substrate: `${REPO}/src/*.jl — read the MODULE docstring of each module as well as every exported function and type docstring, since that is what a REPL reader actually sees.` },
]

phase('Lanes')
const results = await parallel(lanes.map((l, i) => () =>
  agent(`${PREAMBLE}

YOUR LANE: ${l.key}
${l.persona ? '\n' + l.persona + '\n' : ''}
SURFACE TO AUDIT (read it fully):
${l.substrate}

Return the structured object with lane="${l.key}".`,
    { label: l.key, phase: 'Lanes', schema: SCHEMA, agentType: 'general-purpose',
      ...(STRENGTH === 'economy' ? { model: 'sonnet' } : {}) })))

const all = results.filter(Boolean)
for (const r of all) log(`${r.lane}: ${(r.findings || []).length} findings`)
log(`TOTAL: ${all.reduce((n, r) => n + (r.findings || []).length, 0)}`)
return { results: all }

// /check-consistency panel — a fresh-eyed 11-expert audit of the RENDERED docs, sequential & collect-only.
// Args (absolute paths): { full, siteonly, rawhtml, pile }
//   full     — manuscript of every page incl. Architecture (for most hats).
//   siteonly — manuscript with Architecture withheld (for the two no-architecture hats).
//   rawhtml  — docs/build (the style-editor also inspects the raw HTML for silent-render failures).
//   pile     — .claude/doc-review (each hat Writes NN-<key>.md here).
// Each hat reads ONLY its manuscript (no src/, no CLAUDE.md), banks a findings file, and returns a
// structured object. Sequential: a token-out loses at most the current hat, so hats are in PRIORITY order.
export const meta = {
  name: 'check-consistency-panel',
  description: 'Fresh-eyed 11-expert panel auditing the RENDERED docs for consistency, physics, typesetting, structure & design (sequential, collect-only)',
  phases: [ { title: 'Panel' } ],
}

const FULL = args.full
const SITEONLY = args.siteonly
const RAWHTML = args.rawhtml
const PILE = args.pile

const SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    hat: { type: 'string' },
    findings: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      properties: {
        type: { type: 'string', enum: ['contradiction','physics','method','performance','format','typesetting','organization','design','language-tone','clarity','api-gap','citation','dimensional','other'] },
        severity: { type: 'string', enum: ['blocker','major','minor','nit'] },
        confidence: { type: 'string', enum: ['high','medium','low'] },
        title: { type: 'string' },
        locations: { type: 'array', items: { type: 'string' }, description: 'page/section + the exact quoted rendered text' },
        contradicts: { type: 'string', description: 'for a contradiction: the OTHER location + its quote + the axis; else empty' },
        description: { type: 'string' },
        resolution_hint: { type: 'string', description: 'advisory only — we decide later' },
      },
      required: ['type','severity','confidence','title','locations','description'],
    } },
  },
  required: ['hat','findings'],
}

const PREAMBLE = `You are a fresh-eyed reviewer on an expert panel auditing the RENDERED documentation of GBGIsotropicTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence (one velocity field u and one passive scalar phi on a triple-periodic box; integrating-factor time-stepping; pluggable forcing and dealiasing; Lagrangian particles; forthcoming Eulerian + Lagrangian statistics). The document you are given is a faithful reader-text consolidation of the rendered HTML site (math is shown as its TeX; each page is delimited by a "PAGE:" banner).

RULES:
- Read ONLY the document(s) named below. Do NOT open src/, tests, CLAUDE.md, memory, or anything else — you judge the docs AS WRITTEN, from your own expertise.
- COLLECT findings only. Do NOT edit anything and do NOT apply fixes.
- A PRIMARY goal is INTERNAL CONSISTENCY: flag anything defined, stated, valued, or formatted one way in one place and DIFFERENTLY in a similar place. Cross-reference relentlessly across every page you are given.
- ALSO flag anything that contradicts your expert knowledge or instinct ("this smells wrong").
- EVERY finding needs EVIDENCE: quote the exact rendered text and name the page (the "PAGE:" banner) + section. For a contradiction, quote BOTH sides and name the axis of disagreement.
- Severity: blocker (wrong/misleading) / major / minor / nit. Confidence: high / medium / low — a marked-low suspicion is welcome; do not inflate.
- resolution_hint is optional and advisory only.
- NOTE: report what you actually see NOW in the document, not what you might expect from a prior version.`

// PRIORITY order (most important first): a token-out truncates the tail, i.e. the least-critical lens.
const hats = [
  { key: 'consistency-matrix', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a systematic CONSISTENCY AUDITOR — the spine of this panel. Build a MATRIX of every recurring entity and diff it across ALL pages: each physical quantity (symbol, defining formula, normalization, units, code name), each notation convention, each numerical method / constant / claim, and the docstring structure itself. For EACH entity, collect every page's version, then flag divergences. Be exhaustive about "the same thing, stated differently in two places", including site<->Architecture-page disagreements.` },

  { key: 'software-architect', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a SOFTWARE ARCHITECT and senior Julia programmer reviewing the DOCUMENTED design — the API pages and the Architecture page (its rationale, invariants, decision log). Judge the design as a Julia expert would, from the docs as written: are the documented signatures idiomatic Julia (argument order, positional vs keyword, multiple dispatch, the f/f! in-place convention, return types, naming); is the type and module decomposition coherent and each abstraction earned (no premature generality, no leaky abstraction, the single-source-of-truth respected); does the documented interface compose cleanly, hide its internals, and match what a Julia user expects (constructors, immutability, the claimed allocation discipline); are there over- or under-abstractions, god-objects, or coupling smells visible in the documented design; is the decision log's rationale sound and internally consistent (no decision contradicting another or the current API)? Flag design / API / architecture concerns and any place the documented design fights itself or good Julia practice. (You judge the docs as written; a separate code-level pass would read the source.)` },

  { key: 'turbulence-theoretician', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a TURBULENCE THEORETICIAN. Check every physical definition, conservation law, scaling law, dimensionless constant, and relation against established theory AND against itself across pages: kinetic energy (1/2)<|u|^2>, dissipation eps = nu<|omega|^2>, scalar variance and scalar dissipation 2*kappa_phi<|grad phi|^2>, energy vs spectrum split E(kappa), Re = 1/nu vs measured Re_lambda, derivative skewness S ~ -0.5, the Kolmogorov constant, the integral scales L11/L22/L_E, and the derived scales (eta, tau_eta, lambda). Flag fishy physics and any quantity defined or valued two ways.` },

  { key: 'dns-practitioner', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a PERFORMANCE-FOCUSED DNS PRACTITIONER who writes and optimizes pseudospectral codes. Scrutinize the numerical methods (rotational form, exact integrating factor, dealiasing strategies and retained bands, IF-RK2 and low-storage RK3, per-scheme buffers, particle interpolation, forcing) and the performance claims (allocation-free hot loop, in-place, GPU-agnostic AbstractArray storage, minimal footprint, per-scheme exact allocation, CFL scaling, the "2x transforms" cost of phase-shift). ESPECIALLY verify the dealias band is stated consistently everywhere (2/3 vs sqrt(2)N/3 vs a fraction of Nyquist — these must agree). Flag method errors, performance overclaims, and any cross-page method disagreement.` },

  { key: 'structure-consistency', substrate: `The rendered user-facing site, Architecture page EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a DOCUMENTATION-STRUCTURE auditor, and you do NOT see the Architecture page — you judge the user-facing docstrings and API pages purely on the UNIFORMITY of their logical organization. FIRST, infer the implicit template the corpus follows and STATE it: the standard skeleton of a function docstring (e.g. identity sentence -> when-to-use -> each argument -> caveats -> formula -> citation) and of a type docstring (constructor-first: identity -> constructor+arguments -> example -> a demoted # Fields). THEN flag every OUTLIER against that inferred template: a docstring whose sections run in a different order, one missing a section its siblings have (or carrying one they don't), reference detail mixed into the opening sentence, a formula placed before the identity, an f/f! pair organized differently across its two docstrings, a # Fields section present on some types but absent on others, an arguments block enumerated differently from its peers, inconsistent admonition use (!!! note/warning). You care about the SHAPE and ORDER of the exposition, not its physics or wording — is the whole corpus written to ONE consistent organizing principle, and which entries break it?` },

  { key: 'latex-typesetter', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a LaTeX and mathematical-TYPESETTING expert. Scrutinize every rendered formula for typesetting quality against LaTeX best practice and the intended mechanisms — NOT the physics or normalization (other hats own those), the typesetting itself. The TeX is shown verbatim in the consolidation, so read it as source, and be LITERAL and EXHAUSTIVE about idiom (a reader hat tends to gloss these). Flag: named operators/functions set as italic letter-products instead of their upright command (det, tr, sym, sin, cos, exp, log, max, min, sup should be \\det, \\operatorname{tr}, \\sin, ... not a product d·e·t); a differential d not upright (\\mathrm{d}) and lacking its thin space in integrals/derivatives; EVERY gratuitous thin space \\, that is NOT before a differential (a \\, between two factors, e.g. C_K\\,\\varepsilon, is unwanted — juxtaposition is standard); multi-letter identifiers set as a product of italics (should be one \\mathrm/\\text token); an unbraced group argument (\\tfrac45 should be \\tfrac{4}{5}; \\boldsymbol u should be \\boldsymbol{u}); delimiters not sized to content (\\left…\\right or \\bigl where a tall fraction, integral, or matrix sits inside); sub/superscripts spanning more than one token without {} grouping; a tall construction set inline where it should be display (or vice versa); multi-line equations not aligned at the = / operator; vectors/tensors bolded via the wrong command or inconsistently; stray, missing, or mismatched braces; inconsistent spacing (\\,\\;\\quad). Judge each formula as a professional typesetter: correct idiomatic LaTeX, or an approximation that merely looks right?` },

  { key: 'api-user', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a PHYSICIST-PROGRAMMER trying to USE this library from the docs alone. Check: every public type's constructor and all its arguments/defaults are documented; every function's positional AND keyword arguments appear in its body (an arg mentioned only inside a formula is undocumented); return shapes/types are clear; examples are correct and mutually consistent; and the public surface agrees (nothing exported-but-undocumented or documented-but-not-exported, and the api-map one-liner matches each operation's own docstring). Flag API-doc gaps and drift.` },

  { key: 'dimensional', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a DIMENSIONAL-ANALYSIS & NORMALIZATION specialist. Mechanically verify every formula is dimensionally consistent and every normalization factor is correct AND identical across pages: the 1/2 in kinetic energy, the 2*kappa_phi in scalar dissipation, transform 1/N factors, Parseval / spectral factors, the spectrum halving, the L11/L22/L_E relations, and the integrating-factor exponent. Flag any dimensional slip or a normalization that differs between two places.` },

  { key: 'citations-integrity', substrate: `The whole rendered site incl. Architecture: ${FULL}`,
    persona: `You are a SCIENTIFIC-INTEGRITY & CITATIONS auditor. Check every named or published method carries a consistent author-year citation; that references agree across pages (same work cited the same way) and every inline cite has a matching References entry (and vice-versa); that no inaccessible or private source is cited on a user-facing surface; and that nothing overclaims ("exact", "optimal", "allocation-free", "the largest/first") beyond what the docs substantiate. Flag citation inconsistencies and overclaims.` },

  { key: 'style-editor', substrate: `The whole rendered site incl. Architecture: ${FULL}\n\nAlso inspect the RAW built HTML under: ${RAWHTML}`,
    persona: `You are a TECHNICAL COPY-EDITOR enforcing INTERNAL uniformity — derive the norm from the corpus itself (majority style), not an external guide. Check uniform notation rendering (bold vectors, upright imaginary unit, subscripted partials, phi for the scalar), ONE docstring skeleton, constructor-first type docstrings, uniform heading levels / tables / citation format, one neutral register and voice. You ALSO have the raw built HTML: inspect it for SILENT rendering failures — math that rendered wrong, a cross-reference that rendered as dead/plain text, formulas split across spans, horizontal-scroll or layout breakage. Flag anything where one part looks or reads differently from a similar part.` },

  { key: 'cold-reader', substrate: `The rendered user-facing site, Architecture page EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a FIRST-YEAR TURBULENCE GRAD STUDENT reading these user docs top-to-bottom for the first time. You do NOT know the codebase. Flag every symbol, term of art, or package concept used before it is defined (or never defined anywhere); every argument mentioned only inside a formula; every leap that assumes insider knowledge. A term used consistently but never introduced is STILL a defect. Judge self-containedness — the "cold read".` },
]

phase('Panel')
const results = []
for (let i = 0; i < hats.length; i++) {
  const h = hats[i]
  const nn = String(i + 1).padStart(2, '0')
  const prompt = `${PREAMBLE}

YOUR HAT:
${h.persona}

DOCUMENT(S) TO READ (read fully, with the Read tool; nothing else):
${h.substrate}

When your review is complete, FIRST use the Write tool to save your findings as readable markdown to:
  ${PILE}/${nn}-${h.key}.md
(a title line naming your hat, then one clearly-formatted section per finding: type / severity / confidence / locations-with-quotes / contradicts / description). THEN return the structured object with hat="${h.key}".`
  const r = await agent(prompt, { label: h.key, phase: 'Panel', schema: SCHEMA, agentType: 'general-purpose' })
  results.push(r)
  log(`[${nn}/${hats.length}] ${h.key}: ${r && r.findings ? r.findings.length : 0} findings -> ${nn}-${h.key}.md`)
}
return { results }

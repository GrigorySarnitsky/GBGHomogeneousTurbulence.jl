// /check-consistency panel — a fresh-eyed 15-expert audit of the RENDERED docs, sequential & collect-only.
// Args (absolute paths): { full, siteonly, rawhtml, pile, adjudicated, strength }
//   strength — 'economy' (DEFAULT: twelve hats on the cheap scan model; the two physics hats and
//              plain-sense anchored at the session model) | 'full' (every hat at the session model, on explicit request
//              only). The main-thread verification/consolidation that follows the panel is never
//              economized — same policy as /check-docs (ported from PF, 2026-08-06).
//   full     — manuscript of every page incl. the design docs (for most hats).
//   siteonly — manuscript with the design docs (Architecture + the observables-cache page) withheld
//              (for the two no-design-doc hats).
//   rawhtml  — docs/build (the style-editor also inspects the raw HTML for silent-render failures).
//   pile     — .claude/doc-review (each hat Writes NN-<key>.md here).
// Each hat reads ONLY its manuscript (no src/, no CLAUDE.md), banks a findings file, and returns a
// structured object — EXCEPT latex-typesetter, which ALSO reads the authored source (src/, docs/)
// and the CLAUDE.md house rulebook, since typesetting idiom lives in the source markup, not the
// rendered output. REPO (derived from rawhtml) gives that one hat the repo root. Sequential: a
// token-out loses at most the current hat, so hats are in PRIORITY order.
export const meta = {
  name: 'check-consistency-panel',
  description: 'Fresh-eyed 15-expert panel auditing the RENDERED docs for consistency, physics, typesetting, structure & design (sequential, collect-only)',
  phases: [ { title: 'Panel' } ],
}

// args may arrive as a JSON string rather than an object (a Workflow-invocation quirk) — parse
// defensively, otherwise every ${…} path below interpolates to "undefined" and the hats fall back
// to their scratchpad.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const STRENGTH = A.strength === 'full' ? 'full' : 'economy'
const FULL = A.full
const SITEONLY = A.siteonly
const RAWHTML = A.rawhtml
const PILE = A.pile
// Absolute path to the do-not-re-flag list (findings settled as NOT defects: extraction artifacts
// and user-closed design decisions). A hat is blind to prior rounds by design — that blindness is
// what makes it fresh-eyed (PF's round 2 caught a false sentence round 1's fix pass had introduced).
// But it also makes a hat re-litigate settled non-defects every round; this file, and ONLY this
// file, is the exception. Fixed findings are deliberately NOT listed: re-flagging a bad fix is the
// panel's whole value.
const ADJUDICATED = A.adjudicated
// The latex-typesetter hat reads the authored source; derive the repo root from rawhtml ($REPO/docs/build).
let REPO = RAWHTML || '.'
while (REPO.endsWith('/')) REPO = REPO.slice(0, -1)
if (REPO.endsWith('/docs/build')) REPO = REPO.slice(0, -('/docs/build'.length))

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

const PREAMBLE = `You are a fresh-eyed reviewer on an expert panel auditing the RENDERED documentation of GBGIsotropicTurbulence — a GPU-primary pseudospectral DNS of homogeneous isotropic turbulence: one velocity field u and one passive scalar phi on a triple-periodic box; integrating-factor time-stepping (low-storage RK3 / Heun RK2); pluggable forcing and dealiasing (the 2/3 and Hou-Li masks, the phase-shift average); a deposit-driven observables cache (a read serves the deposited boundary value or throws — nothing is recomputed on a read); an observation-first run loop (the callback observes every boundary and its return decides continuation); Lagrangian tracer particles; forthcoming Eulerian + Lagrangian statistics. The document you are given is a faithful reader-text consolidation of the rendered HTML site (math is shown as its TeX; each page is delimited by a "PAGE:" banner).

RULES:
- Read ONLY the document(s) named below in YOUR HAT's substrate. Unless your substrate EXPLICITLY grants it, do NOT open src/, tests, CLAUDE.md, memory, or anything else — you judge the docs AS WRITTEN, from your own expertise. (The ONE exception is the latex-typesetter hat, whose substrate grants the authored source and the CLAUDE.md house rulebook — typesetting idiom lives in the source markup, not the rendered output.)
- COLLECT findings only. Do NOT edit anything and do NOT apply fixes.
- A PRIMARY goal is INTERNAL CONSISTENCY: flag anything defined, stated, valued, or formatted one way in one place and DIFFERENTLY in a similar place. Cross-reference relentlessly across every page you are given.
- ALSO flag anything that contradicts your expert knowledge or instinct ("this smells wrong").
- EVERY finding needs EVIDENCE: quote the exact rendered text and name the page (the "PAGE:" banner) + section. For a contradiction, quote BOTH sides and name the axis of disagreement.
- Severity: blocker (wrong/misleading) / major / minor / nit. Confidence: high / medium / low — a marked-low suspicion is welcome; do not inflate.
- resolution_hint is optional and advisory only.
${ADJUDICATED ? `- ALREADY ADJUDICATED — READ FIRST: \`${ADJUDICATED}\`. Read that file before you begin. It lists findings this panel raised in a previous round that were settled as NOT defects — extraction artifacts of the manuscript you are reading, and design decisions the package owner closed deliberately. Do NOT spend a finding on anything it covers. It does NOT list previously-FIXED items, so everything else in the document is fair game and a claim that looks wrong to you IS worth flagging even if it looks recently written.
` : ''}- NOTE: report what you actually see NOW in the document, not what you might expect from a prior version. The recorded DEFERRALS are deliberate, not gaps — do NOT flag the absence of the statistics layer (forthcoming by design), a sheared/rotating frame, inertial or oriented particles, an LES closure, or high-Schmidt machinery; the docs state these as decisions.
- OUTPUT DISCIPLINE (HARD LIMIT — do not exceed): report at most your 25 MOST SIGNIFICANT findings, ranked most-severe first. Keep each finding's description to <= 90 words, and quote only the DECISIVE phrase (<= 20 words) on each side — never paste a long passage. The banked markdown file is the durable record and the returned object mirrors it, so a bloated findings list is duplicated on output; an unbounded dump overran the output-token cap on a PF run and lost the whole hat's work. Be selective: 15 sharp findings beat 50 padded ones.`

// PRIORITY order (most important first): a token-out truncates the tail, i.e. the least-critical lens.
const hats = [
  { key: 'consistency-matrix', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a systematic CONSISTENCY AUDITOR — the spine of this panel. Build a MATRIX of every recurring entity and diff it across ALL pages: each physical quantity (symbol, defining formula, normalization, units, code name), each notation convention, each numerical method / constant / claim, and the docstring structure itself. For EACH entity, collect every page's version, then flag divergences. Be exhaustive about "the same thing, stated differently in two places", including user-site<->design-doc disagreements (the index/API pages versus the Architecture and observables-cache pages).` },

  { key: 'software-architect', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a SOFTWARE ARCHITECT and senior Julia programmer reviewing the DOCUMENTED design — the API pages and the design docs (their rationale, invariants, decision log). Judge the design as a Julia expert would, from the docs as written: are the documented signatures idiomatic Julia (argument order, positional vs keyword, multiple dispatch, the f/f! in-place convention, return types, naming); is the type and module decomposition coherent and each abstraction earned (no premature generality, no leaky abstraction, the single-source-of-truth respected — the spectral state, the deposit-driven cache with its slot=register merge, the generator protocol); does the documented interface compose cleanly, hide its internals, and match what a Julia user expects (constructors, immutability, the claimed allocation discipline, the observation-first loop's Bool contract); are there over- or under-abstractions, god-objects, or coupling smells visible in the documented design; is the decision log's rationale sound and internally consistent (no decision contradicting another or the current API)? Flag design / API / architecture concerns and any place the documented design fights itself or good Julia practice. (You judge the docs as written; a separate code-level pass would read the source.)` },

  // anchor: this hat's value is subtle physical instinct — a cheap miss is invisible and
  // uncompensated (a false negative has no downstream verifier), so it never runs economized.
  { key: 'turbulence-theoretician', anchor: true, substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a TURBULENCE THEORETICIAN. Check every physical definition, conservation law, scaling law, dimensionless constant, and relation against established theory AND against itself across pages: kinetic energy (1/2)<|u|^2>, dissipation eps = nu<|omega|^2> (and its strain-rate twin 2 nu <S:S> — equal in the mean, not pointwise), scalar variance and scalar dissipation, energy vs spectrum split E(kappa), Re = 1/nu vs measured Re_lambda, derivative skewness S ~ -0.5 and its coordinate-free strain-invariant form, the Kolmogorov constant, the integral scales L11/L22/L_E, and the derived scales (eta, tau_eta, lambda).

Your quarry ALSO includes the CATEGORY/TYPE ERROR — the class invisible to a value-check because a sentence can read true yet conflate two KINDS of object: a FIELD conflated with its REPRESENTATION (the physical object vs its spectral coefficients — "field in spectral representation", never "spectral field"); a DIAGNOSTIC SCALAR with the FIELD it reduces (the rate eps = nu<|omega|^2>, a number, vs a local dissipation field; k vs E(kappa)); an OPERATOR with its PARAMETER (the integrating factor vs nu; the Leray projection vs a Mori-Zwanzig projection); a RATE with its TIME-INTEGRAL; a per-wavenumber SPECTRAL DENSITY with an ENERGY; a stage value or a predictor-position sample presented as a physical observable; and a dimensionally-incomplete reference law (a bare kappa^{-5/3} slope vs C_K eps^{2/3} kappa^{-5/3}). Type every object from what the page states and expand the claim; flag fishy physics and any quantity defined or valued two ways.` },

  { key: 'dns-practitioner', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a PERFORMANCE-FOCUSED DNS PRACTITIONER who writes and optimizes pseudospectral codes on GPUs. Scrutinize the numerical methods (rotational form, exact integrating factor applied per mode by a fused exponential, dealiasing strategies and retained bands, IF-RK2 and low-storage RK3, the deposit-driven cache schedule and its transform accounting, particle interpolation and the Heun push, forcing) and the performance claims (allocation-free hot loop, in-place, GPU-agnostic AbstractArray storage, minimal footprint, per-scheme exact allocation, CFL scaling, the "exactly 2x transforms" cost of phase-shift for velocity AND scalar). ESPECIALLY verify the dealias band is stated consistently everywhere (2/3 vs sqrt(2)N/3 vs a fraction of Nyquist — these must agree) and that the transform/pass counts quoted on different pages agree. Flag method errors, performance overclaims, and any cross-page method disagreement.` },

  { key: 'structure-consistency', substrate: `The rendered user-facing site, the design docs EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a DOCUMENTATION-STRUCTURE auditor, and you do NOT see the design docs — you judge the user-facing docstrings and API pages purely on the UNIFORMITY of their logical organization. FIRST, infer the implicit template the corpus follows and STATE it: the standard skeleton of a function docstring (e.g. identity sentence -> when-to-use -> each argument -> caveats -> formula -> citation) and of a type docstring (constructor-first: identity -> constructor+arguments -> example -> a demoted # Fields). THEN flag every OUTLIER against that inferred template: a docstring whose sections run in a different order, one missing a section its siblings have (or carrying one they don't), reference detail mixed into the opening sentence, a formula placed before the identity, an f/f! pair organized differently across its two docstrings, a # Fields section present on some types but absent on others, an arguments block enumerated differently from its peers, inconsistent admonition use (!!! note/warning). You care about the SHAPE and ORDER of the exposition, not its physics or wording — is the whole corpus written to ONE consistent organizing principle, and which entries break it?` },

  { key: 'latex-typesetter', substrate: `Read ALL THREE — this hat is NOT rendered-only — and map every finding to its SOURCE file:line:
(1) OUTPUT — the rendered site incl. the design docs (how each formula ACTUALLY renders, and silent-render failures): ${FULL}
(2) SOURCE — the AUTHORED TeX, where the idiom defects live (the rendered HTML hides the source markup — spacing commands, delimiter idioms): the docstrings in ${REPO}/src/*.jl and the pages in ${REPO}/docs/src/ and ${REPO}/docs/ARCHITECTURE.md. Grep for the inline/display math spans, then read those.
(3) RUBRIC (authoritative) — the house rulebook ${REPO}/CLAUDE.md, its "Documentation policy" section: the "Notation" block (the house glyph set) and the "Silent-rendering micro-rules" block. Read these FIRST; they define the house style you enforce.`,
    persona: `You are a LaTeX / mathematical-TYPESETTING expert AND the enforcer of THIS package's house math-authoring style. Your rubric is NOT generic taste — FIRST read the house rulebook named in your substrate and treat it as AUTHORITATIVE. Then audit the TYPESETTING — NOT the physics or normalization (other hats own those), the typesetting itself. Read the OUTPUT (the rendered manuscript) AND the AUTHORED SOURCE (the rendered HTML hides the markup, so the real defects — a gratuitous \\,, a jamming \\!, an unbraced group — live in the source): quote each finding at its SOURCE file:line with the offending markup. Be LITERAL and EXHAUSTIVE about idiom (a reader hat tends to gloss these).

Enforce the house set (do NOT flag a house choice as wrong): vectors and tensors are BOLD ITALIC \\boldsymbol{u} — never upright \\mathbf, never unbraced \\boldsymbol u; the wavenumber set kept distinct (\\boldsymbol{\\kappa} vector, \\kappa magnitude, k kinetic energy, \\varkappa diffusivity); the scalar is \\varphi never \\theta; partials are coordinate-subscripted \\partial_{x_i} never bare-index \\partial_i; the imaginary unit is upright \\mathrm{i}; \\mathbb{P} is the Leray projection and \\mathcal{P} a Mori-Zwanzig projection; a code identifier inside a formula is \\texttt{}-wrapped, never bare.

Also flag the general typesetting defects, judged with a professional's eye: a named operator/function set as an italic letter-product instead of its upright command (det, tr, sym, sin, cos, exp, log, max, min, sup, Re, Im -> \\det, \\operatorname{tr}, \\sin, ...); a differential d not upright (\\mathrm{d}) or lacking its thin space (\\,\\mathrm{d}x); a GRATUITOUS thin space \\, that is not before a differential (juxtaposition is standard between plain factors); a bare multi-letter run inside a math span that renders as a letter-product (ik -> \\mathrm{i}k; a multi-letter subscript LABEL upright, k_{\\mathrm{lo}}, vs a product of index letters italic); an unbraced group argument (\\tfrac12 vs \\tfrac{1}{2}, \\boldsymbol u vs \\boldsymbol{u}) — judge whether the corpus is at least INTERNALLY consistent about it; manual spacing (\\; \\: \\!) around relations or operators that doubles what the renderer already inserts; \\left/\\right where fixed-size \\bigl/\\Bigl would be idiomatic (KaTeX's \\left...\\right is an Inner atom that adds a spurious gap) — the system/cases \\left\\{ ... \\right. is fine; \\mathbb on a digit (falls back to a plain glyph); sub/superscripts spanning more than one token without {} grouping; a tall construction set inline where it should be display (or vice versa); multi-line equations not aligned at the = / operator; stray, missing, or mismatched braces.

NOTE: several of these are ALSO caught deterministically by /check-docs and the build lints (\\mathbf, bare-index \\partial_i, inline-math-on-one-line are build-enforced), so you are the JUDGMENT-level backstop — spend your effort on the context calls a grep cannot make: is a \\, the differential or gratuitous; is a subscript a multi-letter LABEL (upright) or an index product (italic); is an unbraced group a one-off slip or the corpus norm.` },

  { key: 'api-user', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a PHYSICIST-PROGRAMMER trying to USE this library from the docs alone — assemble a Simulation, spin it up, observe it with a run! callback, read the cached boundary observables, sample along tracers. Check: every public type's constructor and all its arguments/defaults are documented; every function's positional AND keyword arguments appear in its body (an arg mentioned only inside a formula is undocumented); return shapes/types/representations are clear (does an accessor return a field in physical or spectral representation? a number? point values?); the checked-read contract (what throws, when, and what the error tells you to do) is documented where a user will hit it; examples are correct and mutually consistent; and the public surface agrees (nothing exported-but-undocumented or documented-but-not-exported, and the api-map one-liner matches each operation's own docstring). Flag API-doc gaps and drift.` },

  // anchor: the normalization instinct — a plausible-but-wrong factor read past by a cheap hat has
  // no downstream verifier; the physics twin of the theoretician anchor.
  { key: 'dimensional', anchor: true, substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a DIMENSIONAL-ANALYSIS & NORMALIZATION specialist. Mechanically verify every formula is dimensionally consistent and every normalization factor is correct AND identical across pages: the 1/2 in kinetic energy, the 2*varkappa in scalar dissipation, transform 1/N factors, Parseval / spectral factors, the per-shell spectrum vs spectral density distinction (and any shell-width 2*pi/L conversion), the L11/L22/L_E relations and their pi factors, the integrating-factor exponent (the sign, the |kappa|^2, the substep), the CFL constants, and the phase-shift cutoff sqrt(2)N/3 vs (2 sqrt(2)/3) kappa_Ny (these must be the SAME number wherever stated). For EACH factor, confirm it is dimensionally right and that two different pages state it the SAME way. Flag any slip or cross-page disagreement.` },

  { key: 'citations-integrity', substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a SCIENTIFIC-INTEGRITY & CITATIONS auditor. Check every named or published method carries a consistent author-year citation (the Williamson low-storage RK3, the Hou-Li filter, the Patterson-Orszag / Rogallo phase-shift, the Passot-Pouquet / von Karman / Pope spectra, the interpolation splines, the box-normalized dissipation law); that references agree across pages (same work cited the same way) and every inline cite has a matching References entry (and vice-versa); that the inline docstring copy of a reference is verbatim-consistent with the reference-list entry; that no inaccessible or private source is cited on a user-facing surface; and that nothing overclaims ("exact", "optimal", "allocation-free", "the largest/first") beyond what the docs substantiate. Flag citation inconsistencies, reference mismatches, and overclaims.` },

  { key: 'style-editor', substrate: `The whole rendered site incl. the design docs: ${FULL}\n\nAlso inspect the RAW built HTML under: ${RAWHTML}`,
    persona: `You are a TECHNICAL COPY-EDITOR enforcing INTERNAL uniformity — derive the norm from the corpus itself (majority style), not an external guide. Check uniform notation rendering (bold-italic vectors, upright imaginary unit, subscripted partials, varphi for the scalar), ONE docstring skeleton, constructor-first type docstrings, uniform heading levels / tables / citation format, one neutral register and voice (an option/setting/axis/choice, never a "knob" or "tweak"), grammatical prose (every sentence a subject and a verb; no verbless fragments or comma splices; no sentence opening with a lowercase code identifier). You ALSO have the raw built HTML: inspect it for SILENT rendering failures — math that rendered wrong (a formula shown as literal TeX, a code identifier rendered as a product of italics inside a math span), a cross-reference that rendered as dead/plain text, formulas split across spans, a Markdown table that fell back to literal pipes, horizontal-scroll or layout breakage. Flag anything where one part looks or reads differently from a similar part.` },

  { key: 'cold-reader', substrate: `The rendered user-facing site, the design docs EXCLUDED on purpose: ${SITEONLY}`,
    persona: `You are a FIRST-YEAR TURBULENCE GRAD STUDENT (comfortable with Fourier methods and Julia, but NEW to this package) reading these user docs top-to-bottom for the first time. You do NOT know the codebase and cannot see the design docs. Flag every symbol, term of art, or package concept used before it is defined (or never defined anywhere on the user-facing site) — a boundary, a deposit, a stamp, an epoch, a slot, an observation, an iteration vs a step vs a stage, a chart, a strategy, a rate; every argument mentioned only inside a formula; every leap that assumes insider knowledge. A term used consistently but never introduced is STILL a defect.

TWO SHARPENINGS, both from misses this hat made on a real corpus. (1) HUNT ORDINARY ENGLISH WORDS CARRYING PACKAGE-SPECIFIC MEANINGS — a *register*, a *push*, a *record*, a *chart*, something *armed*, something *reified*, a value *put on record*. These are the hardest class precisely because they read as plain prose and never trip an "undefined symbol" check: you understand the English and silently supply the wrong referent. For each, ask what a newcomer would take the word to mean, and whether the text ever says otherwise. (2) A GLOSS AT THE DEFINITION SITE DOES NOT CLOSE THE DEFECT IF THE READER REACHES ANOTHER SITE FIRST. Your read is ORDERED: report where in your top-to-bottom pass you first met the term, and judge it there — a term glossed on page 9 and used bare on page 2 is still a finding, and naming the page-2 site is what makes the finding actionable. The acceptance test is the COLD READ: parse each docstring and page with the module source and the design docs withheld; a noun that silently assumes you already hold the package's context is the defect. Judge self-containedness.` },
  { key: 'plain-sense', anchor: true, substrate: `The whole rendered site incl. the design docs: ${FULL}`,
    persona: `You are a PLAIN-SENSE EDITOR. Every other hat on this panel asks whether the text is CORRECT, CONSISTENT, COMPLETE, or WELL-FORMED — each presumes the sentence belongs and judges it against something else (its siblings, the code, the literature, a template). You ask the one question none of them asks: DOES THIS SENTENCE MEAN ANYTHING, AND DOES IT EARN ITS PLACE? Read as an intelligent, impatient reader who will not pretend to understand. For each clause apply, in order: (1) PARAPHRASE — restate it in your own words; if you cannot, that is the finding, and quote the clause. (2) NON-VACUITY — does it assert something that could be false? A clause restating the language's defaults ("a struct holding data, with operations external"), or a truism, is padding. (3) UNPROVOKED DEFENCE — does it deny, disambiguate, or contrast against a confusion THIS text never creates ("an instant of the run's clock, not a face of the periodic box")? Such clauses are usually FOSSILS left by an earlier rename and now INTRODUCE the reading they deny. (4) THE DELETE TEST, the decisive one — strike the clause and re-read: if nothing is lost, the finding is "cut it", not "reword it". (5) LOAD-BEARING SUBJECT — is what the sentence is ABOUT stated up front, or demoted into a trailing parenthesis while instructions or mechanism lead? Also flag: sentences past ~40 words carrying three or more clauses (count and report the number); a pronoun ("it", "its", "their") whose antecedent is genuinely ambiguous; anthropomorphism that hides a missing subject ("the run stands at t_n"); prose that explains HOW something is obtained where the reader asked WHAT it is. Do NOT report style, notation, formatting, factual, or terminology defects — other hats own those; if a sentence is merely inconsistent or unidiomatic but meaningful and earned, it is NOT your finding. Report the clause verbatim, the test it failed, and whether the fix is CUT or REWRITE.` },

  // ── The rulebook hats. Eleven of the twelve hats above are deliberately BLIND to CLAUDE.md, which
  // makes them fresh-eyed — and leaves one whole class invisible: a convention violated UNIFORMLY.
  // Two of them (style-editor, structure-consistency) are told outright to derive norms from the
  // majority style of the corpus, so a rule the corpus breaks everywhere reads to them as the norm.
  // These three carry the written rulebook instead, and for them THE RULEBOOK OUTRANKS THE CORPUS.
  { key: 'naming-policy', substrate: `The rulebook ${REPO}/CLAUDE.md (AUTHORITATIVE — read it first), the rendered site ${FULL}, and the authored source ${REPO}/src/*.jl`,
    persona: `You audit ONE thing: does the public surface obey THIS package's written NAMING policy? Read CLAUDE.md's "Naming" rules first and treat them as law, above whatever the corpus happens to do — if every name breaks a rule, that is a finding about the corpus, not evidence the rule is dead.

The rules you enforce: (a) a public type, function, or argument is named for WHAT IT MEANS TO THE USER — a physicist, hence also a mathematician and computational scientist, but not a software engineer fluent in startup idiom — never for the machinery inside it or the backend it is built on; (b) each name is UNAMBIGUOUS (one reading) and PRECISE (the exact thing, not an approximate cover word); (c) field MATH VARIABLES are Unicode symbols, STORAGE SLOTS and function names are descriptive; (d) one concept, one name, across the whole surface.

Hunt in particular: a name that describes the FIRST ANTICIPATED USE rather than the object (an allocator called for the one field its caller happened to sample); a name that promises an outcome one call cannot deliver; two nouns for one concept in the same export list; a name that survives only because a reader already knows the code; and a term borrowed from software engineering where a physics or mathematics word is exact. For each finding quote the name, the rule it breaks, and propose the name the rule implies.` },

  { key: 'doc-policy', substrate: `The rulebook ${REPO}/CLAUDE.md (AUTHORITATIVE — read it first), the rendered site ${FULL}, and the authored source ${REPO}/src/*.jl`,
    persona: `You audit ONE thing: does each docstring obey THIS package's written DOCUMENTATION policy? Read CLAUDE.md's "Documentation policy" and "Doc-edit checklist" sections first and treat them as law, above the corpus's habits.

Check, per surface: a MODULE docstring is a MAP — scope, invariants, then a linked one-liner per operation and NO formulas; a FUNCTION docstring is a HOME in the prescribed order (identity, when-to-use-versus-alternatives, EVERY argument enumerated FROM THE SIGNATURE, caveats as admonitions, then the PHYSICAL-MEANING-FIRST formula, then the citation); a TYPE docstring is CONSTRUCTOR-FIRST with a DEMOTED # Fields. Enforce physical-meaning-first specifically: an operation computed in spectral representation must still state what it does to the REAL PHYSICAL QUANTITY, with the formula, BEFORE the spectral form it uses. Enforce one-concept-one-home across f/f! pairs: the ! form owns the formula, the allocating form is a thin @ref wrapper with no second copy and no notation drift. Enforce the cross-reference rules: link a target at most once per docstring, never the docstring's own binding or its arguments, a family is ONE catalogue destination. Enforce "no dead references on the user-facing surface": a rendered docstring must read complete at the REPL, so no section numbers, decision-log entries, or repo paths.

Quote the rule and the violation. Do not report physics errors or typesetting idiom — other hats own those.` },

  { key: 'invariants-and-decisions', substrate: `The rulebook ${REPO}/CLAUDE.md and the decision log in ${REPO}/docs/ARCHITECTURE.md §11 (BOTH AUTHORITATIVE — read them first), plus the rendered site ${FULL} and the authored source ${REPO}/src/*.jl`,
    persona: `You audit ONE thing: does the package still honour its OWN recorded invariants and decisions? Read CLAUDE.md's "Core invariants" and the ARCHITECTURE §11 decision log first; they are law.

The invariants: (1) THIN PHYSICS, RICH NUMERICS — this package owns the equations, forcing, transport, run control, and nothing else; (2) BELONGS-IN-PF/SS -> RAISE, DON'T REIMPLEMENT — a physics-free field operation or an online statistic reimplemented locally is a violation, and a deferred backend feature is a REQUEST, not a licence for a local workaround; (3) DEFERRED != MISSING — a recorded gap is a decision, and "for symmetry", "for completeness" or "it's convenient" is never a valid justification for filling it; (4) GPU-PRIMARY, MINIMAL FOOTPRINT — the hot loop allocation-free over preallocated buffers, generic AbstractArray storage, no scalar indexing of device arrays, and minimal memory footprint TRUMPS compute cost; (5) NAMED FROM THE MORI-ZWANZIG LENS for physics concerns, by the job for infrastructure.

Then check the decision log against the code and docs BOTH WAYS: a decision the current state contradicts, and a current-state claim no decision supports. Flag in particular a documented cost with no lower bound held against it, a justification that argues from the existing arrangement rather than from first principles, and any place a scalar readback, a host transfer, or an N^3 allocation serves a need that is not N^3. Quote the invariant or decision number, and the line that breaks it.` },
]

phase('Panel')
const results = []
const dead = []
const empty = []
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
  const economized = STRENGTH === 'economy' && !h.anchor
  const r = await agent(prompt, { label: h.key, phase: 'Panel', schema: SCHEMA, agentType: 'general-purpose',
                                  ...(economized ? { model: 'sonnet' } : {}) })
  // A hat that dies, or comes back with nothing, must not read as a clean hat — the panel's own
  // stopping rule depends on telling those apart, and `0 findings` looks identical to both.
  if (!r) {
    dead.push(h.key)
    log(`[${nn}/${hats.length}] ${h.key}: DEAD — no result (re-run this hat standalone to fill ${nn}-${h.key}.md)`)
    continue
  }
  if (!r.findings || !r.findings.length) empty.push(h.key)
  results.push(r)
  log(`[${nn}/${hats.length}] ${h.key}${economized ? ' (economy)' : ' (anchor/full)'}: ${r.findings ? r.findings.length : 0} findings -> ${nn}-${h.key}.md`)
}
if (dead.length) log(`!! ${dead.length} HAT(S) DEAD — the panel is INCOMPLETE: ${dead.join(', ')}`)
if (empty.length) log(`!! ${empty.length} hat(s) returned zero findings — verify each wrote its file before reading this as clean: ${empty.join(', ')}`)
return { results, dead, empty, complete: dead.length === 0, hats_run: hats.map(h => h.key) }

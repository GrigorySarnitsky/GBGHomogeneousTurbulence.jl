Status: open — approved by the owner on 2026-10-06; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: a fix the owner rules on cannot pass the change guard

Found in HT's documentation review `2026-10-04-documentation-review-01`, at rc.58. HT asks for the
gap to be closed; how is the tool's call.

## What happened

The change guard refused 15 fixers' commits under clause 6 ("mathematics changed, which is the
owner's to answer"). Almost all of them did one thing: they defined a symbol in words at its first
use, as `RULE.DOC.SELF_CONTAINED` asks — "…with ``k_{\mathrm{band}}`` the kinetic energy held in
the forced band". That clause has to write the symbol, and in a docstring the symbol is a one-symbol
math span. No formula changes; the span repeats a symbol a formula already uses.

The findings were parked. On 2026-10-05 the owner answered them `fix it on my ruling`, with the
direction "a clause that defines in words a symbol already used in a formula may write that symbol
as a math span". `gbg answer` replied that the finding is the fixer's again, to commit with
`gbg docfix commit --finding <id>`.

That commit is refused again under clause 6: `Guard.jl` refuses any change to math spans, and
nothing consults the owner's answer. So `fix it on my ruling` cannot be carried out on a finding
whose fix touches mathematics. That is the only kind of finding where the ruling is needed.

HT made the fixes as ordinary commits, naming each finding and the ruling in the message. They carry
no `GBG-Docfix-Finding` trailer, so no verifier will judge them, and the run's record keeps them
open. Because a closed run no longer re-records grown prose, HT re-recorded the prose baseline by
hand with `gbg check --rebaseline`.

## What HT asks

1. **A ruled finding can be committed through the guard.** Clause 6 could pass a change to
   mathematics for a finding the owner answered `fix it on my ruling`, within the files that finding
   names, and record the ruling in the commit. A verifier would then judge the fix as usual.

2. **Optionally, the guard could tell a definition from a formula change.** A new math span that
   repeats a symbol already present in the same unit, inside a clause that defines it, changes no
   formula. If the guard admitted that one case, a self-containedness finding would no longer need
   the owner at all. HT would not need item 1 for these findings, but item 1 still matters for real
   formula changes the owner rules on.

## Evidence

- HT's run record: `.gbg/runs/2026-10-04-documentation-review-01/` (the answers are in `run.json`).
- The guard's refusal, at rc.58: `src/Engine/Guard.jl`, the clause 6 `math_diff_texts` check.
- HT's ordinary commits for the ruled fixes: `1cb41c3f..cd83fae9` on HT's `master`.

Status: open — approved by the owner on 2026-10-03; sent to the GBGCodingTools session the same day.

# To GBGCodingTools: two checks HT still keeps in its own build

HT is moving everything to the tool, keeping only what is really specific to HT. On 2026-10-03 it
deleted three of its own doc lints the rulebook already covers: inline math on one line, the notation
variants, and the length caps with the growth ratchet (`RULE.DOC.SHAPE` does the same, with the same
caps of 120 words and 3 admonitions). Two remain in HT's `docs/make.jl`, each for a capability the
tool lacks. HT asks for both; how to build them is the tool's call.

## 1. A program for `RULE.DOC.HOME_ORDER`'s section order

`RULE.DOC.HOME_ORDER` puts a docstring's caveats last among its prose, then `# References`, then
`# Fields` last; it is covered by a reader. Two consequences of that order are mechanical, and HT's
`lint_docstring_order()` checks them:
- no column-0 `!!!` caveat admonition after `# Fields`;
- no `# Arguments` after a column-0 caveat admonition.

An indented `!!!` belongs to a list item and does not count. A program in the tool would check them
for every package, and HT would delete its lint.

## 2. A `PatternRule` with a window, an escape and an exempt section

HT's `lint_lamb_vector_sign()` holds a physics sign convention, which is HT's: the Lamb vector is
ω × u, and the rotational form carries its negation u × ω. It fails when a u-first cross product — in
LaTeX (`\boldsymbol{u} \times \boldsymbol{\omega}`), in Unicode (`u × ω`), or as the call
`cross!(ω, u, ω)` — appears within three lines of the word "Lamb", unless the same window contains
"negat". `ARCHITECTURE.md`'s decision log (from `## 11.` to `## References`) is exempt, being history.

The content is HT's, but the mechanism is general. Today's `PatternRule` is a file set, one regex and
a `forbidden` flag, which cannot express it. With three additions HT would declare the rule in its
`.gbg/config.jl` and delete its lint:
- a trigger pattern and a line window around it;
- an escape pattern that clears a match in the same window;
- excluded regions of a file between two headings.

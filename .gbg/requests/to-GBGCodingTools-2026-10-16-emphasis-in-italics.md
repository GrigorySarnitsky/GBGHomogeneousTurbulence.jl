# To GBGCodingTools: emphasis in italics, bold for structure

Status: approved by the owner on 2026-10-16, sent to the GBGCodingTools session the same day.

## What the owner asks

The owner's words: follow the `\emph` practice of LaTeX. Emphasis is italics, and so is a term at
its definition. Bold is fine for structuring. The owner asks the tool to think it through and find
the best practice before writing a rule, from the authorities on typography and technical writing
(Knuth, Tufte, and whatever else it needs to get it right), rather than take this request's wording
as the rule.

## What prompted it

The rulebook says nothing about where bold may go, so prose in this package uses bold for three
unrelated things, and a reader cannot tell which is meant:

- **Structure.** The lead words of a bullet, a run-in paragraph label, a table cell that stands out.
- **A term at its definition.** The `Cache` module docstring defines three terms of art by setting
  each in bold: "for any **observation** to read", "Each value is **deposited**", "its **epoch**, a
  count of changes to the state".
- **Emphasis.** The most frequent bold span mid-sentence is "not", 13 times; then "one" and "and",
  6 each; then figures such as "28" and "81".

Measured over `src/*.jl` and `docs/src/` on 2026-10-16, with a regex that counts a span as leading
when only a list marker, a table bar or white space precedes it on its line:

| Position | Bold spans |
|:--|--:|
| leading a line, a bullet or a table cell | 141 |
| inside a sentence | 349 |

The one sentence in the rulebook that speaks of bold contradicts the owner's practice. It is the
rationale of `RULE.DOC.ARG_BULLET`: "Bold marks emphasis; a name set in bold reads as a heading over
the paragraph rather than as the argument." The rule itself fits the practice, since its point is
that bold reads as a heading. Only the rationale's first clause would need rewording.

## What a good answer settles

These are the questions this package could not settle alone. They are offered as a starting point,
not as the answer:

1. **Where bold belongs.** Which structural positions admit it, and whether a figure singled out in
   a table or a ledger is structure.
2. **How a definition is marked.** LaTeX's `\emph` and the `amsthm` definition style set a defined
   term in italics, and many textbooks set it in bold. Which practice the rulebook adopts, and why.
3. **How emphasis is used at all.** Most of the 349 mid-sentence spans are emphasis a sentence could
   carry by its own word order. Whether the rule says only what mark emphasis takes, or also that
   it is rare. A mechanical swap of bold for italics would keep every instance of shouting.
4. **Nesting.** `\emph` inside italic text turns upright; Markdown cannot express that. Whether the
   rule needs to say anything about it.
5. **The check.** A rule with no check drifts, which is how these three uses came to share one mark.
   Position looks decidable: the 141 leading spans are structure by where they stand. Whether a
   mid-sentence bold span is a finding, with which exceptions, and what a fixture pair shows.
6. **Mathematics is out of scope.** `\boldsymbol{u}` and `RULE.TEX.BOLD_LISTED` are notation, not
   typography of prose, and this request does not touch them.

## What this package does on its side

Nothing until the rule lands. Then it sweeps every bold span, reading each in context, and gives it
one of three outcomes: bold kept as structure, italic as a definition or a real contrast, or the
sentence rewritten so it needs no mark. The `Cache` paragraph and its definition of *epoch*, which
also needs rewording, come first.

# To GBGCodingTools: two bold spans `RULE.DOC.EMPHASIS` passes inside a block quote

Status: approved by the owner on 2026-10-17, sent to the GBGCodingTools session the same day.

## What the check misses

At rc.79 the check reads a block quote line by line, where it reads a paragraph as a block. Two
kinds of bold span inside a quote therefore pass, and both are findings under the rule's own
statement:

- **A span that crosses a line break.** In a paragraph the check finds it; inside a quote, where
  each continuation line begins with `> `, it does not.
- **A span at the start of a continuation line.** It is read as a run-in head opening the
  quotation, though it sits in the middle of the quote's paragraph.

A head that opens the quote passes, as it should.

## How it was found

Sweeping this package to rc.79, a scan for bold the check had passed found four spans in the
identity quote at the top of `docs/ARCHITECTURE.md`: three crossing a line break
(`**library\n> of composable pieces …**`, `**thin, fixed\n> core**`, `**not\n> dimensional**`) and
one at a continuation line's start (`> **no** speculative`). They were set plain by hand in
23f4c7bd. The same quote's single-line spans in mid-line were found.

## A fixture pair

This page, run through `gbg check`, reports lines 4 and 7 alone; lines 3 and 5 are the misses, and
line 10 is the head the rule admits.

```markdown
# Probe

> A quote with a **span
> across lines** in it, and **one** on a line.
> **lead** at a continuation line start.

A paragraph with a **span
across lines** in it.

> **Head.** A quote that opens with a head.
```

A fix would strip the quote markers and read the quote as the block it renders as, so that both
misses become findings and line 10 still passes.

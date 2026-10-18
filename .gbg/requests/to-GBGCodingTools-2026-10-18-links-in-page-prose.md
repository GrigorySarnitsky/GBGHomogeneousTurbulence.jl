# To GBGCodingTools: the linking rules stop at the docstring; a page's own prose links nothing

Status: approved by the owner on 2026-10-18, sent to the GBGCodingTools session the same day.

## What is not checked

`RULE.DOC.XLINK` and `RULE.DOC.LINKS` both speak of a docstring: a name another module owns is
linked "at its first mention in a docstring", and a target is linked "at most once in one
docstring". XLINK reads the loaded module, so it sees docstrings alone. The hand-written prose of a
documentation page — an API page's section leads, the home page's module map, the glossary's
tables, a design page — is under neither rule, and nothing reports an unlinked name there.

## How it was found

The owner, reading HT's rendered Cache page, asked why `max_speed` was not clickable in "the cached
maximum speed is read through `max_speed`, documented with the reduction it stores" — a sentence
that sends the reader to a docstring and gives him no way to reach it. A scan of HT's pages then
found 85 exported names never linked anywhere on the page that mentions them, across 11 pages:
the module maps of `api.md` (25) and `index.md` (20) named every type and function plain, and
`notation.md`, whose job is to map each symbol to its object, had 5. HT linked 84 of them by hand;
the 85th, `history_depth` on `observables_cache.md`, is a keyword argument that shares the name of
an exported function, and stays plain.

## What a page rule would read

- A page's prose, outside fenced blocks, `@docs` / `@autodocs` / `@example` blocks and headings.
- A name in a code span on its own that is a documented binding of the package: the first mention
  on the page is linked, qualified so it resolves; a later one is not, as LINKS asks of a
  docstring. A page has no owning module, so the docstring rule's "another module owns it" has no
  counterpart: every documented binding owes the link.
- A name inside a code expression owes none, as in XLINK.
- The case a check cannot decide alone: a code span naming an argument or a keyword that shares an
  exported name (`history_depth` above). HT has one such case today.

## A second thing, found doing the fix: a link counts as a word

`RULE.DOC.SHAPE` counts the words of the source, and ``[`max_speed`](@ref
GBGHomogeneousTurbulence.Observables.max_speed)`` splits at its space into two, where the reader
sees one. Each of HT's 84 links therefore grew its section by one word: 23 sections reported GREW,
by exactly their number of new links, and were re-recorded by hand. A page rule would make every
fix it asks for trip SHAPE the same way, so counting a link as its rendered text — as a formula
already counts as one word — belongs with it.

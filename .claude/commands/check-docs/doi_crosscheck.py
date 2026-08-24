"""check-docs backstop: every citation link in a src docstring matches ARCHITECTURE §References.

ONE FORMAT since 2026-08-24 (owner-ruled, adopting PF's convention): a citation carries its
clickable DOI on the paper's *title* — `[*Title*](https://doi.org/…)` — identically in the
§References bibliography and in every inline docstring copy. The format is self-verifying by
construction: this script checks that (a) every inline citation link's DOI appears in §References,
and (b) the inline TITLE matches the §References title for that DOI, so the two surfaces cannot
drift apart in either half. DOIs are still compared DECODED (an AMS DOI percent-encodes `()<>`,
and two encoders may differ on which characters they escape).

The extraction-bound `Phenomenology` leaf is exempt: its reference laws carry self-contained
`Reference` values by design (compact author–year + labelled DOI, no title) and are not duplicated
in §References.
"""
import re
import glob
import urllib.parse

ARCH = 'docs/ARCHITECTURE.md'
arch = open(ARCH).read()
refs = arch[arch.find('## References'):]

# §References: [*Title*](https://doi.org/...) — title-as-link entries.
TITLE_LINK = re.compile(r'\[(\*[^]]+?\*)\]\((https://doi\.org/[^)]*(?:%29[^)]*)*)\)')
arch_by_doi = {}
for title, url in TITLE_LINK.findall(refs):
    arch_by_doi[urllib.parse.unquote(url)] = ' '.join(title.split())

problems = 0
for f in glob.glob('src/*.jl'):
    if 'Phenomenology' in f:
        continue
    text = open(f).read()
    for title, url in TITLE_LINK.findall(text):
        doi = urllib.parse.unquote(url)
        flat = ' '.join(title.split())
        if doi not in arch_by_doi:
            print(f'{f}: cited DOI not in ARCHITECTURE §References: {doi}')
            problems += 1
        elif arch_by_doi[doi] != flat:
            print(f'{f}: inline title differs from §References for {doi}:')
            print(f'  inline: {flat}')
            print(f'  refs:   {arch_by_doi[doi]}')
            problems += 1
    # The retired two-format world's inline label must not reappear outside the exempt leaf.
    for m in re.findall(r'\[doi:[^\]]+\]', text):
        print(f'{f}: retired [doi:…] label form: {m} — use the title-as-link form')
        problems += 1

print('doi_crosscheck:', 'CLEAN' if problems == 0 else f'{problems} problem(s)')
raise SystemExit(1 if problems else 0)

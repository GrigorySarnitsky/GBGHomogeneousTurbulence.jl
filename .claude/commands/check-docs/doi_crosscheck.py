"""check-docs backstop: every DOI cited in a src docstring appears in ARCHITECTURE §References.

The subtlety this script exists for. `ARCHITECTURE.md` carries its DOIs as markdown AUTOLINKS
(`<https://doi.org/…>`), which cannot contain `>`; a docstring carries them as INLINE LINKS
(`[text](https://doi.org/…)`), which cannot contain unescaped `(` or `)`. An AMS DOI such as

    10.1175/1520-0469(1971)028<1074:OTEOAI>2.0.CO;2

contains all three characters, so the SAME identifier must be percent-encoded DIFFERENTLY on the two
surfaces. Comparing the raw strings therefore reports a mismatch that is not one — and a regex that
stops at the first `)` truncates the identifier and reports mismatches in both directions. Extract
per format, then compare DECODED.

The extraction-bound `Phenomenology` leaf is exempt: its reference laws carry self-contained
`Reference` values by design and are not duplicated in §References.
"""
import re
import glob
import urllib.parse

ARCH = 'docs/ARCHITECTURE.md'

# ARCHITECTURE: autolinks. Everything up to the closing '>' is the identifier.
architecture_dois = {
    urllib.parse.unquote(m)
    for m in re.findall(r'<https://(doi\.org/[^>]+)>', open(ARCH).read())
}

# A docstring: inline links. A percent-encoded ')' (%29) is part of the DOI, a literal ')' closes it.
INLINE = re.compile(r'\]\(https://(doi\.org/[^)]*(?:%29[^)]*)*)\)')

mismatches = 0
cited = 0
for path in sorted(glob.glob('src/*.jl')):
    if 'Phenomenology' in path:
        continue
    for match in INLINE.findall(open(path).read()):
        cited += 1
        doi = urllib.parse.unquote(match)
        if doi not in architecture_dois:
            mismatches += 1
            print(f'NOT IN §References: {path}  {doi}')

print(f'docstring DOIs: {cited}   §References DOIs: {len(architecture_dois)}   '
      f'mismatches: {mismatches}')

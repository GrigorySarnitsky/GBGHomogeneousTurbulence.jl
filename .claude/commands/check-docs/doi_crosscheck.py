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

# The reverse pass. The doc policy requires every inline cite to have a §References entry AND every
# entry a citing docstring or body mention, so a one-directional check certifies half the rule.
#
# Parse the ENTRY, not the line the DOI happens to sit on: a reference bullet wraps across lines, and
# taking the surname from the DOI's own line yields the middle of a journal title. Split §References
# into bullets first, then read each bullet's leading surname.
docstring_dois = set()
for path in sorted(glob.glob('src/*.jl')):
    if 'Phenomenology' in path:
        continue
    docstring_dois |= {urllib.parse.unquote(m) for m in INLINE.findall(open(path).read())}

body, _, references = open(ARCH).read().partition('\n## References')
entries = re.split(r'\n(?=- )', references)

uncited = []
for entry in entries:
    if not entry.lstrip().startswith('- '):
        continue
    found = re.search(r'<https://(doi\.org/[^>]+)>', entry)
    if not found:
        continue                                   # the three works with no DOI
    doi = urllib.parse.unquote(found.group(1))
    if doi in docstring_dois:
        continue                                   # cited by a docstring
    surname = entry.lstrip('- ').split(',')[0].strip()
    if surname and surname not in body:            # nor discussed in the design-doc body
        uncited.append((doi, surname))

for doi, surname in uncited:
    print(f'IN §References, cited by no docstring and no body mention: {surname}  {doi}')

print(f'docstring DOIs: {cited}   §References DOIs: {len(architecture_dois)}   '
      f'mismatches: {mismatches}   uncited entries: {len(uncited)}')

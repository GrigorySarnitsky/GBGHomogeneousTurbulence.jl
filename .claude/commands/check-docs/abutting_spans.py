r"""check-docs scan: a code span abutting a math span.

The house rule is that a binding between a code object and its symbol is ONE LaTeX span —
``\texttt{dissipation} \equiv \varepsilon`` — never a `code` span sitting next to a ``math`` span,
which renders as two disjoint runs with a gap between them. The build cannot see this: the page
compiles and renders, just wrongly.

TRIAGE. The common true hit is an argument name followed by the symbol it denotes, or a formula split
across the boundary (`coefficient` ``= -D\tau``). The common false positive is plain adjacency of two
unrelated things — a grid size next to a strategy name, ``256^{3}`` `PhaseShift` — which is not a
split formula and should be left alone.
"""
import re
import glob

PATTERN = re.compile(
    r'(``[^`\n]{1,60}``\s*`[A-Za-z_][A-Za-z0-9_!]*`'      # math span, then a code span
    r'|`[A-Za-z_][A-Za-z0-9_!]*`\s*``[^`\n]{1,60}``)'     # code span, then a math span
)

SURFACES = (sorted(glob.glob('src/*.jl'))
            + sorted(glob.glob('src/phenomenology/*.jl'))
            + sorted(glob.glob('docs/src/*.md'))
            + sorted(glob.glob('docs/src/api/*.md'))
            + sorted(glob.glob('docs/src/api/phenomenology/*.md'))
            + ['docs/ARCHITECTURE.md'])

hits = 0
for path in SURFACES:
    if path.endswith('docs/src/architecture.md'):
        continue                                          # the gitignored generated copy
    for number, line in enumerate(open(path), 1):
        if line.lstrip().startswith('#'):                 # a plain comment is not rendered
            continue
        for match in PATTERN.finditer(line):
            hits += 1
            excerpt = line[max(0, match.start() - 40):match.end() + 20].strip()
            print(f'{path}:{number}  …{excerpt}…')
print(f'abutting spans: {hits}')

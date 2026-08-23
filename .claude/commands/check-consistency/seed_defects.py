#!/usr/bin/env python3
# Seeded-defect calibration for the /check-consistency panel (attack round C7/C13, 2026-08-23).
#
# THE PROBLEM IT SOLVES: the panel has no denominator. Its output is evidence of YIELD and was being
# read as evidence of COVERAGE — nothing measured recall, so "the physics core came back clean"
# conflated "no defect found" with "no defect present". This injects k known, labeled defects into
# the consolidated manuscripts BEFORE a round, so the round's banked findings carry a measurable
# per-class recall (computed afterwards by recall.py), and a class with 0/k seeded recall is known
# to be UNMEASURED rather than clean.
#
#   Usage: seed_defects.py <manuscript_full.md> <manuscript_siteonly.md> <ground_truth.json>
#
# Mutates BOTH manuscripts in place (the siteonly copy receives the same mutation wherever its text
# contains the same anchor) and writes the ground truth: one record per seeded defect with its
# class, the original and mutated snippets, and the page banner it landed under. Deterministic: the
# k-th eligible anchor occurrence is chosen by a fixed stride, no RNG, so a re-run reproduces the
# same seeding. The catalog is CLASS-shaped: each entry plants a defect of a class some hat exists
# to catch, so recall is attributable per hat.
#
# DISCIPLINE: the seeded manuscripts are DISPOSABLE — never fix the real corpus from a seeded
# finding without checking ground_truth.json first, and the consolidation must subtract seeded hits
# (recall.py marks them) before the summary is written.
import json, re, sys

FULL, SITE, TRUTH = sys.argv[1], sys.argv[2], sys.argv[3]

# (class, description, anchor regex, replacement, which-occurrence)
# Occurrence indices are 1-based over the FULL manuscript and deliberately not all "first": the
# first occurrence of a normalization is usually its definition site, and a calibration defect is
# more realistic mid-corpus.
CATALOG = [
    ("normalization", "kinetic-energy 1/2 corrupted to 1/3",
     r"\\tfrac\{1\}\{2\}", r"\\tfrac{1}{3}", 3),
    ("sign-flip", "integrating-factor exponent sign flipped",
     r"\\exp\(-\\nu\\kappa\^\{2\}", r"\\exp(+\\nu\\kappa^{2}", 1),
    ("citation-drift", "Rogallo's year shifted",
     r"Rogallo \(1981\)", "Rogallo (1984)", 1),
    ("quantifier", "a universal weakened to a false near-universal",
     r"\bevery stage\b", "all but the last stage", 1),
    ("cross-page", "the 2/3 rule corrupted at ONE site only",
     r"2/3\$ rule", "3/4$ rule", 2),
    ("notation", "the scalar's varphi replaced by the banned theta at one site",
     r"\\varphi\^2", r"\\theta^2", 2),
    ("stale-name", "a current binding replaced by its retired name at one site",
     r"`integration_scheme`", "`integrator`", 2),
    ("wrong-constant", "the developed-cascade skewness magnitude corrupted",
     r"-0\.5", "-0.05", 2),
]


def seed(text, anchor, repl, nth):
    hits = list(re.finditer(anchor, text))
    if len(hits) < nth:
        return None, None, None
    m = hits[nth - 1]
    start, end = m.span()
    page = "?"
    for pm in re.finditer(r"===== PAGE: (.+?) =====", text[:start]):
        page = pm.group(1)
    before = text[max(0, start - 60):min(len(text), end + 60)]
    mutated = text[:start] + m.expand(repl) if "\\" in repl else text[:start] + repl
    mutated += text[end:]
    after = mutated[max(0, start - 60):min(len(mutated), start - end + end + 60 + len(repl))]
    return mutated, page, (before.strip(), after.strip())


full = open(FULL).read()
site = open(SITE).read()
truth, skipped = [], []
for cls, desc, anchor, repl, nth in CATALOG:
    mutated, page, ctx = seed(full, anchor, repl, nth)
    if mutated is None:
        skipped.append((cls, anchor))
        continue
    full = mutated
    # The siteonly manuscript is a subset: apply the identical local edit where its text carries the
    # same before-context, so the two substrates tell one consistent (seeded) story.
    if ctx[0] in site:
        site = site.replace(ctx[0], ctx[1], 1)
    truth.append({"id": f"seed-{len(truth)+1:02d}", "class": cls, "description": desc,
                  "page": page, "original_context": ctx[0], "mutated_context": ctx[1]})

open(FULL, "w").write(full)
open(SITE, "w").write(site)
json.dump({"seeded": truth, "skipped": [c for c, _ in skipped]}, open(TRUTH, "w"), indent=2)
print(f"seeded {len(truth)} defects ({', '.join(t['class'] for t in truth)})")
for cls, anchor in skipped:
    print(f"SKIPPED {cls}: anchor {anchor!r} not found often enough — catalog needs re-anchoring")

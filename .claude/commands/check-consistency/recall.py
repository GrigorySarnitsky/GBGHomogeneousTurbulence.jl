#!/usr/bin/env python3
# The read-back half of seeded-defect calibration (C7/C13): given the ground truth seed_defects.py
# wrote and the panel's banked pile, report per-class and per-hat recall, and list every banked
# finding that matches a seeded defect so the consolidation can SUBTRACT it (a seeded hit must
# never reach the real summary, and a real fix must never be driven by a planted defect).
#
#   Usage: recall.py <ground_truth.json> <pile_dir>
#
# Matching is deliberately generous-then-reviewed: a hat detects a seed if its banked file quotes a
# distinctive fragment of the MUTATED text, or names the seed's page while quoting the mutated
# value. The printed match list is for hand review — the recall number is only as honest as the
# matches, so read them.
#
# TESTED BY PERTURBATION, not by reading (PF's suggestion, 2026-08-27; the only check that separates
# "measures recall" from "prints a number"). Three arms on a stand-in truth file of 3 seeded and 2
# unanchored classes, ~2 minutes, no agents:
#   A  empty pile                          -> 0/3, every seed MISSED, 2 UNDEFINED.        PASS
#   B  one hat quoting exactly ONE mutation -> that seed DETECTED and attributed to that
#      hat, the other two still MISSED.                                                    PASS
#   C  one hat quoting the ORIGINAL text at all three sites -> 0/3.                        PASS
#   D  a seed whose ORIGINAL contains a hyphenated token, hat quotes the original -> 0/1.  PASS
#
# Arms A and B check that recall is not falsely LOW. Arms C and D check that it is not falsely
# HIGH — the direction that flatters, so the one nobody reading the number questions.
#
# ARM D EXISTS BECAUSE IT FAILED. PF ran arm C against ITS catalog, hit a false positive, traced it
# to `fragments()`, and warned IT to check. IT's arm C passed — but only because no IT mutation
# happened to produce a word inside a hyphenated original. Arm D constructs that case directly and
# IT scored 1/1 recall on a defect nobody found. A passing test over a catalog is not a property of
# the code; it is a property of the catalog. Both fixes are PF's: substring containment against the
# original TEXT rather than membership in its token SET, and no `frags or [mut[:40]]` fallback,
# since a slice of mostly-shared context is how a false positive gets in.
#
# All four arms test `fragments()` and nothing else. Re-run them after any change to it.
import json, glob, os, re, sys

TRUTH, PILE = sys.argv[1], sys.argv[2]
_gt = json.load(open(TRUTH))
truth = _gt["seeded"]
# A class the seeder could not anchor was never planted, so the panel was never tested on it. Its
# recall is UNDEFINED, not zero and not one — and leaving it out of the report entirely (as this
# script did until 2026-08-27, raised by the PF session) is the yield-as-coverage error one level
# down, committed by the instrument built to catch it: the per-class table read as though every
# class had been measured. Skipped classes are now named, and named as EXCLUDED from the denominator.
skipped = _gt.get("skipped", [])


def fragments(seed):
    """Distinctive pieces of the MUTATION — tokens that do not occur in the original AT ALL.

    Containment is a SUBSTRING test against the original text, not membership in its token set.
    The difference is the whole correctness of this function, and it was found by PF running arm C
    on its own catalog (2026-08-27): with whitespace tokenising, `bitwise-identical` is ONE token,
    so a mutation's standalone `identical` is absent from the original's token SET while being
    plainly present in the original's TEXT. A hat quoting the unmutated sentence then scored a
    detection. IT had the identical bug and passed arm C only because no IT mutation happened to
    produce a word inside a hyphenated original — a property of the catalog, not of the code.
    Reproduced in IT as arm D before this fix: 1/1 recall for a defect nobody found.
    """
    mut, orig = seed["mutated_context"], seed["original_context"]
    frags = [t for t in re.findall(r"\S+", mut) if len(t) >= 4 and t not in orig]
    # No fallback. A slice of mostly-shared context is exactly how a false positive gets in, so a
    # seed with no distinctive fragment is UNVERIFIABLE and is excluded from the denominator rather
    # than measured against a fragment that cannot discriminate.
    return frags


unverifiable = [s for s in truth if not fragments(s)]
truth = [s for s in truth if fragments(s)]

hits = {s["id"]: [] for s in truth}
for path in sorted(glob.glob(os.path.join(PILE, "[0-9][0-9]-*.md"))):
    hat = os.path.basename(path)
    text = open(path).read()
    for s in truth:
        if any(f in text for f in fragments(s)):
            hits[s["id"]].append(hat)

measured_classes = sorted({s["class"] for s in truth})
print(f"seeded: {len(truth)}   detected: {sum(1 for v in hits.values() if v)}")
print(f"classes MEASURED: {len(measured_classes)}   classes SKIPPED (recall UNDEFINED): {len(skipped)}")
if unverifiable:
    print(f"UNVERIFIABLE seeds (no fragment distinguishes the mutation from the original): "
          f"{len(unverifiable)} — excluded from every number below")
    for s in unverifiable:
        print(f"  {s['id']} [{s['class']}] on '{s['page']}' — re-word the mutation so it introduces "
              f"text absent from the original")
if skipped:
    print("  the panel was NOT tested on: " + ", ".join(sorted(skipped)))
    print("  re-anchor these in the catalog before reading any coverage claim off this run")
print()
by_class = {}
for s in truth:
    detected = hits[s["id"]]
    by_class.setdefault(s["class"], []).append(bool(detected))
    mark = "DETECTED" if detected else "MISSED  "
    print(f"{mark} {s['id']} [{s['class']}] on page '{s['page']}': {s['description']}")
    for h in detected:
        print(f"         found by {h}")
print()
print("per-class recall (a 0/k class is UNMEASURED coverage, not a clean corpus):")
for cls, results in sorted(by_class.items()):
    print(f"  {cls:16s} {sum(results)}/{len(results)}")
for cls in sorted(skipped):
    print(f"  {cls:16s} UNDEFINED — never seeded, so this class is absent from the numbers above")
if skipped:
    print()
    print(f"COVERAGE CAVEAT: this run measures {len(measured_classes)} of "
          f"{len(measured_classes) + len(skipped)} catalogued classes. Any statement of the form "
          f"'the panel catches X%' is about the measured subset only.")

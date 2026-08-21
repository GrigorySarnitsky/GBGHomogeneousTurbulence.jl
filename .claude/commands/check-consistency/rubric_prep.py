#!/usr/bin/env python3
"""Split the extracted findings into two DISJOINT sets of files, and keep them disjoint.

  substrate/<id>.txt  — ONLY the historical passage, as it stood at the baseline commit. This is what
                        a hat under test is allowed to see. It contains no critique, no title, no
                        hint that anything is wrong with it.
  defect/<id>.md      — the user's finding. This is for the ASSIGNER (which hat should own this?) and
                        the SCORER (did the hat report it?). A hat under test must NEVER see it.

The separation is the whole experiment. A hat shown the finding will always "find" it, so an audit
that hands both to the same agent cannot fail and therefore measures nothing.
"""
import json, os, io

BASE = ".claude/rubric-audit"
findings = json.load(open(f"{BASE}/findings.json", encoding="utf-8"))
os.makedirs(f"{BASE}/substrate", exist_ok=True)
os.makedirs(f"{BASE}/defect", exist_ok=True)

index = []
for f in findings:
    if not f["excerpts"]:
        continue
    fid = f"{f['id']:02d}"
    with io.open(f"{BASE}/substrate/{fid}.txt", "w", encoding="utf-8") as out:
        for e in f["excerpts"]:
            out.write(f"----- {e['path']} (around line {e['line']}) -----\n{e['text']}\n\n")
    with io.open(f"{BASE}/defect/{fid}.md", "w", encoding="utf-8") as out:
        out.write(f"# Finding {f['id']}: {f['title']}\n\nLocations: {', '.join(f['locations'])}\n\n{f['defect']}\n")
    index.append({"id": f["id"], "title": f["title"], "locations": f["locations"]})

json.dump(index, open(f"{BASE}/index.json", "w", encoding="utf-8"), indent=1)
print(f"{len(index)} findings prepared: substrate/ and defect/ written")

# A cheap contamination assertion: no substrate file may contain the finding's title, which is the
# user's words about the passage rather than the passage itself.
leaks = []
for f in findings:
    if not f["excerpts"]:
        continue
    fid = f"{f['id']:02d}"
    text = io.open(f"{BASE}/substrate/{fid}.txt", encoding="utf-8").read()
    probe = f["title"][:40].strip("`* ")
    if probe and probe.lower() in text.lower():
        leaks.append(fid)
print("contamination check:", "CLEAN" if not leaks else f"LEAK in {leaks}")

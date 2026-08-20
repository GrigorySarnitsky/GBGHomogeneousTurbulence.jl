#!/usr/bin/env python3
"""Extract the user's read-through findings and reconstruct, from git, the text each one was about.

This is the mechanical half of the rubric audit. The audit asks a question about the INSTRUMENTS —
"which hat should have caught this, and why didn't it?" — and the only honest way to answer it is to
run the hat's own persona on the text the user was looking at and see what comes out. That requires
two things a judgement call cannot supply:

  * the persona VERBATIM, not a paraphrase (a paraphrase tests my summary of the rubric, not the
    rubric), and
  * the substrate UNCONTAMINATED — the passage as it stood, never the user's critique of it. A hat
    shown the finding will always "find" it, which is why the naive version of this audit cannot
    fail and therefore proves nothing.

The baseline commit is the state the user was actually reading: the panel's findings all
dispositioned, none of the read-through fixes applied yet.
"""
import re, json, subprocess, sys, os

BASELINE = "b16a7df"
PILE = ".claude/doc-reading-pile-2026-08-15.md"
OUT = ".claude/rubric-audit"
WINDOW = 28                      # lines either side of a cited line

def git_show(path):
    try:
        return subprocess.run(["git", "show", f"{BASELINE}:{path}"], capture_output=True,
                              text=True, check=True).stdout.splitlines()
    except subprocess.CalledProcessError:
        return None

def main():
    text = open(PILE, encoding="utf-8").read()
    # A finding runs from its `### n.` heading to the next one. Headings wrap onto a second `###`
    # line, so the id is taken from the numbered one only.
    # Split only on a NUMBERED heading. A finding's heading routinely wraps onto a second `### `
    # line carrying the file:line citation, and splitting on every `### ` orphaned that line into a
    # fragment with no id — which was silently dropped, taking the substrate location with it. The
    # first run recovered 6 of 42; the locations were never missing, only severed from their entry.
    parts = re.split(r"\n(?=### \d+\.)", text)
    findings, cache = [], {}
    for part in parts:
        m = re.match(r"### (\d+)\.\s*(.+)", part)
        if not m:
            continue
        fid, title = int(m.group(1)), m.group(2).strip()
        # Locations: every `file.jl:NN` / `file.md:NN` the entry cites.
        locs = []
        for lm in re.finditer(r"([A-Za-z0-9_./-]+\.(?:jl|md)):(\d+)", part):
            path, line = lm.group(1), int(lm.group(2))
            if path.startswith("."):            # the pile citing itself
                continue
            locs.append((path, line))
        # Deduplicate, keep order.
        seen, uniq = set(), []
        for p, l in locs:
            if (p, l) in seen: continue
            seen.add((p, l)); uniq.append((p, l))
        excerpts = []
        for path, line in uniq[:4]:             # at most four windows per finding
            if path not in cache:
                cache[path] = git_show(path)
            lines = cache[path]
            if lines is None:
                continue
            lo, hi = max(0, line - 1 - WINDOW), min(len(lines), line + WINDOW)
            excerpts.append({"path": path, "line": line,
                             "text": "\n".join(lines[lo:hi])})
        findings.append({"id": fid, "title": title,
                         "defect": part[:2600],          # the pile entry — for the ASSIGNER and the
                                                         # SCORER only, never for a hat under test
                         "locations": [f"{p}:{l}" for p, l in uniq],
                         "excerpts": excerpts})
    os.makedirs(OUT, exist_ok=True)
    json.dump(findings, open(f"{OUT}/findings.json", "w", encoding="utf-8"), indent=1)
    recovered = sum(1 for f in findings if f["excerpts"])
    print(f"{len(findings)} findings; {recovered} with recovered substrate; "
          f"{len(findings)-recovered} without (no parsable location, or the file did not exist at {BASELINE})")
    for f in findings:
        if not f["excerpts"]:
            print(f"  no substrate: #{f['id']} {f['title'][:70]}")

main()

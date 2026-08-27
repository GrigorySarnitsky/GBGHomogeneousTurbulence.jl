#!/usr/bin/env python3
"""Regenerate MANIFEST.txt for every instrument directory under .claude/commands/.

One line per file: name, the date git last changed it, and a one-line purpose taken from the file's
first comment line. Committed, so either package can diff toolboxes in a single read instead of
discovering divergence three requests later.

Format agreed with the PF session on 2026-08-27, which identified the failure it fixes: neither
package gets any signal when the other moves, so a request describes NEW mechanisms and stays silent
about CHANGED ones. PF inherited a stale form from its clone twice that way.

    Usage:  python3 .claude/commands/manifest.py     (from the repo root or anywhere)
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
HEADER_RE = re.compile(r"^\s*(?:#!.*|#|//|\"\"\"|'''|--)\s*(.*\S)\s*$")


def purpose(path):
    """First substantive comment line, trimmed. Falls back to a dash rather than guessing."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for i, line in enumerate(fh):
                if i > 12:
                    break
                if line.startswith("#!"):
                    continue
                m = HEADER_RE.match(line)
                if m and len(m.group(1)) > 12:
                    return m.group(1)[:96]
    except OSError:
        pass
    return "—"


def changed(rel):
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", rel],
                             cwd=REPO, capture_output=True, text=True, timeout=20)
        return out.stdout.strip() or "uncommitted"
    except Exception:
        return "?"


def main():
    dirs = sorted(d for d in os.listdir(HERE)
                  if os.path.isdir(os.path.join(HERE, d)))
    for d in dirs:
        full = os.path.join(HERE, d)
        files = sorted(f for f in os.listdir(full)
                       if os.path.isfile(os.path.join(full, f)) and f != "MANIFEST.txt")
        lines = [
            f"# {d} — instrument manifest",
            "#",
            "# One line per file: name, the date git last changed it, and its purpose.",
            "# Regenerate with `python3 .claude/commands/manifest.py` and commit the result.",
            "# Format agreed with the PF session 2026-08-27 so either package can diff toolboxes",
            "# in a single read.",
            "",
            f"{'FILE':<28} {'CHANGED':<12} PURPOSE",
        ]
        for f in files:
            rel = os.path.relpath(os.path.join(full, f), REPO)
            lines.append(f"{f:<28} {changed(rel):<12} {purpose(os.path.join(full, f))}")
        with open(os.path.join(full, "MANIFEST.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"{d}: {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())

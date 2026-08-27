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
    """The file's own statement of what it is. Never a guess: a dash where none is found.

    Markdown is read differently from code, and the difference is not cosmetic. A `#` opens a
    COMMENT in a script and a HEADING in markdown, so the code path would happily return whatever
    section heading it met first — `check-docs.md` reported "Cost modes — cheap lanes by default",
    a real line from the middle of the file and a false description of it. A confidently wrong
    purpose is worse than a dash, because a dash prompts someone to look and a wrong line does not.
    So markdown is read from its front-matter `description:` (which slash commands carry) or its
    first `# ` title, and nothing else.
    """
    md = path.endswith(".md")
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = [next(fh, "") for _ in range(30)]
    except OSError:
        return "—"

    if md:
        for line in lines:
            m = re.match(r"^description:\s*(.*\S)", line)
            if m:
                return m.group(1)[:96]
        for line in lines:
            m = re.match(r"^#\s+(.*\S)", line)
            if m:
                return m.group(1)[:96]
        return "—"

    for i, line in enumerate(lines):
        if line.startswith("#!"):
            continue
        m = HEADER_RE.match(line)
        if m and len(m.group(1)) > 12:
            return m.group(1)[:96]
    return "—"


def changed(rel):
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%cs", "--", rel],
                             cwd=REPO, capture_output=True, text=True, timeout=20)
        return out.stdout.strip() or "uncommitted"
    except Exception:
        return "?"


def write_manifest(full, title, files):
    lines = [
            f"# {title} — instrument manifest",
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
    print(f"{title}: {len(files)} files")


def main():
    # The ROOT manifest, over the command-level files themselves (PF's addition, 2026-08-27).
    # Walking only directories omitted the four `*.md` INSTRUMENT DEFINITIONS — the files a person
    # reads to learn what each instrument does, and the ones most needing visibility. PF hit the
    # same gap: its /check-docs has no directory at all, so a per-directory manifest would have
    # omitted the very instrument it most needed to surface. No extension filter anywhere here, for
    # the reason PF found the hard way — an extension table is a list of the file types you thought
    # of, and PF's omitted `.sh`, making guards.sh invisible to its own manifest.
    root_files = sorted(f for f in os.listdir(HERE)
                        if os.path.isfile(os.path.join(HERE, f)) and f != "MANIFEST.txt")
    write_manifest(HERE, "commands (instrument definitions)", root_files)

    dirs = sorted(d for d in os.listdir(HERE)
                  if os.path.isdir(os.path.join(HERE, d)))
    for d in dirs:
        full = os.path.join(HERE, d)
        files = sorted(f for f in os.listdir(full)
                       if os.path.isfile(os.path.join(full, f)) and f != "MANIFEST.txt")
        write_manifest(full, d, files)
    return 0


if __name__ == "__main__":
    sys.exit(main())

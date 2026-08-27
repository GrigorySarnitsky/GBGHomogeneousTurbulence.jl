# Argument coverage: every positional and keyword parameter in a docstring SIGNATURE must be
# documented in that docstring's body.
#
# The subtlety that makes this a file rather than a one-line sweep: the corpus documents an argument
# in TWO shapes, and both are correct. A bare span `scalar`, and a span carrying the default,
# `scalar = false` — the latter is the house form for a keyword whose default is part of what the
# reader needs (`κ_max_η = 2`, `lowest_shell = 1`). An earlier version matched only the bare form and
# reported six false positives on every run; a scan that always cries wolf is one whose real hit gets
# waved through, so it accepts both.
#
# Also skipped: `prevind` is used rather than `c-1` because û / φ̂ / ω are multibyte — indexing into
# the middle of one throws a StringIndexError that aborts the sweep at the FIRST file while the run
# still looks complete.
#
# FALSIFIED, because a sweep reporting zero is exactly the one to distrust (PF's rule, 2026-08-27).
# This script reported 0 on the whole corpus for as long as it has existed, and that zero was read
# as a clean corpus. It was a blind spot: `split(p, ";")[end]` discarded the LAST POSITIONAL
# ARGUMENT of every signature carrying a `;` — most of the corpus. On the fixture below the old form
# reports 0 and the fixed form reports 1. Fixing it found a real defect on the first corpus run:
# `ResolvedFields(domain; scalar = false)` never bound `domain`, which is the very argument
# CLAUDE.md names as the historical instance of this class.
#
# Fixture arms (rebuild under a scratch `src/` and run this file there):
#   1  caught(domain, dt; scalar = false)     `domain` and `scalar` documented, dt absent  -> 1 hit
#   2  bare_form(alpha, beta)                 both in the bare `arg` form                  -> 0 hits
#   3  default_form(sim; lowest_shell = 1, κ_max_η = 2)   defaults-carrying form           -> 0 hits
# Arm 1 is the positive control and the one that was failing; 2 and 3 are the false-positive
# directions the two accepted shapes exist for. Note when writing arm 1 that the docstring body must
# not mention the undocumented argument in backticks ANYWHERE — a first draft said "but NOT `dt`"
# and thereby documented it.
missing_args = 0
for file in filter(f -> endswith(f, ".jl"), readdir("src"; join = true))
  s = read(file, String)
  for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, s)
    body = m.captures[1]
    sig = strip(first(split(body, "\n")))
    (occursin("(", sig) && occursin(")", sig)) || continue
    o = findfirst("(", sig).start
    c = findlast(")", sig).start
    inside = sig[nextind(sig, o):prevind(sig, c)]
    # Split on `;` FIRST, into the positional half and the keyword half, then split each on `,`.
    # The previous form took `split(p, ";")[end]` AFTER splitting on `,`, so the comma-piece
    # "dt; scalar = false" collapsed to "scalar" and `dt` was silently discarded — the LAST
    # POSITIONAL ARGUMENT of every signature carrying a `;` was invisible to this sweep, which is
    # most of the corpus. The sweep then reported 0 and was read as a clean corpus.
    # Found 2026-08-27 by falsifying the zero on a fixture, prompted by the PF session's rule that
    # a sweep reporting zero is exactly the one to distrust. See the fixture arms in the header.
    for half in split(inside, ";"), raw in split(half, ",")
      p = strip(split(split(raw, "::")[1], "=")[1])
      occursin(r"^[A-Za-zα-ωΑ-Ω][A-Za-z0-9_!α-ωΑ-Ω̂]*$", p) || continue
      q = "\\Q" * p * "\\E"
      documented = occursin(Regex("`" * q * "`"), body) ||          # `scalar`
                   occursin(Regex("`" * q * "\\s*=[^`]*`"), body)   # `scalar = false`
      if !documented
        println(file, ": ", sig, "  UNDOCUMENTED `", p, "`")
        global missing_args += 1
      end
    end
  end
end
println("undocumented arguments: ", missing_args)
exit(missing_args == 0 ? 0 : 1)

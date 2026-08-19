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
    for raw in split(inside, ",")
      p = strip(split(split(raw, "::")[1], "=")[1])
      p = strip(split(p, ";")[end])
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

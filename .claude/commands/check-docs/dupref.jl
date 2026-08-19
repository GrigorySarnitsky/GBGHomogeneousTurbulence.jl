# Same @ref target linked more than once inside one docstring — CLAUDE.md caps a target at its
# first genuine mention. Invisible in the rendered text, so it needs a source-level sweep.
using Printf
total = 0
for file in filter(f -> endswith(f, ".jl"), readdir("src"; join = true))
  s = read(file, String)
  for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, s)
    body = m.captures[1]
    targets = String[]
    for lm in eachmatch(r"\[`([^`]+)`\]\(@ref[^)]*\)", body)
      push!(targets, lm.captures[1])
    end
    for t in unique(targets)
      n = count(==(t), targets)
      if n > 1
        sig = strip(first(split(body, "\n")))
        @printf("%s: %-46s x%d   in %s\n", file, t, n, first(sig, 46))
        global total += 1
      end
    end
  end
end
println("duplicate-linked targets: ", total)

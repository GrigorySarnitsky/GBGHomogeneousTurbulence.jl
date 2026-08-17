using GBGIsotropicTurbulence
const IT = GBGIsotropicTurbulence
const MODS = [:SimulationDomain, :State, :Observables, :Cache, :Forcing,
              :Generator, :Propagator, :Particles, :SimulationRun]

function owners()
  o = Dict{String, Symbol}()
  for m in MODS, n in names(getfield(IT, m))
    s = String(n)
    s == String(m) && continue
    v = getfield(getfield(IT, m), n)
    pm = (v isa Function || v isa Type) ? nameof(parentmodule(v)) : m
    o[s] = pm in MODS ? pm : m
  end
  return o
end

# Every docstring's first mention of a name whose DEFINING module differs from the docstring's own,
# cited in plain backticks and never @ref-linked anywhere in that docstring.
function sites(apply::Bool)
  o = owners()
  n_total = 0
  for m in MODS
    f = "src/" * String(m) * ".jl"
    isfile(f) || continue
    src = read(f, String)
    edits = Tuple{Int, Int, String, Symbol}[]   # (start, stop, name, owner)
    for mm in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, src)
      body = mm.captures[1]
      base = mm.offsets[1]
      lines = split(body, "\n")
      se = something(findfirst(l -> !startswith(l, "    ") && !isempty(strip(l)), lines), 1)
      sighead = join(lines[1:se-1], "\n")
      prose_start = base + (isempty(sighead) ? 0 : ncodeunits(sighead) + 1)
      prose = join(lines[se:end], "\n")
      # The docstring's own binding names AND its own signature arguments are both off limits: the
      # cross-reference rule bars linking either, and a keyword that happens to share a name with an
      # observable elsewhere (`kinetic_energy`, `scalar_variance`) would otherwise be linked to that
      # observable — which reads as a self-link to a different object. Learned the hard way: this
      # sweep silently re-linked two arguments a manual fix had just unlinked, in the same commit.
      own = Set(String.(x.captures[1] for x in eachmatch(r"([A-Za-z_][A-Za-z0-9_!]*)\(", sighead)))
      for argmatch in eachmatch(r"\(([^)]*)\)", sighead)
        for raw in split(argmatch.captures[1], ",")
          a = strip(split(split(split(raw, "::")[1], "=")[1], ";")[end])
          isempty(a) || push!(own, a)
        end
      end
      linked = Set(String.(x.captures[1] for x in eachmatch(r"\[`([^`]+)`\]\(@", prose)))
      seen = Set{String}()
      for x in eachmatch(r"`([A-Za-z_][A-Za-z0-9_!]*)`", prose)
        p = x.captures[1]
        (haskey(o, p) && !(p in own) && !(p in linked) && !(p in seen)) || continue
        push!(seen, p)
        o[p] == m && continue
        s0 = prose_start + x.offset - 1                     # byte index of the opening backtick
        push!(edits, (s0, s0 + ncodeunits(p) + 1, p, o[p]))
        n_total += 1
      end
    end
    if apply && !isempty(edits)
      sort!(edits; by = first, rev = true)                   # back-to-front keeps offsets valid
      for (s0, s1, p, ow) in edits
        src = src[1:prevind(src, s0)] *
              "[`" * p * "`](@ref GBGIsotropicTurbulence." * String(ow) * "." * p * ")" *
              src[nextind(src, s1):end]
      end
      write(f, src)
    end
  end
  println(apply ? "LINKED " : "FOUND ", n_total, " cross-module first mentions")
end

sites(get(ENV, "APPLY", "0") == "1")

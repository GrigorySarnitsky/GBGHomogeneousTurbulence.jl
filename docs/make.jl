# Render the design-rationale doc into the site without moving it: docs/ARCHITECTURE.md stays the
# single source (referenced by CLAUDE.md), copied into src/architecture.md at build time. The copy
# (src/architecture.md) is gitignored.
function copy_rationale_pages()
  for name in ("ARCHITECTURE.md",)
    cp(joinpath(@__DIR__, name), joinpath(@__DIR__, "src", lowercase(name)); force = true)
  end
end

# The rendered-doc source set the lints scan: every src/*.jl docstring, ARCHITECTURE.md, and every
# docs/src page except the gitignored rationale COPY (linted from its source).
function _doc_lint_sources()
  sources = String[]
  for f in readdir(joinpath(@__DIR__, "..", "src"); join = true)
    endswith(f, ".jl") && push!(sources, f)
  end
  push!(sources, joinpath(@__DIR__, "ARCHITECTURE.md"))
  generated = Set(["architecture.md"])
  for (root, _, files) in walkdir(joinpath(@__DIR__, "src")), f in files
    endswith(f, ".md") && !(f in generated) && push!(sources, joinpath(root, f))
  end
  return sources
end

# Doc lint: an inline ``…`` math span must not be split across a source line by a CommonMark
# list/blockquote leader. A wrapped continuation beginning "- "/"* "/"+ "/"> "/"1." (≤ 3 leading
# spaces) is parsed as a *new list item*, which silently drops the span out of math mode — and
# Documenter does NOT flag it (the page builds, then renders the LaTeX as literal text). This guard
# fails the build instead; keep each inline span on one source line (break the prose, not the span).
function lint_inline_math()
  leader = r"^\s{0,3}([-*+>]|\d+[.)])\s"
  twobacktick = r"(?<!`)``(?!`)"
  sources = _doc_lint_sources()
  problems = String[]
  for file in sources
    isjl = endswith(file, ".jl")
    indoc = !isjl                 # .md renders entirely; .jl renders only inside """ … """ docstrings
    infence = false
    inspan = false                # inside an unclosed inline ``…`` span
    for (n, line) in enumerate(eachline(file))
      # Every docstring delimiter in this package is a lone `"""` on its own line, so toggle on that.
      if isjl && strip(line) == "\"\"\""
        indoc = !indoc; inspan = false; continue
      end
      indoc || continue
      if startswith(strip(line), "```")
        infence = !infence; inspan = false; continue
      end
      infence && continue
      if inspan && occursin(leader, line)
        push!(problems, string(relpath(file, joinpath(@__DIR__, "..")), ":", n,
                               "  inline ``math`` broken across a line by a list/blockquote leader"))
      end
      isodd(count(twobacktick, line)) && (inspan = !inspan)
    end
  end
  isempty(problems) || error("doc lint failed — keep inline math on one line:\n  " * join(problems, "\n  "))
  @info "doc lint: inline math OK across $(length(sources)) source files"
end

# Doc lint: canonical notation. A rendered-math token with a single house spelling must never appear
# in a banned variant (a silent drift — the source parses, the page renders, yet the notation
# disagrees with its sibling docstring). Extend `banned` as new canonical spellings are fixed.
function lint_notation_variants()
  banned = [
    (r"\\partial_[ijk]",
     "bare-index partial — write \\partial_{x_i} (subscript the coordinate, not the fiber index)"),
    (r"\\mathbf ?\{?k\}?",
     "\\mathbf k for the wavenumber — write \\boldsymbol{\\kappa} (vector) or \\kappa (magnitude)"),
  ]
  srcs = _doc_lint_sources()
  problems = String[]
  for file in srcs, (n, line) in enumerate(eachline(file)), (re, msg) in banned
    occursin(re, line) &&
      push!(problems, string(relpath(file, joinpath(@__DIR__, "..")), ":", n, "  ", msg))
  end
  isempty(problems) || error("doc lint failed — non-canonical notation:\n  " * join(problems, "\n  "))
  @info "doc lint: notation OK across $(length(srcs)) source files"
end

copy_rationale_pages()
lint_inline_math()
lint_notation_variants()


using Documenter
using GBGIsotropicTurbulence

# Make `using GBGIsotropicTurbulence` available to any `jldoctest` examples (recursive covers the
# submodules). Doctests are off for now (no runnable examples yet); flip `doctest = true` once added.
DocMeta.setdocmeta!(GBGIsotropicTurbulence, :DocTestSetup, :(using GBGIsotropicTurbulence); recursive = true)


makedocs(
  sitename = "GBGIsotropicTurbulence.jl",
  modules  = [
    GBGIsotropicTurbulence,
    GBGIsotropicTurbulence.SimulationState,
    GBGIsotropicTurbulence.Equations,
    GBGIsotropicTurbulence.Forcing,
    GBGIsotropicTurbulence.TimeIntegration,
    GBGIsotropicTurbulence.Particles,
    GBGIsotropicTurbulence.Driver,
  ],
  format = Documenter.HTML(
    canonical     = "https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/stable",
    collapselevel = 1,
  ),
  checkdocs = :exports,
  doctest   = false,
  pages = [
    "Home"     => "index.md",
    "Notation" => "notation.md",
    "API"  => Any[
      "Overview"               => "api.md",
      "GBGIsotropicTurbulence" => "api/GBGIsotropicTurbulence.md",
      "SimulationState"        => "api/SimulationState.md",
      "Equations"              => "api/Equations.md",
      "Forcing"                => "api/Forcing.md",
      "TimeIntegration"        => "api/TimeIntegration.md",
      "Particles"              => "api/Particles.md",
      "Driver"                 => "api/Driver.md",
    ],
    "Design & Internals" => Any[
      "Architecture" => "architecture.md",
    ],
  ],
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGIsotropicTurbulence.jl",
  devbranch = "main",
)

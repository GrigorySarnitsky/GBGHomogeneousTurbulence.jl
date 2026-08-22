# Render the design-rationale doc into the site without moving it: docs/ARCHITECTURE.md stays the
# single source (referenced by CLAUDE.md), copied into src/ at build time. The copies are gitignored.
#
# It is SPLIT at the decision log rather than copied whole. §11 is append-only by construction — it
# grows by one entry per recorded decision and never shrinks — and in 2026-08 the combined page
# reached 199.7 KiB against Documenter's 200 KiB `size_threshold`, so the next decision would have
# failed the build. Raising the threshold would have deferred that by a few entries; splitting puts
# the unbounded half on its own page, where its growth costs nothing. The source file stays one
# document, which is what CLAUDE.md points at and what a reader edits.
const DECISION_LOG_HEADING = "## 11. Decision log"

function copy_rationale_pages()
  text = read(joinpath(@__DIR__, "ARCHITECTURE.md"), String)
  cut = findfirst(DECISION_LOG_HEADING, text)
  cut === nothing && error("ARCHITECTURE.md: cannot find \"$DECISION_LOG_HEADING\" to split on")
  body, log = text[1:prevind(text, first(cut))], text[first(cut):end]
  write(joinpath(@__DIR__, "src", "architecture.md"),
        body * "\n## 11. Decision log\n\nThe decision log lives on its own page: " *
        "[Decision log](decisions.md).\n")
  write(joinpath(@__DIR__, "src", "decisions.md"),
        "# Decision log\n\nThe recorded design decisions of the package, append-only and dated. " *
        "The rest of the rationale is on the [Architecture](architecture.md) page.\n\n" *
        replace(log, DECISION_LOG_HEADING => ""; count = 1))
end

# The rendered-doc source set the lints scan: every src/*.jl docstring, ARCHITECTURE.md, and every
# docs/src page except the gitignored rationale COPY (linted from its source).
function _doc_lint_sources()
  sources = String[]
  for f in readdir(joinpath(@__DIR__, "..", "src"); join = true)
    endswith(f, ".jl") && push!(sources, f)
  end
  push!(sources, joinpath(@__DIR__, "ARCHITECTURE.md"))
  generated = Set(["architecture.md", "decisions.md"])
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
# Doc lint: DOCSTRING SHAPE — the accretion guard.
#
# A docstring can satisfy every template rule in CLAUDE.md and still be unreadable, because a review
# round edits clauses and never re-reads the whole. Measured 2026-08-19, after five rounds of
# patches: `VarianceRescaling` (then named `BandRescaling`) had reached 861 words with four
# scattered admonitions, `# Arguments`
# mid-docstring and a caveat after `# Fields`; `Simulation`'s grid-mode bullet was a 120-word run-on
# with an ungrammatical clause. Every individual edit had been correct. Nothing measured the shape,
# so nothing objected.
#
# Two guards, because the two failure modes need different treatment:
#
#   STRUCTURE is absolute — `# Arguments` before any top-level caveat, `# Fields` last. These are
#   binary, the corpus satisfies them, and any violation fails the build. (Only column-0 `!!!`
#   counts: an indented admonition is part of a list item, not a trailing caveat.)
#
#   LENGTH is a RATCHET against `docs/docstring_shape.csv`, not a fixed ceiling. A hard threshold
#   would either fire on the 20-odd long docstrings that predate the rule or be set so high it never
#   fires. The ratchet instead fails when a docstring GROWS past what it was — which is exactly the
#   accretion signal — and lets a rewrite bank the improvement. New docstrings get the hard cap.
#
# When a docstring legitimately grows, rewrite it whole rather than raise its number; when it
# shrinks, re-baseline with `DOCSTRING_SHAPE_BASELINE=1 julia --project=docs docs/make.jl`.
const SHAPE_BASELINE = joinpath(@__DIR__, "docstring_shape.csv")
const SHAPE_NEW_PARAGRAPH_CAP = 120
const SHAPE_NEW_ADMONITION_CAP = 3

function _docstring_shapes()
  shapes = Dict{String,Tuple{Int,Int,Int}}()
  roots = [joinpath(@__DIR__, "..", "src"), joinpath(@__DIR__, "..", "src", "phenomenology")]
  for root in roots, f in sort(readdir(root; join = true))
    endswith(f, ".jl") || continue
    for m in eachmatch(r"\"\"\"\n(.*?)\n\"\"\""s, read(f, String))
      body = m.captures[1]
      sig = strip(first(split(body, "\n")))
      isempty(sig) && continue
      key = string(basename(f), "::", sig)
      admonitions = count(!isnothing, match.(r"^!!! ", split(body, "\n")))
      longest = 0
      for para in split(body, r"\n[ \t]*\n")
        t = strip(para)
        (isempty(t) || any(p -> startswith(t, p), ("-", "*", "!!!", "```", "#", "|"))) && continue
        longest = max(longest, length(split(t)))
      end
      shapes[key] = (longest, admonitions, length(split(body)))
      # STRUCTURE, checked here so one walk serves both guards.
      tops = [i for (i, l) in enumerate(split(body, "\n")) if startswith(l, "!!! ")]
      fields = findfirst(==("# Fields"), split(body, "\n"))
      args = findfirst(==("# Arguments"), split(body, "\n"))
      if !isempty(tops)
        fields !== nothing && maximum(tops) > fields &&
          error("doc lint failed — caveat admonition after `# Fields` in $key")
        args !== nothing && args > minimum(tops) &&
          error("doc lint failed — `# Arguments` after a caveat admonition in $key")
      end
    end
  end
  return shapes
end

# Paragraphs that predate the always-on cap, enumerated rather than hidden. The cap used to apply
# only to a docstring the baseline did not know, which meant a re-baseline in the same commit as the
# growth blessed an over-cap paragraph permanently, and a RENAME minted a fresh key whose over-cap
# shape was frozen on the next baseline. Closing those holes exposed 21 paragraphs already over the
# limit. They are listed here so the debt is a number rather than a silence: an entry may be removed
# when its paragraph is split, and NOTHING may be added — a new or edited docstring is capped.
const SHAPE_CAP_GRANDFATHERED = Set([
  "Cache.jl::ObservablesCache(domain; scalar = false, particle_velocities = nothing)",
  "Generator.jl::Generator",
  "Generator.jl::scalar_rhs!(N̂, generator, û, φ̂, u_consumed, φ, domain;",
  "Generator.jl::velocity_integrating_factor(generator, τ)",
  "Observables.jl::energy_spectrum(û, domain)",
  "Observables.jl::integral_scale(û, domain)",
  "Observables.jl::kinetic_energy(u)",
  "Observables.jl::Observables",
  "Observables.jl::scalar_dissipation(φ̂, domain, diffusivity)",
  "Particles.jl::Particles",
  "Particles.jl::restart!(scheme, buffers) -> buffers",
  "Propagator.jl::IFLowStorageRK3()",
  "Propagator.jl::step!(scheme, state, generator, domain, buffers, cache, dt)",
  "Scalings.jl::Li2008(; dissipation_group = 0.9)",
  "SimulationDomain.jl::HouLi(; order = 36, strength = nothing)",
  "SimulationDomain.jl::PhaseShift()",
  "SimulationRun.jl::run!(callback, sim)",
  "Spectra.jl::ExponentialDissipation(β)",
  "Spectra.jl::large_scale_length(f, fp) -> Float64",
  "State.jl::random_scalar_spectral!(φ̂, domain; scalar_variance, envelope_wavenumber,",
  "State.jl::random_solenoidal_velocity_spectral!(û, domain; kinetic_energy, envelope_wavenumber,",
])


function lint_docstring_shape()
  shapes = _docstring_shapes()
  if get(ENV, "DOCSTRING_SHAPE_BASELINE", "") == "1"
    open(SHAPE_BASELINE, "w") do io
      println(io, "key,longest_paragraph_words,admonitions,total_words")
      for k in sort(collect(keys(shapes)))
        (p, a, w) = shapes[k]
        println(io, replace(k, "," => "，"), ",", p, ",", a, ",", w)
      end
    end
    @info "docstring shape baseline rewritten" entries = length(shapes)
    return
  end
  isfile(SHAPE_BASELINE) || error("doc lint failed — missing $SHAPE_BASELINE; regenerate with DOCSTRING_SHAPE_BASELINE=1")
  base = Dict{String,Tuple{Int,Int,Int}}()
  for line in Iterators.drop(eachline(SHAPE_BASELINE), 1)
    isempty(strip(line)) && continue
    parts = rsplit(line, ","; limit = 4)
    base[replace(parts[1], "，" => ",")] = (parse(Int, parts[2]), parse(Int, parts[3]), parse(Int, parts[4]))
  end
  problems = String[]
  for (key, (para, adm, words)) in shapes
    # The caps bind ALWAYS, baselined or not. They used to apply only to an unknown key, which left
    # two ways through: re-baselining in the same commit turned a new over-cap docstring into a known
    # one and skipped the cap forever, and because the key is the signature string, any RENAME
    # produced a fresh key whose over-cap shape was then frozen on the next baseline. Both were
    # exercised at once in 2026-08. A cap is an absolute limit; the ratchet is a separate mechanism
    # against accretion, and they compose rather than substitute.
    (para > SHAPE_NEW_PARAGRAPH_CAP && !(key in SHAPE_CAP_GRANDFATHERED)) &&
      push!(problems, "$key: $para-word paragraph (cap $SHAPE_NEW_PARAGRAPH_CAP)")
    adm > SHAPE_NEW_ADMONITION_CAP && push!(problems, "$key: $adm admonitions (cap $SHAPE_NEW_ADMONITION_CAP)")
    if haskey(base, key)
      bp, ba, bw = base[key]
      para > bp && push!(problems, "$key: longest paragraph grew $bp → $para words")
      adm > ba && push!(problems, "$key: admonitions grew $ba → $adm")
      words > bw && push!(problems, "$key: docstring grew $bw → $words words")
    end
  end
  isempty(problems) || error("doc lint failed — docstrings grew rather than being rewritten " *
                             "(rewrite whole, or re-baseline with DOCSTRING_SHAPE_BASELINE=1):\n  " *
                             join(sort(problems), "\n  "))
end


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
    (r"\\mathbf",
     "upright-bold \\mathbf — vectors are bold italic \\boldsymbol{u} (\\boldsymbol{\\kappa} for the wavenumber)"),
    (r"\\[dt]?frac\s*[^{\s]",
     "unbraced fraction numerator — write \\tfrac{1}{2}, never \\tfrac12 or \\tfrac N2"),
    (r"\\boldsymbol(?!\{)",
     "unbraced \\boldsymbol argument — write \\boldsymbol{u}, never \\boldsymbol u or \\boldsymbol\\omega"),
    (r"\\mathbb\s*\{?\s*[0-9]",
     "\\mathbb on a digit falls back to a plain glyph — the indicator/identity is \\mathbf{1}"),
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
lint_docstring_shape()


using Documenter
using DocumenterInterLinks
using GBGIsotropicTurbulence
# Phenomenology is deliberately not re-exported by the umbrella (ARCHITECTURE §4.7); bring its
# submodule names into scope here so the docs pages can reference them by bare name, as the DNS API is.
using GBGIsotropicTurbulence.Phenomenology
using GBGIsotropicTurbulence.Phenomenology.Spectra
using GBGIsotropicTurbulence.Phenomenology.StructureFunctions
using GBGIsotropicTurbulence.Phenomenology.Scalings

# Make `using GBGIsotropicTurbulence` available to any `jldoctest` examples (recursive covers the
# submodules). Doctests are off for now (no runnable examples yet); flip `doctest = true` once added.
DocMeta.setdocmeta!(GBGIsotropicTurbulence, :DocTestSetup, :(using GBGIsotropicTurbulence); recursive = true)


# Cross-package clickable references (DocumenterInterLinks): a backticked external object is linked to
# its own documentation through the published Sphinx-style inventory (`objects.inv`) of each package.
# `@extref` links (in the docstrings and pages) resolve against these. GBGPeriodicFields deploys only
# `dev` docs so far (no tagged release), hence the `dev` inventory. Fetched at build time — CI has network.
links = InterLinks(
  "Julia"             => "https://docs.julialang.org/en/v1/objects.inv",
  "CUDA"              => "https://cuda.juliagpu.org/stable/objects.inv",
  "AMDGPU"            => "https://amdgpu.juliagpu.org/stable/objects.inv",
  "GBGPeriodicFields" => "https://grigorysarnitsky.github.io/GBGPeriodicFields.jl/dev/objects.inv",
)


makedocs(
  sitename = "GBGIsotropicTurbulence.jl",
  modules  = [
    GBGIsotropicTurbulence,
    GBGIsotropicTurbulence.SimulationDomain,
    GBGIsotropicTurbulence.State,
    GBGIsotropicTurbulence.Observables,
    GBGIsotropicTurbulence.Cache,
    GBGIsotropicTurbulence.Forcing,
    GBGIsotropicTurbulence.Generator,
    GBGIsotropicTurbulence.Propagator,
    GBGIsotropicTurbulence.Particles,
    GBGIsotropicTurbulence.SimulationRun,
    GBGIsotropicTurbulence.Phenomenology,
    GBGIsotropicTurbulence.Phenomenology.Spectra,
    GBGIsotropicTurbulence.Phenomenology.StructureFunctions,
    GBGIsotropicTurbulence.Phenomenology.Scalings,
  ],
  format = Documenter.HTML(
    canonical     = "https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/stable",
    collapselevel = 1,
  ),
  checkdocs = :exports,
  doctest   = false,
  plugins   = [links],
  pages = [
    "Home"     => "index.md",
    "Notation" => "notation.md",
    "API"  => Any[
      "Overview"               => "api.md",
      "GBGIsotropicTurbulence" => "api/GBGIsotropicTurbulence.md",
      "SimulationRun"          => "api/SimulationRun.md",
      "SimulationDomain"       => "api/SimulationDomain.md",
      "State"                  => "api/State.md",
      "Observables"            => "api/Observables.md",
      "Cache"                  => "api/Cache.md",
      "Forcing"                => "api/Forcing.md",
      "Generator"              => "api/Generator.md",
      "Propagator"             => "api/Propagator.md",
      "Particles"              => "api/Particles.md",
    ],
    "Phenomenology" => Any[
      "Overview"           => "phenomenology.md",
      "Reference laws"     => "api/phenomenology/Phenomenology.md",
      "Spectra"            => "api/phenomenology/Spectra.md",
      "StructureFunctions" => "api/phenomenology/StructureFunctions.md",
      "Scalings"           => "api/phenomenology/Scalings.md",
    ],
    "Design & Internals" => Any[
      "Architecture"   => "architecture.md",
      "Decision log"   => "decisions.md",
      "Observables cache" => "observables_cache.md",
    ],
  ],
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGIsotropicTurbulence.jl",
  devbranch = "main",
)

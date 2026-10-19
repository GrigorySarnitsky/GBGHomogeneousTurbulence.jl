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

copy_rationale_pages()


using Documenter
using DocumenterInterLinks
using GBGCodingTools
using GBGHomogeneousTurbulence
const ROOT = normpath(joinpath(@__DIR__, ".."))
const TOOLING = GBGCodingTools.Render.pages(GBGCodingTools.ConfigIO.read_config(ROOT), ROOT)

# Make `using GBGHomogeneousTurbulence` available to any `jldoctest` examples (recursive covers the
# submodules). Doctests are off for now (no runnable examples yet); flip `doctest = true` once added.
DocMeta.setdocmeta!(GBGHomogeneousTurbulence, :DocTestSetup, :(using GBGHomogeneousTurbulence); recursive = true)


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


GBGCodingTools.makedocs(ROOT;
  sitename = "GBGHomogeneousTurbulence.jl",
  modules  = [
    GBGHomogeneousTurbulence,
    GBGHomogeneousTurbulence.SimulationDomain,
    GBGHomogeneousTurbulence.State,
    GBGHomogeneousTurbulence.Observables,
    GBGHomogeneousTurbulence.Cache,
    GBGHomogeneousTurbulence.Forcing,
    GBGHomogeneousTurbulence.Generator,
    GBGHomogeneousTurbulence.Propagator,
    GBGHomogeneousTurbulence.Particles,
    GBGHomogeneousTurbulence.SimulationRun,
  ],
  format = Documenter.HTML(
    canonical     = "https://grigorysarnitsky.github.io/GBGHomogeneousTurbulence.jl/stable",
    collapselevel = 1,
    # The decision log is exempt from the page-size limit rather than split again. It is append-only
    # history read by search and by direct link, and it crossed 200 KiB at decision 90; splitting it
    # by date would put one decision's context on a page its successors are not on, which is worse
    # for the one reader it has. Every other page stays under the default.
    size_threshold_ignore = ["decisions.md"],
  ),
  checkdocs = :exports,
  doctest   = false,
  plugins   = [links],
  pages = [
    "Home"              => "index.md",
    "Notation"          => "notation.md",
    "API"  => Any[
      "Overview"               => "api.md",
      "GBGHomogeneousTurbulence" => "api/GBGHomogeneousTurbulence.md",
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
    "Memory footprint"  => "gpu.md",
    "Validation" => "validation.md",
    "Design & Internals" => Any[
      "Architecture"   => "architecture.md",
      "Decision log"   => "decisions.md",
      "Observables cache" => "observables_cache.md",
      "Documentation tooling" => only(TOOLING),
    ],
  ],
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGHomogeneousTurbulence.jl",
  devbranch = "master",
)

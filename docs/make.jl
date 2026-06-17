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
  ],
  format = Documenter.HTML(
    canonical     = "https://grigorysarnitsky.github.io/GBGIsotropicTurbulence.jl/stable",
    collapselevel = 1,
  ),
  checkdocs = :exports,
  doctest   = false,
  pages = [
    "Home" => "index.md",
    "API"  => Any[
      "Overview"               => "api.md",
      "GBGIsotropicTurbulence" => "api/GBGIsotropicTurbulence.md",
      "SimulationState"        => "api/SimulationState.md",
      "Equations"              => "api/Equations.md",
      "Forcing"                => "api/Forcing.md",
      "TimeIntegration"        => "api/TimeIntegration.md",
    ],
  ],
)

deploydocs(
  repo      = "github.com/GrigorySarnitsky/GBGIsotropicTurbulence.jl",
  devbranch = "main",
)

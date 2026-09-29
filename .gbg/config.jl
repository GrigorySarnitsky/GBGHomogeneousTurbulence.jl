# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGHomogeneousTurbulence",
    tool = v"2.0.0-rc.48",
    docs_build = ["julia", "--project=docs", "docs/make.jl"],
    test = ["julia", "--project", "-e", "using Pkg; Pkg.test()"],
    switches = [
        Switch(target = Symbol("RULE.GIT.MANIFEST_TRACKED"), files = ["Manifest.toml"],
               reason = "the root Manifest is committed on purpose: it is the only place the unregistered GBGPeriodicFields git URL and pinned commit are recorded, so it must travel with the repo for a fresh clone or CI to resolve the dependency; nested environment manifests stay ignored"),
    ],
    generated = ["docs/src/architecture.md", "docs/src/decisions.md", "docs/src/gbg.md"],
    exclusions = [
        Exclusion(files = ["src/Phenomenology.jl", "src/phenomenology/**", "docs/src/phenomenology.md",
                           "docs/src/api/phenomenology/**", "test/phenomenology.jl"],
                  reason = "the Phenomenology module is not held to the rulebook until it is extracted into its own package (the owner, 2026-09-29)"),
    ],
)

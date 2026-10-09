# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGHomogeneousTurbulence",
    tool = v"2.0.0-rc.69",
    docs_build = ["julia", "--project=docs", "docs/make.jl"],
    test = ["julia", "--project", "-e", "using Pkg; Pkg.test()"],
    switches = [
        Switch(target = Symbol("RULE.GIT.TRACKED"), files = ["validation/**"],
               reason = "the TurTLE reproduction scripts the Validation page points at, so a reader of the published comparison can rerun it from the repository (the owner, 2026-10-05 and 2026-10-08)"),
    ],
    generated = ["docs/src/architecture.md", "docs/src/decisions.md", "docs/src/gbg.md"],
    disciplines = [:turbulence_theory, :spectral_numerics, :software_architecture],
    rules = [
        PatternRule(id = :lamb_sign,
                    statement = "The Lamb vector is ω × u; u × ω is its negation.",
                    filesets = [FileSet.CODE, FileSet.RATIONALE, FileSet.PAGES],
                    pattern = r"\\{1,2}boldsymbol\{u\}\s*\\{1,2}times\s*\\{1,2}boldsymbol\{\\{1,2}omega\}|\bu\s*×\s*ω|cross!\(\s*ω\s*,\s*u\s*,\s*ω\s*\)",
                    trigger = r"\b[Ll]amb(?![A-Za-z])", window = 3, escape = r"negat",
                    skip = ["## 11." => "## References"]),
    ],
    exclusions = [
        Exclusion(files = ["src/Phenomenology.jl", "src/phenomenology/**", "docs/src/phenomenology.md",
                           "docs/src/api/phenomenology/**", "test/phenomenology.jl"],
                  reason = "the Phenomenology module is not held to the rulebook until it is extracted into its own package (the owner, 2026-09-29)"),
    ],
)

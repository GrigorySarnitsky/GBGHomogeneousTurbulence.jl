# .gbg/config.jl — this package's settings, as data.
#
# Read by `ConfigIO`, which parses this file and evaluates nothing: only literals and the constructors
# of `Model` are accepted. Every field not written here takes its default; write a line only where the
# default is wrong for this package.
Config(
    package = "GBGHomogeneousTurbulence",
    tool = v"2.4.0",
    docs_build = ["julia", "--project=docs", "docs/make.jl"],
    test = ["julia", "--project", "-e", "using Pkg; Pkg.test()"],
    switches = [
        Switch(target = Symbol("RULE.GIT.TRACKED"), files = ["validation/**"],
               reason = "the TurTLE reproduction scripts the Validation page points at, so a reader of the published comparison can rerun it from the repository (the owner, 2026-10-05 and 2026-10-08)"),
        Switch(target = Symbol("RULE.GIT.TRACKED"), files = ["parked/**"],
               reason = "the parked reference-law module Phenomenology — its source, tests and pages kept whole, loaded and built by nothing, in the layout of the standalone package it becomes when extracted (the owner, 2026-10-16, decision 113)"),
        Switch(target = Symbol("RULE.GIT.TRACKED"), files = [".gitattributes"],
               reason = "leaves the validation folder out of GitHub's language count (the owner, 2026-10-20)"),
        Switch(target = Symbol("RULE.DOC.JULIA_MANUAL"), files = ["docs/src/examples/two_peak_scalar_mixing.md"],
               reason = "the owner's own worked example, which uses `do` blocks without the manual link (the owner, 2026-10-20)"),
        Switch(target = Symbol("RULE.TEX.SPACING"), files = ["docs/src/examples/two_peak_scalar_mixing.md"],
               reason = "the owner's own worked example, whose plot title is a LaTeX string in Julia code that the page never renders as mathematics (the owner, 2026-10-21)"),
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
)

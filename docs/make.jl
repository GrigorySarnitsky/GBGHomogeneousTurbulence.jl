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

# ------------------------------------------------------------------ review-round closure
#
# An unclosed review round cannot ship. The rulebook checks the PROSE; this one checks the
# PROCESS — whether the round that examined the prose was ever finished. Ported in shape from the PF
# session's `lint_review_closure()` (2026-08-27), which found it by watching its own rounds
# self-report as done: its rates ran 16.1 → 38.7 → 54.8 % honored across three passes, every one of
# which would have been reported closed.
#
# WHY IT READS A TRACKED MARKER AND NOT THE PILE. IT's findings piles under `.claude/doc-review/` are
# untracked working notes by standing decision. A gate that read only the pile would find no round on
# a fresh clone, find nothing unclosed, and pass — green because the evidence is missing, which is
# exactly the vacuous shape both packages have spent a week learning to distrust. The marker is
# tracked, so the failing case survives a clone.
#
# The escape hatch is a `closed:` line, required non-empty and not parsed further: the gate enforces
# that a human wrote an account, never that the account is true. An enforcement mechanism with no
# escape gets disabled the first time it is inconvenient; one whose escape leaves a committed
# artifact stays on. (That parallel is the prose ratchet's deliberate re-baseline, now
# `RULE.DOC.SHAPE`'s `gbg check --rebaseline`, and it is the same shape deliberately.)
#
# FALSIFIED before landing, four arms, each run as a full docs build:
#   1  no open rounds                  -> PASS, "review rounds closed (0 on record)"
#   2  one marker with no `closed:`    -> BUILD FAILS, names the round and its file
#   3  `closed:` carrying an account   -> PASS
#   4  `closed:` present but EMPTY     -> BUILD FAILS
#   5  a banked pile with NO marker      -> BUILD FAILS (the other direction, PF's hole)
#   6  that pile once marked and closed  -> PASS
# Arm 4 is the one worth keeping: a gate satisfied by the mere presence of the key would let
# `closed:` with nothing after it close a round, which is the escape hatch degenerating into a
# rubber stamp. Arm 5 fired for real on its first run: IT's 2026-08-24 panel pile had been closed
# two days earlier and had no tracked trace of it at all. Re-run all six after any change here.
#
# NOT BUILT, and named so the absence is a decision rather than an oversight (PF, 2026-08-27):
# this gate checks that a round was CLOSED, not that every finding in it was HONORED. The stronger
# check needs the verdicts on disk, and IT's verifiers return them as workflow results — a workflow
# script cannot write files. PF hit the consequence: its lanes write their markdown FIRST carrying
# their own ungraded verdicts, the script's demotion runs in post-processing and never reaches the
# artifact, so its gate read 30 HONORED against the script's authoritative 23 and passed a round
# with eight findings open. Any future strengthening of this gate must read the GRADER's verdicts,
# never the graded party's file. Deferred by the instrument freeze.
const REVIEW_ROUNDS = joinpath(@__DIR__, "..", ".claude", "review-rounds")

function lint_review_closure()
  isdir(REVIEW_ROUNDS) || return @info "doc lint: no review-rounds directory — nothing to close"
  open_rounds = String[]
  for f in sort(readdir(REVIEW_ROUNDS; join = true))
    endswith(f, ".md") || continue
    basename(f) == "README.md" && continue
    body = read(f, String)
    occursin(r"^closed:[ 	]*\S"m, body) && continue
    round = match(r"^round:[ 	]*(\S.*?)[ 	]*$"m, body)
    push!(open_rounds, string(round === nothing ? basename(f) : round.captures[1],
                              "  (", relpath(f, joinpath(@__DIR__, "..")), ")"))
  end
  # THE OTHER DIRECTION, and it is the hole PF shot in this design (2026-08-27): the marker's
  # CREATION is self-reported. Nothing above forces a marker to exist. Bank eighteen findings into
  # the untracked pile, never commit a marker, and CI is green with a round wide open — the missing
  # case passing again, one level up from the case the marker was introduced to close.
  #
  # It cannot be made fully structural from here: a workflow script cannot write files, so the
  # banking step cannot create the marker itself, and any agent or human instructed to do it is
  # self-reporting again. What CAN be done is make the omission fail LOCALLY, where the pile is
  # visible: a non-empty pile with no marker naming it is an unmarked round and fails the build.
  # The residue is someone ignoring a red local build and pushing anyway — a deliberate, visible act,
  # the same class as deleting a tracked marker, and left unguarded for the same reason.
  marked_piles = Set{String}()
  for f in readdir(REVIEW_ROUNDS; join = true)
    endswith(f, ".md") && basename(f) != "README.md" || continue
    m = match(r"^pile:[ \t]*(\S.*?)[ \t]*$"m, read(f, String))
    m === nothing || push!(marked_piles, strip(m.captures[1]))
  end
  unmarked = String[]
  for d in ("​.claude/doc-review", ".claude/doc-review")
    dir = joinpath(@__DIR__, "..", d)
    isdir(dir) || continue
    banked = filter(x -> occursin(r"^\d\d-.*\.md$", x), readdir(dir))
    isempty(banked) && continue
    d in marked_piles || push!(unmarked, "$d  ($(length(banked)) banked hat file(s), no marker names it)")
  end
  isempty(unmarked) || error("doc lint failed — a findings pile exists that no review-round marker " *
        "names:\n  " * join(unmarked, "\n  ") *
        "\n\nA banked round with no tracked marker is invisible to every clone but this one. " *
        "Commit a marker under .claude/review-rounds/ naming this pile, then close it there.")

  isempty(open_rounds) && return @info "doc lint: review rounds closed ($(length(readdir(REVIEW_ROUNDS)) - 1) on record)"
  error("doc lint failed — $(length(open_rounds)) review round(s) still open:\n  " *
        join(open_rounds, "\n  ") *
        "\n\nClose each by adding a non-empty `closed:` line to its marker, in the commit that " *
        "closed it. A round abandoned rather than finished still needs one saying so — deleting " *
        "the marker leaves no trace, which is what the account exists to prevent.")
end

copy_rationale_pages()
lint_review_closure()


using Documenter
using DocumenterInterLinks
using GBGCodingTools
using GBGHomogeneousTurbulence
const ROOT = normpath(joinpath(@__DIR__, ".."))
const TOOLING = GBGCodingTools.Render.pages(GBGCodingTools.ConfigIO.read_config(ROOT), ROOT)
# Phenomenology is deliberately not re-exported by the umbrella (ARCHITECTURE §4.7); bring its
# submodule names into scope here so the docs pages can reference them by bare name, as the DNS API is.
using GBGHomogeneousTurbulence.Phenomenology
using GBGHomogeneousTurbulence.Phenomenology.Spectra
using GBGHomogeneousTurbulence.Phenomenology.StructureFunctions
using GBGHomogeneousTurbulence.Phenomenology.Scalings

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
    GBGHomogeneousTurbulence.Phenomenology,
    GBGHomogeneousTurbulence.Phenomenology.Spectra,
    GBGHomogeneousTurbulence.Phenomenology.StructureFunctions,
    GBGHomogeneousTurbulence.Phenomenology.Scalings,
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
    "Memory footprint"  => "gpu.md",
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
    "Phenomenology" => Any[
      "Overview"           => "phenomenology.md",
      "Reference laws"     => "api/phenomenology/Phenomenology.md",
      "Spectra"            => "api/phenomenology/Spectra.md",
      "StructureFunctions" => "api/phenomenology/StructureFunctions.md",
      "Scalings"           => "api/phenomenology/Scalings.md",
    ],
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

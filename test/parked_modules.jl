# The parked modules — code kept in git, loaded by nothing, named on no user-facing surface.
#
# The reference-law module `Phenomenology` was parked whole under `parked/Phenomenology/` (decision
# 113): the owner ruled that nothing in the package relies on it and that the documentation a user
# reads does not mention it. A sweep claimed and not re-measured is an instance fix wearing a class's
# name, so the sweep is a test: the umbrella defines no module of that name, and the name appears in
# no file under `src/`, `docs/src/` or `README.md`. The design documents (`docs/ARCHITECTURE.md`,
# `CLAUDE.md`) keep the name as the record of the design and are not read here; nor are the copies
# of them the docs build writes into `docs/src/`, which the package's config lists as generated.
using Test
using GBGHomogeneousTurbulence
import GBGCodingTools

const ROOT = dirname(@__DIR__)
const PARKED = ["Phenomenology"]
const GENERATED = Set(GBGCodingTools.ConfigIO.read_config(ROOT).generated)

function user_facing_files()
  out = ["README.md"]
  for top in ("src", "docs/src"), (dir, _, files) in walkdir(joinpath(ROOT, top))
    for f in files
      endswith(f, ".jl") || endswith(f, ".md") || continue
      rel = replace(relpath(joinpath(dir, f), ROOT), '\\' => '/')
      rel in GENERATED || push!(out, rel)
    end
  end
  return sort!(out)
end

@testset "the parked modules are loaded by nothing and named on no user-facing surface" begin
  files = user_facing_files()
  @test length(files) ≥ 25   # the walk found the surfaces; an empty walk would pass vacuously
  for name in PARKED
    @test isdir(joinpath(ROOT, "parked", name))          # parked, not deleted
    @test !isdefined(GBGHomogeneousTurbulence, Symbol(name))
    # Case-insensitive: the module name and the physics word it was taken from are one and the same
    # on these surfaces, and a page that wants the word back is a page the owner reads first.
    hits = filter(f -> occursin(lowercase(name), lowercase(read(joinpath(ROOT, f), String))), files)
    @test isempty(hits)
  end
end

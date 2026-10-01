# Every place HT reads or writes a GBGPeriodicFields field's raw storage, `field_data(…)`, is listed
# here with the ruling that allows it. PF owns the storage layout, and HT reaching past PF's operations
# is how the mean-mode index, the resident band indicator and the raw rescalings got in (decision 99).
# The list works in both directions: a new call site fails until it is ruled on, and an entry whose
# site has gone fails until it is removed.
#
# What this cannot see: a layer built over a CORRECT PF call — a batch width or other constant fitted
# to one machine's measurements, as the below-scale observable once had (decision 98). That is caught
# only in review: a hardware-measured constant wrapped around a PF call is the sign to look for.
using Test

const PACKAGE_ROOT = normpath(joinpath(@__DIR__, ".."))

# The sites allowed, as (file relative to the package root, a fragment of the source line) => ruling.
const ALLOWED = Dict(
  ("src/SimulationDomain.jl", "fill!(field_data(f), zero(eltype(field_data(f))))") =>
    "PF 2026-09-28: PF's constructors return uninitialized memory and PF has no zeroing operation; " *
    "multiply!(f, 0, f) would keep a NaN",
  ("src/SimulationRun.jl", "scale = maximum(abs, field_data(field))") =>
    "PF 2026-09-28: reality_residual is in stored-coefficient units, so the largest stored coefficient " *
    "is its yardstick; PF's `maximum` is physical-only",
  ("src/Forcing.jl", "randn!(ou.rng, field_data(slots.draws))") =>
    "PF 2026-09-28: the draw is made into a HOST field, so a seed gives the same realization on every " *
    "backend; adapt! then moves it",
)

# Every `field_data(` in code, skipping comment lines and docstring bodies. A line is a docstring line
# when an odd number of triple quotes precedes it in the file.
function storage_sites(root)
  sites = Tuple{String, Int, String}[]
  for dir in ("src", "ext"), (path, _, files) in walkdir(joinpath(root, dir)), file in files
    endswith(file, ".jl") || continue
    full = joinpath(path, file)
    relative = replace(relpath(full, root), '\\' => '/')
    in_docstring = false
    for (number, line) in enumerate(eachline(full))
      quotes = count("\"\"\"", line)
      code = !in_docstring && quotes == 0 && !startswith(lstrip(line), "#")
      code && occursin("field_data(", split(line, '#')[1]) && push!(sites, (relative, number, strip(line)))
      isodd(quotes) && (in_docstring = !in_docstring)
    end
  end
  return sites
end

allowed(site) = any(((file, fragment),) -> file == site[1] && occursin(fragment, site[3]), keys(ALLOWED))

function unlisted_and_stale(root)
  sites = storage_sites(root)
  unlisted = filter(!allowed, sites)
  stale = [key for key in keys(ALLOWED) if !any(s -> s[1] == key[1] && occursin(key[2], s[3]), sites)]
  return unlisted, stale, length(sites)
end


@testset "raw PF storage is reached only where PF has ruled it may be" begin
  unlisted, stale, total = unlisted_and_stale(PACKAGE_ROOT)
  for (file, number, line) in unlisted
    @info "unlisted raw-storage site — use PF's operation, or get a ruling and list it" file number line
  end
  for key in stale
    @info "stale allowlist entry — its site is gone, remove it" key
  end
  @test isempty(unlisted)
  @test isempty(stale)
  @test total > 0                          # a scan that finds nothing is the scan to distrust

  # The check can fail: a planted site in a copy of the tree is reported, and so is an entry whose
  # site was deleted.
  mktempdir() do tree
    cp(joinpath(PACKAGE_ROOT, "src"), joinpath(tree, "src"))
    cp(joinpath(PACKAGE_ROOT, "ext"), joinpath(tree, "ext"))
    open(joinpath(tree, "src", "Observables.jl"), "a") do io
      println(io, "_planted(u) = field_data(u) .*= 2")
    end
    run_file = joinpath(tree, "src", "SimulationRun.jl")
    write(run_file, replace(read(run_file, String), "scale = maximum(abs, field_data(field))" => "scale = 1"))
    planted_unlisted, planted_stale, _ = unlisted_and_stale(tree)
    @test any(s -> s[1] == "src/Observables.jl" && occursin("_planted", s[3]), planted_unlisted)
    @test ("src/SimulationRun.jl", "scale = maximum(abs, field_data(field))") in planted_stale
  end
end

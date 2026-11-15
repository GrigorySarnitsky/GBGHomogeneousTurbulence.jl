# Every place HT reads or writes a GBGPeriodicFields object's raw storage — a field's, `field_data(…)`,
# or a point object's, `point_values(…)` and `point_positions(…)` — is listed
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

# The point objects' storage (the owner, 2026-11-13: the package never works on, or hands out, bare
# arrays where a PF object exists). No site reaches the VALUES at points any more. What remains
# reaches a point set's POSITIONS, each for something PF has no operation for yet; each is a request
# to PF, and its entry goes when PF answers it.
const ALLOWED_POINTS = Dict(
  ("src/Particles.jl", "supplied = point_positions(positions)") =>
    "PENDING A PF REQUEST: adopting a caller's point set onto the domain's backend AND element type; " *
    "PF's `adapt!` moves storage and refuses a change of precision",
  ("src/Particles.jl", "coordinates = point_positions(tracers.positions)") =>
    "PENDING A PF REQUEST: the identity permutation a `PointTraversalOrder` starts from is allocated " *
    "like the positions; PF has no constructor of an order for a point set",
  ("src/Particles.jl", "new_vector_point_values(tracers::Tracers) = VectorPointValues(similar(point_positions(tracers.positions)))") =>
    "PENDING A PF REQUEST: point values allocated for a point set; `similar_point_values` takes point " *
    "values as its reference, not a point set",
  ("src/Particles.jl", "ScalarPointValues(similar(point_positions(tracers.positions),") =>
    "PENDING A PF REQUEST: as the vector allocator above",
  ("src/Particles.jl", "eltype(point_positions(tracers.positions)),") =>
    "PENDING A PF REQUEST: as the vector allocator above",
  ("src/SimulationRun.jl", "!(point_positions(particles.tracers.positions) isa domain.array_family) &&") =>
    "PENDING A PF REQUEST: which backend a point set lives on; PF's array-family query is internal",
)

# Every call of one of `needles` (a string, or a regex where a longer name must not match) in code,
# skipping comment lines and docstring bodies. A line is a docstring line
# when an odd number of triple quotes precedes it in the file.
function storage_sites(root, needles = ("field_data(",))
  sites = Tuple{String, Int, String}[]
  for dir in ("src", "ext"), (path, _, files) in walkdir(joinpath(root, dir)), file in files
    endswith(file, ".jl") || continue
    full = joinpath(path, file)
    relative = replace(relpath(full, root), '\\' => '/')
    in_docstring = false
    for (number, line) in enumerate(eachline(full))
      quotes = count("\"\"\"", line)
      code = !in_docstring && quotes == 0 && !startswith(lstrip(line), "#")
      code && any(needle -> occursin(needle, split(line, '#')[1]), needles) &&
        push!(sites, (relative, number, strip(line)))
      isodd(quotes) && (in_docstring = !in_docstring)
    end
  end
  return sites
end

allowed(site, list = ALLOWED) = any(((file, fragment),) -> file == site[1] && occursin(fragment, site[3]), keys(list))

function unlisted_and_stale(root; needles = ("field_data(",), list = ALLOWED)
  sites = storage_sites(root, needles)
  unlisted = filter(site -> !allowed(site, list), sites)
  stale = [key for key in keys(list) if !any(s -> s[1] == key[1] && occursin(key[2], s[3]), sites)]
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
    forcing_file = joinpath(tree, "src", "Forcing.jl")
    write(forcing_file, replace(read(forcing_file, String),
                                "randn!(ou.rng, field_data(slots.draws))" => "randn!(ou.rng, slots.draws)"))
    planted_unlisted, planted_stale, _ = unlisted_and_stale(tree)
    @test any(s -> s[1] == "src/Observables.jl" && occursin("_planted", s[3]), planted_unlisted)
    @test ("src/Forcing.jl", "randn!(ou.rng, field_data(slots.draws))") in planted_stale
  end
end


@testset "raw PF point storage is reached only at the listed sites, and the values at points nowhere" begin
  # The accessor itself, not a longer name ending in it (`similar_point_values`, `new_vector_point_values`).
  values_needle = r"(?<![\w!])point_values\("
  point_needles = (values_needle, r"(?<![\w!])point_positions\(")
  unlisted, stale, total = unlisted_and_stale(PACKAGE_ROOT; needles = point_needles, list = ALLOWED_POINTS)
  for (file, number, line) in unlisted
    @info "unlisted raw point-storage site — use PF's operation, or raise the missing one to PF and list it" file number line
  end
  for key in stale
    @info "stale allowlist entry — its site is gone, remove it" key
  end
  @test isempty(unlisted)
  @test isempty(stale)
  @test total == length(ALLOWED_POINTS)
  # The values at points — the samples, a caller's buffers — are never unwrapped: every listed site
  # is a point set's positions.
  @test isempty(first(unlisted_and_stale(PACKAGE_ROOT; needles = (values_needle,), list = Dict())))

  # The check can fail: a planted unwrap in a copy of the tree is reported.
  mktempdir() do tree
    cp(joinpath(PACKAGE_ROOT, "src"), joinpath(tree, "src"))
    cp(joinpath(PACKAGE_ROOT, "ext"), joinpath(tree, "ext"))
    open(joinpath(tree, "src", "Cache.jl"), "a") do io
      println(io, "_planted(trail) = point_values(trail.values[1])")
    end
    planted, _, _ = unlisted_and_stale(tree; needles = point_needles, list = ALLOWED_POINTS)
    @test any(s -> s[1] == "src/Cache.jl" && occursin("_planted", s[3]), planted)
  end
end

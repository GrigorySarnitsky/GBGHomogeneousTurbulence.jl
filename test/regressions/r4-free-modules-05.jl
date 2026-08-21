# Supporting measurement for the architecture finding "Particles reaches into ObservablesCache's
# struct internals with no import from Cache at all". Not a pass/fail regression test: it prints the
# two blocks side by side and records the measured compiler-invisibility of the coupling.
#
# Measured 2026-08-21 by temporarily renaming `history_filled` -> `history_valid_count` in
# src/Cache.jl ONLY (Particles.jl untouched), then reverting:
#   julia --project -e 'using GBGIsotropicTurbulence'   ->  precompiled + loaded CLEAN
#   EndpointHeun run, two advance! steps                ->  OK, no error
#   AdamsBashforth(order = 2) run, one advance! step    ->  FieldError: type ObservablesCache has no
#                                                           field `history_filled`
# So load, precompile and the docs build are all blind to the rename; the test suite is NOT
# (test/particles.jl:139-180 and ~10 regression witnesses drive front-door AdamsBashforth runs, so
# `Pkg.test()` fails immediately). The defect is the unchecked cross-module coupling, not a silent
# wrong answer.
using GBGIsotropicTurbulence


root = (let d = @__DIR__; while !isfile(joinpath(d, "src", "GBGIsotropicTurbulence.jl")); d = dirname(d); end; d end)
show_lines(path, lines) = for n in lines
  println(lpad(n, 4), ": ", rstrip(readlines(joinpath(root, path))[n]))
end

println("=== src/Particles.jl — the module's ENTIRE cross-module import block ===")
show_lines("src/Particles.jl", 36:41)

println("\n=== src/Particles.jl — the ObservablesCache internals it nonetheless reads and writes ===")
show_lines("src/Particles.jl", [389, 390, 465, 467, 482, 489, 495])

println("\n=== src/Cache.jl — where those three fields are declared ===")
show_lines("src/Cache.jl", 142:144)

println("\n=== src/Cache.jl:365, 410 — the declaring module clearing the same field via its own verbs ===")
show_lines("src/Cache.jl", [365, 410])

println("\n=== src/SimulationRun.jl:41-43 — the convention, for the same object ===")
show_lines("src/SimulationRun.jl", 41:43)

println("\n=== why nothing forces the duck typing: Cache's own imports (no Particles => no cycle) ===")
show_lines("src/Cache.jl", 49:51)
show_lines("src/GBGIsotropicTurbulence.jl", [65, 69])

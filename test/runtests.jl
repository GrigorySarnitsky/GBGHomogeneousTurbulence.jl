# Test suite entry point for GBGIsotropicTurbulence.
#
# Each module's tests live in their own file, included into its own wrapper module so that
# top-level test helpers and constants don't collide across files. Every file is also runnable
# on its own:  julia --project=. test/<module>.jl
#
# (Mirrors the GBGPeriodicFields test layout; suites are added as the package grows.)

using Test

@testset "GBGIsotropicTurbulence" begin
  # Module-specific test files get `include`d here, e.g.:
  # module FooTests; include("foo.jl"); end
end

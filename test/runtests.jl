# Test suite entry point for GBGIsotropicTurbulence.
#
# Each module's tests live in their own file, included into its own wrapper module so that
# top-level test helpers and constants don't collide across files. Every file is also runnable
# on its own:  julia --project=. test/<module>.jl

module VelocitySliceTests; include("velocity_slice.jl"); end

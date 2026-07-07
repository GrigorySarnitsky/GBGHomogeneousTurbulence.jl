# Test suite entry point for GBGIsotropicTurbulence.
#
# Each module's tests live in their own file, included into its own wrapper module so that
# top-level test helpers and constants don't collide across files. Every file is also runnable
# on its own:  julia --project=. test/<module>.jl

module VelocitySliceTests; include("velocity_slice.jl"); end
module DealiasingTests;    include("dealiasing.jl");     end
module IntegratorsTests;   include("integrators.jl");    end
module ScalarTests;        include("scalar.jl");         end
module ForcingTests;       include("forcing.jl");        end
module ParticlesTests;     include("particles.jl");      end
module DriverTests;        include("driver.jl");         end

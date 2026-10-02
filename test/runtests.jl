# Test suite entry point for GBGHomogeneousTurbulence.
#
# Each module's tests live in their own file, included into its own wrapper module so that
# top-level test helpers and constants don't collide across files. Every file is also runnable
# on its own:  julia --project=. test/<module>.jl

# First, before any test module adds methods to the package's functions: a test fixture that
# deliberately defines a stale hook signature would otherwise read as an ambiguity in the package.
module MethodParityTests;   include("method_parity.jl");   end
module VelocitySliceTests; include("velocity_slice.jl"); end
module ObservablesCacheTests; include("observables_cache.jl"); end
module MemoryAuditTests;   include("memory_audit.jl");   end
module TemporaryAuditTests; include("temporary_audit.jl"); end
module SeedBackendsTests;  include("seed_backends.jl");  end
module DeviceHotLoopTests; include("device_hot_loop.jl"); end
module ComputeAuditTests;  include("compute_audit.jl");  end
module OptimalityAuditTests; include("optimality_audit.jl"); end
module DealiasingTests;    include("dealiasing.jl");     end
module IntegratorsTests;   include("integrators.jl");    end
module ScalarTests;        include("scalar.jl");         end
module ForcingTests;       include("forcing.jl");        end
module ParticlesTests;     include("particles.jl");      end
module SimulationRunTests; include("simulation_run.jl"); end
module PhenomenologyTests;  include("phenomenology.jl");  end
module ValidationTests;     include("validation.jl");     end
module BelowScaleTests;     include("below_scale.jl");    end
module ReynoldsTests;       include("reynolds.jl");       end
module StationaryModelTests; include("stationary_model.jl"); end
module HDF5CheckpointTests; include("hdf5_checkpoint.jl"); end
module DisplayTests;        include("display.jl");        end
module GPUMemoryPageTests;  include("gpu_memory_page.jl"); end
module PFStorageAccessTests; include("pf_storage_access.jl"); end
module AllocationsTests;     include("allocations.jl");     end
module ObservablesAnalyticTests; include("observables_analytic.jl"); end
module OracleRegistryTests;  include("oracle_registry.jl");  end
module PassAuditTests;       include("pass_audit.jl");       end

# The /bug-hunt regression witnesses. Each file is the executable form of one confirmed defect: it
# asserts the CORRECT behaviour and was observed to FAIL before its fix landed, so it is already a
# regression test and is promoted here unchanged rather than re-written into the house style. Each
# gets its own module because the witnesses were authored independently and may reuse helper names.
for witness in sort(filter(f -> endswith(f, ".jl"), readdir(joinpath(@__DIR__, "regressions"))))
  name = Symbol("Regression_", replace(splitext(witness)[1], "-" => "_"))
  path = joinpath(@__DIR__, "regressions", witness)
  @eval module $name; include($path); end
end

using GBGCodingTools
GBGCodingTools.Engine.Harness.test(dirname(@__DIR__); checks = (GBGCodingTools.Render.wiring,))

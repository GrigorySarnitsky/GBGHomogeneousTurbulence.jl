# The parked reference-law module's tests. Run on demand from the package root:
#
#     julia --project parked/Phenomenology/test/runtests.jl
#
# The module is loaded here by a bare include — it has no dependencies — so nothing in the package
# has to load it (decision 113). Each test file gets a child module of its own: the oracle tests
# bring the whole leaf into scope, while the bridge test also loads the package, whose exported
# `kolmogorov_length` would otherwise collide with the leaf's.
module ParkedPhenomenologyTests

include(joinpath(@__DIR__, "..", "src", "Phenomenology.jl"))

module Laws;   include(joinpath(@__DIR__, "phenomenology.jl"));     end   # the module's own oracles
module Bridge; include(joinpath(@__DIR__, "validation_bridge.jl")); end   # a run compared to a model

end

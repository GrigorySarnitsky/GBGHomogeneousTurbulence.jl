# Method parity — the public method set is frozen (RULE.TEST.METHOD_PARITY).
#
# The package DECLARES method parity to GBGCodingTools: the engine is the tool's
# `TestHarness.method_parity`, and the frozen numbers live in `test/method_parity_baseline.toml`. It
# asserts the methods each module defines for every public function, and each module's derived count
# over the package's whole function surface, internals included — a method added anywhere moves a
# number, and a method defined under a qualified name cannot hide, since ownership is read from the
# method, not from a namespace. It also asserts that `detect_ambiguities` over the package is empty.
#
# A moved number is refrozen deliberately, in the same commit, with the reason written beside it in the
# baseline. The owned modules are listed here; `Phenomenology` is outside the surface until it is
# extracted (the owner, 2026-09-29).
using Test
using TOML
using GBGHomogeneousTurbulence
import GBGCodingTools

const HT = GBGHomogeneousTurbulence
const OWNED_MODULES = [HT.SimulationDomain, HT.Observables, HT.State, HT.Cache, HT.Forcing,
                       HT.Generator, HT.Propagator, HT.Particles, HT.SimulationRun]
const METHOD_BASELINE = TOML.parsefile(joinpath(@__DIR__, "method_parity_baseline.toml"))

GBGCodingTools.TestHarness.method_parity(HT, OWNED_MODULES, METHOD_BASELINE)

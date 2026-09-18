# Witness: `deposit!`'s scalar-pairing guard must cover BOTH mispairings, not one.
#
# `deposit!` already names one construction mistake — a scalar-carrying state paired with a
# scalar-free cache — with an `ArgumentError` that tells the caller which keyword to set
# (`src/Propagator.jl:527–531`), and its own comment argues that such a mistake "is named here
# rather than discovered later". The sibling mispairing — a scalar-carrying state and cache paired
# with `IntegratorBuffers` built without `scalar = true`, which `allocate_buffers` defaults to —
# reaches `_recovery_scratch(buffers.scalar)` at `src/Propagator.jl:540` with `nothing` and raises
#   MethodError: no method matching _recovery_scratch(::Nothing)
# naming a package-private helper the caller never typed and cannot act on.
#
# The hand-assembled route is the documented one (both `deposit!`'s and `allocate_buffers`'
# docstrings present it), and the package treats exactly this failure shape as a defect elsewhere:
# `Generator.jl:552–557` replaced a dependency-internal `MethodError` with a named `ArgumentError`
# naming the `scalar` keyword (pinned by test/regressions/r4-aliasing-and-mutation-03.jl).
#
# Either repair satisfies this test: reject the mispairing with a package-level `ArgumentError` that
# names the keyword, or make the call work and deposit the scalar. What must not stand is the
# current outcome — a `MethodError` from a private helper.

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Propagator: deposit!


small_domain() = FixedDomain(grid_points_per_axis = 8, side_length = 2π, dealiasing = TwoThirds(),
                             element_type = Float64, array_type = Array)


@testset "deposit! names a scalar/buffers mispairing instead of dying in a private helper" begin
  # The control: the mispairing `deposit!` DOES guard — a scalar state, a scalar-free cache — is
  # rejected with a named `ArgumentError`. This is the house response to a scalar-pairing mistake.
  let domain = small_domain()
    state   = ResolvedFields(domain; scalar = true)
    cache   = ObservablesCache(domain; scalar = false)
    buffers = allocate_buffers(IFLowStorageRK3(), domain; scalar = true)
    @test_throws ArgumentError deposit!(cache, state, domain, buffers)
  end

  # The claim: the sibling mispairing — scalar state, scalar cache, scalar-free buffers, the
  # `allocate_buffers` default — must not surface as a `MethodError` from `_recovery_scratch`.
  let domain = small_domain()
    state   = ResolvedFields(domain; scalar = true)
    cache   = ObservablesCache(domain; scalar = true)
    buffers = allocate_buffers(IFLowStorageRK3(), domain)   # `scalar` defaults to false
    @test buffers.scalar === nothing                        # the precondition this witness needs

    outcome = try
      deposit!(cache, state, domain, buffers)
      nothing                                               # the other admissible repair: it works
    catch err
      err
    end
    @test !(outcome isa MethodError)
    @test outcome === nothing || outcome isa ArgumentError
  end
end

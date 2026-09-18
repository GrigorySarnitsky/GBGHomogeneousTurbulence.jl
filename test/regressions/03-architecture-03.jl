# Witness — an undeclared trajectory-field scheme must be REFUSED symmetrically by both per-scheme
# generics, not hard-errored by one and silently guessed at by the other.
#
# REWRITTEN 2026-08-21. As found, this file printed values and asserted nothing — a demonstration
# script, not a witness. That is the shape the instrument forbids: it can neither fail before a fix
# nor pass after one, so it proves nothing in either direction and the runner correctly called it
# BROKEN. The finding it was gathering evidence for was real: `allocate_buffers` had no
# `::AbstractIntegrator` fallback and hard-errored, while `_base_cfl` returned 0.3 — a constant
# appearing in no docstring, and ABOVE `IFHeun`'s 0.25, so a new scheme with a tighter stability limit
# was silently handed too large a timestep.

using Test
using GBGHomogeneousTurbulence
using GBGHomogeneousTurbulence.Propagator: AbstractIntegrator, allocate_buffers, recommended_cfl
using GBGHomogeneousTurbulence.SimulationDomain: FixedDomain, TwoThirds

struct ProbeScheme <: AbstractIntegrator end

@testset "an undeclared scheme is refused by every per-scheme generic, not guessed at" begin
  domain = FixedDomain(grid_points_per_axis = 8, side_length = 2π, element_type = Float64,
                       array_type = Array, dealiasing = TwoThirds())

  # Both generics ask the scheme for something only the scheme knows: its register set, and its
  # stability limit. Neither may invent an answer.
  @test_throws MethodError allocate_buffers(ProbeScheme(), domain)
  @test_throws MethodError recommended_cfl(ProbeScheme(), domain)

  # The declared schemes are unaffected, and their limits remain distinct — which is why no single
  # fallback value could have been right for an undeclared one.
  cfl2 = recommended_cfl(IFHeun(), domain)
  cfl3 = recommended_cfl(IFLowStorageRK3(), domain)
  @test cfl2 > 0 && cfl3 > 0
  @test cfl2 < cfl3            # 0.25 against 0.5: any fixed guess is wrong for one of them
end

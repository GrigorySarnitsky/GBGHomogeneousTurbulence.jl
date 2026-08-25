# r6-free-hot-path-02: allocate_buffers(AdamsBashforth{K}) admits a cache history deeper than
# K - 1 (its guard is `>=`), but every advect!(AdamsBashforth{K}, ...) demands strict equality
# (`== K - 1`) — so a cache built with history_depth = 5 for an order-3 scheme passes register
# allocation and then throws on the very first push, with a message blaming the buffers for being
# "built for a different order" although this scheme's own allocator built them for this call.
# Correct behaviour: a buffer set the allocator accepts must be usable by at least one push, OR the
# allocator must refuse it at construction time. Currently neither holds.

using Test
using GBGIsotropicTurbulence
using GBGPeriodicFields: VectorFieldPhysical, field_data, PointSet, CatmullRom, npoints

@testset "allocate_buffers(AdamsBashforth) either refuses an over-deep cache history or hands back buffers one advect! accepts" begin
  T = Float64
  N = 16
  L = 2π
  domain = FixedDomain(grid_points_per_axis = N, side_length = L, element_type = T,
                       dealiasing = TwoThirds(), array_type = Array)
  X0 = T[0.1 0.2 0.3; 1.0 2.0 3.0; 2.0 3.0 4.0; 4.0 5.0 6.0]
  tracers = Tracers(domain; positions = PointSet(copy(X0)), interpolation_scheme = CatmullRom)
  # A cache sized for a deeper scheme (history_depth = 5 → 4 past samples), handed to order = 3.
  cache = ObservablesCache(domain; number_of_particles = npoints(tracers.positions),
                           history_depth = 5)
  scheme = AdamsBashforth(order = 3)

  buffers = try
    allocate_buffers(scheme, tracers, cache)
  catch err
    err
  end

  if buffers isa Exception
    # Acceptable resolution: the allocator refuses the mismatched history at construction time.
    @test buffers isa ArgumentError
  else
    # The allocator accepted the cache, so the buffers it built must survive at least one push.
    u = VectorFieldPhysical(zeros(T, N, N, N, 3), domain.grid)
    field_data(u)[:, :, :, 1] .= 0.5
    deposit!(cache, tracers, u)
    @test try
      advect!(scheme, tracers, u, domain, buffers, 0.01)
      true
    catch
      false                     # the push refused buffers its own allocator handed back
    end
  end
end

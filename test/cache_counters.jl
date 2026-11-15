# An audit calls one operation at a time, out of the order a run keeps and more than once, where the
# particle step and the particle deposit each refuse to run unless the cache's two counters say the
# field and the positions are where that operation needs them. These put the counters there by hand.
# They touch no array, so they add nothing to what an audit measures; a run never needs them.

# As an iteration stands before its particle step: the fields one step past the positions, and the
# newest velocity sample taken at those positions.
function ready_for_particle_step!(cache)
  cache.particles_epoch = cache.fields_epoch - 1
  cache.velocity_at_particles_epoch = cache.particles_epoch
  return cache
end

# As it stands after the particle step: the positions caught up, not yet sampled.
function ready_for_particle_deposit!(cache)
  cache.particles_epoch = cache.fields_epoch
  cache.velocity_at_particles_epoch = cache.particles_epoch - 1
  return cache
end

# As it stands between iterations: the positions caught up and sampled.
function paired!(cache)
  cache.particles_epoch = cache.fields_epoch
  cache.velocity_at_particles_epoch = cache.particles_epoch
  return cache
end

# A time later than any sample's, for a deposit made out of order.
const LATER = Ref(1.0e6)
later() = (LATER[] += 1.0)

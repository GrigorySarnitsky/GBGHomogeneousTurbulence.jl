# A velocity field written by formula, put in the observables cache the way the field step and its
# deposit put theirs: the slot is borrowed, written, and marked as filled at the fields' new epoch.
# To the particle step this is indistinguishable from a real field step, so a tracer can be advected
# in a flow whose trajectories are known exactly, with every check of the step and of the particle
# deposit in force.

using GBGHomogeneousTurbulence.Cache: take_velocity!, deposit_velocity!, advance_fields_epoch!

# `write!(u)` fills the cache's velocity in physical representation. `step = false` writes the field
# of the starting time, before any step has been taken.
function deposit_prescribed_velocity!(write!, cache; step::Bool = true)
  step && advance_fields_epoch!(cache)
  write!(take_velocity!(cache))
  deposit_velocity!(cache)
  return cache
end

# Advance `tracers` through the step sizes `steps` from time `t0` in the flow `write!(u, t)`: the
# starting field and sample, then, per step, the field at the new time, the particle step and the
# particle deposit. Returns the final time.
function advect_in_prescribed_flow!(write!, scheme, tracers, domain, cache, steps; t0 = 0.0,
                                    traversal = nothing, started::Bool = false)
  if !started
    deposit_prescribed_velocity!(u -> write!(u, t0), cache; step = false)
    deposit!(cache, tracers, t0; traversal)
  end
  t = t0
  for h in steps
    deposit_prescribed_velocity!(u -> write!(u, t + h), cache)
    advect!(scheme, tracers, domain, cache, h; traversal)
    t += h
    deposit!(cache, tracers, t; traversal)
  end
  return t
end

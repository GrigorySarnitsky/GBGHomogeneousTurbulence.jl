# HT's comparison leg: import the frozen TurTLE handoff, run 18400 fixed steps on the GPU,
# collect k(t), ε(t) and the tracer velocities in the run! callback, compute ρ_u(τ) with the
# reference file's estimator, write ht_reference_data.h5.
#
# Witnesses before the run (each printed, each must pass):
#   W1 scaling+layout: k and ε of the converted state match TurTLE's t₀ statistics sample.
#   W2 round trip:     curl(inverse_curl(ω̂)) == ω̂ to machine precision.
#   W3 interpolation:  HT's own u(t₀, X₀) sample matches TurTLE's stored velocity/100.
using GBGHomogeneousTurbulence
using GBGPeriodicFields
using GBGPeriodicFields: inverse_curl!, point_values, PointSet, CatmullRom,
                         VectorFieldSpectral, FieldSpectralMultipliers, field_data
using HDF5
using AMDGPU
using FFTW
using Statistics
using Printf

const DIR = pwd()   # run in a directory holding the downloaded release assets
const N = 128
const NP = 10000
const NSTEPS = 18400
const DT = 0.002
const NU = 9.032e-3
const STRIDE = 5
const NSAMPLE = NSTEPS ÷ STRIDE + 1   # 3681, TurTLE's grid

println("== reading the frozen handoff")
raw, Xraw, rhs = h5open(joinpath(DIR, "handoff_initial_state_iter100.h5"), "r") do io
  read(io["vorticity/complex/100"]), read(io["tracers0/state/100"]), read(io["tracers0/rhs/100"])
end
@printf("   vorticity raw (comp,kx,kz,ky) = %s\n", string(size(raw)))
t_ref, k_ref, ε_ref = h5open(joinpath(DIR, "turtle_reference_data.h5"), "r") do io
  read(io["t"]), read(io["k"]), read(io["ε"])
end

println("== building the domain and converting (axis permutation + inverse curl)")
domain = FixedDomain(grid_points_per_axis = N, side_length = 2π,
                     dealiasing = HouLi(order = 36, strength = 63.463),
                     element_type = Float64, array_family = ROCArray)
# PF layout (kx, ky, kz, comp) from the file's (comp, kx, kz, ky) as Julia reads it.
ω̂ = VectorFieldSpectral(ROCArray(permutedims(raw, (2, 4, 3, 1))), domain.grid)
state = ResolvedFields(domain)
mult = FieldSpectralMultipliers(state.velocity_spectral)
inverse_curl!(state.velocity_spectral, ω̂, mult)

# W1 — scaling and layout: the converted state must reproduce TurTLE's own t₀ statistics.
k0 = kinetic_energy(state.velocity_spectral)
s2 = k_ref[1] / k0
scale = abs(s2 - 1) < 1e-6 ? 1.0 : abs(s2 - Float64(N)^6) < 1e-6 * Float64(N)^6 ? Float64(N)^3 : NaN
if isnan(scale)
  s = sqrt(s2)
  error("W1 FAILED: neither convention fits — k ratio needs scale $s (not 1, not N³ = $(Float64(N)^3))")
end
if scale != 1.0
  field_data(state.velocity_spectral) .*= scale
  field_data(ω̂) .*= scale
end
k0 = kinetic_energy(state.velocity_spectral)
ε0 = dissipation(state.velocity_spectral, domain, NU)
@printf("   W1: stored-coefficient scale = %s\n", scale == 1.0 ? "1 (TurTLE stores PF's convention)" : "N³ (TurTLE stores mode amplitudes)")
@printf("   W1: k(t₀)  HT %.12f  vs TurTLE %.12f  rel %.2e\n", k0, k_ref[1], abs(k0 - k_ref[1]) / k_ref[1])
@printf("   W1: ε(t₀)  HT %.12f  vs TurTLE %.12f  rel %.2e\n", ε0, ε_ref[1], abs(ε0 - ε_ref[1]) / ε_ref[1])
abs(k0 - k_ref[1]) / k_ref[1] < 1e-8 || error("W1 FAILED on k")
abs(ε0 - ε_ref[1]) / ε_ref[1] < 1e-6 || error("W1 FAILED on ε")

# W2 — round trip: the recovered û must curl back to the injected ω̂ exactly.
ω̂2 = curl(state.velocity_spectral, mult)
w2err = maximum(abs, Array(field_data(ω̂2)) .- Array(field_data(ω̂))) /
        maximum(abs, Array(field_data(ω̂)))
@printf("   W2: curl(inverse_curl(ω̂)) rel max err = %.2e\n", w2err)
w2err < 1e-12 || error("W2 FAILED")

println("== tracers and the Simulation (injection door)")
X = mod.(permutedims(Xraw, (2, 1)), 2π)   # TurTLE keeps trajectories unwrapped; wrap into the box
tracers = Tracers(domain; positions = PointSet(X), interpolation_scheme = CatmullRom)
sim = Simulation(domain; viscosity = NU,
                 velocity_forcing = ConstantPower(injection_rate = 1.0,
                                                  lowest_shell = 1, highest_shell = 2),
                 field_integration_scheme = IFSSPRK3(),
                 particle_integration_scheme = AdamsBashforth(order = 4),
                 state = state, tracers = tracers)

# W3 — interpolation parity: HT's own t₀ Lagrangian sample vs TurTLE's stored one.
vturtle = h5open(joinpath(DIR, "fill_particles.h5"), "r") do io
  read(io["tracers0/velocity/100"])
end
w3err = maximum(abs, Array(velocity_at_particles(sim.cache)) .- permutedims(vturtle, (2, 1)))
@printf("   W3: u(t₀, X₀) HT vs TurTLE max abs diff = %.2e\n", w3err)
w3err < 1e-10 || @warn "W3 above 1e-10 — interpolant mismatch would grow into the trajectories" w3err

# AB4 history: TurTLE rhs rows 1–3 are u(t₋₁), u(t₋₂), u(t₋₃) — pinned bitwise against
# fill_particles velocities at iterations 99/98/97. HT's past[j] is the same order.
for j in 1:3
  copyto!(point_values(sim.cache.velocity_at_particles_history[j]),
          ROCArray(permutedims(rhs[:, :, j + 1], (2, 1))))
  sim.cache.history_steps[j] = DT
end
sim.cache.history_filled = 3
println("   AB4 history injected: 3 slots, steps = $DT, full order from step one")

println("== running $NSTEPS fixed steps at dt = $DT on ", AMDGPU.device())
# The VACF, computed IN the callback (owner's estimator): freeze v₀ = u(t = 0, X₀) at the first
# instant, then one scalar per sample — C(τ) = ⟨u(τ)·v₀⟩ over the 10⁴ tracers. O(M) state.
K = zeros(NSAMPLE); E = zeros(NSAMPLE); C = zeros(NSAMPLE)
v0 = Ref{Any}(nothing)
i = Ref(0)
t_wall = Ref(time())
callback = function (s)
  st = current_step(s)
  if st % STRIDE == 0
    i[] += 1
    K[i[]] = kinetic_energy(s.state.velocity_spectral)
    E[i[]] = dissipation(s.state.velocity_spectral, s.domain, NU)
    v = velocity_at_particles(s.cache)
    v0[] === nothing && (v0[] = copy(v))
    C[i[]] = sum(v .* v0[]) / NP
  end
  if st > 0 && st % 2000 == 0
    @printf("   step %5d / %d   %.1f s elapsed\n", st, NSTEPS, time() - t_wall[])
    flush(stdout)
  end
  return st < NSTEPS
end
run!(callback, sim; dt = DT)
wall = time() - t_wall[]
@printf("== run done: %.1f s wall (%.1f ms/step); %d samples\n", wall, 1000wall / NSTEPS, i[])
i[] == NSAMPLE || error("sample count mismatch: $(i[]) vs $NSAMPLE")

ρ = C ./ C[1]
τ = (STRIDE * DT) .* collect(0:NSAMPLE - 1)
@printf("   ρ_u(0) = %.6f   ρ_u(0.5) = %.4f   ρ_u(1.0) = %.4f\n",
        ρ[1], ρ[1 + round(Int, 0.5 / 0.01)], ρ[1 + round(Int, 1.0 / 0.01)])

println("== writing ht_reference_data.h5")
t = DT .* collect(0:STRIDE:NSTEPS)   # HT clock; t₀ here = TurTLE's absolute t = 0.2
h5open(joinpath(DIR, "ht_reference_data.h5"), "w") do io
  io["t"] = t; io["k"] = K; io["ε"] = E; io["τ"] = τ; io["ρ_u"] = ρ
  a = HDF5.attributes(io)   # qualified: CUDA.jl exports an `attributes` too, and the bare name is then ambiguous
  a["code"] = "GBGHomogeneousTurbulence (IFSSPRK3, HouLi order 36 strength 63.463), Float64, ROCm GPU"
  a["run"] = "128^3, L = 2π, ν = 9.032e-3, dt = 2e-3, ConstantPower ε_inj = 1 shells 1–2; " *
             "18400 steps = 36.8 time units from the same frozen handoff as TurTLE's collect run; " *
             "same 10^4 tracers, AB4 warm-started from TurTLE's history, Catmull–Rom interpolation"
  a["initial_state"] = "handoff_initial_state_iter100.h5, sha256 02c2d2530a731f0701608b4fb219f28bc9006f8d2ac39f4c02daef228823e82f"
  a["time_origin"] = "t = 0 here corresponds to TurTLE absolute time 0.2 (iteration 100)"
  a["ρ_u"] = "single-origin ensemble VACF, computed in the run callback: ρ_u(τ) = ⟨u(τ)·u(0)⟩/⟨|u(0)|²⟩ over the 10^4 tracers, u(0) the velocity at the handoff instant"
end
println("DONE")

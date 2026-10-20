# Two-peak scalar mixing

This example uses `GBGHomogeneousTurbulence` to study a classic problem of scalar mixing: the
relaxation of a two-peak scalar distribution in stationary isotropic turbulence. The two peaks can
be set up in several ways. Here the box is split into two equal slabs, with ``\varphi = -1`` in one
and ``\varphi = 1`` in the other. Up to the smoothed edges of the slabs, the initial probability
density function of ``\varphi`` is then a pair of delta functions,

```math
f(\varphi, 0) = \frac{1}{2}\bigl[\delta(\varphi + 1) + \delta(\varphi - 1)\bigr].
```

The video below shows the mixing. Its left pane is the scalar on a plane section of the box, and its right
pane is the density ``f(\varphi, t)``.

```@raw html
<video controls loop muted playsinline width="100%">
  <source src="../../assets/mix_top_hat.mp4" type="video/mp4">
</video>
```

## Preparing the velocity field

First we bring the velocity field to a statistically stationary state, into which the scalar is
later released. The run is forced at a constant injection rate ``\varepsilon``, the default
[`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) forcing.

The resolution is set by `κ_max_η = 1.5`, the product ``\kappa_{\max}\eta`` of the largest
resolved wavenumber and the Kolmogorov length, from which the viscosity is derived. On the ``192^3`` grid with [`PhaseShift`](@ref GBGHomogeneousTurbulence.SimulationDomain.PhaseShift) dealiasing, the stationary flow reaches ``\mathrm{Re}_\lambda \approx 100`` and ``L/\eta \approx 383``, where ``L`` is the box side.

The run is advanced for twenty large-eddy times ``k/\varepsilon`` and written to an HDF5 file; the scalar
runs below start from that file.

The code below is written for ROCm. To use CUDA, load `CUDA` instead of `AMDGPU` and pass
`array_family = CuArray`. The run takes about 13 minutes on a Radeon RX 7900 XTX, and ???
minutes on a GeForce RTX 5070 Ti.

```julia
using AMDGPU
using HDF5
using GBGHomogeneousTurbulence

function write_stationary_run(; file_name_write, grid_points_per_axis, element_type, array_family)
  sim = Simulation(
    grid_points_per_axis = grid_points_per_axis,
    element_type = element_type,
    array_family = array_family,
    κ_max_η = 1.5,
    dealiasing = PhaseShift(),
    field_integration_scheme = IFLowStorageRK4(),
  )

  run!(sim) do s
    k, ε = kinetic_energy_and_dissipation(s.state.velocity_spectral, s.domain, s.generator.conditions.viscosity)
    current_time(s) < 20 * k / ε
  end
  
  h5open(file_name_write, "w") do file
    write_simulation(file, "stationary", sim)
  end
  
  return sim
end

@time write_stationary_run(
  file_name_write = "stationary.h5",
  grid_points_per_axis = 192,
  element_type = Float32,
  array_family = ROCArray
)

AMDGPU.reclaim()
```

## Next section


```julia
using GBGPeriodicFields
using GBGStreamingStatistics

function smooth_top_hat(x, L, N)
  δ = 3 * L / N
  return -tanh(L * cos(2π * x / L) / (2π * δ))
end

function mix_top_hat(; file_name_read, file_name_write, turnovers, snapshots_per_turnover, array_family)
  stationary_sim = h5open(file_name_read, "r") do file
    read_simulation(file, "stationary"; array_family)
  end

  domain = stationary_sim.domain
  L = domain.grid.domain_size[1]
  N = domain.grid.grid_size[1]
  
  ν = stationary_sim.generator.conditions.viscosity
  k, ε = kinetic_energy_and_dissipation(stationary_sim.state.velocity_spectral, domain, ν)

  # first create the initial scalar field in physical representation,
  # then convert it to the spectral one stored in the state
  φ = ScalarFieldPhysical(array_family, (x, y, z) -> smooth_top_hat(x, L, N), domain.grid; layout = domain.layout)
  φ̂ = to_spectral(φ, domain.transform_plans)
  truncate_to_band!(φ̂, domain)

  state = ResolvedFields(stationary_sim.state.velocity_spectral, φ̂)
  sim = Simulation(domain; viscosity = ν, state, scalar = PassiveScalar())

  h5open(file_name_write, "w") do file
    pdfs = create_group(file, "PDFs")
    snapshots = create_group(file, "snapshots")
    
    snapshot = every_time(k / ε / snapshots_per_turnover)
    k_t, ε_t, t = Float64[], Float64[], Float64[]
    count = 0
    
    run!(sim) do s
      k_current, ε_current = kinetic_energy_and_dissipation(s.state.velocity_spectral, domain, ν)
      push!(k_t, k_current)
      push!(ε_t, ε_current)
      push!(t,   current_time(s))
      
      if snapshot(s)
        count += 1
        name = lpad(count, 4, '0')

        φ_summary = Histogram1D(array_family, -1.25, 1.25, 10^4)
        observe!(φ_summary, field_data(scalar_physical(s.cache)))
        pdfs[name] = φ_summary
        attributes(pdfs[name])["time"] = current_time(s)

        snapshots[name] = Array(field_data(scalar_physical(s.cache))[:, :, 1])
        attributes(snapshots[name])["time"] = current_time(s)
      end
      current_time(s) < turnovers * k / ε
    end
   
    # time averages via explicit integration, since the timestep is adaptive
    k_mean = sum(0.5 * (k_t[1:end-1] .+ k_t[2:end]) .* diff(t)) / (t[end] - t[1])
    ε_mean = sum(0.5 * (ε_t[1:end-1] .+ ε_t[2:end]) .* diff(t)) / (t[end] - t[1])

    attributes(file)["L"] = L
    attributes(file)["N"] = N
    attributes(file)["ν"] = ν
    
    attributes(file)["k"] = k_mean
    attributes(file)["ε"] = ε_mean

    attributes(file)["Re_λ"] = reynolds_taylor(k_mean, ε_mean, ν)
  end
  
  return sim
end

@time mix_top_hat(
  file_name_read = "stationary.h5",
  file_name_write = "mix_top_hat.h5",
  turnovers = 3,
  snapshots_per_turnover = 180,
  array_family = ROCArray,
)

AMDGPU.reclaim()
```

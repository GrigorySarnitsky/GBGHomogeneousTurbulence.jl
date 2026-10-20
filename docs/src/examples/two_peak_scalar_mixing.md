# Two-peak scalar mixing

This is a short guide how to use `GBGHomogeneousTurbulence` to study the classic problem of scalar mixing: the relaxation of an initial a two-peak . There are several ways to initialize the two-peak scalar distribution, here we follow a simple where the simulation domain. Below is the video of the , that has 

```@raw html
<video controls loop muted playsinline width="100%">
  <source src="../../assets/mix_top_hat.mp4" type="video/mp4">
</video>
```

## Initializing the velocity field

First we need to prepare .

The code below is written for ROCm. To use CUDA simply switch to `using CUDA` and `array_family = CuArray`. On Radeon RX 7900 XT/XTX it takes around 13 minutes to execute this code, and ??? minutes on GeForce RTX 5070 Ti.

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



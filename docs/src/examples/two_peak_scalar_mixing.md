# Two-peak scalar mixing

This example uses `GBGHomogeneousTurbulence` to study a classic problem of scalar mixing: the relaxation of a two-peak scalar distribution in stationary isotropic turbulence. The two peaks can be set up in several ways. Here the box is split into two equal slabs, with ``\varphi = -1`` in one and ``\varphi = 1`` in the other. Up to the smoothed edges of the slabs, the initial probability density function of ``\varphi`` is then a pair of delta functions,

```math
f(\varphi, 0) = \frac{1}{2}\bigl[\delta(\varphi + 1) + \delta(\varphi - 1)\bigr].
```

The video below shows the mixing. Its left pane is the scalar on a plane section of the box, and its right pane is the probability density ``f(\varphi, t)``.

```@raw html
<video controls loop muted playsinline width="100%">
  <source src="../../assets/mixing_slabs_192.mp4" type="video/mp4">
</video>
```

## Preparing the velocity field

First we bring the velocity field to a statistically stationary state, into which the scalar is later released. The run is forced at a constant injection rate ``\varepsilon``, the default [`ConstantPower`](@ref GBGHomogeneousTurbulence.Forcing.ConstantPower) forcing.

The resolution is set by `κ_max_η = 1.5`, the product ``\kappa_{\max}\eta`` of the largest resolved wavenumber and the Kolmogorov length, from which the viscosity is derived. On a ``192^3`` grid with [`PhaseShift`](@ref GBGHomogeneousTurbulence.SimulationDomain.PhaseShift) dealiasing, the stationary flow reaches ``\mathrm{Re}_\lambda \approx 100`` and ``L/\eta \approx 383``, where ``L`` is the box side.

The run is advanced for twenty large-eddy times ``k/\varepsilon`` and written to an HDF5 file; the scalar runs below start from that file.

The code is written for ROCm. To use CUDA, load `CUDA` instead of `AMDGPU` and pass `array_family = CuArray`. The run takes about 12 minutes on a Radeon RX 7900 XTX and 9 minutes on a GeForce RTX 5070 Ti.

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

## Releasing the scalar

Next we release the scalar into the stationary flow prepared in the previous step. At the start the scalar fills the two slabs: ``\varphi = 1`` where ``L/4 < x < 3L/4`` and ``\varphi = -1`` elsewhere. Each edge is a ``\tanh`` profile whose length scale is three grid spacings, so that the grid resolves it. The scalar has Schmidt number one and is unforced, so its variance decays. The velocity is still forced at constant power, so the flow stays stationary.

The run lasts three large-eddy times (``3 k / \varepsilon``), and 180 times per ``k/\varepsilon`` it writes two records to an HDF5 file: the values of ``\varphi`` on the plane ``z = 0``, and a histogram of ``\varphi`` over the whole box, built with [`GBGStreamingStatistics`](https://grigorysarnitsky.github.io/GBGStreamingStatistics.jl), from which ``f(\varphi, t)`` is later estimated. The time averages of ``k`` and ``\varepsilon`` and the resulting ``\mathrm{Re}_\lambda`` are stored in the same file. The run takes about 3 minutes on a Radeon RX 7900 XTX and 2 minutes on a GeForce RTX 5070 Ti.

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

  # initial top-hat profile
  φ = ScalarFieldPhysical(array_family, (x, y, z) -> smooth_top_hat(x, L, N),
    domain.grid; layout = domain.layout)

  # scalar in the state is stored in spectral representation
  φ̂ = to_spectral(φ, domain.transform_plans)
  truncate_to_band!(φ̂, domain) # apply dealias low-pass kernel

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
        HDF5.attributes(pdfs[name])["time"] = current_time(s)

        snapshots[name] = Array(field_data(scalar_physical(s.cache))[:, :, 1])
        HDF5.attributes(snapshots[name])["time"] = current_time(s)
      end
      current_time(s) < turnovers * k / ε
    end
   
    # time averages via explicit integration, since the timestep is adaptive
    k_mean = sum(0.5 * (k_t[1:end-1] .+ k_t[2:end]) .* diff(t)) / (t[end] - t[1])
    ε_mean = sum(0.5 * (ε_t[1:end-1] .+ ε_t[2:end]) .* diff(t)) / (t[end] - t[1])

    HDF5.attributes(file)["L"] = L
    HDF5.attributes(file)["N"] = N
    HDF5.attributes(file)["ν"] = ν
    
    HDF5.attributes(file)["k"] = k_mean
    HDF5.attributes(file)["ε"] = ε_mean

    HDF5.attributes(file)["Re_λ"] = reynolds_taylor(k_mean, ε_mean, ν)
  end
  
  return sim
end

@time mix_top_hat(
  file_name_read = "stationary.h5",
  file_name_write = "mixing_slabs.h5",
  turnovers = 3,
  snapshots_per_turnover = 180,
  array_family = ROCArray,
)

AMDGPU.reclaim()
```

## Plotting the results

Each record in the file becomes one frame of the video above. The scalar on the plane ``z = 0`` is drawn as a heatmap. The histogram is read back from the file, and the density ``f(\varphi, t)`` is estimated from it with a Gaussian kernel. The kernel's bandwidth is chosen by the improved Sheather–Jones rule and kept at two bin widths or more. The density curve uses the same color scale as the heatmap, so a value of ``\varphi`` has one color in both panes. The frames are written as PNG files.

```julia
using Plots
using LaTeXStrings
using Printf

default(;fontfamily = "Computer Modern")

function plot_snapshots(;file_name_read, folder_path_write)
  mkpath(folder_path_write)
  
  h5open(file_name_read, "r") do file
    turnover_time = read_attribute(file, "k") / read_attribute(file, "ε")
    Re_λ = round(Int, read_attribute(file, "Re_λ"))
    L, N = read_attribute(file, "L"), read_attribute(file, "N")
    x, y = (0:N-1) ./ N, (0:N-1) ./ N
    
    pdfs = file["PDFs"]
    snapshots = file["snapshots"]
    
    for name in sort(keys(snapshots))
      time = read_attribute(snapshots[name], "time")
      τ = @sprintf("%.2f", time / turnover_time) 

      summary = read_histogram(pdfs, name)
      Δ = 1 / summary.scale
      φ = range(summary.lower + Δ / 2, summary.upper - Δ / 2; step = 10*Δ)
      h = max(bandwidth(summary; rule = :isj), 2Δ)
      pdf_φ = GBGStreamingStatistics.density(summary, φ; h = h)

      plane = read(snapshots[name])
      
      plot_pdf = plot(
        φ, pdf_φ;
        line_z = φ, color = cgrad(:RdBu, rev = true), clims = (-1, 1), colorbar = false,
        linewidth = 2.5, legend = false,
        background_color_inside = :gray, gridcolor = :whitesmoke, gridlinewidth = 1.5,
        xlims = (-1.25, 1.25), ylims = (0, 12),
        xlabel = L"\varphi", ylabel = L"f(\varphi, t)",
        right_margin = 2Plots.mm,
      )

      plot_snapshot = heatmap(
        x, y, permutedims(plane); color = cgrad(:RdBu, rev = true),
        clims = (-1, 1), aspect_ratio = 1, xlims = (0, 1), ylims = (0, 1),
        xlabel = L"x/L", ylabel = L"y/L",
      )

      figure = plot(plot_snapshot, plot_pdf;
        layout = grid(1, 2; widths = [0.562, 0.438]),
        size = (960, 440), dpi = 200,
        plot_title = L"t = %$(τ) \, k / \varepsilon,\ \mathrm{Re}_\lambda = %$(Re_λ),\ \mathrm{Sc} = 1",
        left_margin = 5Plots.mm, bottom_margin = 5Plots.mm,
      )
      
      savefig(figure, joinpath(folder_path_write, "$name.png"))
    end
  end
end

@time plot_snapshots(
  file_name_read = "mixing_slabs.h5",
  folder_path_write = joinpath("figures", "frames")
)
```

Finally, use `ffmpeg` in a terminal to join the frames into the video:

```console
ffmpeg -framerate 30 -i figures/frames/%04d.png -c:v libx264 -pix_fmt yuv420p -crf 23 -preset slow -movflags +faststart figures/mixing_slabs_192.mp4
```

## Mixing on a 512³ grid
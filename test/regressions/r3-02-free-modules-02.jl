# Witness: a Phenomenology model spectrum handed to the front door must be usable on the GPU.
#
# `Simulation(; initial_spectrum = <an EnergySpectrum>)` builds
#     ic_spectrum = κ -> spectrum(initial_spectrum, κ, fp)      (src/SimulationRun.jl:304)
# and hands it to `random_solenoidal_velocity_spectral!`, which wraps it in the `sigma` of PF's
# `radial_kernel` (src/State.jl:128).  PF's documented contract for that `sigma` is that it must be
# GPU-safe — "capture only values … a closure holding a `Type` is not a bitstype and a device
# rejects it at launch" — and CUDA.jl states that "all arguments of a CUDA kernel need to be
# bitstypes".  A `ModelSpectrum` carries a `Reference` whose `citation::String` is not isbits, so
# the closure captures a non-bitstype value and the branch cannot launch.
#
# The CUDA block runs only where a device is present; the bitstype assertions run everywhere.

using Test, GBGIsotropicTurbulence
using GBGIsotropicTurbulence.Phenomenology: FlowParameters
using GBGIsotropicTurbulence.Phenomenology.Spectra: VonKarman1948, spectrum
import Random

const HAVE_CUDA = try
  @eval using CUDA
  CUDA.functional()
catch
  false
end

# src/SimulationRun.jl:304 verbatim, inside a function so the captures are locals.
build_phenomenology_closure(model, fp) = (κ -> spectrum(model, κ, fp))

# src/State.jl's default branch, verbatim in shape: values only.
function build_default_closure(T, envelope_wavenumber)
  zero_value = zero(T)
  inverse_peak_squared = one(T) / T(envelope_wavenumber)^2
  return k2 -> ifelse(k2 > zero_value, exp(-inverse_peak_squared * k2), zero_value)
end

@testset "A Phenomenology-seeded run meets PF's radial-kernel bitstype contract and launches on a GPU" begin
  fp = FlowParameters(; viscosity = 1e-2, dissipation = 0.34,
                      rms_velocity = 1.0, integral_scale = 0.5)

  # The control: the default Gaussian branch honours the contract.
  @test isbitstype(typeof(build_default_closure(Float64, 4.0)))

  # The claim: the Phenomenology branch must honour it too.
  @test isbitstype(typeof(build_phenomenology_closure(VonKarman1948(), fp)))

  if HAVE_CUDA
    # The control: the default seed launches on the device.
    @test Simulation(; grid_points_per_axis = 8, viscosity = 0.05,
                     array_type = CuArray, rng = Random.Xoshiro(1)) isa Simulation
    # The claim: so must the documented Phenomenology seed.
    @test Simulation(; grid_points_per_axis = 8, viscosity = 0.05, array_type = CuArray,
                     initial_spectrum = VonKarman1948(), rng = Random.Xoshiro(1)) isa Simulation
  else
    @info "no CUDA device: the GPU-launch half of the witness was skipped"
  end
end

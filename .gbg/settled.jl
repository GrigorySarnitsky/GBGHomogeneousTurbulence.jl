# .gbg/settled.jl — what the owner has already decided, and agents are told not to report.
#
# Read as data by ConfigIO, which evaluates nothing. Written by `gbg answer`; no build, test
# or check reads it, and only the agents of a run are shown it.
[
    Settled(question = "2026-10-04-documentation-review-01-023-code",
            text = "Already fixed by finding 008's commit, which restored the truncated references verbatim (owner, 2026-10-11).",
            date = "2026-10-11",
            locations = [
                Location(file = "src/Forcing.jl", node = "VarianceController", text = "[A unified formulation of the constant temperature molecular dynamics methods](https://doi.org/10.1063/1.447334). J. Chem. Phys. **81*", line = 785),
                Location(file = "src/Forcing.jl", node = "VarianceController", text = "[Canonical dynamics: Equilibrium phase-space distributions](https://doi.org/10.1103/PhysRevA.31.1695). Phys. Rev. A **31*", line = 786),
                Location(file = "src/Forcing.jl", node = "VarianceRescaling", text = "[Deterministic forcing of homogeneous, isotropic turbulence](https://doi.org/10.1063/1.868274). Phys. Fluids **6*", line = 529),
            ]),
    Settled(question = "2026-10-04-documentation-review-01-038-code",
            text = "Already fixed by finding 008's commit, which restored the truncated references verbatim (owner, 2026-10-11).",
            date = "2026-10-11",
            locations = [
                Location(file = "src/Observables.jl", node = "derivative_skewness", text = "J. Fluid Mech. **1*", line = 415),
            ]),
    Settled(question = "2026-10-04-documentation-review-01-043-code",
            text = "Already fixed by finding 008's commit, which restored the truncated references verbatim (owner, 2026-10-11).",
            date = "2026-10-11",
            locations = [
                Location(file = "src/Particles.jl", node = "AdamsBashforth", text = "J. Comput. Phys. **229*", line = 483),
            ]),
    Settled(question = "2026-10-04-documentation-review-01-093-code",
            text = "Already fixed by finding 003's commit: the page counts six published files (owner, 2026-10-11).",
            date = "2026-10-11",
            locations = [
                Location(file = "docs/src/validation.md", node = "Validation — code-to-code comparison against TurTLE / Reproducing the comparison", text = "The three published files (release assets; verify the hashes):", line = 218),
            ]),
    Settled(question = "2026-10-04-documentation-review-01-073-code",
            text = "The components are bulleted list entries, a name and its contents, not sentences; the list form is the finding's own remedy (owner, 2026-10-11).",
            date = "2026-10-11",
            locations = [
                Location(file = "docs/src/index.md", node = "GBGHomogeneousTurbulence.jl / Components", text = "[`Propagator`](api/Propagator/): the interchangeable integrating-factor schemes under `AbstractIntegrator`.", line = 134),
                Location(file = "docs/src/index.md", node = "GBGHomogeneousTurbulence.jl / Components", text = "[`Forcing`](api/Forcing/): the interchangeable energy-injection strategies under `AbstractForcing`, chosen independently for the velocity and the scalar.", line = 126),
            ]),
    Settled(question = "2026-10-04-documentation-review-01-010-code",
            text = "Already fixed by 07f0cd34 on the owner's ruling of 2026-10-09: the seeders' required inputs are positional; the timestep, the scalar flag and the helpers' inputs stay keywords under the keyword-default rule (owner, 2026-10-19).",
            date = "2026-10-19",
            locations = [
                Location(file = "src/State.jl", node = "random_solenoidal_velocity_spectral!", text = "random_solenoidal_velocity_spectral!(û, domain; kinetic_energy, envelope_wavenumber,", line = 148),
                Location(file = "src/State.jl", node = "random_scalar_spectral!", text = "random_scalar_spectral!(φ̂, domain; scalar_variance, envelope_wavenumber,", line = 250),
                Location(file = "src/SimulationRun.jl", node = "advance!", text = "    advance!(sim; dt = nothing)", line = 1038),
                Location(file = "src/SimulationRun.jl", node = "run!", text = "    run!(callback, sim; dt = nothing)", line = 1269),
                Location(file = "src/SimulationRun.jl", node = "predicted_stationary_state", text = "predicted_stationary_state(domain; velocity_forcing = ConstantPower(),", line = 434),
                Location(file = "src/Forcing.jl", node = "kinetic_energy_in_box_units", text = "kinetic_energy_in_box_units(forcing; reynolds_box = nothing, reynolds_taylor = nothing)", line = 940),
                Location(file = "src/Propagator.jl", node = "allocate_buffers", text = "allocate_buffers(scheme, domain; scalar = false) -> IntegratorBuffers", line = 153),
                Location(file = "src/Forcing.jl", node = "kinetic_energy_in_box_units", text = "kinetic_energy_in_box_units(forcing; reynolds_box = nothing, reynolds_taylor = nothing)", line = 970),
            ]),
]

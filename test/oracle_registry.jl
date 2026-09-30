# Oracle provenance (RULE.TEST.ORACLE_INDEPENDENT): every public value-returning operation is classified
# by how its tests know the answer, and none rests on other package operations alone.
#
# The package DECLARES the registry to GBGCodingTools: the engine is `TestHarness.oracle_registry`,
# which derives the required set from the export list, so a new operation fails until it is
# classified here, and checks that every cited test file exists and mentions the operation. The
# classes:
#   analytic     a closed form derived independently of the package
#   independent  a direct computation written in the test (a sum, a count, a formula, an expected list)
#   property     an invariant that pins the operation without computing it (a round trip, a symmetry)
#   relational   compared only against other package operations; legitimate as a second layer, and a
#                finding as the only one
#   structural   returns metadata or storage, not a value
# The classification is the moment to notice an operation with no independent oracle. Declaring the
# registry found the core observables checked only against other package operations, against a trivial zero, or not at all —
# `kinetic_energy`, `dissipation`, `energy_spectrum`, `integral_scale`, `max_speed`,
# `derivative_skewness`, `flow_parameters`, `max_resolved_wavenumber`, the two integrating factors and
# `recommended_cfl` — and `observables_analytic.jl` supplies their closed forms.
# `Phenomenology` is outside the surface until it is extracted (the owner, 2026-09-29).
using Test
using GBGHomogeneousTurbulence
import GBGCodingTools

const HT = GBGHomogeneousTurbulence
const OWNED_MODULES = [HT.SimulationDomain, HT.Observables, HT.State, HT.Cache, HT.Forcing,
                       HT.Generator, HT.Propagator, HT.Particles, HT.SimulationRun]

# operation => (class, where the strongest oracle lives)
const ORACLE_PROVENANCE = Dict{Symbol, Tuple{Symbol, String}}(
  # ---- the observables: closed forms on a single-shell field ----
  :kinetic_energy        => (:analytic, "observables_analytic.jl — k = (A² + B² + C²)/4 on u = (A sin y, B sin z, C sin x)"),
  :dissipation           => (:analytic, "observables_analytic.jl — ε = ν(A² + B² + C²)/2 from ω = −(B cos z, C cos x, A cos y)"),
  :kinetic_energy_and_dissipation => (:analytic, "observables_analytic.jl — the same k and ε, as one pair"),
  :scalar_variance       => (:analytic, "observables_analytic.jl — ⟨φ²⟩ = D²/2 on φ = D sin x"),
  :scalar_dissipation    => (:analytic, "observables_analytic.jl — ε_φ = ϰD²; and scalar.jl, 2ϰ⟨|∇φ|²⟩ from an explicit physical gradient"),
  :energy_spectrum       => (:analytic, "observables_analytic.jl — all of k in shell 1, nothing elsewhere"),
  :integral_scale        => (:analytic, "observables_analytic.jl — L₁₁ = 3π/4 for a single shell"),
  :max_speed             => (:analytic, "observables_analytic.jl — √(A² + B² + C²), sampled where every sine is ±1"),
  :derivative_skewness   => (:analytic, "observables_analytic.jl — S = 0 for the single-shell field, and odd under u → −u for any field"),
  :kinetic_energy_and_dissipation_below_scale => (:independent, "below_scale.jl — the spectral sums as host loops, and the box-mean definition on an 8× finer grid"),
  :reynolds_box          => (:independent, "reynolds.jl — through the Kolmogorov velocity of a box-sized eddy, and (L/η)^{4/3}"),
  :reynolds_taylor       => (:independent, "reynolds.jl — u′λ/ν with u′ and λ written out"),
  :flow_parameters       => (:analytic, "observables_analytic.jl — ε and u′ = √(2k/3) of the single-shell field, on a run that adopts it"),

  # ---- the domain and the step ----
  :max_resolved_wavenumber => (:analytic, "observables_analytic.jl — f·(N/2)·2π/L with f = 2/3, 4/5, 2√2/3"),
  :max_retained_wavenumber => (:analytic, "observables_analytic.jl — f·(N/2)·2π/L with f = 2/3, 1, 2√2/3; and dealiasing.jl"),
  :velocity_integrating_factor => (:analytic, "observables_analytic.jl — coefficient −ντ, offset scale τ"),
  :scalar_integrating_factor   => (:analytic, "observables_analytic.jl — coefficient −(ν/Sc)τ, offset scale τ"),
  :recommended_cfl       => (:property, "observables_analytic.jl — C·κ_max·Δx the same under every dealiasing strategy, below √3 for three-stage third-order schemes"),

  # ---- the stationary-state model and its prediction ----
  :kinetic_energy_in_box_units => (:independent, "stationary_model.jl — the placeholder table and its interpolation in 1/highest_shell, written in the test"),
  :band_energy_fraction  => (:independent, "stationary_model.jl — the inertial-tail formula written in the test"),
  :predicted_stationary_state => (:independent, "stationary_model.jl — ε = (k/k̃)^{3/2}/L, η = (ν³/ε)^{1/4} and Re_box written out, and the derived and given-ν states agreeing"),

  # ---- the run's clock and cadence ----
  :current_step          => (:independent, "simulation_run.jl — the count of iterations the test ran"),
  :current_time          => (:independent, "simulation_run.jl — the elapsed time the test's fixed steps sum to"),
  :every_steps           => (:independent, "simulation_run.jl — the expected firing steps [0, 3, 6, 9], written in the test"),
  :every_time            => (:independent, "simulation_run.jl — the expected firing count and window around each multiple"),

  # ---- persistence: round trips ----
  :write_domain          => (:property, "hdf5_checkpoint.jl — written then read back identical"),
  :read_domain           => (:property, "hdf5_checkpoint.jl — reads back what was written"),
  :write_state           => (:property, "hdf5_checkpoint.jl — written then read back bit for bit"),
  :read_state            => (:property, "hdf5_checkpoint.jl — reads back what was written, bit for bit"),
  :write_tracers         => (:property, "hdf5_checkpoint.jl — written then read back bit for bit"),
  :read_tracers          => (:property, "hdf5_checkpoint.jl — reads back what was written, bit for bit"),
  :write_forcing         => (:property, "hdf5_checkpoint.jl — written then rebuilt with the same parameters"),
  :read_forcing          => (:property, "hdf5_checkpoint.jl — rebuilds the forcing that was written"),
  :write_simulation      => (:property, "hdf5_checkpoint.jl — a restored run continues bitwise as the uninterrupted one"),
  :read_simulation       => (:property, "hdf5_checkpoint.jl — a restored run continues bitwise as the uninterrupted one"),

  # ---- storage, metadata, traits and display ----
  :new_scalar_field_physical => (:structural, "allocates a zeroed field on the domain"),
  :new_scalar_field_spectral => (:structural, "allocates a zeroed field on the domain"),
  :new_vector_field_physical => (:structural, "allocates a zeroed field on the domain"),
  :new_vector_field_spectral => (:structural, "allocates a zeroed field on the domain"),
  :new_tensor_field_physical => (:structural, "allocates a zeroed field on the domain"),
  :new_tensor_field_spectral => (:structural, "allocates a zeroed field on the domain"),
  :new_scalar_point_values => (:structural, "allocates a point-value set for the tracers"),
  :new_vector_point_values => (:structural, "allocates a point-value set for the tracers"),
  :allocate_buffers      => (:structural, "allocates a scheme's registers"),
  :initial_forcing_state => (:structural, "allocates a forcing's evolving state, or returns nothing"),
  :velocity_physical     => (:structural, "reads a cache slot's storage"),
  :vorticity_physical    => (:structural, "reads a cache slot's storage"),
  :scalar_physical       => (:structural, "reads a cache slot's storage"),
  :velocity_at_particles => (:structural, "reads a cache slot's storage"),
  :unwrapped_positions   => (:structural, "returns the tracers' unwrapped position record"),
  :history_depth         => (:structural, "a scheme's number of past samples, metadata"),
  :uses_steady_linear_rate => (:structural, "a strategy's declaration, a trait"),
  :show                  => (:structural, "a display, gated in display.jl"),
)

GBGCodingTools.TestHarness.oracle_registry(HT, OWNED_MODULES,
  Dict("operation" => [Dict("name" => String(name), "class" => String(class), "evidence" => evidence)
                       for (name, (class, evidence)) in ORACLE_PROVENANCE]),
  @__DIR__)

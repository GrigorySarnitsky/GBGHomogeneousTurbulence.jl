// ============================================================================
// GBGHomogeneousTurbulence — physics-first architecture, Alloy spec v4.
//
// Fourth pass (the bounded objects->morphisms completion the nine lenses asked
// for). v3 landed the STRUCTURAL arrows (Projection coverage, the metriplectic
// SubGenerator split, MaterialAdvection, the coarsens poset) — all KEPT. v4
// homes the FOUR arrows that were still objects/half-arrows, and kills the one
// surviving v2-class defect (a tautological measurement seam forced by a blanket
// fact). The five moves:
//   (1) MEASUREMENT is DERIVED, not declared: `fact observed` is gone; the
//       observed set is exactly what the Observables module computes (energy,
//       dissipation, the E(kappa) shell spectrum), each a full arrow Slot->Referent.
//   (2) CLOSURE has a positive consumer: needsClosure[m] => modeled DOF OR a
//       rung-homed closure; ClosureStrategy is homed per reduced rung.
//   (3) The SOURCE is a SubGenerator (acts->Energy); the gate closes the P=eps
//       budget triangle (source-injection AND dissipation), both measured.
//   (4) The Generator's halves carry src/dst Slots (FieldSlot->FieldSlot self-
//       advection), matching MaterialAdvection's arrow shape; the seam rule is
//       quantified universally over `sense`, not hardcoded by name.
//   (5) BUG fix: the inertial phase is its own EnsembleRole (it slips), never
//       materially advected by the fluid (removes the tracer tau->0 falsehood).
//
// Scope discipline (decision 12 / §10): dynamics are verified by numerical oracle,
// NOT here. Alloy carries only STRUCTURAL SHADOWS. Every new assert below is paired
// with a fact whose removal makes it FAIL (the drop-a-fact non-vacuity experiment),
// so no check passes by re-reading its own premise.
// ============================================================================
module gbgit_architecture

// ===== Modules & dependency DAG (edges = the code's actual `using ..`) =====
abstract sig Module { depends : set Module }
one sig State, SimulationDomain, Generator, Forcing,
        Observables, Propagator, Particles, SimulationRun, Phenomenology extends Module {}
fact dependencyGraph {
  depends =
      Generator -> State + Generator -> SimulationDomain
    + Generator -> Forcing                                             // FlowConditions holds the forcings (the RHS source)
    + Forcing -> SimulationDomain
    + Observables -> State + Observables -> SimulationDomain
    + Propagator -> State + Propagator -> Generator
    + Propagator -> SimulationDomain + Propagator -> Forcing        // step! applies forcing
    + Particles -> SimulationDomain                                   // velocity passed as args
    + SimulationRun -> State + SimulationRun -> SimulationDomain
    + SimulationRun -> Generator + SimulationRun -> Observables
    + SimulationRun -> Propagator + SimulationRun -> Particles
    + SimulationRun -> Forcing + SimulationRun -> Phenomenology
}
assert acyclic { no m: Module | m in m.^depends }  check acyclic for 20
assert phenomenologyLeaf {
  no Phenomenology.depends
  all m: Module | Phenomenology in m.depends implies m = SimulationRun
}
check phenomenologyLeaf for 20

// ===== Slots, typed; ParticleEnsemble refined by role (the v2 overload fix) =====
abstract sig SlotKind {}
one sig FieldRep, StatMoment extends SlotKind {}
abstract sig EnsembleRole extends SlotKind {}
// (5) InertialParticle is its OWN role: an inertial phase slips (own momentum eqn),
//     so it is NOT a passive tracer and NOT materially advected by the fluid.
one sig PhysicalTracer, NotionalDevice, CompositionSample, InertialParticle extends EnsembleRole {}
abstract sig Slot { onModule : one Module, kind : one SlotKind }
one sig FieldSlot         extends Slot {} { onModule = State  kind = FieldRep }
one sig FilteredFieldSlot extends Slot {} { onModule = State  kind = FieldRep }
one sig ShellSpectrumSlot extends Slot {} { onModule = State  kind = StatMoment }
one sig TracerSlot        extends Slot {} { onModule = State  kind = PhysicalTracer }    // DNS instrument (one-way)
one sig InertialSlot      extends Slot {} { onModule = State  kind = InertialParticle }  // (x,v) dispersed phase — slips
one sig NotionalSlot      extends Slot {} { onModule = State  kind = NotionalDevice }    // FDF subgrid Q-space (two-way)
one sig CompositionSlot   extends Slot {} { onModule = State  kind = CompositionSample } // PDF composition state
// Extend, never re-carve: every slot lives on the ONE State module.
fact slotsOnState { all s: Slot | s.onModule = State }
assert extendsNeverRecarves { all s: Slot | s.onModule = State }  check extendsNeverRecarves for 20

// ===== The Model ladder: a coarsens POSET + resolved/modeled/added-phase partition =====
abstract sig Model { resolved : set Slot, modeled : set Slot, extra : set Slot,
                     coarsens : set Model, closedBy : lone Strategy }
one sig DNS, LES, FDF, Inertial, PDF, EDQNM extends Model {}
fun slotsOf [m: Model] : set Slot { m.resolved + m.modeled + m.extra }
fact partitionDisjoint {
  all m: Model | no (m.resolved & m.modeled) and no (m.resolved & m.extra) and no (m.modeled & m.extra)
}
fact stateContents {
  DNS.resolved = FieldSlot           no DNS.modeled    DNS.extra = TracerSlot   // optional tracer instrument
  LES.resolved = FilteredFieldSlot   no LES.modeled    no LES.extra
  FDF.resolved = FilteredFieldSlot   FDF.modeled = NotionalSlot   no FDF.extra  // subgrid PDF as notional particles
  PDF.resolved = CompositionSlot     no PDF.modeled    no PDF.extra
  EDQNM.resolved = ShellSpectrumSlot no EDQNM.modeled  no EDQNM.extra
  Inertial.resolved = FieldSlot      no Inertial.modeled  Inertial.extra = InertialSlot   // fluid + dispersed phase
}
// The fluid Model ladder DNS -> {LES, FDF}, LES -> {EDQNM, PDF}. Inertial is OFF the ladder
// (a dispersed-phase extension, not a projection).
fact ladder {
  DNS.coarsens = LES + FDF
  LES.coarsens = EDQNM + PDF
  no FDF.coarsens   no EDQNM.coarsens   no PDF.coarsens   no Inertial.coarsens
}
assert ladderDAG { no m: Model | m in m.^coarsens }  check ladderDAG for 20
assert dnsFinest  { no coarsens.DNS }  check dnsFinest for 20   // nothing projects INTO DNS: the finest rung
assert stateRealizedEachRung { all m: Model | some slotsOf[m] }  check stateRealizedEachRung for 20

// ===== MORPHISMS made first-class =====
// (P) The projection: each coarsening edge carries slot-level reduction edges from the fine rung's
//     resolved image onto the coarse rung's — many-to-one allowed (filter, angle-average).
sig Projection { fine : one Model, coarse : one Model, src : one Slot, dst : one Slot }
fact projectionEdges {
  // Every projection lies on a real coarsening and maps a fine resolved slot to a coarse resolved slot.
  all p: Projection | p.coarse in p.fine.coarsens and p.src in p.fine.resolved and p.dst in p.coarse.resolved
  // Every coarsening carries at least one projection (the reduction map exists).
  all m: Model, c: m.coarsens | some p: Projection | p.fine = m and p.coarse = c
}
// The reduction COVERS the coarse image (replacing v2's `!=`): every coarse resolved slot is the image
// of some fine resolved slot under a projection. `modeled` is deliberately NOT covered — the closure
// obstruction is precisely the cokernel of the projection.
assert projectionCovers {
  all m: Model, c: m.coarsens, s: c.resolved |
    some p: Projection | p.fine = m and p.coarse = c and p.dst = s
}
check projectionCovers for 20

// (Closure) A rung REQUIRES a closure iff it is a proper projection of a finer rung. DNS (the identity
//   projection) requires none. (2) Closure is now HOMED per reduced rung — either explicit modeled DOF
//   (FDF's notional Q-space) OR a rung-bound closure strategy (LES eddy-viscosity, EDQNM eddy-damping,
//   PDF micromixing) — so `needsClosure` has a POSITIVE consumer, not just the DNS negative.
pred needsClosure [m: Model] { some coarsens.m }        // something projects onto m => m is reduced
fact closureHoming {
  no DNS.closedBy   no Inertial.closedBy                 // finest / off-ladder: no closure
  LES.closedBy   = ClosureStrategy                        // eddy-viscosity subgrid model (no extra DOF)
  EDQNM.closedBy = ClosureStrategy                        // eddy-damping markovianization
  PDF.closedBy   = ClosureStrategy                        // micromixing model
  no FDF.closedBy                                         // FDF closes via modeled DOF (NotionalSlot), not a strategy
  all m: Model | some m.closedBy implies m.closedBy.sense = Irreversible   // a closure is net-dissipative
}
assert dnsNoClosure { not needsClosure[DNS] and no DNS.modeled and no DNS.closedBy }  check dnsNoClosure for 20
// Every reduced rung represents its unresolved DOF — as modeled state OR a homed closure. (Drop any
// `*.closedBy` line above and LES/EDQNM/PDF fails this: the surviving `needsClosure` tautology cure.)
assert closureRepresented {
  all m: Model | needsClosure[m] implies (some m.modeled or some m.closedBy)
}
check closureRepresented for 20

// ===== The metriplectic seam + the source, as first-class sub-generators with slot arrows =====
abstract sig Referent {}  one sig Energy, Dissipation extends Referent {}
abstract sig GenKind {}   one sig Reversible, Irreversible, Source extends GenKind {}
// (4) src/dst make each sub-generator a real arrow between slots — the field self-advection
//     FieldSlot->FieldSlot the core nonlinearity IS, matching MaterialAdvection's shape.
abstract sig SubGenerator { within : one Module, sense : one GenKind, acts : set Referent,
                            src : lone Slot, dst : lone Slot }
one sig Advection extends SubGenerator {} {
  within = Generator  sense = Reversible    acts = Energy       src = FieldSlot  dst = FieldSlot }
one sig Diffusion extends SubGenerator {} {
  within = Generator  sense = Irreversible  acts = Dissipation  src = FieldSlot  dst = FieldSlot }
// (3) The SOURCE is a sub-generator too — external driving, homed in the Forcing module, injecting energy.
one sig Injection extends SubGenerator {} {
  within = Forcing    sense = Source        acts = Energy       no src           dst = FieldSlot }

// (1) MEASUREMENT is a full arrow Slot -> Referent, and the observed set is DERIVED from what the
//     Observables module actually computes — NOT a blanket `fact observed`. `produces` is the optional
//     StatMoment an observable populates (the E(kappa) shell spectrum), homing ShellSpectrumSlot on DNS.
sig Observation { on : one Slot, observes : one Referent, produces : lone Slot }
one sig EnergyObs      extends Observation {} { on = FieldSlot  observes = Energy       no produces }        // kinetic_energy
one sig DissipationObs extends Observation {} { on = FieldSlot  observes = Dissipation  no produces }        // dissipation
one sig SpectrumObs    extends Observation {} { on = FieldSlot  observes = Energy  produces = ShellSpectrumSlot } // energy_spectrum: E(kappa)
fact observationWellFormed {
  all obs: Observation | obs.on.kind = FieldRep and obs.on in DNS.resolved              // observables read the resolved field
  all obs: Observation | some obs.produces implies obs.produces.kind = StatMoment        // a produced slot is a moment
}
// The interior seam (reversible + irreversible) shares ONE host module; the source is external to it.
assert seamInterior {
  one (sense.Reversible + sense.Irreversible).within
  (sense.Reversible + sense.Irreversible).within = Generator
  no (sense.Source.within & Generator)
}
check seamInterior for 20
// Every sub-generator acts on a referent the Observables module actually MEASURES. Non-vacuous now:
// drop DissipationObs (the SOLE Dissipation observer — Energy is double-covered by EnergyObs and
// SpectrumObs) and this fails: the observed set no longer covers the dissipative seam half.
assert seamMeasured { all sg: SubGenerator | sg.acts in Observation.observes }
check seamMeasured for 20
// The reversible half produces NO dissipation — the one-sided degeneracy, quantified over `sense`
// (not hardcoded by name). Widen Advection.acts to include Dissipation and this fails.
assert seamOneSided { all sg: SubGenerator | sg.sense = Reversible implies Dissipation not in sg.acts }
check seamOneSided for 20
// The Generator's halves are endomorphisms of the resolved field (src = dst in DNS.resolved) —
// the field-on-itself arrow, consistent with MaterialAdvection being a field->ensemble arrow.
assert seamEndomorphic {
  all sg: SubGenerator | sg.within = Generator implies (some sg.src and sg.src = sg.dst and sg.src in DNS.resolved)
}
check seamEndomorphic for 20
// The E(kappa) diagnostic reaches the SAME shell-moment slot EDQNM evolves — DNS observes onto it.
assert spectrumHomedOnDNS {
  some obs: Observation | obs.on in DNS.resolved and obs.produces = ShellSpectrumSlot
}
check spectrumHomedOnDNS for 20
// (A `spectrumIsReducedState` coherence assert — the produced slot is a coarse rung's resolved state —
// was considered and REJECTED: ShellSpectrumSlot is the only StatMoment and is already EDQNM.resolved,
// so no perturbation preserving `observationWellFormed` can falsify it. A non-falsifiable assert is the
// defect class this spec exists to avoid; the content is already carried by spectrumHomedOnDNS.)

// ===== Strategies: specification vs realization =====
abstract sig Layer {}  one sig Specification, Realization extends Layer {}
abstract sig Strategy { actsOn : one Module, layer : one Layer, sense : lone GenKind }
one sig ForcingStrategy    extends Strategy {} { actsOn = Generator       layer = Specification  sense = Source }       // external driving
one sig ClosureStrategy    extends Strategy {} { actsOn = Generator       layer = Specification  sense = Irreversible } // net-dissipative
one sig IntegratorStrategy extends Strategy {} { actsOn = Propagator     layer = Realization    no sense }
one sig DealiasStrategy    extends Strategy {} { actsOn = SimulationDomain layer = Realization    no sense }
one sig TracerScheme       extends Strategy {} { actsOn = Particles       layer = Realization    no sense }             // interpolation scheme
// The two Source encodings agree: the forcing STRATEGY (spec) and the Injection SUB-GENERATOR (RHS term)
// carry the same sense. Cross-check (not a re-read): change either and this fails.
assert forcingStrategyLinked { ForcingStrategy.sense = Injection.sense }  check forcingStrategyLinked for 20
// Forcing drives, closure dissipates — never the same seam side.
assert forcingNotClosure { Injection.sense != ClosureStrategy.sense and Injection.sense = Source }
check forcingNotClosure for 20
// The two Reversible/Irreversible encodings agree: the closure lands on the irreversible sub-generator.
assert seamStrategyLinked { ClosureStrategy.sense = Diffusion.sense }  check seamStrategyLinked for 20

// (Material advection) A tracer/ensemble slot is advected by the velocity FIELD slot — dX/dt = u(X,t).
// (5) Only the PASSIVE tracer is material; the inertial phase slips (own momentum) and is excluded.
sig MaterialAdvection { ensemble : one Slot, byField : one Slot }
fact materialAdvection {
  all ma: MaterialAdvection |
    ma.ensemble.kind in (EnsembleRole - InertialParticle) and ma.byField.kind = FieldRep
  (some ma: MaterialAdvection | ma.ensemble = TracerSlot and ma.byField = FieldSlot)   // the DNS tracer is material
}
assert advectionByField { all ma: MaterialAdvection | ma.byField.kind = FieldRep }  check advectionByField for 20
// The inertial phase is NEVER materially advected (it slips). Non-vacuous: allow InertialParticle back
// into the `materialAdvection` role restriction and this fails.
assert inertialNotMaterial { no ma: MaterialAdvection | ma.ensemble = InertialSlot }
check inertialNotMaterial for 20

// ===== The two rulings + product arity + the gate =====
assert stateIsInert { no s: Strategy | s.actsOn = State   no State.depends }
check stateIsInert for 20
// System <-> Model orthogonality (both directions), via strategy layer, not a fictional Closure edge.
assert systemModelOrthogonal { ForcingStrategy.layer = Specification and ClosureStrategy.layer = Specification }
check systemModelOrthogonal for 20
assert stateProductArity {
  one DNS.resolved
  #FDF.slotsOf >= 2                                        // filtered field + notional ensemble
  no (EDQNM.slotsOf & (FieldSlot + FilteredFieldSlot))     // no field: state is a spectrum
}
check stateProductArity for 20

// (3) The stationarity gate closes the P = eps BUDGET TRIANGLE: it reads the source-injected referent
//     AND the dissipated one, both MEASURED (never the raw state, decision 13). Three independent ways
//     to break it: drop Injection (no Source side), read Energy only (no Dissipation), drop DissipationObs
//     (Dissipation unmeasured).
one sig StationarityGate { reads : set Referent, livesIn : one Module } { livesIn = SimulationRun }
fact gateReads { StationarityGate.reads = Energy + Dissipation }
assert gateClosesBudget {
  (some sg: SubGenerator | sg.sense = Source       and sg.acts in StationarityGate.reads)
  (some sg: SubGenerator | sg.sense = Irreversible and sg.acts in StationarityGate.reads)
  StationarityGate.reads in Observation.observes
}
check gateClosesBudget for 20

pred show {}  run show for 20

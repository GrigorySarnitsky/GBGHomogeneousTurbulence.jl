# Reference laws — the interface

```@autodocs
Modules = [GBGIsotropicTurbulence.Phenomenology]
Order   = [:module]
```

## The flow-state bundle

The dimensionless flow state a law is evaluated against.

```@docs
FlowParameters
```

The derived scales, computed from the bundle.

```@docs
kolmogorov_length
kolmogorov_time
taylor_microscale
taylor_reynolds
scalar_diffusivity
```

## The law interface

The law supertype and its provenance.

```@docs
TurbulenceLaw
Reference
```

The evaluators — one per representation, plus the fitting seam.

```@docs
provenance
spectrum
structure_function
scaling_exponent
scaling
fit
```

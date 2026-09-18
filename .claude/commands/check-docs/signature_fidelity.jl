# Signature fidelity — the ADVERTISED signature versus the DEFINED one (attack round C4/C8,
# 2026-08-23). Every existing check walks one direction (each signature argument documented in the
# body); nothing compared the displayed signature against the actual method table, so a docstring
# could advertise a keyword the method lost, or a method could grow a keyword no signature shows.
# This closes the loop mechanically: parse each docstring's displayed signature lines, reflect on
# the real methods, and report the symmetric difference of argument-name sets per binding.
#
#   Usage: julia --project --startup-file=no .claude/commands/check-docs/signature_fidelity.jl
#
# TRIAGE scan, not must-be-empty: an inner positional constructor deliberately omitted from the
# docstring (the who-builds-this rule), an extended Base function whose other methods live
# elsewhere, and a `kwargs...` passthrough all produce legitimate asymmetries. Count first, read all.
using GBGHomogeneousTurbulence

const PKG = GBGHomogeneousTurbulence

# ---- collect displayed signatures: (name => Set of arg names) per docstring signature block ----
displayed = Dict{Symbol, Set{Symbol}}()
displayed_kw = Dict{Symbol, Set{Symbol}}()
elided = Set{Symbol}()      # a displayed form carried `kwargs...`/`...` or failed to parse — its
                            # keyword list is deliberately abridged, so the hidden-kw direction
                            # cannot be judged from the signature alone (the # Arguments bullets
                            # carry it, and the arg-coverage sweep audits those)

# The spectral-pair convention: one generic method serves both representations, and the docstring
# displays two forms differing exactly by the hat (`kinetic_energy(u)` / `kinetic_energy(û)`).
# Strip combining accents so that pair compares equal instead of flagging every û/φ̂ form.
dehat(s::Symbol) = Symbol(replace(Base.Unicode.normalize(String(s), :NFD), r"[\u0302\u0304\u0307]" => ""))

function note!(dict, name, args)
  s = get!(dict, name, Set{Symbol}())
  union!(s, args)
end

function harvest_call!(ex)
  ex isa Expr && ex.head === :where && return harvest_call!(ex.args[1])
  (ex isa Expr && ex.head === :call) || return
  name = ex.args[1]
  name isa Symbol || return
  pos, kw = Symbol[], Symbol[]
  for a in ex.args[2:end]
    if a isa Expr && a.head === :parameters
      for k in a.args
        k isa Expr && k.head === :(...) && (push!(elided, name); continue)
        k isa Expr && k.head === :kw && (k = k.args[1])
        k isa Expr && k.head === :(::) && (k = k.args[1])
        k isa Symbol && push!(kw, k)
      end
    else
      a isa Expr && a.head === :(...) && (push!(elided, name); continue)
      a isa Expr && a.head === :kw && (a = a.args[1])
      a isa Expr && a.head === :(::) && (a = a.args[1])
      a isa Symbol && push!(pos, a)
    end
  end
  note!(displayed, name, dehat.(pos))
  note!(displayed_kw, name, kw)
end

for file in filter(f -> endswith(f, ".jl"), readdir(joinpath(dirname(pathof(PKG))); join = true))
  src = read(file, String)
  for m in eachmatch(r"\"\"\"\n((?:    [^\n]*\n)+)"s, src)
    block = m.captures[1]
    # Join hanging-indent continuations: a line whose trailing char leaves the call open.
    lines = split(block, '\n'; keepempty = false)
    joined, cur = String[], ""
    for ln in lines
      cur *= strip(ln) * " "
      if count('(', cur) == count(')', cur) && !isempty(strip(cur))
        push!(joined, strip(cur)); cur = ""
      end
    end
    for sig in joined
      sig = replace(sig, r"\s*->.*$" => "")           # strip the return-arrow annotation
      ex = try Meta.parse(sig) catch; nothing end
      ex === nothing || harvest_call!(ex)
    end
  end
end

# ---- reflect the defined methods for each displayed name found in the package ----
function defined_sets(name)
  f = nothing
  for mod in (PKG, PKG.SimulationDomain, PKG.State, PKG.Observables, PKG.Cache, PKG.Forcing,
              PKG.Generator, PKG.Propagator, PKG.Particles, PKG.SimulationRun, PKG.Phenomenology)
    isdefined(mod, name) && (f = getfield(mod, name); break)
  end
  f isa Function || f isa Type || return nothing
  # A bare generic whose methods live in an unloaded weak-dependency extension (the HDF5
  # persistence pairs) has an empty method table here: nothing to compare a displayed signature
  # against, so it is reported once as extension-homed rather than as thirty phantom arguments.
  if f isa Function && isempty(methods(f))
    println("$name: EXTENSION-HOMED (no methods loaded) — skipped")
    return nothing
  end
  pkgroot = dirname(dirname(pathof(PKG)))
  pos, kw = Set{Symbol}(), Set{Symbol}()
  unnamed = false             # a `::DispatchTag` slot with no binding reports `#unused#`; a
                              # displayed name standing in for it (`scheme`, `forcing`) is the
                              # convention, not a phantom
  for m in methods(f)
    startswith(String(m.file), pkgroot) || occursin("GBGHomogeneousTurbulence", String(m.file)) || continue
    for a in Base.method_argnames(m)[2:end]
      if a === Symbol("#unused#") || a === Symbol("")
        unnamed = true
      else
        push!(pos, dehat(a))
      end
    end
    for k in Base.kwarg_decl(m)
      endswith(String(k), "...") || push!(kw, k)
    end
  end
  (pos = pos, kw = kw, unnamed = unnamed)
end

exported = Set(names(PKG))
issues = 0
for name in sort!(collect(keys(displayed)))
  name in exported || continue                        # public surface only
  def = defined_sets(name)
  def === nothing && continue
  phantom_kw = setdiff(displayed_kw[name], def.kw)
  hidden_kw  = name in elided ? Symbol[] : setdiff(def.kw, displayed_kw[name])
  phantom_pos = def.unnamed ? Symbol[] : setdiff(displayed[name], def.pos, def.kw)
  for a in phantom_kw
    global issues += 1
    println("$name: displayed keyword `$a` matches NO defined method (stale signature?)")
  end
  for a in hidden_kw
    global issues += 1
    println("$name: defined keyword `$a` appears in NO displayed signature (unadvertised)")
  end
  for a in phantom_pos
    global issues += 1
    println("$name: displayed positional `$a` matches no defined argument name")
  end
end
println(issues == 0 ? "signature fidelity: CLEAN over $(length(displayed)) displayed bindings" :
        "signature fidelity: $issues asymmetries (TRIAGE — read each; inner constructors and Base extensions produce legitimate ones)")

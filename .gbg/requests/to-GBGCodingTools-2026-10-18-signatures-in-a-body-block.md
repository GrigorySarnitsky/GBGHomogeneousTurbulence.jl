# To GBGCodingTools: `RULE.DOC.SIGNATURE_FIDELITY` reads only a docstring's leading block

Status: approved by the owner on 2026-10-18, sent to the GBGCodingTools session the same day.

## What happens

`displayed_signatures` harvests `Texts.signature_lines(d.text)`, the indented block at the top of a
docstring, and nothing after it. A signature list a docstring displays further down is therefore
neither checked against the methods nor counted as displayed.

HT's `DeferredForcing` docstring is such a list. After one sentence of prose it shows the five
domain-free keyword constructors, `ConstantPower(; …)` through `Linear(; …)`, which return a
`DeferredForcing`; that docstring is their home. Two costs follow:

- **The five go unchecked.** They match their methods today (verified one by one), but a drifted
  keyword there would pass.
- **A keyword shown only there counts as shown nowhere.** `StochasticOU`'s domain-free constructor
  takes `correlation_time_in_box_units`, which the domain form lacks. Removing that constructor's
  signature from `StochasticOU`'s own docstring, so that `DeferredForcing` holds all five, fails the
  build with "`StochasticOU`: the defined keyword `correlation_time_in_box_units` appears in no
  displayed signature". HT therefore shows it twice.

Moving the five into `DeferredForcing`'s leading block was tried and is no fix: fidelity then passes,
but `RULE.DOC.ARGCOV` and `RULE.DOC.ARGS_FORM` ask that docstring to restate all five strategies'
arguments in bullets.

## What is asked

Read a signature list displayed in a docstring's body as the leading block is read: harvested under
the name of the function it calls, held to that function's methods in both directions, and counted
as displayed.

A body block cannot be told from an example call by position alone, so the criterion matters. The
one that separated them in every GBG tree:

- an indented code block opened by a blank line, outside an admonition and a list item;
- every line of it, joined until its parentheses balance, parses as a call;
- every positional argument of each call is a bare or typed name, as in a signature. A keyword may
  default to any expression, as `seed = rand(Int)` does in a signature.

## Measured in each tree, under that criterion

An indented block opened by a blank line, after the leading block, that parses as calls:

| Tree | Blocks | Under the criterion |
|---|---|---|
| GBGHomogeneousTurbulence | `DeferredForcing` (`src/Forcing.jl`), five constructors | read; all five match their methods |
| GBGCloudPhysics | `DeferredForcing` (`src/dns/FieldForcing.jl`), four constructors | read; each matches its definition at lines 926–937 |
| GBGCloudPhysics | `empty_closure` (`src/Generator.jl`), `StochasticModelCache(state; closure = empty_closure(generator, state))` | read; matches `StochasticModelCache(state::StochasticModelState; closure = nothing)` at `src/Cache.jl:149` |
| GBGPeriodicFields | `radial_spectrum` (`src/Reductions.jl`), `weighted_inner(f, radial_kernel(identity, multipliers))` | excluded: a positional argument is a call, so it is an example |
| GBGStreamingStatistics, GBGCodingTools | none | — |

So under the criterion no tree gains a finding, and without its third clause the
GBGPeriodicFields example would report `weighted_inner`'s positionals as matching no method. The
scan was a script over the working copies, read only, on 2026-10-18; the trees will have moved by the
time this is read.

# To GBGCodingTools: a descriptive subscript is upright

Status: approved by the owner on 2026-11-06, to be sent to the GBGCodingTools session when it is
next online (it was offline when this was written). HT applied the convention the same day (HT
decision 120).

## The convention

A subscript that stands for a word is set in roman; a subscript that is itself a quantity, a
variable or an index stays italic. This is the rule of ISO 80000-1, which replaced ISO 31-0; IEC
60050 and IUPAC state it the same way.

- Upright: ``\kappa_{\mathrm{p}}`` (peak), ``C_{\mathrm{K}}`` (Kolmogorov), ``\eta_{\mathrm{B}}``
  (Batchelor), ``\kappa_{\mathrm{c}}`` (cutoff), ``k_{\mathrm{band}}``, ``C_{\mathrm{CFL}}``.
- Italic: ``C_\varepsilon``, ``\tau_\eta``, ``t_n``, ``u_i``, ``\kappa_a``, and ``C_S`` where ``S``
  is the skewness.

The rulebook has nothing on subscripts. `latex-idiom.md` already sets the imaginary unit and the
differential upright, which are the same principle applied to two symbols.

## How it was found

The owner read ``\kappa_p`` in a seeder docstring, asked what the ``p`` stood for, and pointed out
that a ``p`` meaning "peak" should have been ``\kappa_{\mathrm{p}}``. A sweep of HT then found
thirteen descriptive subscripts set in italic across its docstrings, pages and design document,
where others were already upright. Two symbols were spelt both ways: ``y_s`` and ``y_{\mathrm{s}}``,
``\kappa_c`` and ``\kappa_{\mathrm{c}}``. Nothing could have caught either.

## What is asked

1. A rule in `latex-idiom.md` stating the convention, in the brace form the rulebook already
   requires (``_{\mathrm{p}}``, never ``_\mathrm{p}``).
2. A check. Which subscripts are words cannot be known from the TeX alone, so the check probably
   has two parts:
   - mechanical, for every package: a subscript of two or more Latin letters that is not inside
     ``\mathrm``, ``\text`` or an operator such as ``\max`` (``k_{band}`` would be caught);
   - declared, per package: a list of single-letter labels in its `.gbg/config.jl` (HT's would
     be ``\kappa_p``, ``T_L``, ``k_f``, ``C_K``, ``\kappa_c``, ``\eta_B``, ``L_E``, ``\nu_e``,
     ``N_c``, ``y_s``, ``C_t``, ``\kappa_M``, and ``D_L``), whose italic spelling then fails the
     build.

   This is a suggestion; the form of the check is the tool's to decide.

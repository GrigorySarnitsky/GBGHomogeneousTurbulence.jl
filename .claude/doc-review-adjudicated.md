# Adjudicated non-defects — do NOT re-flag

The one file a `/check-consistency` hat is shown from prior rounds. It lists ONLY findings settled as
**not defects** — manuscript-extraction artifacts and design decisions the package owner closed
deliberately. Previously-FIXED items are deliberately absent: re-flagging a bad fix is the panel's
whole value. Keep entries short: what was flagged, why it is not a defect.

- **Saffman-spectrum attribution** (round 1): flagged as a misattribution; verified CORRECT against
  the literature — the citation stands as written.
- **`kinetic_energy` default target 1.5 vs 0.5** (round 1): the `Simulation` default `kinetic_energy
  = 1.5` gives u' = 1 (k = 3/2 u'²); not a normalization slip.
- **Decision-log entries describing superseded APIs** (any round): the ARCHITECTURE decision log is
  append-only HISTORY — an old entry naming a renamed verb or a deleted register records what was
  decided then and is not stale prose. Only *current-state* sections (§1–§10) must match the code.
- **The absence of a statistics layer, a sheared frame, inertial/oriented particles, an LES
  closure, high-Schmidt machinery** (any round): recorded deferrals (ARCHITECTURE §7), not gaps.
- **`vorticity_spectral(sim)` does not exist** (any round): deliberate — an accessor exists exactly
  for what the run holds, and the spectral vorticity is materialized nowhere (decision 43).

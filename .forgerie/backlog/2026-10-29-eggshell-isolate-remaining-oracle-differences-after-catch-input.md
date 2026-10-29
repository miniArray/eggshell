---
id: 2026-10-29-eggshell-isolate-remaining-oracle-differences-after-catch-input
title: "Eggshell: isolate remaining oracle differences after catch-input fix"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
---

The REJOIN input fix now matches the stored original at the targeted velocities, but full 900-step comparisons still fail with `--offset 1`.

Private evidence and original card provenance remain outside this repository.
See `docs/backlog.md` for the recovery directory and ID mapping.

First sample level: jump release at aligned 300 is now −91.6 px/s, and first resumed move at 332 is −57.4667 on both sides. First position episode beyond 0.5 px is now aligned 357, x 1067.315 original versus 1068.915 fixed, a 1.6 px episode. At 376, original vy is −257.6 versus −264.0 fixed near x 1174.195/y 925.94. Original dies at 725; fixed has no death by 898. Root cause of later velocity/contact/death differences is not isolated.

Second sample level: frozen jump at 360 now sets −776 px/s; frozen release at 390 now sets −194 px/s on both sides. The original catch begins four steps earlier, before the repaired event path: first position difference at 353, original x919.100 versus fixed x921.589. Original freeze ends at 403; fixed resumes at 407. First deaths are now 543 original versus 546 fixed, rather than 639 before. Original has another death at 830; fixed does not.

Use the original-backed traces to isolate the first cause in each path. Add regressions for catch timing and later velocity/contact outcomes. Do not rebaseline or claim matching full-level death paths from the repaired input rows.

## Context

### Why
The requested input-starvation defect is fixed, but these measurements show that release rule 3 still needs separate work. The first post-fix differences are now recorded for a focused diagnosis.

### Files
- src/sim/life.gd
- src/sim/moves.gd
- src/sim/water.gd
- src/sim/water_flow.gd
- src/sim/step.gd

### Decisions
- Keep fixed 60 Hz integer simulation.
- Treat stored original oracle recordings as the reference and compare with --offset 1.
- Do not change unrelated contact or catch geometry without evidence of its cause.

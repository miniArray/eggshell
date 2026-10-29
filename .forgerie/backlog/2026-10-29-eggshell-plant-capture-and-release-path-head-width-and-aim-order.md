---
id: 2026-10-29-eggshell-plant-capture-and-release-path-head-width-and-aim-order
title: "Eggshell: plant capture and release path (head width and aim order)"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
  01a17f22-de21-73fa-a989-34ad6632a697/a048d5da-4881-4d46-be55-d9134389e00f
---

On corpus level `645fbb53`, the plant capture still diverges at step 34 and later outcomes differ: first deaths at 629 (original) vs 414 (Eggshell) on the right probe, 749 vs 280 on run_jump. The original's head is 66.2069 px wide at capture against the port's 64 px. The original aims using the player's position after its move and the stem after its carrier moves; the port aims earlier in the enemy step (`src/sim/enemy_plant.gd:68-85,130-134`). The aim-order part is inferred.

Fix: port the head width and aim order from the source, then check the release and death path against the oracle with full-episode regressions.

Evidence: `~/.local/share/eggshell-run/finish/review2/sol/review.md` (B3), `fix-integrate-r3/diag/plant-*`, private `docs/reports/fix-integrate-r3.md`.

## Context

### Why
One coverage-set level has different deaths because of this.

### Files
- src/sim/types/enemy_plant.gd
- src/sim/enemy_plant.gd

### Decisions
- The original is the reference; prove with the deterministic oracle

Suggested in yfs full backwards compat (01a17f22-de21-73fa-a989-34ad6632a697), 2026-10-29

---
id: 2026-10-29-eggshell-plant-capture-and-release-path-head-width-and-aim-order
title: "Eggshell: plant capture and release path (head width and aim order)"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
---

On the plant capture regression level, the plant capture still diverges at step 34 and later outcomes differ: first deaths at 629 (original) vs 414 (Eggshell) on the right probe, 749 vs 280 on run_jump. The original's head is 66.2069 px wide at capture against the port's 64 px. The original aims using the player's position after its move and the stem after its carrier moves; the port aims earlier in the enemy step (`src/sim/enemy_plant.gd:68-85,130-134`). The aim-order part is inferred.

Fix: port the head width and aim order from the source, then check the release and death path against the oracle with full-episode regressions.

Evidence, the sample-level identifier, and source provenance are stored in private review reports under this task's ID.

## Context

### Why
One coverage-set level has different deaths because of this.

### Files
- src/sim/types/enemy_plant.gd
- src/sim/enemy_plant.gd

### Decisions
- The original is the reference; prove with the deterministic oracle

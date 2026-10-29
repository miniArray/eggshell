---
id: 2026-10-29-eggshell-fix-the-remaining-missed-and-extra-enemy-contacts-found-by-review
title: "Eggshell: fix the remaining missed and extra enemy contacts found by review"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
---

Review round 2 verified contact differences that change gameplay, not just positions (all with `--offset 1` against the deterministic oracle):

- Flutter probe step 240: the original bounces off a flyer (vy −704); Eggshell keeps falling. The flyer is about 22 px off in y (level-clock phase or creation timing suspected, not proven).
- Right probe step 172 and flutter probe step 182: the roller bounces an already-hurt player in Eggshell (vy −320) and not in the original (`hanging_roller.gd:106-115`).
- Run_jump probe step 107: an extra bounce in Eggshell; first deaths 320 vs 234.
- Two sample levels: a wrong later hit (steps 543 and 397).
- One sample level: an extra bounce at step 679.

Use the oracle's nearby-entity traces to find each contacting actor, fix it, and add an outcome regression per case.

Evidence, sample-level identifiers, and source provenance are stored in private review reports under this task's ID.

## Context

### Why
These are the main reason 9 of the 30 coverage-set levels still play differently from the original.

### Files
- src/sim/enemies.gd
- src/sim/types/hanging_roller.gd
- src/sim/types/shell_walker.gd
- src/sim/types/armored_walker.gd
- src/sim/enemy_fish.gd
- src/sim/types/actor.gd

### Decisions
- Don't change behaviour just to fit a trace; find the source rule
- Random idle waits are not reproducible and are excluded

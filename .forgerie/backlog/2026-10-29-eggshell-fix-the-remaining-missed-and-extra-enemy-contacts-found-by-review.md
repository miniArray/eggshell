---
id: 2026-10-29-eggshell-fix-the-remaining-missed-and-extra-enemy-contacts-found-by-review
title: "Eggshell: fix the remaining missed and extra enemy contacts found by review"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
  01a17f22-de21-73fa-a989-34ad6632a697/d329b775-d3ad-411e-9126-a86f1d4306f7
---

Review round 2 verified contact differences that change gameplay, not just positions (all with `--offset 1` against the deterministic oracle):

- `67a3db0e` flutter step 240: the original bounces off a flyer (vy −704); Eggshell keeps falling. The flyer is about 22 px off in y (level-clock phase or creation timing suspected, not proven).
- `6a1644ae` right 172 and flutter 182: the roller bounces an already-hurt player in Eggshell (vy −320) and not in the original (`hanging_roller.gd:106-115`).
- `66c4880e` run_jump 107: an extra bounce in Eggshell; first deaths 320 vs 234.
- Two sample levels: a wrong later hit (steps 543 and 397).
- One sample level: an extra bounce at step 679.

Use the oracle's nearby-entity traces to find each contacting actor, fix it, and add an outcome regression per case.

Evidence: `~/.local/share/eggshell-run/finish/review2/sol/review.md` (B2) and `review2/sol/oracle/`.

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
- Random idle waits (EX378 random(1, 2.5)) are not reproducible and are excluded

Suggested in yfs full backwards compat (01a17f22-de21-73fa-a989-34ad6632a697), 2026-10-29

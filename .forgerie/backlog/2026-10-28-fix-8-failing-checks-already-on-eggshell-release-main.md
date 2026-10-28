---
id: 2026-10-28-fix-8-failing-checks-already-on-eggshell-release-main
title: Fix 8 failing checks already on eggshell-release main
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a17f92-cd9d-70c6-8814-a9440c419c42/5a8cb065-bf62-46c5-b374-fa93b4ecb1c3
---

On unchanged `main` at 1c8362f (verified by the integer-scale agent on 2026-10-27), the full suite `nix develop -c python3 tests/check_all.py` stops at `tests/objects.gd`. Running the remaining checks one by one shows 8 failures:

- objects.gd, 1 of 14: "Bridge supports falling feet"
- enemies.gd, 4 of 106: flyer three-second vertical period at the tween endpoint; fish accelerates to but never exceeds swim cap; vertical fish floats, waits, prepares and leaps; unrecovered countdown ends in spawn reset
- test_pantry_bread.py, 3 of 264: horizontal join 1 to 2, horizontal join 12 to 13, solid vertical join

Core (200,088 assertions) passes. Suspected source, not verified: the integer polygon collision merge 5736de9, the last physics change before these runs. First step: bisect between ad88b03 and 5736de9 with objects.gd and enemies.gd. Logs: `.worktrees/c-bdfdfae4.../build/check-all.log` and `check-remaining.log`. The slice-5 worktrees (`.worktree/s5-*`) may already touch the same code.

## Context

### Why
The public tree's physics checks are red, so no later change can show a clean suite, and real physics regressions can hide behind the known failures.

### Files
- src/sim/collision.gd
- src/sim/step.gd
- src/sim/enemy_fish.gd
- src/sim/damage.gd
- tests/objects.gd
- tests/enemies.gd
- tests/test_pantry_bread.py

### Decisions
- Kept out of the integer-scaling change, because the same failures occur on unchanged main

Suggested in Art direction pivot, Eggshell (01a17f92-cd9d-70c6-8814-a9440c419c42), 2026-10-28

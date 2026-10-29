---
id: 2026-10-29-eggshell-process-player-input-events-during-the-companion-catch-freeze
title: "Eggshell: process player input events during the companion catch freeze"
status: To Do
created: 2026-10-29
source: forgerie-suggestion
  01a17f22-de21-73fa-a989-34ad6632a697/6782ec8f-dfed-4727-9148-3303c36a0407
---

Review round 2 of the finish run found that `src/sim/step.gd:37-41` returns before reading input while `Life.blocks_step` treats REJOIN as blocked (`src/sim/life.gd:189-192`). In the original, the catch freeze sets time scale to zero, but player input events (jump release, a new jump) still change velocity and pose. Measured on two sample levels with the flutter probe: after the freeze, vy is −57.47 in the original versus −332.27 in Eggshell, and deaths happen at different steps.

Fix: during REJOIN, run the player's input and event updates without advancing the world or moving the body. Add release-during-catch and jump-during-catch regressions and prove them against the stored oracle traces (`--offset 1`).

Evidence: `~/.local/share/eggshell-run/finish/review2/sol/review.md` (B1), `review2/sol/oracle/direct-evidence.json`. Private findings: `eggshell-private/docs/reports/findings.md`, "Review round 2".

## Context

### Why
Release rule 3 fails on two coverage-set levels because of this; it is the clearest remaining player-visible difference.

### Files
- src/sim/step.gd
- src/sim/life.gd

### Decisions
- Physics stays a fixed 60 Hz integer simulation; the freeze must not move the body or the world
- The original is the reference; prove with the deterministic oracle

Suggested in yfs full backwards compat (01a17f22-de21-73fa-a989-34ad6632a697), 2026-10-29

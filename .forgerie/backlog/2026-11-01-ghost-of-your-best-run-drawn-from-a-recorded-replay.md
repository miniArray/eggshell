---
id: 2026-11-01-ghost-of-your-best-run-drawn-from-a-recorded-replay
title: Ghost of your best run, drawn from a recorded replay
status: To Do
created: 2026-11-01
source: forgerie-suggestion
  01a197a3-6afa-7459-90ba-dd095f7b3670/e253c3d8-9bb3-4206-baa0-226d948ad934
---

Draw a translucent ghost of the player's best run of the current level, played back from a recorded input replay.

## Design notes
- The ghost is a second simulation that only the view reads. Nothing goes into the main play state, the snapshot or the level code.
- It needs in-game replay recording first. Today `src/view/game.gd` can only *play* an input-mask replay (the `replay` option). Recording must save the masks in that same format.
- Store each recording in `levels/<level identity>/` with the level identity (SHA-256 of the level code) and the snapshot schema digest. A recording whose identity or digest does not match is ignored, not played wrong.
- "Best" means the lowest goal time. Replace the stored ghost only when a run reaches the goal faster.
- Off by default or a setting (optional `settings.json` key; settings v1 accepts new optional keys).

## Acceptance checks
- The main simulation's snapshot bytes are the same with the ghost on and off for the same inputs.
- A ghost from an edited level (new identity) or an old schema is not shown, and a log line says why.
- The ghost replays to the same goal frame as the recorded run.
- Frame time on the development handheld stays within budget with the ghost on.

## Risks
- It doubles the simulation cost per step. The handheld already shows a 52–54 fps drop in another backlog card, so measure there first.
- Assisted runs (if assists are added) must not become the stored best ghost.

## Context

### Why
Gives players a reason to replay levels and a way to learn routes, without changing YFS level codes or simulation behaviour.

### Files
- src/view/game.gd
- src/view/level_view.gd
- src/save/store.gd
- src/save/settings.gd
- docs/saves.md
- docs/ui.md

### Decisions
- The ghost is view-only: a separate simulation, never part of play state or snapshots.
- Recordings reuse the existing replay input-mask format.
- Recordings are bound to level identity and schema digest and are ignored on mismatch.
- Level codes are never modified.

Suggested in Non-breaking YFS enhancements (01a197a3-6afa-7459-90ba-dd095f7b3670), 2026-11-01

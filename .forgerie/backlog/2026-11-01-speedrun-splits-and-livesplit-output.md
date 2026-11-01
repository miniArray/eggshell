---
id: 2026-11-01-speedrun-splits-and-livesplit-output
title: "Speedrun splits and LiveSplit output"
status: To Do
created: 2026-11-01
source: chat
---

Support speedrunning: automatic splits and a connection to LiveSplit, so runners do not need to split by hand.

## Scope
- **Split events** taken from play state: level start, checkpoint reached, map change, goal reached, and level change in a `--levels` folder.
- **Timing uses simulation frames**, not wall-clock time. 60 frames are one second. Menu time and load time do not count, matching the existing Level and Total clocks (`src/view/play_timer.gd`).
- **LiveSplit output** through the LiveSplit Server protocol (TCP commands such as start, split, reset and set game time). Off by default; the host and port are optional `settings.json` keys (settings stays version 1).
- **In-game splits view** (optional): current split, delta to the best split, stored per level under `levels/<level identity>/` in the save directory.

## Design notes
- Read-only: the splitter reads state after each step and never writes it.
- Restoring a manual slot or rewinding is a reset or an invalid run for splitting purposes; send a reset or mark the run, never a silent time jump.
- Level codes are never changed.

## Acceptance checks
- Snapshot bytes are equal with splitting on and off.
- A recorded replay produces the same split frames on every run.
- With LiveSplit unreachable, the game logs one warning and keeps playing.
- Pausing the menu stops game time in LiveSplit.
- Loading a slot during a run resets or marks the run.

## Context

### Files
- src/view/play_timer.gd
- src/view/game.gd
- src/save/settings.gd
- src/save/store.gd
- docs/ui.md

### Decisions
- Game time comes from simulation frames.
- LiveSplit connection is off by default.
- Slot loads and rewinds never produce a valid continuous time.

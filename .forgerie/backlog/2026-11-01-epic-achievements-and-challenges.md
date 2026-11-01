---
id: 2026-11-01-epic-achievements-and-challenges
title: "Epic: achievements and challenges"
status: To Do
created: 2026-11-01
source: chat
---

Add a local achievement and challenge system, modelled on RetroAchievements but run entirely by Eggshell. This ticket holds the whole epic; the parts below can land one at a time.

## Compatibility rules (apply to every part)

- Achievement and challenge checks only read play state after each step. They never write play state and never remove or change an action. Snapshot bytes are equal with the system on and off.
- Level codes are never changed. Per-level data lives in an optional separate file or in a level bundle.
- Progress lives in the save directory: global achievements at the top, per-level progress under `levels/<level identity>/`.
- The RetroAchievements service itself is out of scope: it supports emulated consoles, not this player.

## Parts

### 1. Local achievements
Conditions checked on saved state, for example "clear a level without getting hit", "all red coins and no deaths", "clear 10 levels". A small condition format (fields, comparisons, counts, "during the whole run") defined in one place. An unlock shows a short notice and is saved at once.

### 2. Replay verification
An achievement unlock stores the run's input replay, level identity and schema digest. Re-running the replay must reproduce the unlock. This depends on in-game replay recording (see the ghost card, `2026-11-01-ghost-of-your-best-run-drawn-from-a-recorded-replay`).

### 3. Achievements for one level
An optional file next to the level (or inside a level bundle) defines that level's achievements with the same condition format. A missing or invalid file never stops the level from loading; an invalid file logs why. Key it to the level identity so an edited level does not keep stale achievements without a warning.

### 4. Time-trial medals
Bronze, silver and gold target times per level, compared with the Level clock at the goal (simulation frames). Targets come from the per-level file (part 3). Show the medal in the level list.

### 5. Challenge rules
Opt-in rules such as "no flutter", "no ground pound" or "pacifist". The game watches for the forbidden action and fails the challenge; it never disables the action. Show the active challenge and its failure clearly.

### 6. Death heatmap
Save death positions per level under `levels/<level identity>/`. Show them as an overlay or in the level list. Also useful for level testing.

### Integrity
- A run that used a slot load, rewind or any assist (if assists are added) does not unlock achievements, medals or challenges, and the UI says why.

## Acceptance checks

- Snapshot bytes are equal with the system on and off for the same inputs.
- A recorded replay of an unlocking run reproduces the unlock.
- A level with a missing or invalid per-level file still loads and plays.
- Loading a slot mid-run blocks unlocks for that run.
- A challenge fails on the first forbidden action and the action still works.
- Progress survives restart and is not lost when one save file is invalid.
- `docs/ui.md` and `docs/saves.md` describe the condition format, files and progress storage.

## Context

### Files
- src/view/game.gd
- src/view/level_list.gd
- src/view/hud.gd
- src/view/play_timer.gd
- src/save/store.gd
- src/save/settings.gd
- docs/ui.md
- docs/saves.md

### Decisions
- Local system only; no RetroAchievements service.
- Checks are read-only and never disable actions.
- Level codes are never modified; per-level data is an optional separate file.
- Slot loads, rewinds and assists block unlocks.

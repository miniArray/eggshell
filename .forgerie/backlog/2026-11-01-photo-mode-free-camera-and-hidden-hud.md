---
id: 2026-11-01-photo-mode-free-camera-and-hidden-hud
title: "Photo mode: pause, move the camera freely and hide the HUD"
status: To Do
created: 2026-11-01
source: chat
---

Add a photo mode: play pauses, the player moves the camera freely, hides the HUD and takes a screenshot.

## Scope
- Open it from the pause menu (and optionally a key/button).
- Move the camera with the stick or arrow keys, zoom in whole steps, and reset to the player.
- Hide or show the HUD and play timer.
- Take a screenshot at the current window size, saved to a `screenshots/` folder in the save directory.
- Leaving photo mode returns to the pause menu with the camera back on the player.

## Design notes
- The simulation is already stopped while the menu is open, so photo mode adds no simulation step. Snapshot bytes before and after photo mode must be equal (same rule as `tests/menu_pause.gd`).
- The free camera is view only. It never moves the follow point or the 832×448 reference screen.
- The camera stays inside the map's drawable area, the same limit zoom already uses.
- Effects that read the saved tick stay frozen on that tick.
- Every control stays reachable at every window size.

## Acceptance checks
- Snapshot bytes are equal before and after a photo-mode session.
- A screenshot file is written with the HUD hidden when the HUD is hidden.
- Leaving photo mode does not send the confirm press to play (same rule as closing the menu).
- Controller and keyboard both work.
- `docs/ui.md` documents the mode and its controls.

## Context

### Files
- src/view/game.gd
- src/view/level_view.gd
- src/view/menu_model.gd
- src/view/menu_input.gd
- src/view/hud.gd
- docs/ui.md

### Decisions
- No simulation step runs in photo mode.
- The free camera never changes the reference screen or the follow point.

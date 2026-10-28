---
id: 2026-10-28-find-the-handheld-frame-rate-drop-endurance-replay-now-52-54-fps-was-60
title: "Find the handheld frame-rate drop: Endurance replay now 52-54 fps, was 60"
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a182b7-7d54-739b-9012-066125bd31f3/dab1c9b8-2a43-47af-a2b5-f24771f14295
---

On the RG35XX Pro, main 06012b4 runs the Endurance replay (`tools/device.py measure game-replay <label> 120 pause opengl3_es`) at 53.9 fps mean, p95 27.3 ms, p99 68.5 ms with Pantry. With Verdigris pack 3 it runs at 52.1 fps, p95 27.3 ms, p99 69.8 ms. Older device runs (`stall-*`, `stall-final-*` logs in /tmp/eggshell/logs on the device, also fetched to /tmp/eggshell-pack3/device-results/logs) held 60.0 fps with p99 around 19-21 ms. The pack adds little, so the drop is in the engine.

Steps: find the engine commit of the last 60 fps run, then bisect on the device with the same replay and Pantry. Candidates are the slice 6 merges (runtime objects, decorations, enemies, 9748d1e terrain strips) and 25507b5 (background dedupe, HUD backing).

## Context

### Why
Hands-on play on the target handheld is below 60 fps with p99 frames near 70 ms. Every later art check on the device is affected by this.

### Files
- src/view/pack_background.gd
- src/view/terrain_strips.gd
- src/view/level_view.gd
- tools/device-runtime.sh

### Decisions
- Pantry and pack 3 measured on the same build within 2 fps of each other, so this is an engine regression, not an art cost

Suggested in Verdigris pack 3 parallax (01a182b7-7d54-739b-9012-066125bd31f3), 2026-10-28

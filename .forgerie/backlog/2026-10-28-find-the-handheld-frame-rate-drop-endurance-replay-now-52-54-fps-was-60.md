---
id: 2026-10-28-find-the-handheld-frame-rate-drop-endurance-replay-now-52-54-fps-was-60
title: "Find the handheld frame-rate drop: Endurance replay now 52-54 fps, was 60"
status: Done
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

## Result (2026-10-28)

Fixed by "perf(save): compose snapshot schemas once instead of on every autosave".

Cause: the 60-tick autosave, not the view or the pack. `Snapshot.encode` rebuilt
`State.fields()` about four times (each call composed the level schema again and
deep-copied every field pair) and hashed the full schema of every registered code.
On the device the autosave frame took about 70 ms; one such frame each second is
the p99 near 70 ms. The cost grew with each schema change: a229d6d (v4 registry),
then each slice 6 type merge (545c76b, e4971dd, fd748a7, 7019af2). 9748d1e and
25507b5 changed nothing measurable.

Device, Endurance replay, Pantry, `measure game-replay <label> 120 pause opengl3_es`:

| Build | fps | p95 ms | p99 ms | autosave frame ms |
| --- | --- | --- | --- | --- |
| ad88b03 (last 60 fps engine) | 60.0 | 17.7 | 18.5-18.7 | 17 |
| 06012b4 | 58.3 | 18.6 | 24.8-25.6 | 72 |
| main 68663e5 | 57.9-58.1 | 19.0-19.3 | 25.2-26.6 | 77 |
| main + fix | 59.9-60.0 | 18.0-18.3 | 20.5-20.9 | 21 |

The 52-54 fps runs in the original report were not reproduced with the same build
and pack later the same day (58.3 fps). The rest of that gap is likely device load,
not code: korrid used 50-190% of one core across later runs and probes. Its load
during the original runs was not measured. Sim cost per tick also rose about
3x since ad88b03 (0.9 to 3.7 ms per tick on the device); it still fits a 16.7 ms frame.

After landing, main 0eabc35 on the device: 59.9 fps, p99 20.7-20.8 ms in two runs.
A third run fell to 53.9 fps, p99 44.9 ms. Its slow frames were all between 40 s and
80 s, the autosave frame stayed at 25 ms, and korrid used 103% of one core during it.
That matches the original 52-54 fps reports: background load on the device, not
engine code.

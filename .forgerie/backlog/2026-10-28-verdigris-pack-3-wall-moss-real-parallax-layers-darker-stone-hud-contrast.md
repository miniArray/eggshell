---
id: 2026-10-28-verdigris-pack-3-wall-moss-real-parallax-layers-darker-stone-hud-contrast
title: "Verdigris pack 3: wall moss, real parallax layers, darker stone, HUD contrast"
status: To Do
created: 2026-10-28
source: forgerie-suggestion
  01a17f92-cd9d-70c6-8814-a9440c419c42/f5373867-79f1-459d-bfae-0fdaef853f43
---

Follow-ups from pack 2 (`~/.local/share/eggshell/packs/verdigris-wip-2/`, page http://zao.hummingbird-lake.ts.net:8481/pack-2/, notes `art-direction/pack-2/work/NOTES.md`):

- Side and underside moss strips (the engine supports `side` and `underside` since 9748d1e; the pack declares none yet).
- Generate separate far, mid and near parallax layers instead of slicing one picture of style frame A. The current cut shows a faint straight line above the ground and patched spots while scrolling. Blocked until the image gateway's monthly paid cap resets or is raised.
- Stone is lighter and cleaner than frame A's dark masonry, and its 64 px repeat shows. Water below the surface line is one flat colour.
- HUD text is hard to read over the bright sky; it needs a contrast backing.
- Low: a map without background slots draws background 0 three times (same picture, wasted draw time).
- The device tool's `pack` command accepts only version 2 packs, so Verdigris (v3, density 2) cannot be sent to the RG35XX Pro for the in-game check yet.

Rules: docs/art-brief.md (nearest only, never resample below the generator grid, alpha 0/255; image model Nano Banana Pro).

## Context

### Why
Pack 2 is the first version that looks like style frame A; these are the visible gaps left before sprite sheets for enemies and objects, and the handheld check is a required approval step in the brief.

### Files
- docs/art-brief.md
- tools/device.py
- src/view/hud.gd
- src/view/pack_background.gd

### Decisions
- Moss, water and background in pack 2 were cut from style frame A because the image gateway hit its paid cap

Suggested in Art direction pivot, Eggshell (01a17f92-cd9d-70c6-8814-a9440c419c42), 2026-10-28

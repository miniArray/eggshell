---
id: 2026-11-01-screen-filters-crt-scanlines-soft-pixel-colour-blind-correction
title: "Screen filters: CRT scanlines, soft pixel, colour-blind correction"
status: To Do
created: 2026-11-01
source: chat
---

Add optional full-screen filters chosen from the Settings page: CRT scanlines, soft pixel (smoothed edges on scaled pixel art) and colour-blind correction (protanopia, deuteranopia, tritanopia).

## Design notes
- A full-screen shader applied after the game picture. View only; it never writes play state.
- The filter is a setting: an optional `settings.json` key, default off. Settings stays version 1; an invalid value logs a warning and uses off.
- Decide per filter whether it also covers the menu and HUD. Colour-blind correction must cover everything on screen; scanlines may skip the menu so text stays readable.
- Filters must work with integer scaling and nearest-neighbour drawing, and with high-refresh blending.
- Works with any graphics pack; filters are not pack data.

## Acceptance checks
- Snapshot bytes are equal with each filter on and off for the same inputs.
- Menu text stays readable at scale 1 with each filter on.
- An invalid or missing setting falls back to off with a warning, and the game still starts.
- Frame time on the development handheld stays within budget with each filter on.
- `docs/ui.md` lists the setting; `docs/saves.md` lists the key.

## Context

### Files
- src/view/game.gd
- src/view/screen_plan.gd
- src/view/menu_model.gd
- src/save/settings.gd
- docs/ui.md
- docs/saves.md

### Decisions
- View-only shader; default off.
- Colour-blind correction applies to the whole screen, including menus and HUD.

---
id: 2026-11-01-remap-keys-and-controller-buttons-saved-as-optional-settings-json-keys
title: Remap keys and controller buttons, saved as optional settings.json keys
status: To Do
created: 2026-11-01
source: forgerie-suggestion
  01a197a3-6afa-7459-90ba-dd095f7b3670/31c7440c-24d8-4876-aa89-af83eae719cf
---

Let the player change keyboard and controller bindings from the Settings page.

## Design notes
- Bindings are already built through `InputMap` in `src/view/game.gd`. Remapping changes those events, not the simulation's input masks, so physics and replays are unaffected.
- Save bindings as optional keys in `settings.json`. Settings stays version 1: a missing key uses the current defaults, an invalid one logs a warning and uses the default (same rule as the volume keys).
- Add a "Reset to defaults" item.
- Menu navigation (Back, Select, open/close menu) must always keep a working binding, so the player cannot lock themselves out. Refuse a change that would leave a menu action unbound.
- Show the current binding next to each action. Keyboard and controller bindings are edited separately.

## Acceptance checks
- A remapped action drives the same input mask as the default binding (same snapshot bytes for the same masks).
- Deleting or corrupting the binding keys falls back to defaults with a warning, and the game still starts.
- The menu cannot reach a state with no way to go Back or close it.
- Layout keeps every binding row reachable at every window size (`MenuView.plan`).
- README and `docs/ui.md` control tables state that they are defaults.

## Context

### Why
Accessibility and controller support, with no effect on YFS levels or simulation.

### Files
- src/view/game.gd
- src/save/settings.gd
- src/view/menu_model.gd
- src/view/menu_view.gd
- src/view/menu_input.gd
- docs/ui.md
- docs/saves.md
- README.md

### Decisions
- Bindings are optional settings.json keys; settings stays version 1.
- Menu navigation actions can never be left unbound.
- Remapping changes InputMap events only, never the simulation input masks.

Suggested in Non-breaking YFS enhancements (01a197a3-6afa-7459-90ba-dd095f7b3670), 2026-11-01

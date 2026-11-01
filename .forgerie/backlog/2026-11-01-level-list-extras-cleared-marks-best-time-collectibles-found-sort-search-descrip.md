---
id: 2026-11-01-level-list-extras-cleared-marks-best-time-collectibles-found-sort-search-descrip
title: "Level list extras: cleared marks, best time, collectibles found, sort,
  search, description panel"
status: To Do
created: 2026-11-01
source: forgerie-suggestion
  01a197a3-6afa-7459-90ba-dd095f7b3670/8401e4ae-c1d8-4df7-8e76-1a7df20a86d7
---

Extend the `--levels` list with per-level progress and better navigation.

## Scope
- **Cleared mark** on a row once the goal has been reached.
- **Best time** (the Level clock at the goal) on each row.
- **Red coins and flowers found**, shown as found / total. Totals come from the level code's `redcoins` and `flowers`; found counts come from the best run.
- **Sort** by file name (current natural order, stays the default), name, author, cleared state and best time.
- **Search** that filters rows by level name, author or file name.
- **Description panel** that shows the level's `desc`, author and revision for the focused row.

## Storage
- Store stats in the save directory under `levels/<level identity>/`, next to the autosave and slot. Never write into the level file.
- The level identity is the SHA-256 of the level code, so editing a level in its editor changes it. Also keep a file-name index so stats can still be found, marked as possibly out of date, after an edit.

## Layout
- The menu stays a function of window size (`MenuView.plan`). Every row, the search field and the panel must stay reachable at every size, at scale 1 and 16 px text.
- Search must work with a controller, not only a keyboard.

## Acceptance checks
- Reaching a goal updates the row's cleared mark, best time and collectibles found. A slower run does not overwrite the best time.
- Level files are byte-for-byte unchanged after play.
- Sort and search keep the focused level focused when it is still in the filtered list.
- Lists of 4096 files stay responsive.
- The menu never writes play state (snapshot bytes before and after using the list are equal).

## Context

### Why
Makes a folder of levels usable as a collection, with progress, without touching the level codes.

### Files
- src/view/level_list.gd
- src/view/menu_model.gd
- src/view/menu_view.gd
- src/view/menu_input.gd
- src/save/store.gd
- docs/ui.md
- docs/saves.md

### Decisions
- Stats live in the save directory under levels/<level identity>/, never in the level file.
- A file-name index is kept as a fallback so edited levels keep their stats, flagged as possibly stale.
- Natural file-name order stays the default sort.

Suggested in Non-breaking enhancements (01a197a3-6afa-7459-90ba-dd095f7b3670), 2026-11-01

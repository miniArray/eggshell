---
id: 2026-11-01-bundle-levels-and-packs-play-a-zip-or-folder-that-holds-both
title: "Bundle levels and packs: play a zip or folder that holds both"
status: To Do
created: 2026-11-01
source: forgerie-suggestion
  01a197a3-6afa-7459-90ba-dd095f7b3670/6242d83c-f9bf-4a30-8b70-5b483a830322
---

Accept one bundle (a folder or a zip) that holds a set of level codes and, optionally, a graphics pack, so a level collection can ship as one file.

## Design notes
- Level files inside the bundle stay byte-for-byte YFS level codes. The bundle adds no fields to them. Their level identity (SHA-256) and saves are the same as when the file is opened on its own.
- A small optional bundle manifest may name the collection, its level order and the pack directory. Without a manifest, use the existing `--levels` rules (every `.json` / `.txt`, natural order) and a `pack/` subfolder if present.
- The pack inside must be a normal version 2 or 3 pack. The existing rule stays: a pack never selects or supplies the level, and never changes physics.
- `--pack=` on the command line still wins over the bundled pack.
- Zip reading: reject absolute paths and parent traversal (same rule as pack file paths), and cap total uncompressed size.
- Saves go under `levels/<level identity>/` as with `--levels`.

## Acceptance checks
- The same level gives the same identity and loads the same autosave whether opened alone, from a folder or from a bundle.
- A bundle with an invalid pack still plays its levels with placeholder art, and logs why.
- A zip with traversal paths or an oversized entry is refused with a clear error.
- `--pack=` overrides the bundled pack.

## Risks
- If a bundle's manifest becomes required for anything gameplay-related, bundles stop being plain YFS level collections. Keep it presentation and ordering only.

## Context

### Why
Makes level collections with matching art easy to share and open, while each level stays a plain YFS level code.

### Files
- src/view/game.gd
- src/view/level_list.gd
- src/level/asset_pack.gd
- src/save/store.gd
- docs/ui.md
- docs/graphics.md
- README.md

### Decisions
- Level files inside a bundle are unmodified YFS level codes.
- The bundle manifest is optional and limited to name, order and pack location.
- A command-line --pack= overrides the bundled pack.
- Packs still never supply or select a level.

Suggested in Non-breaking YFS enhancements (01a197a3-6afa-7459-90ba-dd095f7b3670), 2026-11-01

# Graphics packs

Pantry is the built-in version 2 graphics pack at `res://packs/pantry`.
Its empty texture maps currently select diagnostic shapes. No third-party
art, fonts or music are bundled.

Select an external pack with `--pack=/absolute/path` after `--`, or with the
`EGGSHELL_PACK` environment variable. The command line wins. An invalid pack
logs the problem and uses placeholders. `--placeholder` bypasses pack loading.
Graphics never select or supply the level. Pass `--level-code=PATH` separately.

The version 2 manifest has `version`, `tiles`, `player` and `drawing_facts`.
The last field names `drawing_facts.json` within the pack. Drawing metadata
supplies a `tilemaps` dictionary and per-tileset draw-slot instances. The loader
and `src/view/level_view.gd` define the accepted texture and animation entries.
Those files are local pack inputs, not bundled content.

## View policy

The view fits its container, uses nearest-neighbor filtering and clamps inside
level bounds. It can show a larger area on a wider screen without activating
more enemies. Activation belongs to the fixed simulation reference area.

Goal and recovery markers use the same generated sprite texture. This keeps
their first appearance on the sprite shader path already used at startup.
Creating a new drawing primitive mid-level can trigger shader compilation.

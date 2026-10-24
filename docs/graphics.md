# Graphics packs

Pantry is the built-in version 2 graphics pack at `res://packs/pantry`.
It draws bread terrain (`garden64`, `garden32` and their variants), the
egg-carton level end (`levelEnd`), water (`water3`), the chick player, 24
object codes, a tiled kitchen wall and wall-mounted shelves. Other tilemaps and
object codes still use diagnostic shapes. No third-party art, fonts or music
are bundled. Source images and prompts: [art/pantry/README.md](../art/pantry/README.md).

Select an external pack with `--pack=/absolute/path` after `--`, or with the
`EGGSHELL_PACK` environment variable. The command line wins. An invalid pack
logs the problem and uses placeholders. `--placeholder` bypasses pack loading.
Graphics never select or supply the level. Pass `--level-code=PATH` separately.

The version 2 manifest has `version`, `tiles`, `player` and `drawing_facts`.
The last field names `drawing_facts.json` within the pack. Drawing metadata
supplies a `tilemaps` dictionary and per-tileset draw-slot instances. The loader
and `src/view/level_view.gd` define the accepted texture and animation entries.
Those files are local pack inputs, not bundled content.

## Pantry scenery and objects (provisional)

The manifest may carry three optional dictionaries. Packs without them, such as
user imports, draw exactly as before.

- `objects`: object code to `file` and `origin` (pixel anchor). The view uses
  them for simulated objects (enemies, spring, bridge, goal) and draws every
  other placed object as a static sprite at its level position, with its
  rotation and mirror fields. Static objects have no behaviour yet. `e5_head`
  and `recovery` name the plant head and the recovery marker.
- `background`: `wall`, `counter` and `cabinet` textures. The wall repeats
  over the whole map and scrolls 1:1 with the terrain, because supports are
  fixed to it. There is no parallax. The counter runs along the map bottom and
  the cabinet band along the map top.
- `supports`: `shelf` and `bracket` textures. `src/view/pack_dressing.gd`
  finds every downward-facing collision edge whose open side has no solid
  terrain and no map bottom. Flat runs get a shelf board inside the terrain's
  bottom edge and brackets on the wall below. Sloped undersides get a diagonal
  brace inside the terrain. Back-layer supports are tinted. Nothing hangs into
  the space the player moves through, and no support has collision.

All of this is drawing only. Level JSON, collision, simulation and saves are
unchanged. Built-in `res://` textures load through `ResourceLoader`; external
PNGs load directly. A source checkout needs
`godot --headless --path . --editor --import` after an artwork change.

## View policy

The view fits its container, uses nearest-neighbor filtering and clamps inside
level bounds. It can show a larger area on a wider screen without activating
more enemies. Activation belongs to the fixed simulation reference area.

Goal and recovery markers are sprites (generated, or the pack's art). This
keeps their first appearance on the sprite shader path already used at startup.
Creating a new drawing primitive mid-level can trigger shader compilation.

# Level codes

The reader accepts JSON level codes, preserves unknown fields and validates
size limits before expanding tile grids. It performs no file or network access.

## Metadata and normalization

`version`, `name`, `desc` and `author` supply `world.info` for level information.
Finite numeric authors are converted to display text, including the exported
zero sentinel. Other metadata strings remain unchanged. `world.info.revision`
contains numeric revision components; the original `version` string also remains.

`flowers` and `redcoins` are integer totals. Missing totals default to zero.
Negative exported totals stay in the decoded level; their simulation targets
are zero because they specify no positive requirement. The targets are separate
from collected counts.

The reader migrates the legacy `o14.E1: "1"` toggle to `F: 1`, removing `E1`.
Its compatibility gate compares writer strings with `"s3.8"` lexically. This is
separate from the numeric revision components used for level information.

A `startpoint` object supplies `map`, `X`, `Y`, optional `M` and optional
`palette`. Coordinates use pixels at the player's feet. `M: 1` selects left
facing. A palette is three RGB triples separated by underscores. Matching keyed
player-art tones receive these replacements; other art tones remain unchanged.

## Maps and simulation state

`maps` is a non-empty dictionary keyed by `map1`, `map2`, and so on. Each map has
positive pixel `width` and `height`, plus an `objects` dictionary. Every map is
compiled and cached, not only the starting map. Numeric key order gives stable,
one-based internal indices. For sparse keys, an internal index can differ from
the number in the key; `Maps.index_for(world, number)` resolves that number.

`src/sim/maps.gd` declares these int64 level fields:

| Field | Default |
| --- | ---: |
| `map_index` | 1 |
| `map_count` | 1 |
| `flowers_target` | 0 |
| `redcoins_target` | 0 |

State creation calls `Maps.initialize(state, world)`. `Maps.sync(state, world)`
selects cached geometry from the saved index before a step. It also checks the
map count and targets against the loaded level. `Maps.valid_state(state)` checks
field types, bounds and non-negative targets for the save boundary.

```gdscript
Maps.change(state, world, map_index, target_x, target_y, reset_map)
```

This pure function selects the destination, calls the supplied actor-reset
callable, clears basic movement and actor attachment, and places the player and
follow point exactly. Coordinates use simulation units: 3600 units per pixel.
Pass `Registry.spawn_map` as `reset_map`; the callable is never stored in state
or world. Invalid destinations, out-of-map points and missing callbacks return
false. Level-wide counts remain intact. No placed object automatically invokes
map travel yet. The view rebuilds terrain, backgrounds and placed visuals when
the saved index changes, including after restoration.

## Terrain and contacts

Optional `layer1`, `layer2` and `layer3` dictionaries map a tileset identifier to
a JSON string. Each string contains `c2tilemap: true`, cell `width` and `height`,
and comma-separated run data. `4x0` repeats tile zero four times; `-1` is empty.
Suffixes `h`, `v` and `d` select transforms. Decoded cells are signed int32.

Draw slots put rear terrain behind regular terrain and preserve front-family
slots. A tileset with no draw slot for its layer still loads: it takes the
diagnostic slot (`layer2` behind `layer1`). Draw order never blocks play.
Optional `layer3` draws at overlay slot 16, after regular terrain and actors.
This is an Eggshell fallback; it has neither solid nor liquid contacts.

`src/level/collision_table.json` version 2 supplies tile size, solid and water
membership, disabled tiles, full tiles and tile-local polygons for every
tileset the level format can name. A level that names a tileset absent from the
table is refused (`Unsupported tilemap`); terrain is never skipped. A tileset
with non-square tiles is refused (`Unsupported tile shape`) because cell lookup
assumes square cells. Graphics packs can replace draw order, never physical
membership. Non-solid contact terrain also caches polygons. Its pure query is:

```gdscript
World.named_overlaps(world, tilemap_name, left, top, right, bottom)
```

The rectangle uses simulation units. It applies the same transformed-polygon
contact rule as water and excludes `layer3`.

## Presentation

Each active map supplies:

- `bg1`, `bg2`, `bg3`, `gradient` and `bgcolor` for background drawing.
- `music` as an integer/string id, or `{src, dat}` selection. The compiled
  `music` dictionary retains `id`, `settings` and `custom` for later audio. No
  external source is fetched and no music is played here.
- `darkness`, clamped to 0–100 percent, with a player-centered light region.
- `tint`, encoded as `percent_r,g,b`, clamped to 0–50 percent.
- `caveShimmer: 1`, which enables timed tone swaps on the five 64-pixel cave
  styles. The saved tick supplies the phase; rendering has no independent clock.
- `diceBlockColours`, a nested JSON array string. Its RGB entries select the
  initial linked colours of placed `o33` and `o34` visuals by their `E4` group.
  This does not implement either object's behavior.

`src/view/map_effects.gd` draws the base color behind backgrounds, darkness above
world art, and tint above darkness. Labels remain above the effects. It only
reads play state. The light falloff is analytic; additional light-emitting
objects and terrain, custom terrain palettes and exact rendered comparison
remain follow-up work.

Objects use `A` as a kind identifier, `X`/`Y` as coordinates and optional
code-specific fields. Reading or drawing an object is not a claim that its
behavior is implemented. An empty `A` is accepted and behaves as the blank editor
form `empty`: nothing spawns, contacts or draws, and its fields are kept unread. The reader, compiler and focused synthetic checks in
`tests/level_format.gd` define the current accepted boundary.

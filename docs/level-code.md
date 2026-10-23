# Level codes

The reader accepts the existing JSON level-code structure. It preserves unknown
fields. It validates size limits before expanding tile grids.

A level contains string `version`, `name`, `desc` and `author` fields, a
`startpoint` object with `map`, `X` and `Y`, and a `maps` dictionary. The start
map number selects a key such as `map1`.

Each map has positive pixel `width` and `height`, an `objects` dictionary and
optional `layer1`, `layer2` and `layer3` dictionaries. Each layer maps a tileset
identifier to a JSON string. That string contains `c2tilemap: true`, grid `width`
and `height`, and `data` as comma-separated runs. A run such as `4x0` repeats
value zero four times. `-1` is empty. Suffixes `h`, `v` and `d` flip a tile.
The current player draws the first two layers.

Objects use `A` as a kind identifier and `X`, `Y` as placement coordinates.
The engine interprets `o5` as a goal, `o11` as a bounce pad, `p1` as a bridge,
and `e1`, `e2`, `e3`, `e5`, `e20` as the five implemented enemy types.
Other records are preserved but have no effect.

## Collision table

`src/level/collision_table.json` uses version 2. For each tileset it records the
tile size, solid and water membership, disabled tile numbers, full tile numbers
and tile-local collision polygons. It contains no images or atlas rectangles.
The loader adds diagnostic draw slots in memory. An optional graphics pack can
replace drawing order without changing collision or simulation state.

The reader and the compiler are authoritative. The courses under
`tests/fixtures/` demonstrate their current accepted structure.

# Graphics packs

Pantry is the built-in version 3 graphics pack at `res://packs/pantry`.
It draws bread terrain (`garden64`, `garden32` and their variants), the
egg-carton level end (`levelEnd`), water (`water3`), the chick player, 24
object codes, a tiled kitchen wall and wall-mounted shelves. Other tilemaps and
object codes still use diagnostic shapes. No third-party art, fonts or music
are bundled. Source images and prompts: [art/pantry/README.md](../art/pantry/README.md).

Select an external pack with `--pack=/absolute/path` after `--`, or with the
`EGGSHELL_PACK` environment variable. The command line wins. An invalid pack
logs the problem and uses placeholders. `--placeholder` bypasses pack loading.
Graphics never select or supply the level. Pass `--level-code=PATH` separately.

## Manifest versions 2 and 3

The loader accepts `version: 2` and `version: 3`. Both require `tiles` and
`player` dictionaries, and `drawing_facts: "drawing_facts.json"`. Drawing
metadata supplies a `tilemaps` dictionary and per-tileset draw-slot instances.
An unsupported version or invalid required section uses diagnostic shapes.
The optional top-level `density` is the number of art pixels per world pixel.
It accepts integers 1 through 4 and defaults to 1. An invalid value logs a
warning and uses 1; the pack still loads. Both versions accept it.
At density 2, a 32-world-pixel tile uses 64 by 64 art pixels. A 24 by 56
player image uses 48 by 112 art pixels.

Invalid optional sections are ignored. Missing images keep the existing
placeholder path. Files must be relative pack paths, without parent traversal.

`tiles` maps tilemap names to PNG files. `player` maps animation names to
animation entries. An animation has `frames`, `fps`, `loop` and an optional
pixel `origin: [x,y]`. Each frame has `file`, an optional overriding `origin`,
and an optional positive `duration` in frame units. Version 2's `speed` is
still accepted in place of `fps`. Zero fps selects a fixed frame. A looping
animation wraps; a non-looping animation holds its final frame.

Version 3 adds these optional dictionaries:

| Section | Shape |
| --- | --- |
| `objects` | Object code to a visual entry: `file` and pixel `origin`, or `animations` keyed by name. Animated entries may name `default_animation` and a `states` map. |
| `backgrounds` | Background id to `layers`, with optional per-frame `variants`. A layer has `file`, `frames` or `animation`, `scroll: [x,y]`, `scale: [x,y]`, `offset: [x,y]`, `reference: [x,y]`, `repeat_x` and `repeat_y`. `anchor` can replace `offset` and uses the selected frame's origin. |
| `gradients` | Name to `strips` of `{height, color: [r,g,b]}`, with optional `scroll` and `reference`. RGB values use 0–255. |
| `hud` | Named visual entries, reserved for future HUD drawing. |
| `fonts` | Named font files or bitmap sheets and glyph metadata, reserved for future text drawing. |
| `audio` | Music tracks, effects, and maps from game events and music roles to them. See [Audio](#audio). |
| `terrain` | Tilemap or tileset family name to optional `surface`, `underside` and `side` strips. A strip has `file` and `edge`. See [Terrain strips](#terrain-strips). |

Object entries may use `anchor: "position"` to keep the simulation origin,
rather than fit the art to its diagnostic box. `facing: -1` describes art that
faces left without a mirror. A `variants` dictionary may select a visual by
the placed object's `F` value. A state map may use `walk`, `idle`, `turn`, `fly`,
`active`, `chew`, `swim`, `prepare`, `jump`, `fall` or an animation name; a
`state:variant` key takes precedence. Missing states use the default animation.
The view uses the saved tick as its animation clock. It does not write an
animation clock, change simulation state or add fields to saves.

The view reads `bg1`, `bg2`, `bg3`, `gradient` and `bgcolor` from the selected
map. A background setting is `id,frame`, with frame 0 as the default. Entries
may supply `slots.bg1`, `slots.bg2` and `slots.bg3` scroll overrides and
`offset_by_height` maps. Scroll 1 follows terrain; scroll 0 stays fixed relative
to the reference point. Attached layers may specify a pack-pixel `repeat_size`
to keep their parent's spacing, `min_repeat` to limit repeated copies, and
`frame` for a fixed animation variant. Backgrounds repeat only across the visible region. The base RGB color remains
behind the gradient and all three background slots. A gradient setting is
`name_offset_scale`, or custom `height,r,g,b` groups in place of the name.
The offset replaces the first strip height; scale multiplies strip heights.

HUD and font metadata is retained but is not used by the current diagnostic
labels.

Fast metadata checks, without starting the game:

```sh
nix develop -c godot --headless --path . --script tests/pack_manifest.gd
```

## Audio

The optional `audio` section supplies sound. Pantry has no audio, so it is
silent. Every file is a relative Ogg Vorbis path; other entries are ignored.

```json
"audio": {
  "music": {
    "1": {"file": "audio/meadow.ogg", "loop_start": 1.95, "volume_db": 0},
    "2": "audio/caves.ogg",
    "fanfare": "audio/fanfare.ogg"
  },
  "effects": {"hop": "audio/hop.ogg", "chime": "audio/chime.ogg"},
  "events": {"jump": "hop", "coin": "chime"},
  "tracks": {"goal": "fanfare"}
}
```

| Key | Meaning |
| --- | --- |
| `music` | Track key to a file, or to `{file, loop_start, volume_db}`. Playback loops back to `loop_start` seconds (default 0). `volume_db` offsets the track volume (default 0, clamped to -60..24). |
| `effects` | Effect key to a file. |
| `events` | Game event name to an effect key. An unmapped event uses the effect with its own name. |
| `tracks` | Music role (`goal`, `death`) to a track key. An unmapped role uses the track with its own name. |

A map's level-code `music` id selects the track with that key. Id 0, an unknown
id and a remote address play no music; the player never downloads music. A
custom selection whose source names a pack track uses its own
`loop_start,volume_db` settings from the level code.

Game events:

| Group | Events |
| --- | --- |
| Movement | `jump`, `flutter`, `pound_start`, `pound_land`, `head_bump`, `splash`, `snow_step` |
| Mouth and eggs | `tongue`, `spit`, `spit_fire`, `spit_ice`, `spit_seed`, `egg_throw`, `aim_tick`, `egg_made`, `egg_pickup` |
| Damage and companion | `hit`, `stomp`, `companion_cry`, `countdown_high`, `countdown_low`, `countdown_full`, `rescue`, `rejoin`, `quick_death` |
| Items | `coin`, `red_coin`, `all_red_coins`, `flower`, `all_flowers`, `star`, `checkpoint` |
| Level objects | `switch_press`, `switch_timer`, `message_hit`, `message_open`, `message_scroll`, `message_close` |

The level track plays during play. Death stops all sound and plays the `death`
role once. Reaching the goal stops the level track and plays the `goal` role
once. The level track restarts after a respawn.

`src/view/audio_player.gd` derives these events by comparing the previous and
current saved state after each simulation step: counters, life phases, action
changes, request serials and the switch's saved sound triggers. It never
writes state, so sound cannot change physics or saves. A restored or replaced
state, a backward frame or a gap of more than four frames resynchronizes
without events: a restore never replays old sounds. After a restore the level
track starts again, and a running switch timer resumes at its saved position.
Effects share eight voices. A new sound for an event restarts that event's
voice; otherwise the oldest voice is reused. Effects are not positional.

`settings.json` holds `music_volume` and `effects_volume`, whole numbers from 0
to 100 (default 80). 0 silences that group. An invalid value logs a warning and
uses 80. Pass `--mute` after `--` to silence all audio, for example in tests.
Headless runs use the dummy audio driver; event derivation still runs.

Fast derivation checks, without audio output:

```sh
nix develop -c godot --headless --path . --script tests/audio.gd
```

## Terrain strips

The optional `terrain` dictionary lets fill tiles hold only interior material.
The view draws edge material from collision, so moss appears only where the
terrain's top is open to air. Each key is a tilemap name, such as `garden32_1`,
or a tileset family, such as `garden32`. The family is the name without a final
`_` and number. A tilemap's own entry wins over its family's entry.

```json
"terrain": {
  "castle32": {
    "surface": {"file": "terrain/moss.png", "edge": 6},
    "underside": {"file": "terrain/drip.png", "edge": 0},
    "side": {"file": "terrain/wall.png", "edge": 1}
  }
}
```

| Strip | Drawn along | Repeats | `edge` |
| --- | --- | --- | --- |
| `surface` | Every upward-facing open edge | Along x, with the image width | Image rows above the edge line, in the open air. Rows below it are inside the terrain. |
| `underside` | Every downward-facing open edge | Along x | Image rows above the edge line, inside the terrain. Rows below it hang into the open air. |
| `side` | Every sideways open edge | Along y, with the image height | Image columns left of the edge line. Draw the strip for a wall whose open side faces left. The view mirrors it for walls that face right. |

`edge` is a whole number of art pixels from 0 to the strip's height (width for
`side`). It defaults to 0. An invalid strip logs a warning and is ignored.
The strip pattern is fixed to the world: art column `x` uses image column
`x mod width`, so a run continues across tiles without a seam.

`src/view/terrain_edges.gd` finds the open edges. It takes every edge of every
cell's collision polygon, with the cell's flips. An edge faces up or down when its
normal is at least as vertical as it is horizontal; otherwise it is a side.
For each art pixel along the edge, it probes half an art pixel outside the
edge. The edge is open there when no terrain of the same kind covers the probe.
Solid terrain counts only solid layers; water counts only water layers. Only
layers in the same drawing group (`layer1` or `layer2`) count. The map border
counts as closed, so the ground along the map bottom and sides gets no strip.
Placed objects, such as one-way bridges, neither receive nor hide strips.
The finder first probes the middle of every 8-world-pixel interval and both
ends; an edge with no open probe is skipped. A gap narrower than 8 world
pixels between two other cells can therefore be missed.

Slopes are stepped, never rotated: each art column (each row, for a side) is
one whole slice of the strip, moved by whole art pixels. The edge line in a
column follows the same pixel-centre rule that masks partial fill tiles.
No strip pixel is scaled, blended or dropped. `src/view/terrain_strips.gd`
draws one node per dressed tile layer at the layer's own z index, after all
tile layers, in the order sides, undersides, surfaces. A surface covers the top
corner of a wall. Strips have no collision and change no saved state.

Packs without `terrain` add no node and draw exactly as before.

Checks: `tests/terrain_edges.gd` finds edges on small generated levels
(headless). `tests/test_terrain_render.py` reads back GPU frames under Xvfb and
checks each strip pixel on open tops, mirrored walls and unchanged internal joins.

## Pantry scenery and objects (provisional)

The manifest may carry three optional dictionaries. Packs without them keep the diagnostic path.

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

All pack image sizes and pixel coordinates use art pixels. This includes
origins, offsets, anchors, repeat sizes and scroll references. Divide them by
`density` to get world pixels. Layer `scale` and `scroll` remain ratios.
Simulation positions, level positions and map settings stay in world pixels.
Missing art keeps its diagnostic world size.

The view uses nearest filtering only, with no smoothing or mipmapping.
The reference scale is the square root of container area divided by 832 by 448.
Divide that reference by density. Choose the integer `m` closest in ratio,
never below 1. Each art pixel covers `m` screen pixels on each axis.
World scale is `m * density`. Raise `m` to fit level bounds if needed.
Clamp the camera inside the level. Round the root offset to whole screen pixels.

Density 1 keeps the existing drawing and layer transforms. For denser packs,
snap each sprite's final corner to screen pixels, including origins and mirrors.
Round squash, fit and layer scales to whole screen pixels per art pixel, with
a minimum of 1. This can change the fitted width or squash amount. Restore the
unsnapped transforms before each draw so resizing cannot cause drift.
Off-axis rotations use nearest sampling, so their art pixels are not uniform.
HUD icons and bitmap glyphs use the same `m`; they wrap instead of shrinking.
Omit an icon if it would push its text out of a narrow window.
In a window too small for one readout, later HUD items can be clipped; health
stays first at the top.

At density 1, a 640 by 480 container shows 640 by 480 world pixels. At density 2,
it shows 320 by 240. At 1920 by 1080, both show 960 by 540. At 3840 by 2160,
density 2 shows 960 by 540. A wider view does not activate more enemies.
Activation belongs to the fixed simulation reference area.

Goal and recovery markers are sprites (generated, or the pack's art). This
keeps their first appearance on the sprite shader path already used at startup.
Creating a new drawing primitive mid-level can trigger shader compilation.

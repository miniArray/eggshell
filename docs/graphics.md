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
| `audio` | `music` and `effects` dictionaries mapping ids or names to relative Ogg Vorbis files. |

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

`src/view/pack_audio.gd` holds the audio maps. It can lazily load a requested
stream, but creates no audio player and plays nothing. HUD and font metadata
is retained but is not used by the current diagnostic labels.

Fast metadata checks, without starting the game:

```sh
nix develop -c godot --headless --path . --script tests/pack_manifest.gd
```

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

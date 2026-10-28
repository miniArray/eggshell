# Art brief: Verdigris

This brief is decided with the user before any art is made. Agents follow it
for every picture in the Verdigris graphics pack. It replaces Pantry as the
direction for the original game. Pantry stays in the repository until
Verdigris is locked.

## Decided

| Topic | Decision |
|---|---|
| Concept | Verdigris, chosen 2026-10-27 from three concepts: the overgrown ruins of a glasshouse city. Teal and verdigris copper stone, jade water, coral-pink blossoms, pale gold light and cream mist |
| Look | Hi-bit pixel art near Hyper Light Drifter: many tones, large dithered gradients, crisp silhouettes, glowing accents, layered haze. Direction only; nothing is copied. It must not read as 8-bit or 16-bit |
| Style | Style frame round 1 variant A, "pastel painterly" (chosen 2026-10-27): soft pastel colour like a chalk-and-crayon picture book made of pixels, long gentle colour ramps, fine dithered texture on stone and moss, a rich layered background. Reference: `~/.local/share/eggshell/art-direction/style-frames/round-1/A-d1.png` until assets are locked |
| Art density | Two art pixels per world pixel (user, 2026-10-27, replacing an earlier choice of one). The pack declares its density; packs without the field stay at one. Oriel is about 110 art px tall, which is 55 world px, matching the collision box |
| Crisp pixels | No smoothing of any kind, ever (user, 2026-10-27): no bilinear, sharp-bilinear, box filter or other blending of art pixels on screen. Every art pixel is drawn with nearest-neighbour filtering |
| Screen scaling | Each art pixel covers a whole number of screen pixels, never fewer than one: no art pixel is dropped and none is blended. The scale is the integer closest in ratio to the 832x448 reference scale, raised only to fit level bounds. Visible world area varies by screen. See [View policy](graphics.md#view-policy) |
| Hero | Oriel, a slender young heron courier: pale blue-grey feathers, white chest, long yellow beak, coral-red scarf, leather satchel. She carries the city's last living seed to the central glasshouse |
| Oriel design | Reference drawing round 1, candidate A "true heron" (chosen 2026-10-27): small head, long S-curved neck, very long thin legs, a long dagger beak, wings folded neatly. Reference sprite: `~/.local/share/eggshell/art-direction/approved/oriel-reference/oriel-1x.png`, 91x110 art px, cut on the generator's own pixel grid |
| Companion | Pip, a seedling with a face in a small broken terracotta pot-shard it carries like a shell (design C, chosen 2026-10-27, reference `approved/pip-reference/`), rides in the satchel. The shard keeps Pip visible against foliage. A hit throws Pip out, and Pip drifts away under a dandelion parachute. The countdown shows as Pip wilting. Enemies that chase Pip are seed-eaters |
| Grab move | The neck strike: Oriel shoots out her neck and beak, grabs an enemy and swallows it |
| Throwables | Brass casings: a swallowed clockwork enemy becomes a brass ball. Casings follow her in a line and she throws them along an aim line. Refill blocks are old pneumatic post chutes |
| Enemies | Clockwork and glass creatures and carnivorous plants, for example a copper beetle (walker), a glass dragonfly (flyer) and a pitcher plant (rooted biter) |
| Scale | 832x448 reference view (`src/view/screen_plan.gd`); terrain tiles 32 world px (64 art px); player collision box 24x56 world px (48x112 art px). Oriel is about 55 world px tall |
| Outlines | Dark coloured one-pixel outlines on characters, enemies and items, never pure black; no outlines on terrain or background |
| Readability | Every surface you can stand on has a lit 1-2 px top edge. The foreground is calmer than the background |
| Compatibility | Verdigris is a graphics pack. It never changes world units, collision, level data or saves. Every level JSON plays the same with Verdigris, Pantry, the user's imported original pack or placeholders |
| Engine | The engine may change when that shows the art better (user, 2026-10-27). Each such change is an optional pack field or a view change. Packs without the field keep their current look and still load |
| Generator | gpt-image-2 made the concept, style frames, Oriel and Pip. From 2026-10-27 new art uses Nano Banana Pro (`gemini-3-pro-image`), because Codex credits are running out; a side-by-side redraw of Oriel kept the approved look. It returns JPEG, so cuts must ignore each generator pixel's edge ring and be checked for artefact specks |
| Method | Generate, cut to the pixel grid with a cluster-preserving downscale (mode colour per cell, never an average), then clean up only. Never redraw characters from scratch as typed pixels. Never shrink generated art below the generator's own pixel grid: ask the generator for the target size and cut on its grid (round 2 lost the drawing's detail by shrinking 110 px to 60 px) |
| Clean-up | Agents clean up generated art pixel by pixel; the user approves each sheet |

## Open

| Topic | Status |
|---|---|
| Mechanics | The simulation has no companion, grab or throwables yet; the view draws a recovery marker in the companion's place. Sheets for these moves wait until the moves exist |
| Animation | The user wants more animation frames for every character (2026-10-28). Today Oriel's run, jump and fall are single frames and the walk has two, so she looks still while running. Plan, ready to generate (`art-direction/oriel/anim-1/`): Idle 4 frames, Walk 6, Run 6, Jump 2, Fall 2, Flutter 4. That is 17 new in-between frames around the 7 approved key poses. All player cycles loop, because the view animates them on the global tick. Blocked by the image gateway's monthly paid cap until 2026-11-01 00:00 UTC. Pip and the enemies have no moving sprites in a pack yet: each gets its cycles in its first sheet, with at least 4 frames for a walk and 2 for a hover or idle |
| HUD | The final HUD should be ultra-minimal or hidden, shown only when it is relevant (user, 2026-10-28). Research on HUDs that appear when needed comes first; postponed. Until then, pack 3 draws an opaque dark-teal backing behind each readout (`hud.backing`) |
| Background layers | Separate generated far, mid and near layers wait for the image gateway's monthly paid cap. Pack 3 still cuts both layers from style frame A. Prompts and commands: `art-direction/pack-3/work/GENERATE-LATER.md` |
| Stone repeat | The 64 px stone period stays visible on the handheld (user, 2026-10-28). A 64 px tile cannot hide it; per-cell tile variants or a larger fill period need an engine change |

## Known costs

- Dense, painterly detail is the part most likely to be lost when art is cut
  to the pixel grid. Each round compares the cut art with the generator image.
- Free colour means consistency between images depends on cleanup. Agents keep
  a reference swatch of approved colours for Oriel, Pip and the casings.
- Pip must read at about 12 px inside a leafy world. The style frames check
  this before Pip's sheet is made.
- The neck strike needs wide frames. The art may extend past the collision box,
  but the box itself never changes.
- Density 2 costs four times the texture memory and about four times the
  cleanup per frame.
- On the 640x480 handheld, one screen pixel per art pixel shows only 320x240
  of the world. Platforming there sees much less ahead than on a TV. Packs at
  density 1, such as the original pack, keep 640x480.

## Approval steps

1. Concept: chosen (Verdigris).
2. Style frame: one mock game screen at real size, three variants; A chosen.
3. Reference drawing of Oriel: approved (round 3, 91x110 art px). Key poses idle, walk-a, walk-b, run, jump, fall and flutter approved as generated (2026-10-27, `approved/oriel-poses-1/`). Pip: design C, cleaned calm, drifting and wilting sprites approved (2026-10-27, `approved/pip-cleaned/`). Next, terrain tiles.
4. Asset sheets built on the approved frame and drawings, each approved on the page.
5. In-game check on the handheld and a 1080p screen with the test courses.
   Pack 3 (`packs/verdigris-wip-3/`) approved on the RG35XX Pro on 2026-10-28,
   as a recorded Endurance replay (Korri's controller capture was failing).
   The 1080p check is still to do.
6. Lock: approved files move into the repository with a list of what the user
   approved. Work-in-progress images stay in `~/.local/share/eggshell/art-direction/`.

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
| Art density | One art pixel per world pixel (user, 2026-10-27). One art set serves every screen. Oriel is about 56 art px tall |
| Crisp pixels | No smoothing of any kind, ever (user, 2026-10-27): no bilinear, sharp-bilinear, box filter or other blending of art pixels on screen. Every art pixel is drawn with nearest-neighbour filtering |
| Screen scaling | Positive integer scale, closest in ratio to the 832x448 reference scale, raised only to fit level bounds. One art set serves every screen; visible world area varies. See [View policy](graphics.md#view-policy) |
| Hero | Oriel, a slender young heron courier: pale blue-grey feathers, white chest, long yellow beak, coral-red scarf, leather satchel. She carries the city's last living seed to the central glasshouse |
| Oriel design | Reference drawing round 1, candidate A "true heron" (chosen 2026-10-27): small head, long S-curved neck, very long thin legs, a long dagger beak, wings folded neatly. Source: `~/.local/share/eggshell/art-direction/oriel/round-1/A-raw.png`. In game she is 60 art px from crest to toes, crown about 56, so her body matches the collision box |
| Companion | Pip, a seedling with a face, rides in the satchel. A hit throws Pip out, and Pip drifts away under a dandelion parachute. The countdown shows as Pip wilting. Enemies that chase Pip are seed-eaters |
| Grab move | The neck strike: Oriel shoots out her neck and beak, grabs an enemy and swallows it |
| Throwables | Brass casings: a swallowed clockwork enemy becomes a brass ball. Casings follow her in a line and she throws them along an aim line. Refill blocks are old pneumatic post chutes |
| Enemies | Clockwork and glass creatures and carnivorous plants, for example a copper beetle (walker), a glass dragonfly (flyer) and a pitcher plant (rooted biter) |
| Scale | 832x448 reference view (`src/view/screen_plan.gd`); terrain tiles 32 world px; player collision box 24x56 world px. Oriel is about 56 world px tall from feet to crown |
| Outlines | Dark coloured one-pixel outlines on characters, enemies and items, never pure black; no outlines on terrain or background |
| Readability | Every surface you can stand on has a lit 1-2 px top edge. The foreground is calmer than the background |
| Compatibility | Verdigris is a graphics pack. It never changes world units, collision, level data or saves. Every level JSON plays the same with Verdigris, Pantry, the user's imported original pack or placeholders |
| Engine | The engine may change when that shows the art better (user, 2026-10-27). Each such change is an optional pack field or a view change. Packs without the field keep their current look and still load |
| Generator | gpt-image-2 with the approved concept as an image reference (agent's choice, 2026-10-27; the user may change it) |
| Method | Generate, cut to the pixel grid with a cluster-preserving downscale (mode colour per cell, never an average), then clean up only. Never redraw characters from scratch as typed pixels |
| Clean-up | Agents clean up generated art pixel by pixel; the user approves each sheet |

## Open

| Topic | Status |
|---|---|
| Mechanics | The simulation has no companion, grab or throwables yet; the view draws a recovery marker in the companion's place. Sheets for these moves wait until the moves exist |

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
  cleanup per frame, and the 640x480 handheld shows less than half of its
  pixels.

## Approval steps

1. Concept: chosen (Verdigris).
2. Style frame: one mock game screen at real size, three variants; A chosen. Next,
   hand clean-up of the A frame on a Tailscale page.
3. Reference drawing of Oriel (design A chosen; clean-up at game size next), then of Pip.
4. Asset sheets built on the approved frame and drawings, each approved on the page.
5. In-game check on the handheld and a 1080p screen with the test courses.
6. Lock: approved files move into the repository with a list of what the user
   approved. Work-in-progress images stay in `~/.local/share/eggshell/art-direction/`.

# Eggshell

Eggshell is a Godot platform-level player for Linux. It uses a fixed 60 Hz
integer simulation, separate graphics packs and resumable play sessions.

Pantry is the bundled graphics pack: a chick in half an eggshell in a kitchen
at insect scale. It draws the `garden`, `levelEnd` and `water3` tilemaps, the
player, 24 object codes, a 1:1 kitchen wall and wall-mounted shelves under
raised terrain. Other tilemaps and object codes still draw as diagnostic shapes. See
[graphics packs](docs/graphics.md) and the [art sources](art/pantry/README.md).
No third-party artwork, music, fonts or levels ship with the player.

## Run

Enter the pinned development shell and build its engine link:

```sh
nix develop
nix build .#godot --out-link build/godot
# Import built-in textures after a fresh checkout or artwork change:
godot --headless --path . --editor --import
bash tools/play --path . -- --level-code=tests/fixtures/stride.level.json
```

| Action | Keyboard | Controller |
| --- | --- | --- |
| Move | Left/right or A/D | Left stick or D-pad |
| Jump and flutter | Space or Z | Either lower face button |
| Tongue or spit | Shift or X | Either upper face button |
| Look or direct upward | Up or W | Stick or D-pad up |
| Crouch, pound or dive | Down or S | Stick or D-pad down |
| Aim, then throw | C | Left shoulder |
| Toggle aim lock | V | Right shoulder |
| Save / restore slot | F5 / F9 | Back + left / right shoulder |

Movement reaches running speed without a modifier. Hold jump to flutter.
Up directs tongue and spit actions upward. Down in the air starts a ground
pound; in water it selects the submerged posture. Press throw twice to aim
and throw. Up selects vertical aim; tongue cancels aim.
The game automatically resumes the last session by default.

Use `--pack=/absolute/path` after the argument separator to select an external
version 2 or 3 graphics pack. A pack never supplies the level. A pack may also
supply music and sound effects; Pantry has none, so it is silent. Use `--mute`
after the separator to silence all audio.

## Implemented behavior

- Acceleration, turns, jumping, fluttering, crouching, ground pounds and swimming.
- Directed tongue, held-item, digestion, aiming and emission state with object hooks.
- Bounce pads, semisolid bridges, checkpoints and a timed goal sequence.
- Walkers, flyers, tumblers, shelled and armored walkers, shooters and fish.
- Coins, red coins, flowers, health drops, food contacts and thrown inventory items.
- Releasing blocks, linked solids, timed switches and saved message pages.
- Moving and falling supports, redirect clouds, rock blocks, posts and rotated gates.
- Typed decorations, top-only decoration strips and tick-driven effects.
- Knockback, temporary immunity, a moving companion bubble and body or tongue rescue.
- Countdown, capture, death and checkpoint respawn phases with a run HUD.
- Several compiled maps, map selection, three drawing layers and map effects.
- A type registry and composed version 6 snapshots with autosave and automatic resume.
- Pack music and sound effects derived from saved state, with music and effect volumes.
- Container-sized camera fitting with integer scales and nearest-neighbor graphics.

Terrain collision uses integer polygons, slope walking and floor snapping.
Player colliders follow the action and posture. Companion rescue uses the full
tongue reach; eating keeps its separate tip sensor. Map travel is a simulation
interface; no travel object is implemented yet.
Registered food and projectile families use the saved player-side requests.
Some object codes and variants remain unsupported. Such an object loads as an
inert placeholder and logs `Unsupported object <code> (<reason>)`; the level
still loads. Malformed object data still stops the level.
Packs without art use diagnostic shapes; absent action poses use the default pose.
Messages use Up/Down for pages and Throw to close. Red coins change only the red
counter. A level editor is not implemented.

## Physics and screens

Physics advances exactly 60 times per second on every device. Screen shape,
zoom and graphics packs do not change the simulation. A future high-refresh
view can interpolate pictures without changing physics or snapshot bytes.

## Tests

Fast synthetic player checks (no game scene or graphics pack):

```sh
nix develop -c godot --headless --path . --script tests/moves.gd
nix develop -c godot --headless --path . --script tests/move_input.gd
```

The full suite is reserved for hardening. Its recorded routes need updates after
movement changes:

```sh
nix develop -c python3 tests/check_all.py
```

The suite uses six original geometric courses in `tests/fixtures/`.
It needs no external game, download or graphics pack. Tests cover parsing,
movement, objects, enemies, damage, view invariance, exact restoration,
clean shutdown and twenty hard-kill recovery cycles.

## Development

Read `docs/architecture.md`, `docs/level-code.md`, `docs/graphics.md` and
`docs/saves.md`. Tools under `tools/device*` target a development handheld.
They require a separately configured, host-key-pinned SSH transport.
No device operation runs as part of the public test suite.

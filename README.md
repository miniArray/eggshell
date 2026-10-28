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
version 2 or 3 graphics pack. A pack never supplies the level.

## Implemented behavior

- Acceleration, turns, jumping, fluttering, crouching, ground pounds and swimming.
- Directed tongue, held-item, digestion, aiming and emission state with object hooks.
- Bounce pads, semisolid bridges and goal sensors.
- Walkers, flyers, tumblers, rooted biters and fish.
- Knockback, temporary immunity, a recovery marker and a failure countdown.
- Exact versioned snapshots with threaded autosave and automatic resume.
- Container-sized camera fitting with nearest-neighbor graphics.

Terrain collision uses integer polygons, slope walking and floor snapping.
Player colliders follow the action and posture. The recovery marker is stationary.
Food contacts, carried items and projectile objects are not yet wired to their
player-side hooks. Packs without an action pose use their usual default pose.
Audio and a level editor are not implemented.

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

Full suite:

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

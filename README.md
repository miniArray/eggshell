<p align="center">
  <img src="art/logo/eggshell-logo.png" width="549" height="261" alt="Eggshell">
</p>

<p align="center">
  <b>A platform-level player for Linux handhelds, written in Rust.</b>
</p>

Eggshell runs a fixed 60 Hz integer simulation. It draws with OpenGL ES through
SDL2 on Wayland and plays music and effects from a graphics pack. The target
device is the Anbernic RG35XX Pro (Mali-G31, Panfrost).

## Status

Measured on 2026-11-03:

| Result | Check |
| ---: | --- |
| 858&nbsp;of&nbsp;858 | Levels in the reference corpus that load, play and match the former Godot game on every tick of a 900-tick route |
| 849&nbsp;of&nbsp;854 | Measured levels that hold 60 frames per second on the RG35XX Pro |

## Controls

| Action | Controller |
| --- | --- |
| Move | D-pad |
| Jump, hold to flutter | A or B |
| Tongue or spit | X or Y |
| Aim, then throw | L1 |
| Aim lock | R1 |
| Ground pound, lay an egg | Down |
| Zoom in / out, reset zoom | R2 / L2, R3 |
| Pause | Start |
| Save / load slot | Select + L1 / Select + R1 |
| Quit | Select + Start |

In the level list, the D-pad moves, L1/R1 page, A plays and B goes back. After a goal
the menu offers Next level, Restart level, Levels and Quit.

## Build

```sh
# Host build and tests (Linux x86_64).
nix develop ./spikes/rust-stack/player -c cargo test --manifest-path spikes/rust-stack/core/Cargo.toml --release
nix develop ./spikes/rust-stack/player -c cargo test --manifest-path spikes/rust-stack/player/Cargo.toml --lib
# The aarch64 game binary for the handheld.
nix build ./spikes/rust-stack/player#arm64
```

The full gate (`spikes/rust-stack/tools/check-conversion.sh TAG BASE_TAG`) and the
device bundle (`spikes/rust-stack/tools/build-smoke.sh`) run on the build host `aka`.

## Layout

| Path | What |
| --- | --- |
| `spikes/rust-stack/core` | Simulation: level compile, the step, saves (`v10`), presentation state. |
| `spikes/rust-stack/player` | The game: SDL2 window, GLES drawing, input, audio, menus, level list. |
| `spikes/rust-stack/tools` | Gate, bundle and device scripts. |
| `data/collision_table.json` | Tile collision shapes that every level compile reads. |
| `tests/fixtures` | Public test levels and input routes. |
| `packs/pantry`, `art/pantry` | The built-in Pantry graphics pack and its sources. |
| `art/logo` | The title logo on this page. |
| `docs` | The level code format and the graphics pack format. |

No third-party artwork, music, fonts or levels are in Git. The original pack and the
level corpus are private inputs that the device bundle copies in at build time.

## Known gaps

- Levels whose music is a web link play no music (275 of 858).
- Five levels drop frames on the RG35XX Pro; the slowest holds 336 of 600 frames.
- Fixes made to the Godot game after commit `297ada9` are not in the Rust game.
- The Pantry pack builder was a Godot script; the built pack in `packs/pantry` stays.

## History

Eggshell started as a Godot game. Godot was removed on 2026-11-03. The last Godot
game is at tag `godot-final`. The Godot state checker that proved the Rust game equal
to it runs from tag `rust-parity-oracle`.

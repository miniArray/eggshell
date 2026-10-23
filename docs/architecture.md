# Architecture

The player has three parts:

- `src/level/` reads level codes and the collision table.
- `src/sim/` advances a plain integer state by one fixed 60 Hz step.
- `src/view/` collects input, draws state and performs storage effects.

`src/save/` encodes snapshots and writes them through a persistent worker.
`src/diag/` measures frame timing without changing the simulation.

## Invariants

Physics does not depend on screen size, graphics, rendering rate or zoom.
Position uses 1/3600 pixel units. Velocity uses those units per simulation step.
Enemy activation uses a fixed 832 by 448 reference area around the saved follow
point. It never uses the display viewport.

All mutable play fields, including the integer random-generator state, are
serialized. Restoring a snapshot and replaying the same inputs must reproduce
the same bytes. Rendering must not mutate those fields.

High-refresh presentation must interpolate between simulation steps. It must
not change the step rate or retune physics constants.

## Limits

Tile polygons currently collide through their bounding boxes. Curved motion
uses integer approximations. Recovery uses a stationary marker and an immediate
reset at countdown zero. These choices are tested behavior, not unfinished
runtime migrations.

## Test ownership

The six courses and recordings under `tests/fixtures/` are original geometric
test inputs. Focused tests also initialize controlled states to exercise contacts,
restore points and failure branches. A finishing recording never injects state.
The longer endurance course keeps real subprocesses alive during kill tests.

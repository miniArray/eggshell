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

## Terrain contacts

Level loading caches transformed integer tile polygons and their bounds. Bounds
only reject distant candidates; polygon edges and containment decide contact,
including concave shapes. Touching an edge counts as contact. Solid movement
uses pixel-step push-out followed by four fractional probes, down to 1/16 pixel.
A one-pixel raised side probe separates walkable slopes from walls. Grounded
movement follows descending slopes only within a speed-sized probe distance.
Floor detection probes one pixel below the actor without moving saved state.

The player, terrain-aware enemies and bounce pads share `src/sim/collision.gd`.
Bridges catch downward entry from above, not upward travel or entry from below.
All contact queries and movement after level loading use integer arithmetic.
No contact cache or new mutable state enters snapshots.

## Limits

Actor collision boxes stay fixed rather than following animation shapes.
Overlap recovery and sideways push limits use those fixed actor dimensions.
Movement tests endpoints and pushes out; it is not a continuous collision sweep.
Curved motion uses integer approximations. Recovery uses a stationary marker
and an immediate reset at countdown zero. Recorded routes need hardening after
physics changes; polygon contacts do not establish whole-game movement parity.

## Test ownership

The six courses and recordings under `tests/fixtures/` are original geometric
test inputs. Focused tests also initialize controlled states to exercise contacts,
restore points and failure branches. A finishing recording never injects state.
The longer endurance course keeps real subprocesses alive during kill tests.

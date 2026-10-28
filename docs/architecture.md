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

## Entity model and schemas

`src/sim/registry.gd` selects a module in `src/sim/types/` for each object code.
Each type declares `CODES` and `FIELDS`, an ordered array of `[name, default]`
int64 pairs. It supplies `create(source, world)`, `step(entity, state, world)`
and `valid(entity)`. Creation returns declared field overrides, including common
fields when needed. Type modules can also supply `prepare(source, world)` for
placement validation, plus `bounds`, `activate` and `contact` hooks. Optional phase constants preserve movement and contact order;
a type without them steps in phase 0 and contacts in phase 1.

`state.entities` is the single ordered saved entity table. Every placement,
including an unknown code, gets its original string `id`, its code, common
int64 lifecycle fields and type fields. `source_index` selects its immutable
compiled placement. The placement retains all property keys and value shapes.
Unknown codes have no simulation effects. Adding a type does not require new
snapshot layout code or a new per-kind state list.

Actors activate by collision bounds in the fixed 832 by 448 reference area.
The shared lifecycle can queue distant actors and recreate them after their
placement anchor leaves and returns. The distances and flags are common saved
fields. Load-active pads and static sensors keep their previous timing.
Collection and checkpoint-collection flags are also common saved fields. Camera
respawn preserves both flags; only an explicit map reset rolls them back or clears
them. The checkpoint type passes its declared respawn coordinates to the lifetime
hook. That module owns contact checks, awards and phases.

`Registry.spawn_map(state, world, keep_flags = false)` is the only entity reset
entry point. A same-map respawn can set `keep_flags` to roll collection back to
the checkpoint. It does not reset player state or level counters. The old
`state.enemies` and `state.springs` arrays are transitional read views containing
the very same dictionaries as the entity table. They keep the current view and
capture indexing working; they are not separately serialized. Never replace
or mutate those arrays to reset actors. `captured_by` remains a one-based index
in the actor read view until that consumer moves to stable ids.

`PlayState.player_fields()` composes base, movement and lifetime field lists.
`PlayState.level_fields()` composes base, lifetime and map field lists. Entries
are `[String, int]` pairs. Repeated declarations within one scope keep their
first position and use the last default; a name cannot belong to both scopes.
Creation initializes defaults and takes level-field values from matching world
keys. All other new mutable scalar state must be declared in these lists.
Optional module `valid_state(state)` hooks own their semantic validation.

The state module has no preload of world, collision, registry or step. It binds
the registry only when creating entities. `units.gd` is the scale-only leaf.
The world calls its separate `setup_objects(map, world)` placement compiler.
These boundaries avoid a preload cycle through state, movement and collision.

Snapshot version 4 writes these schemas and the registry's entity schemas.
It also stores a schema digest and checksum. See [saves](saves.md) for the exact
byte order, limits, reset flags and compatibility rules.

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

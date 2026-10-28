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
int64 lifecycle fields and type fields. A placed row's `source_index` selects its immutable
compiled placement; runtime rows use -1. The placement retains all property keys and value shapes.
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
the checkpoint. A non-keep reset clears held-item references and interrupts the
current move. Every table replacement clears its modal holder. Level counters
and the runtime serial remain unchanged. The old
`state.enemies` and `state.springs` arrays are transitional read views containing
the very same dictionaries as the entity table. They keep the current view and
capture indexing working; they are not separately serialized. Never replace
or mutate those arrays to reset actors. `captured_by` remains a one-based index
in the actor read view until that consumer moves to stable ids.

`PlayState.player_fields()` composes base, movement and lifetime field lists.
`PlayState.level_fields()` composes base, lifetime, map and registered type-level
field lists. Type `LEVEL_FIELDS` follow registry order and must have unique
names, separate from core fields. Entries
are `[String, int]` pairs. Repeated declarations within one scope keep their
first position and use the last default; a name cannot belong to both scopes.
Creation initializes defaults and takes level-field values from matching world
keys. It calls `Maps.initialize` and `Life.initialize` before spawning entities.
All other new mutable scalar state must be declared in these lists.
The movement, lifetime, map and registered type `valid_state(state)` hooks all
run at the snapshot boundary. Input masks use eight bits. Base validation permits a six-tick jump
buffer, flutter counters through 71 and water braking of 128.

The state module binds the registry late for schema composition and entity creation. `units.gd` is
the scale-only leaf. The world calls its `_build_objects` seam for every compiled
map, using that map's source and the registry placement compiler. Map caches
hold geometry and immutable entity sources; `Maps.sync` selects the saved map.
These boundaries avoid a preload cycle through state, movement and collision.

Snapshot version 4 writes these schemas and the registry's entity schemas.
It also stores a schema digest and checksum. See [saves](saves.md) for the exact
byte order, limits, reset flags and compatibility rules.

## Fixed step order

1. Synchronize the selected map and increment the simulation frame.
2. Advance lifetime phases with the registry reset callback and the bound map
   change callback. On respawn, reset movement-owned fields. A blocking phase
   returns before input, actor or player motion.
3. Sample input edges, then advance registered actors and pads. Capture keeps
   its early exit and fixed camera follow point.
4. Advance player actions and motion. Water entry and exit set braking to 128
   and 1296; a release value persists until one of those transitions.
5. Dispatch registered pad, actor and sensor contacts in phase order. Entering
   the goal phase converts active eligible actor bodies in the fixed reference
   area into coins once. An extended plant head is not a separate award.
6. Check the full tongue reach for companion rescue, then check lifetime terrain
   hazards and body rescue. Save the follow point and finish the player pose
   only while play remains active. The delayed goal pose stays intact.

Life and Maps call their callbacks immediately. They never store callbacks in
state or world. `move_tongue.gd` supplies read-only tongue geometry; movement
owns action transitions. Rendering rebuilds the active map's nodes and uses the
existing integer camera scale and rounded root offset. HUD and companion nodes
read saved state; they do not write it.

## Runtime entity hooks

`Registry.spawn_dynamic(state, world, code, x, y, options)` accepts registered
types that opt in with `DYNAMIC := true`. Coordinates use simulation units.
Placement-style `F`, `M`, `R` and `E1` through `E8` go through type preparation.
Other options must be declared int64 type fields, or `vx`, `vy`, `facing`,
`layer`, `can_despawn` or `despawn_radius`. Invalid or non-opted-in requests return
an empty dictionary, with a warning in debug builds. Creation stores every
needed option in declared fields; a runtime row has no placement to consult.

Placed rows keep the prefix in source order and use token `source_index + 1`.
Runtime rows append as `+n`, with token `1_000_000 + n`, from `dynamic_serial`.
Their ids and tokens are never reused within a map table. The serial continues
across map resets. `find_token` returns the current table entry or an empty
dictionary. `source_for` builds runtime descriptors from saved fields; lifecycle
never uses a runtime placement anchor or camera respawn.

`ENEMY := true` joins the enemy read view, as Actor codes already do. Runtime
compaction removes only defeated runtime rows, unless `finished(entity)` delays
removal. It never removes held items or the current captor. Rebuilding views
remaps `captured_by` through the captor's token. Snapshot restoration rebuilds
views without reindexing, so invalid encoded family indices remain detectable.
The legacy bridge support index refers to immutable geometry, not the runtime
suffix, and does not move during compaction.

A declared `held == 1` keeps step/request consumption but skips contact,
despawn, tongue contact, goal conversion and compaction. A declared `hidden == 1`
skips contact, tongue contact, projectile contact and goal conversion, but keeps
normal lifecycle timing. Optional world-space `activation_bounds` select the
activation/despawn body; relative `bounds` remain the hit and drawing body.

Integration calls `modal_step(state, world, input)` before lifetime advancement.
`modal_token` names the sole holder. Its optional
`modal_step(entity, state, world, input)` returns true while the world must wait;
false releases the holder. Enabled full solids without a special tongue hook
block the tongue; top-only solids do not add that fallback. After movement and contacts, call `tongue_contact`
with the tongue sensor, then `consume_requests`, then `compact` once. Type-level
consumers use `consume_level_requests(state, world)`; entity consumers use
`consume_requests(entity, state, world)` and save their own cursors.

A projectile first calls optional `projectile_contact`: 0 ignores, 1 consumes,
2 redirects, and 3 reacts and continues. Without that hook, `hit` receives the
integer kind from `hits.gd`, and consumes the projectile. Reaction 3 preserves
a solid's normal bounce, including its last pre-destruction geometry; a
non-solid target can be pierced. Pickup `origin_token` links collection back to
a retained producer row before checkpoint flags are captured.

`runtime_objects.gd` draws the runtime suffix using pack frames or the existing
diagnostic textures. `view_state` can select visibility, a literal animation,
a held frame, pixel offsets/sizes, degree rotation, horizontal flip and alpha.
The helper changes nodes only. The message type exposes immutable text through
`message(state, world)` and saved paging through `message_state(state, world)`.

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

Enemy collision boxes stay fixed. The player collider follows actions and
posture. Movement tests endpoints and pushes out; it is not a continuous sweep.
Curved motion uses integer approximations. The companion launches, floats and
returns through saved phases. A lost companion leads through capture, death,
fade and respawn phases rather than an immediate reset at countdown zero.
Item consumers and thrown inventory items use saved requests. More food,
projectile and liquid interaction variants remain object work.
Recorded routes need hardening after physics changes; focused contacts do not
establish whole-game movement parity.

## Test ownership

The six courses and recordings under `tests/fixtures/` are original geometric
test inputs. Focused tests also initialize controlled states to exercise contacts,
restore points and failure branches. A finishing recording never injects state.
The longer endurance course keeps real subprocesses alive during kill tests.

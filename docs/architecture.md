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
Its per-step entity loops (lifecycle and step, contact, request consumption) live
in `dispatch_loops.gd` and the camera lifecycle in `entity_lifecycle.gd`, behind the
same `Registry` functions.
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

No unbuilt object stops a level from loading. `Registry.compile_map` turns an
unregistered code, or a placement whose form a type does not build yet, into an
inert placeholder and logs one line, `Unsupported object <code> (<reason>)`. A
type signals an unbuilt form by returning `{"ok": false, "degrade": true,
"error": reason}` from `prepare` or `create`; a plain `{"ok": false}` is malformed
data and still fails the level. A placeholder keeps its id, token, position and
raw properties, and its compiled placement records the reason in `placeholder`.
An unregistered code keeps its code. A known code gets the `?` prefix (`?e1`), so
lookup, the family read views and the saved schema all select the inert type and
nothing treats the placeholder as the real object. It never steps or contacts,
and it draws as the diagnostic square.

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

Snapshot version 9 writes these schemas and the registry's entity schemas.
It also stores a schema digest and checksum. See [saves](saves.md) for the exact
byte order, limits, reset flags and compatibility rules.

## Fixed step order

Before a step, and never while the pause menu is open, the game copies the quick
death setting into the saved player field `quick_death`. Nothing else outside the
simulation writes play state.

1. Synchronize the selected map and increment the simulation frame. Dispatch
   `Registry.modal_step`; return while a message or switch holds the world.
2. Advance `Life.before_step` with the registry reset callback and bound map
   change callback. Reset Moves on respawn. Return when `Life.blocks_step` holds.
3. Sample input edges. Call `Collision.begin_step` immediately before
   `Registry.advance`, capturing the old solid geometry before object motion.
   `Registry.advance` runs `dispatch_loops.gd`: the camera lifecycle
   (`entity_lifecycle.gd`) and the step of every entity, in table order and
   phase order, including rows appended during the loop.
4. Unless captured, advance Moves. Its `Collision.prepare` carries the player
   using old and new support positions before floor and jump processing. Object
   motion must precede this carry. Water entry/exit braking remains 128/1296.
5. Dispatch registry contacts (`dispatch_loops.gd`, three contact phases). On a not-GOAL to GOAL transition, convert eligible
   visible active enemy bodies once. Keep the goal pose and delay.
6. Dispatch `Registry.tongue_contact` with the eating tip sensor. Check companion
   rescue with the full tongue reach, not that tip.
7. Call `Registry.consume_requests` (type-level consumers such as seed, fire and
   ice shots first, then entity consumers), then `Life.after_step`, then
   `Registry.compact` once outside entity loops. Captured players skip movement/contact paths but
   still reach request cleanup and compaction.
8. Save the fixed follow point. Finish the movement pose only during uncaptured
   active play.

Movement, damage, life and some types emit sound events during these phases
(`SoundEvents.emit`). Listeners compare their saved serial in their own step, so
they react one step later. Any code in these phases that moves another entity, or
changes a field its `bounds` read, calls `Collision.refresh(world, entity)`, and
no phase replaces or removes elements of `state.entities` in place (see
[query indexes](#query-indexes)).

Life and Maps call their callbacks immediately. They never store callbacks in
state or world. `move_tongue.gd` supplies read-only tongue geometry; movement
owns action transitions. Rendering rebuilds the active map's nodes and uses the
existing integer camera scale and rounded root offset. HUD and companion nodes
read saved state; they do not write it.

## View

The game node runs the fixed step and drawing through `src/view/frame_loop.gd`.
Each physics callback calls `tick`; an advancing callback calls `step`, which
records the drawn positions, advances the simulation once and lets sound observe
the new state once. Each rendered frame draws `picture`, then the view reads it.
The view and sound never write state (the quick death copy above is the one setting that reaches it). Snapshots, saves and activation never read
zoom, refresh rate, container size or the drawn picture.

On displays faster than 60 Hz, `picture` blends positions between the state
before the last step and the current state (`src/view/view_motion.gd`). The
blend is a shallow copy: moved entity rows are copied, still rows are shared and
the `enemies` and `springs` read views follow the copies. It covers the player,
camera, companion and rescue positions and every entity `x` and `y`, matched by
token. Values that types derive inside `view_state` are not blended. A restored
or replaced state, a frame gap, a map change, a respawn, a tick without a step
and a move longer than 64 pixels in one step draw the current state instead.
At 60 Hz, or with `--smooth=off`, the view draws saved states directly.

`src/view/screen_plan.gd` is a pure function of the container, level size,
follow point, pack density and zoom step. See [graphics](graphics.md#zoom) for
the zoom range and the look of enemies that the simulation has not activated.

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
2 redirects and stops travel for the rest of that tick, and 3 reacts and continues.
The redirected velocity starts on the next tick. Without that hook, `hit` receives the
integer kind from `hits.gd`, and consumes the projectile. Reaction 3 preserves
a non-enemy solid's normal bounce, including its last pre-destruction geometry.
Enemy reactions are pierced, including a flattened rideable enemy. Pickup `origin_token` links collection back to
a retained producer row before checkpoint flags are captured.

Fire and ice use the same hooks. `src/sim/elements.gd` names the elements, the
player's element ammunition and the reaction flags a type declares in
`ELEMENT_REACTIONS`. Heat and cold movement requests become `fire_shot` and
`ice_shot` runtime rows that pass through what they strike. A shot strikes only
types that declare reactions: through `hit` with `Hits.FIRE` or `Hits.ICE`, or,
for a type without `hit`, through `projectile_contact`. Lamps and launchers
keep `hit` absent on purpose, because eggs, seeds and spat bodies treat a
`hit`-only target as one that consumes them. `src/sim/element_reactions.gd`
holds the shared burn and freeze rules: a reacting enemy's `hit` passes element
strikes there first, and its `step` and `contact` call `frozen_step` and
`frozen_contact` before their own logic. Frozen bodies stop, fall unless
anchored, can still be eaten, and shatter on the player's touch. They never
become solid; freezing a launcher only removes its solid box.

`runtime_objects.gd` draws the runtime suffix using pack frames or the existing
diagnostic textures. `view_state` can select visibility, a literal animation,
a held frame, pixel offsets/sizes, degree rotation, horizontal flip and alpha.
The helper changes nodes only. The view calls it once for all dynamic rows,
including enemies; placed enemies keep their own nodes. Both paths hide held
and hidden rows. Separate head hulls use `head_box` for their diagnostic views.
Art density, integer camera scales and pixel snapping apply to the new paths too.
The message type exposes immutable text through `message(state, world)` and saved
paging through `message_state(state, world)`. A plain default-font HUD panel reads
these values without handling input or changing simulation state.

## Sound events

Some objects react to what they hear, so a sound is play state, not only audio.
`src/sim/sound_events.gd` owns the core level fields `sound_serial`, `sound_kind`,
`sound_x` and `sound_y`: a counter of events and the kind and position of the latest
one. `SoundEvents.emit(state, kind, x, y)` is pure; the serial wraps to 1, never to 0.
Kinds: `PLAYER` (a player sound effect at the body centre, 28 px above the feet),
`PICKUP` (a coin, flower or star at the pickup), `SWITCH` (a pressed switch) and
`RELEASE` (a flower releasing a pickup, heard by each listener at its own position).

Player events come from the moments that voice the player: a jump, a flutter start,
starting and landing a ground pound, the tongue, a toss, a head bump, getting hurt,
a slow death, reaching the goal and the companion rejoining. Aim ticks, pushing and
ducking are silent to listeners. Collection, switch and flower types emit their own.

A listener saves the serial it last heard and reacts when the state's serial
differs, so it hears only the latest event of a step, one step later. It takes the
current serial when it activates, so sounds from before then are not news. A restored
snapshot carries the serial and every cursor, so restoring replays nothing. The
audio view still derives its cues from state and does not read these fields.

## Terrain contacts

Level loading caches transformed integer tile polygons and their bounds. Bounds
only reject distant candidates; polygon edges and containment decide contact,
including concave shapes. Touching an edge counts as contact. Solid movement
uses pixel-step push-out followed by four fractional probes, down to 1/16 pixel.
A one-pixel raised side probe separates walkable slopes from walls. Grounded
movement follows descending slopes only within a speed-sized probe distance.
Floor detection probes one pixel below the actor without moving saved state.

Lava and spike tilemaps are contact-only hazards. `World.LAVA_LAYERS` names the
whole lava family (`lava` and `lava_1` through `lava_4`), and every consumer reads
that one list: the player dies, enemies and stars are removed, and thrown eggs
treat it as lava. The spike tilemap kills only the player.

The player, terrain-aware enemies and bounce pads share `src/sim/collision.gd`.
Bridges catch downward entry from above, not upward travel or entry from below.
All contact queries and movement after level loading use integer arithmetic.
Registered `SOLID` types supply world-space `solid_box` or `solid_boxes`, with
an optional `solid_touches` narrow phase. Top-only boxes keep strip gaps open.
The transient `world.solids_step` cache is rebuilt each normal step. It carries
support history and deduplicates bump callbacks, but never enters snapshots.
The legacy saved bridge index never refers to a transient support handle.

## Query indexes

Indexes change how queries are answered, never their results or the order of
side effects. None of them enters snapshots.

- `Registry.lookup`, script constants (`script_constants.gd`), field schemas and
  per-code dispatch facts are read once per code or type.
- Each compiled map caches, per 256 px chunk, which terrain layers have contact
  cells there. Terrain queries read only those layers. Terrain never changes
  after loading, so each map also remembers recent terrain answers per probe
  box, and where `Collision.prepare` moves a body out of terrain when no solid
  row is filed within the search's reach (that search then reads terrain only).
- The solid index files each solid row in a 128 px grid under its region: its
  live boxes plus its `bounds` around its position. The registry refiles a row
  after every dispatch on its entity (lifecycle and step, contact, tongue,
  request consumption, switch toggle), and collision refiles it after a bump
  callback. While a dispatch on a solid runs, that solid is always a candidate.
  Queries evaluate candidate boxes live, in entity order.
- **Contract for types:** between dispatches on an entity, other code may only
  shrink or remove that entity's solid boxes, or enable boxes inside its
  `bounds`. Code that moves or enlarges another entity's solid boxes must call
  `Collision.refresh(world, entity)`. `Collision.verify_index = true` compares
  every indexed query with a full scan and counts differences in
  `Collision.verify_failures`; tests and identity runs use it.
- `Registry.nearby(state, world, box)` returns the entities whose bounds may
  overlap a box (edges count), in entity order, including every status. Area
  queries in new types use it instead of iterating `state.entities`. During
  steps the entity grid (`entity_grid.gd`) answers it: every entity filed in
  128 px cells under its bounds around its position, candidates tested live.
  The registry marks an entity after every dispatch on it and refiles marked
  entities at the next query; a dispatching entity is always a candidate.
  Compaction and runtime creation are found by a walk of the table. A step uses
  the grid when the previous step asked at least four queries, and scans
  otherwise; both give the same answer.
- **Contract for types (all entities):** code that moves another entity, or
  changes a field its `bounds` read (a hit that changes its form, for example),
  must call `Collision.refresh(world, entity)` (`NearQuery.refresh_solid` in
  types). It refiles both indexes. Verify runs compare every `nearby` answer
  with a scan too.
- Tables change only by replacement or by appending (runtime creation).
  Compaction builds a new table when an entity leaves and keeps the table
  otherwise. Code must not replace or remove elements of `state.entities` in
  place: `Collision.begin_step` reuses its rows while the table array and its
  size are unchanged.

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

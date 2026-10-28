# Saves

Snapshot version 4 stores the complete integer play state in little-endian
bytes. Its layout follows the declared schemas, not a hand-written list of
object families. Version 3 and all other versions are rejected with a log line;
old saves are not migrated.

## Layout

| Order | Representation |
| --- | --- |
| Header | `EGGSTATE` (8 bytes), version (u32), level identity (32 bytes), schema digest (32 bytes) |
| Level fields | int64 values in `PlayState.level_fields()` order |
| Player fields | int64 values in `PlayState.player_fields()` order |
| Entity count | u32 |
| Each entity | code string, stable id string, field count (u32), common then type-specific int64 values |
| Checksum | SHA-256 of all preceding bytes (32 bytes) |

Both strings use a u32 byte length followed by UTF-8, with a 4096-byte limit
per string. An entity's `id` is the original placement key, not an integer
conversion or an array position. Its int64 `source_index` is the zero-based
position in the active map's compiled entity table. Entity order is placement
order. Unknown codes use the common schema and stay inert; their ids and state
round trip like known types. Placement properties stay in the immutable world,
which the level identity binds to the snapshot.

The schema digest covers ordered level/player declarations, common entity
fields, type codes and type fields. A changed schema rejects incompatible bytes
even if someone forgot to change the version. Deliberate layout changes still
require a version bump.

The codec rejects oversized data, invalid UTF-8, wrong lengths, counts, field
counts, schema digest, checksum or level identity. It validates int64 schemas,
unique placement ids, ordered source indices, collection flags, common lifecycle
fields and each type's `valid(entity)` hook. Optional `valid_state(state)` hooks
on movement, lifetime and map modules validate their own state. Extra undeclared
state is rejected instead of silently omitted. `Snapshot.decode(bytes, identity,
world)` can also check the complete ordered entity table against an active world.
The two-argument form retains level-identity validation without a world check.
The three-argument decoder synchronizes a temporary world selection to the saved
map before validating the ordered table and bridge support. A successful decode
selects that map in the caller's world. Rejection leaves its map unchanged.

## Composed version 4 state

Base fields hold simulation frame, follow point, input edges, motion, water and
capture state. Movement owns action and posture timers, tongue reach, aim, held
items, egg counts and the saved emission history. Lifetime owns damage, companion
and rescue motion, countdown, death and goal phases, checkpoints and counters.
Maps owns selected map, map count and collectible targets. All three owner
validation hooks run. Derived actor and pad views share the entity dictionaries
and are not encoded a second time.

This slice keeps version 4 while composing the owners' complete schemas. It does
not retain an intermediate stub layout. Saved nodes, callbacks and view state
are never part of the payload.

## Checkpoint collection flags

Every entity has `collected` and `checkpoint_collected`, both int64 flags with
default 0. `Registry.spawn_map(state, world, keep_flags = false)` rebuilds the
active map's entities and their derived compatibility views. The default clears
both flags. With `keep_flags = true`, it matches same-map old entities by their
stable string id. It restores `collected` from the old `checkpoint_collected`
and keeps that checkpoint flag. It does not retain pickups taken after the
checkpoint, carry flags between maps, or clear level counters. Future pickup
types use these flags to suppress their own effects and presentation.

## Slots and writes

The setting `resume_where_i_left_off` defaults to true. The player loads its
autosave at startup and writes a new one during play and on orderly shutdown.
F5 writes a manual slot and F9 restores it. On a controller, hold the back
button and press the left shoulder to save or the right shoulder to load.

Invalid state encodes to an empty payload. Save callers skip that payload, so a
failed validation cannot replace a valid slot with empty bytes.

Writes happen on a persistent worker. A write flushes and closes a temporary
file, then renames it within the save directory. It does not synchronize the
file or directory to physical storage. Process termination checks do not prove
sudden power-loss safety. A hard kill can lose the most recent unsaved steps.
Changing screen shape or graphics does not change snapshot compatibility.

Fast schema and codec checks, with invented data and no game scene:

```sh
nix develop -c godot --headless --path . --script tests/registry.gd
```

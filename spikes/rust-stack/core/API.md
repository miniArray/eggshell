# Shared API, initial interface

Package `eggshell-spike-core`, library `eggshell_spike_core`, path `../core`.
No engine, graphics, SDL, clock, file I/O, or callbacks belong to this library.

- `Session::load(&str, &str, &str) -> Result<Session, Error>` takes raw level,
  collision table and complete reference schema metadata JSON.
- `advance(u8) -> Result<(), Error>` advances exactly one gameplay tick.
- `snapshot() -> Result<Vec<u8>, Error>` / `restore(&[u8]) -> Result<(), Error>`
  are literal v10. Restore must reject a different world/schema.
- `presentation() -> Presentation` samples semantic visuals. This owned typed
  packet contains table-ordered entity pictures, stable tokens/placement ids,
  current/previous integer positions, follow point, player movement/lifetime,
  sound output and per-type frame/animation/size/alpha/head information.
  `VisualState` values are overrides; absent size/frame/animation uses the
  renderer's pack binding. Rotation/offset/size are pixel/degree values.
- `world() -> &World` is immutable and should be read once. Maps contain all
  terrain layers and placement options in source order, backgrounds and effects.
- `admission_report() -> &AdmissionReport` and `stats() -> &Stats` are read-only.

Positions and velocity use saved integer 1/3600 pixel units. Layer, code,
variant and placement properties select pack art; the pack does not select
simulation rules. Renderer must not write back any packet data.

## Interface refinement 2

- `TileLayer.source_layer` replaces ambiguous `name`; `tilemap` is the family.
  Exact `tile_size_pixels`, `DrawSlot`, solid/water/hazard flags and transformed
  integer collision polygons come from immutable compilation, not name guesses.
- `EntityPicture.source_index` binds `Map.placements` (None for runtime rows).
  Placement properties retain nested original JSON shapes. `body_bounds` is
  relative integer geometry; `visual.head_box` is world-space geometry.
- Visual flip overrides are `Option<bool>` for each axis. Default alpha is 1.
  Optional semantic asset/origin/slice/palette overrides do not replace pack
  binding. Player owns pack texture/frame/origin/slice interpretation.
- `PlayerPicture.selected_pose` is the exact semantic `PlayerPose.select`
  name/tick/frame. Player must not repeat the action-to-pose state machine.
- Presentation has explicit companion, bubble and four rescuer packets,
  HUD lifetime/readouts/status, and optional message text and saved paging.
- World carries spawn, initial map and player palette. Map retains cave shimmer,
  dice colours and original immutable properties for effect bindings.

## Current implemented vertical slice (not target admission)

`Session::load` admits only the exact unchanged public Stride world, the pinned
collision table and the complete original v10 schema. Authoritative Rust state
runs both uncounted start ticks. `advance` implements dry LEFT/RIGHT/JUMP,
terrain-body motion, jump/release/flutter/landing/facing, ordered walker
activation/motion/contact, goal conversion and goal lifetime motion. Damage,
separation/rescue, other actions, other fixtures and the target remain unsupported.
An unsupported step returns an error without changing state or accepted-tick count.

Snapshots reconstruct the literal complete v10 payload from this typed state.
Unused declarations retain their original defaults at the codec boundary;
restore rejects non-default fields whose semantics are not implemented. This is
narrow fixture interoperability, not validation/admission of every original state.
`wire::WireSnapshot` is an inspection codec, not gameplay state or a stepping VM.
There is no per-tick JSON or schema-name dispatch in gameplay.

`Stats.completed_ticks` counts successful `advance` calls, including calls after
Godot's saved frame stops at completion. `Stats.tick` is the saved simulation frame.
Workload counters include actual entity steps and terrain probes during the two
start ticks; restore setup is excluded. This slice uses a typed rollback copy on
each step so unsupported contacts cannot partly change the session. It is not a
candidate performance build. Nearby/runtime-spawn paths are not admitted.

`World::compile` exposes immutable compilation for verification. It is not
simulation admission. Do not use a successful world compilation or structural
wire round-trip as evidence of playable target support.

`EntityPicture.auxiliary` contains typed `EntityAuxiliaryPicture` entries. Kind
`PlantHead` uses an `AuxiliaryPicture` plus nonuniform `scale`; this represents a
separate e5_head visual, not an inferred head hull. It is not populated until e5
rules and sampling exist. The target remains refused in the meantime.

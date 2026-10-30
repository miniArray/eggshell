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
  `rotation_degrees: Option<f64>` defaults to None; Some(0.0) is an explicit
  zero override, not absence. Binding precedence is compiled placement defaults
  and pack anchors first, then present live semantic overrides. Optional sizes,
  flips and palette swaps follow the same rule. Empty palette means no swap.
  Offset zero and alpha one are the current target's safe identity defaults.
  `scale: Option<[f64; 2]>` is an asset-independent multiplicative ratio after
  bound-frame/absolute-size selection and before placement/camera transforms.
  None and Some([1.0, 1.0]) preserve output. Pad squash samples the original
  nonuniform ratio; this adds no v10 fields and does not change gameplay.
- `PlayerPicture.selected_pose` is the exact semantic `PlayerPose.select`
  name/tick/frame. Player must not repeat the action-to-pose state machine.
- Presentation has explicit companion, bubble and four rescuer packets,
  HUD lifetime/readouts/status, and optional message text and saved paging.
- World carries spawn, initial map and player palette. Map retains cave shimmer,
  dice colours and original immutable properties for effect bindings.

## Immutable preparation API (bridge/support gate)

`Placement.prepared: PreparedPlacement` has `None`,
`Bridge { geometry_index: usize }`, and `Pad { large: bool, single_use: bool }`.
The bridge index is zero-based into `Map.bridges: Vec<BridgeGeometry>`.
`BridgeGeometry { left, right, top }` uses saved integer simulation units.
Bridge order is registry/placement order, not drawing order. The saved positive
`support_bridge` value is `geometry_index + 1`; do not confuse those conventions.
The compiler rounds width once as `roundi(E1 * 3600)`, divides that integer by
2 for left/right, and sets top to source y minus 16 pixels. Rendering must not
round these facts again. Raw source properties remain unchanged.

Map owns the immutable geometry. Live entity solids and their old/new geometry
belong to separate typed transient simulation caches, never writes into Map.
Pad flags are immutable source facts; squash/active/velocity are saved entity
state. `None` is not waived admission. o11 Pad is a verification-only dependency
of Bounce; p1 Bridge is also required by the selected target.

## Current implemented vertical slice (not target admission)

`Session::load` admits only the exact unchanged public Stride/Bounce/Lagoon worlds,
the pinned collision table and complete original v10 schema. Authoritative Rust
state runs both uncounted start ticks. `advance` implements LEFT/RIGHT/JUMP,
empty-mouth USE/tongue/terrain blocking, terrain-body/legacy bridge motion,
jump/release/flutter/landing/facing, ordered walker activation/motion/contact,
Pad gravity/contact/squash, damage and hurt input locks, companion launch/bubble/
catch/rejoin, goal conversion and goal lifetime motion. Tongue food capture and
request consumers refuse explicitly. Stride damage and Bounce have every-tick
parity and both restore directions. Original Bounce has 1 bridge-support tick,
12 tongue ticks, but no pad compression. Named `bounce.pad` normal controls
activate 12 squash ticks and verify the sampled ratio on every tick. Lagoon
adds actual water contact, integer buoyancy/wait/bobbing, liquid motion caps,
water jump/exit and wet pose sampling, including 91 swimming snapshots.
Captor/death/respawn code is typed but needs its normally reached route proof.
Other actions, other fixtures and the target remain unsupported.
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

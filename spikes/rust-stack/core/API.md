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

Initial skeleton: load, advance and both codecs return explicit
`Error::NotImplemented`. No Session can be constructed successfully yet;
`presentation` cannot be called without a Session. No successful idle fake.
The initial loader deliberately does not accept schema/world-only state as
playable. Further implementations must retain that admission rule.

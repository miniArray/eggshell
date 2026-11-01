---
id: 2026-11-01-epic-presentation-effects-particles-shake-audio-lighting-water
title: "Epic: presentation effects (particles, screen shake, dynamic audio, lighting, glow, water shaders)"
status: To Do
created: 2026-11-01
source: chat
---

Add a set of drawing and sound effects that make play feel richer. Every part is presentation only: it reads play state and never writes it. This ticket holds the whole epic; the parts below can land one at a time.

## Compatibility rules (apply to every part)

- The view only reads play state. Snapshot bytes for the same level and inputs must be equal with every effect on or off.
- No change to step timing. No hit-stop or freeze frames: a real pause changes timing against the reference behaviour, and a view-only pause would draw a state that is not true.
- Effects derive from saved state (saved tick, sound events, phases), so a restored snapshot or a replay draws the same effects. No independent clocks in the view.
- Level codes are never read for new fields or written. New art data lives in graphics packs, as new optional pack v3 sections or fields. Packs without them draw as today.
- Every effect works with any pack, including a pack that has no art for it (then the effect is skipped or uses a neutral default).
- Each effect has a setting (optional `settings.json` key; settings stays version 1) where players may need to turn it off.

## Parts

### 1. Particles
Landing dust, coin sparkle, water splashes and ground-pound bursts. Trigger them from existing sound events (`src/sim/sound_events.gd`) and state changes (landing, entering water, pickup). Particle art and counts come from an optional pack section. Particles have no collision.

### 2. Screen shake
A short camera shake on ground-pound landings and when the player is hit. It moves the camera only, never the follow point or the 832×448 reference screen (`src/sim/screen.gd`). Setting: on/off, default on, because shake makes some players ill.

### 3. Dynamic audio
Muffle sound (low-pass filter) while the player is under water, read from water state. Make music busier near the goal, for example by adding layers that the pack supplies. The audio view keeps deriving cues from state (`src/view/pack_audio.gd`, `src/view/audio_player.gd`). Packs without layers play as today.

### 4. Real 2D lights from glowing objects
Lamps (lit and put out by fire breath already exist in the simulation), fire breath, burning bubbles and lava emit light. Light reads object state only.
Fairness rule: Level `darkness` hides parts of a level on purpose. Added light must never show more of a dark level than the original darkness shows. The existing analytic light region in `src/view/map_effects.gd` stays the limit.

### 5. Normal maps in packs
An optional per-image normal map in pack v3 entries, so art reacts to the lights from part 4. Images without a normal map draw flat, as today. Document the field in `docs/graphics.md` and cover it in `tests/pack_manifest.gd`.

### 6. Glow and bloom
Glow on fire, coins and the goal. A view-only shader or environment glow. Setting: on/off, because it can wash out on the handheld screen.

### 7. Water shaders
A moving water surface, caustics and a slight bend of the picture under water. Drawn from the water tiles; water contact rules and the collision table do not change.

## Acceptance checks

- For each part: snapshot bytes are equal with the effect on and off over a recorded fixture route (`tests/view_invariance.gd` style).
- Restoring a snapshot mid-effect draws the same effect state as continuous play at that tick.
- Packs without the new sections load and draw as before; `tests/pack_manifest.gd` covers the new optional fields and their invalid forms.
- With lights on, the visible area in a dark map is not larger than with lights off.
- Frame time on the development handheld stays within budget with every effect on; each heavy effect (lights, glow, water) can be turned off.
- `docs/graphics.md`, `docs/ui.md` and `docs/saves.md` (settings keys) describe the new sections and settings.

## Context

### Files
- src/view/level_view.gd
- src/view/map_effects.gd
- src/view/pack_audio.gd
- src/view/audio_player.gd
- src/view/screen_plan.gd
- src/level/asset_pack.gd
- src/sim/sound_events.gd (read only)
- src/save/settings.gd
- docs/graphics.md
- docs/ui.md

### Decisions
- Presentation only; no simulation, timing or level-code change.
- No hit-stop or freeze frames.
- Light never reveals more than the original darkness.
- New art data is optional pack data and is not tied to any one pack.

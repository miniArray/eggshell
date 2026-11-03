# THROWAWAY standalone Rust-owned player

**Question:** can unchanged level `6600ab52a3bb0805d316b9f1` run faithfully and
substantially faster on Pro without Godot? **Answer so far:** native platform
acceptance passed; target gameplay and picture admission remain blocked.
No target A/B, speedup or sustained-60 claim is made.

## Evidence and scope

| Stage | Verified evidence | Not established |
| --- | --- | --- |
| `660b6a3544f5c0fcb748220fe379edd5abd47f85` SDL_Renderer smoke | Parent observed Wayland, genuine SDL2 2.32.10, `opengles2` flags14, Mesa Mali-G31 MC1/Panfrost, GLES3.1 Mesa26.2.3, 640x480, limit16384²; 8 original PNGs, actual GPU readback, clean10s exit | Gameplay, physical controls, picture parity, performance |
| Asset binding stage on aka | 510 target PNGs verified against pinned3028-file inventory; 12,519,816 decoded RGBA bytes; largest576x544. Stride:440 PNGs /5,185,112 bytes | This is immutable asset preparation, not target simulation or GPU proof |
| `aeb9dae` owned GLES Stride120 | Parent observed actual Pro capture: exact v10 match and0 changed pixels across640x480 RGBA against original Godot | Only this fixture/frame; external map observer failed for an unknown cause |
| `2ff26d0` startup-map Stride120 | Parent verified120 calls, exact original v10 and all307200 RGBA pixels unchanged; six device ELF hashes match bundle; private72323-byte maps observed native Panfrost | Maps report EGL/gallium26.2.3 plus libgbm26.1.3; not a proven bug. No physical-input, delivered-frame, target or FPS claim |
| Typed gameplay | Exact canonical51b82b9 core tree `8bd9e2f50e367a20ebb9dcbcb2fc80ac9c713cc4`; admitted Stride damage, Bounce/pad and Lagoon | New scale/wet/count bindings require their own GPU cases; target still refused |

Parent smoke measurements: cold startup3667ms and systemd peak119.9MiB.
These are **capture-tainted platform-smoke** numbers, not full-game measurements.
Four X360 handles opened; zero input events means enumeration only. The smoke
logged two missing Compose-locale errors. Packaging now includes matching locale
data when present in the pinned closure; that fix needs fresh device observation.

## Modes

- Default: bounded SDL_Renderer **presentation-only smoke**, never called gameplay.
- `--play`: actual `Session::load/advance/presentation` verification using the owned
  GLES pipeline. Current target load fails before graphics. No position replay.
  Fixture inputs are literal8-bit masks, not drawing positions.
- `--validate-assets LEVEL COLLISION PACK INVENTORY VIEW_METRICS PRIVATE_REPORT`:
  immutable `World::compile` and original-PNG binding only. Its output explicitly
  says no gameplay admission and no GPU proof.
- `--admit-game LEVEL COLLISION SCHEMA`: reports core admission and refuses any
  not-yet-reviewed player admission. It is not a benchmark switch.

`--play` requires `--level`, `--collision`, `--schema`, `--pack-root`,
`--pack-inventory`, `--view-metrics` and isolated `--save-dir` paths.
Optional: `--replay`, `--ticks`, `--seconds` (hard1..900s bound), `--windowed`,
`--restore`, `--uncapped`, `--capture-tick` plus private `--capture` path.
All runs currently label `benchmark_eligible=false` and `target_A_B_claim=false`.
Correctness replay uses an accepted-input-call cursor, never the saved frame.
It permits800 accepted calls while the saved frame holds419. `--require-active-window`
rejects held-frame calls only when an active performance window is requested.
`--restore` with replay requires explicit `--input-offset`. Capture pauses at the
exact requested call without discarding owed steps and writes associated PNG,
literalv10 and camera/input metadata outside clean timers.

`--presentation-feedback` optionally requests actual `wp_presentation` callbacks
on SDL's Wayland connection. Unsupported/overflow/pending feedback is explicit.
Without it, `actual_compositor_delivered_frames` is null; swap calls are never
called delivered frames. This protocol shim is not a prerequisite for the first
capture-tainted picture gate. It must itself be observed before timing claims.

## Rendering and input contracts

Optional semantic ratios multiply bound frame/absolute sizes before camera/dense
transforms. Pad base size uses prepared large/single-use facts and the selected
original first-frame height. Unknown semantic player poses fail; they never
silently use idle. HUD reads core packets, not inferred placement counts.

The owned GLES backend is an explicit mode, not a fallback from SDL_Renderer.
SDL2 owns its native Wayland window/context; Rust owns the shader pipeline.
The small C shim owns Wayland protocol listeners, not gameplay. SDL2 and drivers
are C/native dependencies: do not call this an all-Rust stack.

Both backends force and inspect native Wayland and GLES/Mali/Panfrost identity.
The owned backend also requires observed RGBA8 and nearest texture filtering;
software, ANGLE/Zink, X11 and unannounced Vulkan substitution are not admitted.
`SDL2` here is genuine upstream2.32.10 pinned in `sdl2.nix`, **not** the Pro's
installed SDL3-backed sdl2-compat. Rust1.97.1/ARM64, Nix inputs and Cargo are locked.

`Scene` clones immutable compiled map data once. It never mutates Session or
serializes gameplay every frame. Current core saved map indices are one-based;
map vectors are zero-based. Screen-plan input is actual drawable size. Simulation
activation receives no viewport, zoom or GPU values. Initial comparison must pin
smoothing off in **both** arms; higher-refresh interpolation is not claimed yet.

Visual direction is reproduction, not redesign. Original PNGs, layers, origins,
flips, palette keys, darkness50% and existing HUD bitmap glyphs remain intact.
Missing required art/effects are explicit errors, not new substitutes. The only
procedural auxiliary pictures reproduce baseline `hud.gd`'s own white fallback
and bubble ring. Background gradients, terrain-strip packs, message panels and
semantic slice overrides are refused if required. The selected target has no
such gradient/strip requirements. Nonzero tint outside the target is refused.

HUD space is absent from the private bitmap sheet. Offline reference extraction
from pinned Godot4.7.2 measured its fallback advance as **5px** at size16; the
candidate reads those metrics, never calls Godot. Keep metadata extracts private.

P / controller Start pauses; Escape / Guide / Back+Start exits. F5/F9 and Back
plus shoulders save/restore. Controller action edges aggregate across handles,
so duplicate interfaces cannot double-toggle pause. Gameplay bit mappings follow
`move_input.gd` and `game.gd`. Physical built-in acceptance remains separate.
Pause/exit stay available at all framebuffer sizes. The internal timer remains
active when paused or unfocused. Unsupported core actions stop with an error.

The fixed60 clock stores nanoseconds-times60 and never drops owed steps. Save
encoding/queueing runs separately from sim/draw/present timers on a60 accepted-call
cadence, with explicit input-offset phase; persistent writes flush/close/rename without fsync. Captures and codec
verification are not clean timings. Main-thread phases do not overlap. Quantiles
use constant-memory log-histogram upper bounds (bucket width<=1/512 above512ns);
maxima are exact. Compositor delivery and swap-return intervals are distinct.

## Matched alpha primitive (diagnostic only)

**Correction:** the actual five-case f316 rerun refuted sampler precision as the
solution: rescue remained exactly the same1456 changed pixels, while the four
opaque/pad/wet/visible-ring controls remained exact. Do not relax equality.
The original A helper captured an opaque SubViewport; B captured its default
window framebuffer. This is a verified path difference, not yet a cause.

`launch-blend-probe` uses unchanged current `Gles::draw/capture`, no gameplay or
private art:256x4 RGBA8 R/G/B/gray ramps; backgroundColor8(42,46,56); four
nearest512x32 quads atx64/y64,144,224,304; alpha.25/.5/.75/1. The default-only6baf control reproduced one-byte RGB differences while the
opaque band matched. The next isolated diagnostic completes that identical
4draw default pass first, then uses the same texture/quads/shader/blend/clear in
owned RGBA8 and RGB10_A2 FBOs for4draws each. It captures each currently bound target before
swap/blit: `data/blend-default.{png,json,maps}` and
`data/blend-rgba8-fbo.{png,json}` and `data/blend-rgb10-a2-fbo.{png,json}`. The FBO's actual internal-format enum and
attachment bits/component/encoding state are recorded; nearest blit only displays
the already-captured FBO image. No gameplay path binds these diagnostic FBOs.
Locked Godot `texture_storage.cpp2554..2571` selects RGBA16F for HDR, RGBA8 for
transparent LDR, and **RGB10_A2 for opaque LDR**, while reporting Image.RGBA8.
Thus8-bit PNG/readback format does not establish8-bit blending storage. Actual
4fa primitive comparisons reduced17536 changed pixels to768 through RGB10_A2,
but direct readback was not exact. Godot GLES `texture_2d_get1515..1632` samples
the source into a temporary unsized RGBA/UNSIGNED_BYTE FBO with blending disabled
before reading RGBA8. The next diagnostic retains all3direct controls, then
samples the SAME rendered RGB10 texture through the exact full-section simple
copy into RGBA8 before readback. Copy source stays nearest; temporary destination
filter is linear, as vendor source specifies. Copy shader has no multiply or
sRGB conversion. Main rendering stays unchanged ESSL100; only the matched copy
uses vendor ESSL300/highp output. Output adds
`data/blend-rgb10-a2-copy-rgba8.{png,json}` and completion13draws/4targets.
Actual d8 sampling copy was byte-identical to direct RGB10:768 changed pixels
remained. No gameplay target/readback changes are enabled. The next isolated
probe retains all4old controls, then renders the SAME RGB10 target/spec with
syntax-only ESSL300 translation and explicit highp output. Numeric expressions,
RGBA8 source texture, blending and geometry remain unchanged. It captures both
direct and SAME vendor-copy readbacks as
`blend-rgb10-a2-es300-fbo.*` and `blend-rgb10-a2-es300-copy-rgba8.*`.
Completion is18draws/6targets. Checked Khronos ESSL100 declares gl_FragColor
mediump; locked Godot ESSL300 declares an explicit output under a highp default.
Actual376b76c GPU matrix passed all4new A/B full-frame pairs at0pixels/0channels;
all4legacy controls stayed unchanged. This proves the combined language/highp-output
and RGB10 path for this primitive, not output precision independently.

Game mode now selects an explicit separate Gles constructor: ESSL300/highp renderer,
persistent opaque RGB10_A2 target, persistent full-screen shader-copy resources and
RGBA8 window swap. Legacy probe construction remains ESSL100/default-target.
Only startup/real resize allocates the game target. Screenshot requests allocate
and release a temporary RGBA8 copy/readback target outside clean CPU timers.
The normal presentation copy runs every presented frame and is INSIDE the
`presentation_copy_and_swap` phase. Runtime metadata queries both actual attachments.
Actual280ce6c five-case state/maps/ELF/pipeline gates passed but ALL5pictures
failed:80/122/80/123/80pixels. Localization proves ONLY3HUD icons differ;
text and world are unchanged. Stride=16LifeCounter+47coin+17red pixels.

Next isolated game candidate replaces vertex division by a CPU-built mat4
screen projection, matching Godot's translate(-size/2),scale(2/size),mat4*vertex
operation. Native Y reflection is kept, so target orientation/readback/presentation
are unchanged. UVs, topology, texture sampling, fragments and RGB10 pipeline
remain unchanged. Godot's conditional pixel-snap UV bias is NOT enabled: original
viewport defaults false and no project override was found. No selected-pixel bias.
Actuale2ee004 retained the SAME5BPNG hashes and80/122/80/123/80red pixels;
CPU matrix projection alone did not fix this device/control.

Next single-axis candidate retains that matrix and changes GAME rect submission
order ONLY. Quad corners are TL,TR,BR,BL; Godot vertex_base TL,BL,BR,TR,TL,BR maps
to indices[0,3,2,1,0,2]. The old[0,1,2,0,2,3] remains explicit for legacy probe
construction. Same diagonal, corners, UVs, textures, samplers, fragments and nativeY
reflection. Copy-effect quad/order remains unchanged. No UV bias/exclusion.
Source-backed, not yet a verified cause/fix. All5full state/picture cases remain
mandatory. This is not a performance result, actor8fa merge or target204 admission. JSON records actual GL framebuffer
bindings, channel/component/encoding enums, samples, blend/dither state and SDL
config queries. Parent owns matched original Godot Window/SubViewport captures
and all Pro operations. This probe does not change gameplay rendering or claim
performance. Use a fresh guarded root and `--done-marker RUST_BLEND_PROBE_DONE`.

## Translucent-color repair probe (historical f316)

The a852 matrix matched saved state and opaque pad/wet pictures, but the
translucent rescue picture had one-byte red/green differences. Criterion remains
full RGBA equality. The isolated repair keeps canonical51b and all geometry,
blending, dither and modulation unchanged. It only declares the texture sampler
`highp`, matching actual pinned Godot4.7.2 `ShaderGLES3` source lines218..225.
Godot's modulation buffer uses float channels, not guessed8-bit packing.
The fetched source file SHA256 is
`17c01277dc3468a1d53081f01a6f7665f5d0f82e7882a8198e1f486ee344d5d8`.
The checked Khronos GLSL ES1.00 specification says sampler defaults are lowp
and texture-return precision follows sampler precision. Native ESSL's previously
implicit lowp sampler could quantize texels before half-alpha blending. The matched Pro rerun found no pixel change; this hypothesis is refuted for the observed red case.
Private pixel/sign analysis runs only on aka through executable
`tools/inspect-alpha.sh` (its own Nix Python/Pillow closure). No reference image,
RGB sample tables, snapshots or generated reports enter Git. Highp may have a GPU
cost; no performance claim follows from this correctness repair.

## Remote-only checks and private bundles

All builds, tests, parsing, asset processing and Nix evaluation run **only on aka**
with `NIX_CONFIG='builders ='`, through the existing runner:

```
python3 ~/.local/share/eggshell-run/aka/aka.py run . full-rust-player -- \
  /run/current-system/sw/bin/nix develop -c bash spikes/rust-stack/tools/check-presentation-stage.sh
```

This runs the player's focused tests/Clippy/format check and private target/Stride
asset binding, plus Bounce/Lagoon binding for the next case bundle.
`check-tools.sh` checks only shipped spike tools. Do not run the
production/full suite here; parent owns combined verification.

After transporting formatted sources/locks back and committing, set a full
`EXPECTED_SOURCE_SHA` and run `../tools/build-smoke.sh` on aka. It checks HEAD and
clean tracked sources before release build. Set `PLAYER_PRESENTATION_BUNDLE=1`
to add the four private asset-binding reports' original PNG sets and a real Stride
verification entrypoint. Artifact root refuses overwrite:

`~/eggshell-remote/artifacts/full-rust-ab/player/FULL_SHA/`

It contains `smoke-arm64.tar.gz`, original full `runtime-closure.nar`, exact
RPATH/NEEDED plus SDL dlopen dependency provenance, original and relocated hashes,
compiler/lock/source records and archive inventory. Private assets, level, schema,
reference metrics and captures never enter Git or a Nix source/cache. Device Mesa
through the parent's pinned `/run/opengl-driver` remains an explicit external
runtime dependency; parent must archive actual loaded maps.

## Parent-only Pro launch

Extract under `/tmp/eggshell-full-rust-LABEL` and use the parent's guarded runner.
`launch-smoke` runs the original10s SDL_Renderer acceptance. With a presentation
bundle, `launch-owned-verify` runs **120 actual Stride ticks**, fixed60, original
pack, v10 saves and GPU capture at tick120 under `data/owned-tick-120.png`.
It directly execs the application using a local unexported `LIBPATH` and explicit
loader `--library-path`; it runs no system grep/tee under candidate library paths.
Parent must use guard `--done-marker RUST_GAME_DONE`, which the application emits
only after120 successful calls. Before ready/clean timers, the application reads
`/proc/self/maps` once into private `data/saves/startup-process.maps` and prints
`RUST_STARTUP_MAPS` with its hash. Existing evidence is never overwritten.
It remains fixture verification, not target B or a clean timing run.
The checked Linux [proc_pid_maps(5)](https://man7.org/linux/man-pages/man5/proc_pid_maps.5.html)
specifies current memory mappings, not libraries that may load later. This is
startup evidence only; parent still audits actual mapped libraries and hardware.

The next bundle also contains `launch-owned-case FIXTURE INPUT_CALLS`, where
FIXTURE is `stride`, `stride.damage`, `bounce`, `bounce.pad` or `lagoon`, and
INPUT_CALLS is1..800. Parent chooses capture calls from original traces, then
runs a fresh guarded root with `--done-marker RUST_GAME_DONE FIXTURE INPUT_CALLS`.
Output is `data/FIXTURE-call-INPUT_CALLS.{png,v10,json}`. These runs execute real
`Session::advance` from original levels and input masks; no oracle snapshots or
position streams are bundled. Each run retains30-second internal bounds and
startup maps. No child device launches; no timing/performance claim.
Parent alone performs every device launch/stop and matched Godot GPU comparison.

Primary sources checked: baseline architecture/saves/graphics docs and owning
view/input files; pinned SDL owning-source capability checks; pinned
wayland-protocols1.49 `stable/presentation-time/presentation-time.xml` for actual
presented/discarded/clock/sequence semantics. Device compatibility is not inferred
from source support. Rust tests and asset counts are not picture evidence.

## Feel spike: pickups, water, and goal music

`feel.json` is local presentation configuration, never snapshot data. The paused
Feel page adds Coin sparkle, Water splashes, Goal music, and Goal music strength
(0..3, default 2). Missing keys in old files use defaults; all three switches
start on. These use the existing menu layout and particle layer 12.

Sparkles read `Presentation.sound` kind 2 and its serial/position: the core's
explicit pickup signal, including tongue pickups and stars at the health cap.
The packet retains the last sound in a step, so simultaneous pickups can coalesce
into one twinkle (or be masked by a later sound in that same step). No viewport
query or full entity scan is added to the per-step observer. Water reads swimming
edges and the current/previous vertical velocity. The fan begins at the nearest
compiled water polygon's top at the player's x; internal tile edges are excluded.

Goal music reads immutable `o5` placements and the presented player position.
The nearest goal starts the lift at 640 level pixels; 64 pixels gives full lift.
A one-second time constant uses saved simulation ticks, not rendering time.
`RUST_AUDIO_GOAL proximity=...` reports changes of at least 0.1.

Music streams through upstream's bounded decoder-thread queue; only compressed
music remains in memory. The music bus gets up to +3 dB and a gentle presence
shelf above 1.5 kHz at strength 3. Effects do not receive that lift. A 20 ms
audio ramp removes control steps; underwater muffle processes the final mix.
Clipping/headroom still need listening checks on device. Packs with no music
stay silent. Remote music retains upstream's verified private-copy loading.

The optional `music_layers` stem from the earlier spike is dropped in rebase 4.
Independent streaming queues can drift on underruns; joint lockstep decoding
needs a separate contract. The current pinned pack has no stems, so it uses
the same gain/presence lift as before. No asset admission checks are relaxed.

Host-only read-only integration probe (needs an existing v10 schema extract):
`nix develop . -c cargo run --example feel_probe -- /path/to/schema.json`.
It runs 400 actual collection steps and 400 Lagoon steps with effects on/off,
checks pickup/water signals, and compares literal snapshot bytes every step.

## Throwaway water feel pass

`water_fx_enabled` (default `true`) and `water_fx_strength` (0..3, default 2)
are local `feel.json` preferences. Missing keys retain defaults. The Feel page
places both rows after Muffle strength. Off or strength zero emits no water
quads, scene copies or water draws; the original world/lighting/HUD path remains.

`water_fx.rs` prepares disjoint rectangles from compiled `TileLayer.water`
contacts, not tilemap names. Empty/disabled contacts and decorative layer3 do not
participate. The existing table's rectangular water contacts include water3/5's
10-pixel dry cap and Tiled transforms. Non-rectangular custom water contacts are
an explicit preparation error rather than an inaccurate bounding-box effect.
Surface adjacency uses occupied water tiles across layers, so an inset contact
does not create a highlight on every submerged tile row. Overlapping layers do
not apply the effect twice. Geometry never feeds back into core contact rules.

The public `tests/fixtures/lagoon.level.json` exercises water3 at world
x=1024..1792, top y=330. Its repeated inset cells produce four clipped water
strips; only the first has a surface highlight. The CPU tests compile this real
level with minimal collision facts matching its two tile families.

The order is world, water refraction/caustics, surface, darkness, tint, HUD.
Animation reads only saved `Presentation.tick` (360-tick cycle), so pausing
freezes it and drawing a replay tick repeats its phase. The surface uses existing
white art and whole-pixel steps. `water_gles.rs` owns separate shaders/resources
from lighting. The combined caustics/refraction shader visits only visible water
rectangles and samples a separate nearest-filtered RGB10_A2 snapshot, displaced
horizontally by at most two framebuffer pixels and clamped to each water region.

The snapshot is persistent (640x480: 1,228,800 bytes), allocated on the first wet
frame or resize. Each wet frame copies only the visible water bounding envelope.
There is one shader draw per visible disjoint rectangle and one batched surface
draw. No per-frame texture/shader allocations or asset reads occur in steady
state. A tile-based GPU can still resolve more than the copied area: Mali p99 and
pixel comparison with water disabled must be checked on hardware. Host tests and
GLSL validation do not establish that GPU cost or visual quality.

## Lighting spike (presentation only)

Object emitters come from `Presentation` (`d25`/`d26` `lit:*`, `fire_shot`,
non-cold/unfrozen `e16`, `o1`/`o2`) and compiled `TerrainHazard::Lava` cells.
At most 16 visible emitters nearest the camera survive. Total intensity is capped.
Saved ticks drive flicker. The map darkness overlay is **unchanged**. Dark maps
use tint-only lighting: RGB can only decrease, so no light can reveal more level.

Optional `foo.normal.png` beside `foo.png` supplies tangent normals (+X right,
+Y up, +Z outward). It must have the same dimensions. Sidecars are unpinned local
spike art; all original image hash checks remain in force. Missing sidecars retain
the original shader. The auto-normal option derives an alpha-edge bevel with four
extra texture taps, with no generated textures. Both paths use one nearby light
per quad and at most 128 replacement draws per frame, preserving painter order,
palette swaps and alpha. With lights off, the exact original renderer is used.

Glow defaults to four hard brightness bands on the level-pixel grid, with a
4x4 Bayer dither only at band boundaries and 85% of the old radius. Warm
lights use the same bands, including normal-bearing draws. `glow_style` is
`"pixel"` by default; Feel → Glow style selects the old `"smooth"` kernel.
Both styles keep glow at 45% light radius for fire,
coins, goals and lit lamps. The light and glow sprites share one additive batch;
there is no full-screen bright-pass, blur target, readback or extra texture.
Dark-map glow follows the same tint-only fairness rule. Each frame caps total
light and glow energy separately, so a dense coin row cannot wash out the screen.

Feel adds Lights (on), Light strength (2), Glow (on), Glow strength (1), and
Auto normals (off), after Muffle strength. Strengths are 0..3. Old `feel.json`
files use these defaults. Turn both Lights and Glow off for the original pixels;
Auto normals has no effect while Lights is off.

Screenshot fixture: `tests/fixtures/lighting.level.json` (use the existing
`--benchmark-unverified-level` path, **not** strict gameplay admission). Map1 has
lit/unlit fire lamps at x184/232, a lit ice lamp at x280, coins at x144..208,
cold/burning bubbles at x352/384, four lava cells at x384..512, and a goal at
x576. The fire melon at x112 supplies breath after swallowing. Capture near tick
30 for bubbles. Enable Auto normals to see sprite-edge shading without sidecars;
compare with it off at the same saved tick. Map2 has identical objects with 80%
darkness; change `startpoint.map` to 2 in a temporary copy for the fairness image.
The original core `elements_target.level.json` also has lamps, bubbles and fire
melons; `collections.level.json` has coins. The new fixture's compiled terrain
and object bindings are covered by a unit test; GPU screenshots remain device
validation, not a host-test claim.

Cost limits: 16 emitters, at most 32 radial quads in one batch, no FBOs or new
full-screen passes, zero fallback-normal texture memory. Normal maps add their
own RGBA textures. Auto normals adds four alpha taps and up to 128 replacement
draws (not extra geometry passes). This cap trades coverage in dense scenes for
bounded work. Mali timings must be measured; no sustained-60 claim is made.

### Fractional zoom playtest

Feel → Zoom steps (`zoom_steps`) defaults to `"whole"`, preserving the old
1x/2x controls and limits. `"quarter"` makes each R2/L2, right-stick or +/- edge
move 0.25x: 1, 1.25, 1.5, 1.75, 2 at 640x480. Larger containers retain their
existing maximum. Reset (0/right-stick click) selects the default scale.
Changing back to whole snaps to the nearest whole offset. `RUST_ZOOM scale=...`
reports each drawn scale change. World textures remain nearest-sampled; unequal
pixel widths are intentional. HUD scale still uses the integer base scale.

### Death animation playtest (presentation deviation)

Verified with `cargo run --example death_probe -- SCHEMA.json PACK_MANIFEST.json`
on the public lighting fixture, starting at x400 above its lava. At call 7 the
core reports `Dying`, phase 2, visible, alpha 1, selected `Fall0` tick 7; at call
247 it reports phase 3 and still `Fall0` tick 247. The same frame resolves without
fallback. The body and camera remain in view. The pinned pack contains `Defeat0`
and `Defeat1`: five frames, 24 fps, non-looping. Thus the missing animation is
pose selection, not missing art or a hidden player.

Fidelity finding: core `src/presentation.rs:475-581` and root
`src/view/player_pose.gd:7-82` never select death art. Root `src/sim/life.gd:318-336`
only changes lifetime/timers and stops hazard motion; `src/view/level_view.gd:471-479`
uses the normal pose selector. Core `src/presentation.rs:612-625` does expose
`Dying` for phases 2/3 and keeps the player visible after death clears capture and
immunity. The existing Rust `sample_required` refuses unknown poses; it does not
silently replace death with idle.

The player now overrides Dying with the pack's Defeat animation, then holds its
last frame. **This is a spike presentation deviation, not reference parity.**
The invented clock starts at the saved tick of the first observed Dying step.
Every successful step observes it, including skipped draws. Pausing does not
advance it; leaving Dying resets it; a backward tick starts a new local episode.
Restoring mid-death restarts the local animation at the restored tick (the DTO
has no death-start timestamp). The clock retains one finished span for the
pipelined draw that can still be in flight. No core or snapshot bytes change.
Full-mouth dry poses select Defeat1; ambiguous wet-action suffixes select
Defeat0 because the DTO has no separate full-mouth flag. If the chosen Defeat
entry is absent, the original selected pose remains in use. This describes the
second pass; the third pass below replaces lava deaths with Spin.

### Prior water-surface jump investigation (superseded by round three below)

This prior synthetic-pool result did not explain the actual showcase. The third
pass below finds submerged dry bands in that map and an input-delivery bug.

The intended rule **does allow a surface jump**, but it needs a **fresh Jump
press**, not a button held while rising from deep water. Release Jump, let
buoyancy bring the player to the surface, then press again. Holding it for the
initial ascent gives full height; release cuts upward speed to one quarter.
No Up input is required. Down changes swimming posture; it is not the surface
jump trigger. The ordinary six-step ground jump buffer does not trigger while
swimming.

| Rule | Rust core | Root GDScript reference |
| --- | --- | --- |
| Fresh edge, downward speed below `96*60`, point 50 px above feet outside water | `src/water.rs:95-99` | `src/sim/water.gd:90-98` |
| Delayed automatic rise in deep water, surface bob | `src/water.rs:59-77,92-94` | `src/sim/water.gd:63-89` |
| Start full jump at `-776*60` (776 px/s upward) | `src/player.rs:226-235,381-386` | `src/sim/moves.gd:213-221,393-404` |
| Release cuts rising speed after water rules | `src/player.rs:381-386` | `src/sim/moves.gd:218-221` |
| Ground jump buffer requires not swimming | `src/player.rs:416-425,621-629` | `src/sim/moves.gd:231-242,353-364` |
| Clear swimming only after the body leaves water | `src/water.rs:104-108` | `src/sim/water.gd:114-135` |

Rust paths in the table are relative to `spikes/rust-stack/core`. Rust computes
press edges from current versus previous input (`src/state.rs:773-775`). The
surface-jump conditions and execution match the reference. No water-rule porting
bug was found, and no core file was changed.

Verified with `cargo run --example water_probe -- SCHEMA.json`: a synthetic pool
12 tiles wide, 3 tiles deep, flat ground, no walls, using the shipped collision
table. This is not a recording of the user's exact showcase level.

| Input sequence | Full water cells | Water3 cap + full lower cells |
| --- | --- | --- |
| Hold Jump for 180 steps from deep water | Still floating, feet y317.914 | Still floating, feet y328.474 |
| Release one step, fresh press and hold | Leaves water after 3 jump steps, feet y279.964 | Leaves after 3 steps, feet y290.524 |
| Idle 180 steps, fresh one-step tap | Leaves after 7 jump steps | Leaves after 8 steps |

The root GDScript `tests/moves.gd:638-660` also explicitly tests a fresh surface
jump, persistence on the next held step, release damping, and no retrigger on a
held button. Host Godot 4.7.2 ran that file: **965 checks, zero failures**.
Holding the button too early is consistent with the reported symptom, but cannot
be established without the actual input trace. Pool layout/contact geometry or
input delivery on the handheld remain untested causes; this investigation does
not change them.

## Third playtest rebase

Rebased with merges onto `1cbbc49b379fade1bdf3b0dd6dba6b2078e2bfaf`
(`rust/conversion`). Conflicts and resolutions:

- `e1e0263`, scene: retained upstream speed-scaled RunClock and spike Shake.
- `92fd255`, game: retained upstream `--view-at` capture handling plus Feel demo.
- `b3ee56a`, lib: retained upstream dressing and spike dust modules.
- `c1ad7d7` water merge, README/feel/feel_menu: restored the original merge's
  combined water, pickup, splash and goal-music controls and tests; kept both docs.
- `0ada977` lighting merge, README/feel/feel_menu/game/gles/scene: retained both
  water and lighting resources, settings, geometry and draw counts. Lit world,
  water and surface, additive lights, darkness, tint, HUD remain in that order.
- `dfba51a`, scene: defeat selection wraps the upstream run-clock frame override;
  normal running still uses the upstream speed-scaled animation.

Post-rebase compile integration: removed a stale placeholder-sidecar filter
(upstream removed placeholder assets); allowed fractional zoom in upstream goal
menu; passed the upstream run-clock override through DeathPose and its probe.
Host checks: 139 library tests passed, one ignored; all-target clippy passed.
No core edits, device builds, deployment, pushes or other branch updates.

### Lava death spin (spike deviation)

The first observed Dying step compares player world body bounds with occupied
compiled `TerrainHazard::Lava` cells. Contact (including the boundary) locks Spin
for that dying episode, even after moving away; other deaths retain Defeat0/1.
The verified private manifest has six Spin frames at 24 fps, looping, versus five
Defeat frames at 24 fps, non-looping. The every-step observer retains the episode
for the pipelined previous frame. No simulation state or visibility changes.
Host death_probe advanced 310 real Session steps and sampled all six Spin frames
through death phases 2 and 3. Visual/device acceptance remains untested.

### Stronger default pixel glow

Default `glow_strength` increases from 1 to 2 on the existing 0..3 scale.
Pixel bands, level-grid alignment and light-energy budgets are unchanged.
An existing explicit `glow_strength` in feel.json remains the user's choice;
Reset to defaults adopts 2. Smooth mode also uses the stronger default.

### Zoom steps

`zoom_steps` now cycles `whole` → `half` → `quarter` on the existing Feel row.
Half advances by 0.5 (1, 1.5, 2, 2.5…). Whole remains the default. Changing mode
snaps to its nearest step; nearest texture sampling is unchanged.

### Controller layouts

Feel → Buttons selects `button_layout: "snes"` (default) or `"xbox"`.
SNES maps by physical position on a modern pad, not its printed letters.

| Action | SNES (position / SNES label) | Xbox (modern label, unchanged) |
| --- | --- | --- |
| Jump / flutter | Bottom / B | A or B |
| Tongue | Left / Y | X or Y |
| Aim, then throw on the next press | Right / A or top / X | L1 |
| Aim lock | L1 or R1 | R1 |
| Menu confirm | Bottom / B | B |
| Menu back | Right / A | A |

Both throw faces feed the existing THROW action; this changes no aim/throw
rules. Back + shoulders still save/restore instead of throwing or locking.
Keyboard controls stay unchanged. Menus, Feel and the level list use separate
confirm/back masks, so a throw face cannot confirm a menu accidentally.
The Feel row prints the gameplay labels; the existing menu wraps long rows and
keeps the focused row visible. Changing layout waits for face release before
another face-button menu action and discards jump edges from the old layout.

Launcher integration: invoke list mode with `--levels ... --feel "$SAVE_ROOT/feel.json"`.
`--feel PATH` reads that exact file (not the level save directory); omitted,
missing or invalid files use defaults. Gameplay still reads save-dir/feel.json.

### Elastic tongue (spike deviation)

`elastic_tongue` defaults on; Feel adds Elastic tongue: on/off. It bends only
while airborne (user playtest request): grounded tongues go straight out and back,
and swimming tongues stay rigid. The observer reads only per-step tongue/velocity data. A quadratic control point trails three steps
of motion, eases 1/4 toward its target each step, and returns by 3/4 when stopped.
Lag caps at 24 level pixels per axis and 35% of tongue length. Vertical motion
drives the bend (3 steps of lag); horizontal motion adds only 0.75 steps of sway.

The original L/R/U nine-patch art is split into <=8-level-pixel segments, with
continuous source UVs and unchanged palette/layer/alpha. Mouth and tip centerlines
stay at the presented simulation coordinates. Short tongues compress the minimum
art margins rather than extending beyond the simulation endpoint. Off retains
the prior straight drawing path. Observation never changes collision or snapshots.
Repeated draws/pauses do not advance lag; restore/map changes reset history. Only
the latest and previous observed bends are retained for pipelined pictures.

Host tongue_probe: 240 actual Session steps, 84 tongue/bent steps, exact endpoints
and identical snapshots before/after observation. Pixel seams and Mali cost still
need device review; the mesh adds tongue-only quads, no textures or shader passes.

### Water exit: real controller path and actual showcase

**Correction to the prior investigation:** the actual showcase does not have
full-contact lower water cells like the prior synthetic test. Releasing and
pressing again is insufficient there. There are also lost jump edges in the old
player input path. Both were reproduced on the host; no core change was made.

Input bug: SDL button events were counted but gameplay sampled only final held
A/B once per event batch, then reused that mask for every owed step. A complete
short tap vanished. Release/repress within one batch (or between two render
batches with no simulation step) stayed held, so the core never saw a fresh edge.
The virtual SDL controller probe failed with `release lost ... left: 4 right: 0`
before the fix. The same real SDL event path now delivers `[4,0,4,4,0]` correctly.

Controls now retain aggregate JUMP transitions from keyboard and all mapped pad
handles. They consume one transition per simulation call in both sequential and
pipeline loops. Final SDL held snapshots reconcile dropped events; sampling with
no step owed does not drain transitions. A/B and duplicate interfaces remain OR
aliases: pressing B while A is still held deliberately does not make a new edge.
Pause, menu release gates, restores and replay discard pending live transitions.
Keyboard Space/Z releases also preserve the other held jump key. Other gameplay
bits retain their previous held-sampling semantics. Replay masks are unchanged.

The tested actual showcase is the local `rg353m-spike-shake/showcase.level.json`,
SHA256 `d0b7d5aeeba9ac85fd6b05ff33a08fee9ad36f63e6a26c16df87166ce99bd2d0`.
Only its startpoint was moved to x800/y384 for the probe. Terrain/objects stayed
unchanged. The pool occupies columns 22..30, rows 9..11; all 27 water3 cells are
cell 0. The shipped collision table gives **each** a ten-pixel dry cap. Thus at
x800 the wet vertical bands are y298..320, y330..352, y362..384. These are actual
compiled contact gaps, not a renderer or input approximation.

| Real SDL input through Controls into Session | Actual showcase | In-memory comparison, full-contact lower water3 cells (cell 1) |
| --- | --- | --- |
| Hold JUMP from pool floor, 180 steps | Feet y358.981, swimming | Feet y328.474, swimming |
| Release/repress in one event batch, deliver 0 then 4 | No Jump0 pose or dry step for next 120 steps | Exits after 3 jump steps |
| At rest after test, 50px-above-feet probe | y309.198: still in top wet band | y278.474: above pool |

The player's upward buoyancy stops at an **internal** dry cap near feet y359,
not the visible top at y298. The 50px probe therefore stays inside the top water
band; a correctly delivered fresh edge cannot satisfy the core jump condition.
The reference water rule still matches (`prepare_water` in core water.rs). The
remaining showcase failure is contact geometry/level authoring, not corrected by
changing input. A parent-side showcase edit can keep surface cell 0 and use full
cell 1 in lower rows. The probe makes that comparison only in memory; no external
map or core file is changed. Cost: it changes the authored lower-row art/contact
choice and needs picture review. Do not weaken the core surface-jump rule for it.

Reproduce on a host (no game window or device build needed):
`nix develop . -c cargo run --example input_probe -- SCHEMA.json SHOWCASE.level.json`.
Without arguments it runs just the real SDL input-edge regression. With arguments
it expects this known 50x14 showcase layout, and tests its exact pool plus the
in-memory full-interior comparison. It enumerates host pads but writes only its
own SDL virtual controller. Device event timing and GPU pictures are not proven.

Third-pass host checks: `nix develop . -c cargo test --lib` passes 145 tests,
one ignored; `nix develop . -c cargo clippy --lib --all-targets -- -D warnings`
passes; `nix develop . -c cargo fmt -- --check` passes. Focused death_pose, feel,
lighting, input and elastic_tongue tests passed during each change. The list CLI
accepted `--feel /tmp/play3-feel.json`, logged `source=file`, then correctly
rejected the intentionally incomplete invocation with `--index required`.
That CLI parse check is not a rendered-list acceptance claim. No device/aka build,
deploy, push, core change, main update or rust/conversion update was performed.

### Air tongue mesh repair

The mesh and observer now share the same airborne/non-swimming gate. The old
mesh gate still required grounded motion, so it suppressed the airborne bend
regardless of the observer. Velocity is already level pixels per simulation
step after division by `SCALE`; no seconds conversion is needed. The 24-pixel
control-point cap gives a maximum 12-pixel midpoint bow (quadratic factor 1/2).
The 35%-of-length control-point cap gives at most 17.5% of length as a bow.
The existing easing reaches a visible 8–12-pixel bow during normal fast ascent
and descent; the apex eases toward straight. Ground contact resets to straight.
This remains an optional spike deviation from the straight reference tongue.

Headless pack-backed regression `airborne_tongue_picture_uses_curve_and_ground_is_rigid`
checks real Session → observer → Scene meshes while rising, near the apex,
falling and grounded, comparing elastic on/off and checking snapshot identity.
Set `PLAYER_PICTURE_OUT` to a private directory to export the real mesh and art
paths for a host picture probe; this does not establish GPU pixel parity.

### Death presentation (current; replaces the historical death passes above)

| Route | Picture sequence, age in saved steps |
| --- | --- |
| Lava | Hurt0/1 frame 0 at ages 0–14, frame 1 at 15–47, frame 0 thereafter |
| Non-lava instant defeat | Spin frame 0 at ages 0–23; slowing Spin at 24–155; Defeat0/1 starts at 156 and holds frame 4 from 166 |

The spin slows from 24 fps to zero over 132 steps. Each frame's duration uses
its current speed, not the integral of speed. The last Spin frame therefore
holds for 36 steps. Pack frames keep their original origins and sizes; the flat
final picture is Defeat frame 4. The non-lava route now uses this sequence
instead of starting Defeat immediately. Generic defeat covers spike contacts
and a core-reported non-lava crushing death, if one is produced.

Cause classification is presentation-only: on the first Dying step, body bounds
intersecting an occupied compiled lava cell lock the lava route. All other
Dying episodes take the generic route, including thorn/spike entities and any
crushing solid. There is no distinct crush signal or death cause in the public
presentation packet. The observer does not invent collisions or a crushing death.

The checked spike route holds its world body position through Spin and Defeat.
Lava instead holds briefly, launches and falls, using Hurt throughout: **no Spin
or final flat pose was observed on that route**. The core freezes its dying body,
so the lava launch/fall remains a simulation gap, not a drawing-only trajectory.
A physical crush route has not been established by the host probe. The generic
sequence must not be treated as proof that crushing is implemented in the core.

Keep the full-screen black fade: it starts at age 240 and reaches black at 300.
This is retained spike presentation policy (also observed on normal reference
deaths), not a sprite-alpha fade or a change to respawn timing. No core changes.

### Capture actor art

The four rescue-timeout captors are `Presentation.companions.rescuers`, not
runtime entity codes. The old renderer looked only for `hud.captor`; the pinned
pack instead stores their art under numeric visual entry `486`. Bind that entry
when the semantic HUD alias is absent. Its four-frame Fly animation loops at
36 fps with a 16×24-pixel origin and 32×48-pixel art. No new art is generated.

A per-step spawn clock starts all four at frame 0, instead of using the global
level tick. It survives skipped draws and the pipeline's previous episode;
rewind/map changes reset it. Core positions and capture timing remain untouched.
The headless `capture_episode_draws_four_pack_animated_captors` regression runs
a real contact/countdown/capture episode and checks four pack sprites per step,
all four flight frames, and byte-identical snapshots before/after drawing.

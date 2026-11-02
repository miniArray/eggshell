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

Glow uses the same soft radial sprite kernel at 45% light radius for fire,
coins, goals and lit lamps. The light and glow sprites share one additive batch;
there is no full-screen bright-pass, blur target, readback or extra texture.
Dark-map glow follows the same tint-only fairness rule. Each frame caps total
light and glow energy separately, so a dense coin row cannot wash out the screen.

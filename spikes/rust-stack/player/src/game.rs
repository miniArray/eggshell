//! Runnable core-connected verification player. Target remains refused by core admission.
use crate::{
    clock::FrameClock,
    gles::Gles,
    input::Controls,
    pack::{Pack, hash},
    scene::Scene,
    timing::{Samples, Timer, memory_kib},
};
use eggshell_spike_core::{Lifetime, Session};
use std::{
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};

enum SaveTask {
    Snapshot(PathBuf, Vec<u8>),
    ClearAutosave(PathBuf),
    Finish,
}
struct Writer {
    send: mpsc::SyncSender<SaveTask>,
    join: Option<thread::JoinHandle<Result<u64, String>>>,
}
impl Writer {
    fn start() -> Self {
        let (send, receive) = mpsc::sync_channel::<SaveTask>(1);
        let join = thread::spawn(move || {
            let mut writes = 0;
            loop {
                match receive.recv().map_err(|e| e.to_string())? {
                    SaveTask::Snapshot(path, bytes) => {
                        let temporary = path.with_extension("tmp");
                        let mut f = std::fs::File::create(&temporary).map_err(|e| e.to_string())?;
                        f.write_all(&bytes).map_err(|e| e.to_string())?;
                        f.flush().map_err(|e| e.to_string())?;
                        drop(f);
                        std::fs::rename(temporary, path).map_err(|e| e.to_string())?;
                        writes += 1;
                    }
                    SaveTask::ClearAutosave(path) => {
                        // FIFO: no previously queued snapshot can recreate this save.
                        match std::fs::remove_file(&path) {
                            Ok(()) => println!("RUST_AUTOSAVE_CLEARED reason=goal"),
                            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                                println!("RUST_AUTOSAVE_CLEARED reason=goal already_absent=true");
                            }
                            Err(e) => eprintln!(
                                "RUST_AUTOSAVE_CLEAR_FAILED reason=goal path={path:?} error={e}"
                            ),
                        }
                    }
                    SaveTask::Finish => break,
                }
            }
            Ok(writes)
        });
        Self {
            send,
            join: Some(join),
        }
    }
    fn enqueue(&self, path: PathBuf, bytes: Vec<u8>) -> Result<(), String> {
        self.send
            .send(SaveTask::Snapshot(path, bytes))
            .map_err(|e| e.to_string())
    }
    fn clear_autosave(&self, path: PathBuf) -> Result<(), String> {
        self.send
            .send(SaveTask::ClearAutosave(path))
            .map_err(|e| e.to_string())
    }
    fn finish(mut self) -> Result<u64, String> {
        // Join even if the worker has failed, so all save I/O has stopped on return.
        let _ = self.send.send(SaveTask::Finish);
        self.join
            .take()
            .unwrap()
            .join()
            .map_err(|_| "save worker panicked")?
    }
}
#[derive(Debug, PartialEq, Eq)]
enum AutosaveAction {
    Skip,
    Write,
    Clear,
}
#[derive(Default)]
struct AutosavePolicy {
    // Shared with the scoped simulation worker; completion is sticky across restores.
    goal_seen: AtomicBool,
}
impl AutosavePolicy {
    fn action(&self, lifetime: Lifetime, life_phase: i64, due: bool) -> AutosaveAction {
        if lifetime == Lifetime::Goal || matches!(life_phase, 7 | 8) {
            if self.goal_seen.swap(true, Ordering::Relaxed) {
                AutosaveAction::Skip
            } else {
                AutosaveAction::Clear
            }
        } else if due && !self.goal_seen.load(Ordering::Relaxed) {
            AutosaveAction::Write
        } else {
            AutosaveAction::Skip
        }
    }
}
/// Shared by the real player and AKA host smoke. Disabled mode never constructs
/// the writer, calls the snapshot codec, or writes a save at any lifecycle hook.
pub(crate) struct SavePipeline {
    writer: Option<Writer>,
    directory: PathBuf,
    autosave: AutosavePolicy,
}
impl SavePipeline {
    pub(crate) fn start(directory: PathBuf, disabled: bool) -> Self {
        Self {
            writer: if disabled {
                None
            } else {
                Some(Writer::start())
            },
            directory,
            autosave: AutosavePolicy::default(),
        }
    }
    fn disabled(&self) -> bool {
        self.writer.is_none()
    }
    pub(crate) fn manual(&self, session: &Session, samples: &mut Samples) -> Result<(), String> {
        self.write_snapshot(session, "manual.v10", samples)
    }
    fn write_snapshot(
        &self,
        session: &Session,
        name: &str,
        samples: &mut Samples,
    ) -> Result<(), String> {
        if let Some(writer) = &self.writer {
            let timer = Timer::new();
            writer.enqueue(
                self.directory.join(name),
                session.snapshot().map_err(|e| e.to_string())?,
            )?;
            samples.add(timer.finish());
        }
        Ok(())
    }
    pub(crate) fn cadence(
        &self,
        session: &Session,
        cursor: u64,
        samples: &mut Samples,
    ) -> Result<(), String> {
        self.autosave(
            session,
            crate::call_cursor::autosave_due(cursor, 60),
            samples,
        )
    }
    fn autosave(&self, session: &Session, due: bool, samples: &mut Samples) -> Result<(), String> {
        let Some(writer) = &self.writer else {
            return Ok(());
        };
        let p = session.presentation_region([0; 4]);
        match self
            .autosave
            .action(p.player.lifetime, p.player.life_phase, due)
        {
            AutosaveAction::Write => self.write_snapshot(session, "autosave.v10", samples),
            AutosaveAction::Clear => writer.clear_autosave(self.directory.join("autosave.v10")),
            AutosaveAction::Skip => Ok(()),
        }
    }
    fn restart(self) -> Result<(), String> {
        // Drain all queued manual/autosave writes before deletion. Never enqueue a
        // final autosave. Even a failed worker must be joined before clearing.
        if let Some(writer) = self.writer
            && let Err(error) = writer.finish()
        {
            eprintln!("RUST_SAVE_DRAIN_FAILED reason=restart error={error}");
        }
        let path = self.directory.join("autosave.v10");
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(format!("restart autosave removal {path:?}: {e}")),
        }
    }
    pub(crate) fn finish(self, session: &Session, samples: &mut Samples) -> Result<u64, String> {
        self.autosave(session, true, samples)?;
        match self.writer {
            Some(writer) => writer.finish(),
            None => Ok(0),
        }
    }
}
fn read(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))
}
fn flush() -> Result<(), String> {
    std::io::stdout().flush().map_err(|e| e.to_string())
}

/// Read once after platform initialization, before the ready/measurement clock.
/// Native Rust I/O avoids a shell observer running under candidate library paths.
fn startup_maps(directory: &Path) -> Result<PathBuf, String> {
    use std::os::unix::fs::OpenOptionsExt;
    let bytes =
        std::fs::read("/proc/self/maps").map_err(|e| format!("startup maps read failed: {e}"))?;
    if bytes.is_empty() {
        return Err("startup maps evidence is empty".into());
    }
    // Evidence is never overwritten: each start of the same level (the level list
    // reopens levels) writes the next free name, startup-process.maps, then -2, -3, ...
    let mut attempt = 1;
    let (path, mut file) = loop {
        let name = if attempt == 1 {
            "startup-process.maps".to_owned()
        } else {
            format!("startup-process-{attempt}.maps")
        };
        let path = directory.join(name);
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(file) => break (path, file),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt < 10_000 => {
                attempt += 1;
            }
            Err(e) => return Err(format!("startup maps evidence {}: {e}", path.display())),
        }
    };
    file.write_all(&bytes).map_err(|e| e.to_string())?;
    file.flush().map_err(|e| e.to_string())?;
    println!(
        "RUST_STARTUP_MAPS path={path:?} bytes={} sha256={} timing=before-ready read_only_source=/proc/self/maps",
        bytes.len(),
        hash(&bytes)
    );
    Ok(path)
}

/// A sampled frame for the pipelined loop: the presentation of one state,
/// cut to the view region the scene asks for, with what drawing needs.
struct Prepared {
    p: eggshell_spike_core::Presentation,
    background: [u8; 3],
    container: [f64; 2],
    zoom: f64,
    completed: u64,
}
fn prepare_frame(
    session: &Session,
    scene: &crate::scene::Scene,
    container: [f64; 2],
    zoom: f64,
    completed: u64,
) -> Result<Prepared, String> {
    let (map_index, focus) = session.presentation_view();
    let region = scene.presentation_region(map_index, focus, container, zoom)?;
    Ok(Prepared {
        p: session.presentation_region(region),
        background: scene.clear_color(map_index)?,
        container,
        zoom,
        completed,
    })
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunExit {
    Success,
    Restart,
}
impl RunExit {
    pub fn code(self) -> u8 {
        match self {
            Self::Success => 0,
            Self::Restart => 75,
        }
    }
}
fn restart(saves: SavePipeline) -> Result<RunExit, String> {
    saves.restart()?;
    println!("RUST_GAME_RESTART");
    flush()?;
    Ok(RunExit::Restart)
}
pub fn run(arguments: impl Iterator<Item = String>) -> Result<RunExit, String> {
    let startup = Instant::now();
    let mut args = arguments;
    let mut files = std::collections::HashMap::new();
    let mut uncapped = false;
    let mut benchmark_unverified_level = false;
    let mut benchmark_single_texture = false;
    let mut benchmark_real_screen = false;
    // Defaults since phase 0 of the conversion: atlas and two-core loop on.
    // `--no-atlas` / `--no-pipeline` give the plain loop for comparisons;
    // GPU captures and the single-texture floor test switch them off by themselves.
    let mut atlas = true;
    let mut pipeline = true;
    let mut digest_every: Option<u64> = None;
    let mut digest_dump: Option<PathBuf> = None;
    let mut want_feedback = false;
    let mut fullscreen = true;
    let mut ticks = None;
    let mut seconds = 180u64;
    let mut capture_tick = None;
    let mut input_offset = None;
    let mut require_active_window = false;
    let mut initial_zoom = 0_i32;
    // Level list runs: the goal menu (game.gd) offers "Next level" when this is set.
    let mut has_next = false;
    // Shots only: centre the view on this level pixel instead of the game camera.
    let mut view_at: Option<eggshell_spike_core::Position> = None;
    let mut mute = false;
    let mut feel_demo_after = None;
    while let Some(key) = args.next() {
        match key.as_str() {
            "--level" | "--collision" | "--schema" | "--pack-root" | "--pack-inventory"
            | "--view-metrics" | "--replay" | "--restore" | "--save-dir" | "--capture"
            | "--result" | "--animated-tiles" | "--custom-music" => {
                files.insert(key, args.next().ok_or("missing argument value")?);
            }
            "--input-offset" => {
                input_offset = Some(
                    args.next()
                        .ok_or("input offset missing")?
                        .parse::<u64>()
                        .map_err(|_| "invalid input offset")?,
                )
            }
            // Hidden view-only automation; use sequential drawing for paused frame dumps.
            "--feel-demo" => {
                feel_demo_after = Some(
                    args.next()
                        .ok_or("--feel-demo needs integer")?
                        .parse::<u64>()
                        .map_err(|_| "invalid feel demo step")?,
                );
            }
            "--zoom" => {
                initial_zoom = args
                    .next()
                    .ok_or("--zoom needs integer")?
                    .parse()
                    .map_err(|_| "invalid zoom")?;
            }
            "--view-at" => {
                let text = args.next().ok_or("--view-at needs X,Y")?;
                let (x, y) = text.split_once(',').ok_or("--view-at needs X,Y")?;
                let pixel = |v: &str| -> Result<i64, String> {
                    let v: f64 = v.parse().map_err(|_| "invalid --view-at")?;
                    if !v.is_finite() || v.abs() > 1e9 {
                        return Err("invalid --view-at".into());
                    }
                    Ok((v * eggshell_spike_core::SCALE as f64) as i64)
                };
                view_at = Some(eggshell_spike_core::Position {
                    x: pixel(x)?,
                    y: pixel(y)?,
                });
            }
            "--has-next" => has_next = true,
            "--require-active-window" => require_active_window = true,
            "--ticks" => {
                ticks = Some(
                    args.next()
                        .ok_or("--ticks needs integer")?
                        .parse::<u64>()
                        .map_err(|_| "invalid ticks")?,
                )
            }
            "--seconds" => {
                seconds = args
                    .next()
                    .ok_or("--seconds needs integer")?
                    .parse()
                    .map_err(|_| "invalid seconds")?
            }
            "--capture-tick" => {
                capture_tick = Some(
                    args.next()
                        .ok_or("capture tick missing")?
                        .parse::<u64>()
                        .map_err(|_| "invalid capture tick")?,
                )
            }
            "--benchmark-unverified-level" => benchmark_unverified_level = true,
            "--benchmark-single-texture" => benchmark_single_texture = true,
            "--benchmark-real-screen" => benchmark_real_screen = true,
            "--atlas" => atlas = true,
            "--pipeline" => pipeline = true,
            "--no-atlas" => atlas = false,
            "--no-pipeline" => pipeline = false,
            "--frame-digest-every" => {
                digest_every = Some(
                    args.next()
                        .ok_or("--frame-digest-every needs integer")?
                        .parse::<u64>()
                        .ok()
                        .filter(|n| *n > 0)
                        .ok_or("invalid frame digest interval")?,
                )
            }
            "--frame-dump-dir" => {
                digest_dump = Some(PathBuf::from(
                    args.next().ok_or("--frame-dump-dir needs a path")?,
                ))
            }
            "--uncapped" => uncapped = true,
            "--presentation-feedback" => want_feedback = true,
            "--windowed" => fullscreen = false,
            "--mute" => mute = true,
            _ => return Err(format!("unrecognized game argument: {key}")),
        }
    }
    if benchmark_real_screen && !benchmark_unverified_level {
        return Err("--benchmark-real-screen requires --benchmark-unverified-level; faithful_real_level=false".into());
    }
    if benchmark_single_texture && !benchmark_unverified_level {
        return Err("--benchmark-single-texture requires --benchmark-unverified-level; picture_invalid=true".into());
    }
    if feel_demo_after.is_some() {
        pipeline = false;
    }
    if capture_tick.is_some() || files.contains_key("--capture") || view_at.is_some() {
        // The pipeline draws one frame behind; captures use the sequential loop.
        pipeline = false;
    }
    if benchmark_single_texture {
        atlas = false;
        pipeline = false;
    }
    if seconds == 0 || seconds > 900 {
        return Err("game safety bound must be1..900 seconds".into());
    }
    let required = |key: &str| {
        files
            .get(key)
            .map(PathBuf::from)
            .ok_or_else(|| format!("{key} required"))
    };
    let level = read(&required("--level")?)?;
    let collision = read(&required("--collision")?)?;
    let schema = read(&required("--schema")?)?;
    let raw_hash = hash(level.as_bytes());
    let is_target = raw_hash == "bbe93d1592bcb6b9576c908ceae50518d42b031cf3f1997486a37daf4a062a17";
    let mut session = if benchmark_real_screen {
        Session::load_benchmark_real_screen(&level, &collision, &schema)
    } else if benchmark_unverified_level {
        Session::load_benchmark_unverified(&level, &collision, &schema)
    } else {
        Session::load(&level, &collision, &schema)
    }
    .map_err(|e| format!("authoritative gameplay admission refused before graphics: {e}"))?;
    let startup_entity_steps = session.stats().entity_steps;
    if !session
        .admission_report()
        .unsupported_requirements
        .is_empty()
    {
        return Err("core returned an unsupported successful session".into());
    }
    // Current imported core proves only the public Stride vertical slice. No
    // throughput mode on that incomplete application can answer the target A/B.
    println!(
        "RUST_GAME_ADMISSION raw_level_sha256={raw_hash} target={is_target} report={:?} mode=verification-or-benchmark-hint benchmark_unverified_level={benchmark_unverified_level} target_A_B_claim=false",
        session.admission_report()
    );
    let pack = Pack::open(&required("--pack-root")?, &required("--pack-inventory")?)?;
    let prepare = if benchmark_real_screen {
        Scene::prepare_benchmark_real_screen
    } else {
        Scene::prepare
    };
    let mut scene = prepare(
        session.world(),
        &session.admission_report().admitted_codes,
        &pack,
        &required("--view-metrics")?,
    )?;
    let fidelity = if benchmark_real_screen {
        "false"
    } else {
        "not_claimed"
    };
    let stand_in = if scene
        .visual_omissions
        .iter()
        .any(|v| v.contains("stand_in=gradient"))
    {
        "gradient"
    } else {
        "none"
    };
    let omission_label =
        serde_json::to_string(&scene.visual_omissions).map_err(|e| e.to_string())?;
    let replay = files
        .get("--replay")
        .map(|p| crate::input::replay(Path::new(p)))
        .transpose()?;
    if files.contains_key("--restore") && replay.is_some() && input_offset.is_none() {
        return Err("replay restore requires explicit --input-offset; saved frame is not an input-call cursor".into());
    }
    let cursor_start = input_offset.unwrap_or(0);
    let remaining = replay
        .as_ref()
        .map(|v| {
            (v.len() as u64)
                .checked_sub(cursor_start)
                .ok_or("input offset exceeds literal replay")
        })
        .transpose()?;
    let stop = ticks.unwrap_or(remaining.unwrap_or(3600));
    if feel_demo_after.is_some_and(|n| n >= stop) {
        return Err("--feel-demo must be before --ticks end".into());
    }
    if stop == 0 || remaining.is_some_and(|n| stop > n) {
        return Err("successful-call window exceeds literal replay or is empty".into());
    }
    if uncapped && replay.is_none() {
        return Err("uncapped fixed-work requires deterministic input replay".into());
    }
    if benchmark_unverified_level
        && (files.contains_key("--restore")
            || files.contains_key("--capture")
            || capture_tick.is_some())
    {
        return Err(
            "benchmark unverified mode disables saves, restore and snapshot captures".into(),
        );
    }
    if capture_tick.is_some() != files.contains_key("--capture") {
        return Err("capture requires both --capture and --capture-tick".into());
    }
    if capture_tick.is_some_and(|n| n > stop) {
        return Err("capture tick exceeds the fixed-work window".into());
    }
    if let Some(path) = files.get("--restore") {
        session
            .restore(&std::fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    }
    let save_dir = required("--save-dir")?;
    std::fs::create_dir_all(&save_dir).map_err(|e| e.to_string())?;
    // The original's animated tilesets, from frames shipped beside the pack (bundle
    // private-animated-tiles); without them the tiles stay still.
    if let Some(dir) = files
        .get("--animated-tiles")
        .map(PathBuf::from)
        .filter(|d| d.is_dir())
    {
        let layers = scene.add_animated_tiles(&dir, &pack)?;
        println!("RUST_ANIMATED_TILES dir={dir:?} layers={layers}");
    }
    *scene.feel.lock().map_err(|_| "feel lock poisoned")? =
        crate::feel::FeelSettings::load(&save_dir);
    let mut gpu = Gles::open_game(fullscreen, !uncapped)?;
    if atlas {
        gpu.begin_atlas()?;
    }
    scene.upload(&mut gpu, &pack)?;
    if atlas {
        gpu.finish_atlas()?;
    }
    session.configure_presentation_index(scene.absolute_origin_guard());
    if benchmark_single_texture {
        if benchmark_real_screen {
            gpu.enable_benchmark_single_texture_image(scene.solid)?;
        } else {
            gpu.enable_benchmark_single_texture()?;
        }
    }
    let mut controls = Controls::open(&gpu.sdl)?;
    // Sound derives cues from each saved step and never writes state (audio_player.gd).
    let mut audio_map = crate::audio::AudioMap::parse(&pack.manifest);
    // Private copies of maps' remote music links (bundle private-custom-music); without
    // them those maps stay silent, as Godot played them.
    if let Some(dir) = files
        .get("--custom-music")
        .map(PathBuf::from)
        .filter(|d| d.is_dir())
    {
        let tracks = audio_map.add_custom_music(&dir)?;
        println!("RUST_CUSTOM_MUSIC dir={dir:?} tracks={tracks}");
    }
    let (mut audio_device, audio_out) = if mute || audio_map.is_empty() {
        (None, None)
    } else {
        match crate::audio::Device::open(&gpu.sdl) {
            Ok((device, out)) => (Some(device), Some(out)),
            Err(reason) => {
                println!("RUST_AUDIO_UNAVAILABLE reason={reason:?}");
                (None, None)
            }
        }
    };
    let mut sound =
        crate::audio::Observer::new(audio_map, session.world(), Some(&pack), audio_out)?;
    let audio_label = match &audio_device {
        Some(device) => format!("sdl-{}", device.driver),
        None => "muted".to_owned(),
    };
    println!(
        "RUST_AUDIO playback={audio_label} device={}",
        audio_device
            .as_ref()
            .map_or(serde_json::Value::Null, |d| d.summary())
    );
    let mut audio_observe = Samples::default();
    let mut events = gpu.sdl.event_pump()?;
    // Declared after gpu: protocol callbacks/proxies drop before SDL_Window.
    // Optional for the first picture gate; mandatory before delivered-frame claims.
    let mut feedback = if want_feedback {
        Some(crate::presentation_feedback::Feedback::new(&gpu.window)?)
    } else {
        None
    };
    let saves = SavePipeline::start(save_dir.clone(), benchmark_unverified_level);
    let startup_maps_path = startup_maps(&save_dir)?;
    // Also clear a restored finished save before the first input call or pause.
    saves.autosave(&session, false, &mut Samples::default())?;
    let initial_picture = session.presentation();
    scene.observe_feel(&initial_picture, &session)?;
    sound.observe_feel(
        &initial_picture,
        *scene.feel.lock().map_err(|_| "feel lock poisoned")?,
    );
    let initial_map = session
        .world()
        .maps
        .get(
            initial_picture
                .map_index
                .checked_sub(1)
                .ok_or("zero initial map")?,
        )
        .ok_or("initial map absent")?;
    let (view_w, view_h) = gpu.window.drawable_size();
    let initial_plan = crate::screen::plan(
        [view_w as f64, view_h as f64],
        [
            initial_map.width_pixels as f64,
            initial_map.height_pixels as f64,
        ],
        [
            initial_picture.follow.current.x as f64 / eggshell_spike_core::SCALE as f64,
            initial_picture.follow.current.y as f64 / eggshell_spike_core::SCALE as f64,
        ],
        pack.density,
        initial_zoom,
    )?;
    let ready = Instant::now();
    let mut clock = FrameClock::new(ready);
    let mut completed = 0u64;
    let mut swap_calls = 0u64;
    let mut paused = false;
    let mut feel_model = crate::feel_menu::Model::default();
    let mut feel_view = scene.feel_view();
    let mut menu_previous = 0u8;
    let mut release_gate = crate::feel_menu::ReleaseGate::default();
    let mut preview: Option<(Instant, bool)> = None;
    let mut feel_demo = feel_demo_after.map(crate::feel_menu::Demo::new);
    let mut pause_frames = 0u64;
    let mut zoom = initial_plan.zoom;
    let mut zoom_min = initial_plan.zoom_min;
    let mut zoom_max = initial_plan.zoom_max;
    let mut captured = false;
    let mut held_saved_frame_calls = 0u64;
    let mut sim = Samples::default();
    let mut draw = Samples::default();
    let mut batch_counts = crate::timing::Histogram::default();
    let mut quad_counts = crate::timing::Histogram::default();
    let mut vertex_counts = crate::timing::Histogram::default();
    let mut entity_view_counts = crate::timing::Histogram::default();
    let mut batch_total = 0_u64;
    let mut quad_total = 0_u64;
    let mut resolved_scale = initial_plan.scale;
    let mut logged_scale = initial_plan.scale;
    let mut present = Samples::default();
    let mut save = Samples::default();
    let mut intervals = crate::timing::Histogram::default();
    let mut previous_present = None;
    let mut missed = 0u64;
    let mut last_report = Instant::now();
    println!(
        "RUST_GAME_READY startup_ms={:.3} audio={audio_label} save_cadence=60-successful-input-calls save_phase_offset={cursor_start} save_sync=false frame_mode={} interpolation=off capture={} benchmark_eligible=false benchmark_unverified_level={benchmark_unverified_level} picture_invalid={benchmark_single_texture} faithful_real_level={fidelity} stand_in={stand_in} visual_omissions={omission_label} saves_disabled={benchmark_unverified_level} zoom={zoom} zoom_min={zoom_min} zoom_max={zoom_max} scale={resolved_scale}",
        startup.elapsed().as_secs_f64() * 1000.0,
        if uncapped {
            "uncapped-fixed-work"
        } else {
            "real-time-fixed60"
        },
        capture_tick.is_some()
    );
    flush()?;
    let mut region_container_mismatch = 0u64;
    let mut pending = if pipeline {
        Some(prepare_frame(
            &session,
            &scene,
            [view_w as f64, view_h as f64],
            zoom,
            0,
        )?)
    } else {
        None
    };
    let mut goal_choice: Option<&str> = None;
    while completed < stop && ready.elapsed() < Duration::from_secs(seconds) {
        controls.set_throw_mode(
            scene
                .feel
                .lock()
                .map_err(|_| "feel lock poisoned")?
                .throw_mode,
        );
        controls.reset_actions();
        for event in events.poll_iter() {
            controls.event(event);
        }
        if let Some(f) = &mut feedback {
            f.collect()?;
        }
        let live = controls.mask(
            scene
                .feel
                .lock()
                .map_err(|_| "feel lock poisoned")?
                .button_layout,
        );
        if !uncapped {
            clock.observe(Instant::now(), paused || release_gate.is_waiting());
        }
        let was_paused = paused;
        let edges = controls.menu_mask & !menu_previous;
        menu_previous = controls.menu_mask;
        if controls.pause_toggle {
            paused = !paused;
        }
        let mut feel_action = crate::feel_menu::Action::None;
        {
            let mut settings = scene.feel.lock().map_err(|_| "feel lock poisoned")?;
            let old = *settings;
            if let Some(demo) = &mut feel_demo {
                if completed >= demo.after {
                    paused = true;
                    feel_action =
                        demo.update(Instant::now(), completed, &mut feel_model, &mut settings);
                }
            } else if was_paused && paused {
                feel_action = feel_model.input(edges, &mut settings);
            }
            if old != *settings {
                settings.save(&save_dir)?;
                sound.observe_feel(&session.presentation_region([0; 4]), *settings);
                let before = serde_json::to_value(old).map_err(|e| e.to_string())?;
                let after = serde_json::to_value(*settings).map_err(|e| e.to_string())?;
                for (key, value) in after.as_object().ok_or("feel settings not object")? {
                    if before.get(key) != Some(value) {
                        println!("RUST_FEEL_CHANGE {key}={value}");
                    }
                }
            }
            match feel_action {
                crate::feel_menu::Action::Preview { hit } => preview = Some((Instant::now(), hit)),
                crate::feel_menu::Action::Resume => paused = false,
                crate::feel_menu::Action::None | crate::feel_menu::Action::Restart => {}
            }
            scene.paused_offset = if paused {
                preview.map_or([0.0; 2], |(at, hit)| {
                    crate::shake::Shake::preview(
                        *settings,
                        hit,
                        (at.elapsed().as_secs_f64() * 60.0) as i64,
                    )
                })
            } else {
                [0.0; 2]
            };
        }
        if feel_action == crate::feel_menu::Action::Restart {
            // Consume the confirm press before returning to the launcher. No
            // simulation or new saves run here; a fast relaunch cannot inherit A.
            release_gate.wait();
            while !controls.exit
                && release_gate.blocked(
                    controls.mask(
                        scene
                            .feel
                            .lock()
                            .map_err(|_| "feel lock poisoned")?
                            .button_layout,
                    ) | controls.menu_mask,
                )
            {
                for event in events.poll_iter() {
                    controls.event(event);
                }
                thread::sleep(Duration::from_millis(1));
            }
            if !controls.exit {
                return restart(saves);
            }
        }
        if feel_action == crate::feel_menu::Action::Resume {
            feel_demo = None;
        }
        if paused != was_paused {
            println!("RUST_GAME_PAUSE paused={paused} completed={completed}");
            if !paused {
                release_gate.wait();
                preview = None;
            }
            if let Some(device) = &mut audio_device {
                device.set_paused(paused && !sound.goal_reached());
            }
        }
        // Do not step until the menu's confirm/back/directions are released.
        let waiting_release = release_gate.blocked(live | controls.menu_mask);
        if paused || waiting_release || replay.is_some() {
            controls.clear_steps();
        }
        if controls.exit {
            break;
        }
        if controls.zoom_reset {
            zoom = 0.0;
        }
        zoom = scene
            .feel
            .lock()
            .map_err(|_| "feel lock poisoned")?
            .zoom_steps
            .advance(zoom, controls.zoom_delta);
        if controls.restore && !saves.disabled() {
            controls.clear_steps();
            if replay.is_some() {
                return Err("interactive replay restore requires an explicit cursor: restart with --restore and --input-offset".into());
            }
            let data = std::fs::read(save_dir.join("manual.v10")).map_err(|e| e.to_string())?;
            session.restore(&data).map_err(|e| e.to_string())?;
            saves.autosave(&session, false, &mut save)?;
            sound.replaced();
            let p = session.presentation_region([0; 4]);
            sound.observe_feel(&p, *scene.feel.lock().map_err(|_| "feel lock poisoned")?);
            scene.observe_feel(&p, &session)?;
        }
        if controls.save {
            saves.manual(&session, &mut save)?;
        }
        if pipeline {
            let steps = if paused || waiting_release {
                0
            } else {
                let owed = if uncapped { 1 } else { clock.owed() };
                owed.min(stop - completed)
            };
            let masks = (0..steps)
                .map(|i| {
                    let cursor = crate::call_cursor::index(cursor_start, completed + i)?;
                    Ok(if let Some(v) = &replay {
                        v[cursor]
                    } else {
                        controls.step_mask(live)
                    })
                })
                .collect::<Result<Vec<u8>, String>>()?;
            let current = pending.take().ok_or("pipeline lost its prepared frame")?;
            let request = (current.container, zoom);
            let base = completed;
            let (worker_result, draw_result) = thread::scope(|s| {
                let session = &mut session;
                let scene_ref = &scene;
                let saves = &saves;
                let save = &mut save;
                let masks = &masks;
                let sound = &mut sound;
                let audio_observe = &mut audio_observe;
                let worker = s.spawn(move || -> Result<(Prepared, Vec<crate::timing::Sample>, u64), String> {
                    let mut samples = Vec::with_capacity(masks.len());
                    let mut held = 0u64;
                    for (i, &mask) in masks.iter().enumerate() {
                        let saved_tick = session.stats().tick;
                        let timer = Timer::new();
                        session.advance(mask).map_err(|e| {
                            format!("tick={} mask={mask} refused without completion: {e}", base + i as u64 + 1)
                        })?;
                        samples.push(timer.finish());
                        let timer = Timer::new();
                        sound.observe(&*session);
                        // A player presentation is sampled every step so short landings
                        // and hits cannot disappear between rendered frames.
                        let p = session.presentation_region([0; 4]);
                        sound.observe_feel(&p, *scene_ref.feel.lock().map_err(|_| "feel lock poisoned")?);
                        audio_observe.add(timer.finish());
                        scene_ref.observe_feel(&p, session)?;
                        if session.stats().tick == saved_tick {
                            held += 1;
                            if require_active_window {
                                return Err("required active performance window includes a held saved frame; correctness mode permits it".into());
                            }
                        }
                        saves.cadence(session, cursor_start + base + i as u64 + 1, save)?;
                    }
                    let prepared = prepare_frame(session, scene_ref, request.0, request.1, base + masks.len() as u64)?;
                    Ok((prepared, samples, held))
                });
                let drawn = (|| -> Result<(), String> {
                    let timer = Timer::new();
                    let container = gpu.begin(current.background)?;
                    let container = [container[0] as f64, container[1] as f64];
                    if container != current.container {
                        region_container_mismatch += 1;
                    }
                    let p = &current.p;
                    let picture = scene.picture(p, container, current.zoom)?;
                    // This frame was prepared one frame earlier, with the zoom of that
                    // time. Writing its zoom back would undo a newer request and swap
                    // the two sizes every frame. Only clamp the request to the range.
                    zoom = zoom.clamp(picture.plan.zoom_min, picture.plan.zoom_max);
                    zoom_min = picture.plan.zoom_min;
                    zoom_max = picture.plan.zoom_max;
                    resolved_scale = picture.plan.scale;
                    if logged_scale != resolved_scale {
                        println!("RUST_ZOOM scale={resolved_scale}");
                        logged_scale = resolved_scale;
                    }
                    let world_draw = gpu.draw_lit_world(&picture.world, &picture.lights)?;
                    let water_draw = gpu.water_fx(&picture.water)?;
                    let surface_draw = gpu.draw(&picture.water_surface)?;
                    let light_draw = gpu.lights(&picture.lights)?;
                    gpu.darkness(picture.light_origin, picture.light_radius, picture.darkness)?;
                    let tint_draw = if picture.tint.is_empty() {
                        crate::gles::DrawCounts::default()
                    } else {
                        gpu.draw(&picture.tint)?
                    };
                    let hud_draw = gpu.draw(&picture.hud)?;
                    if paused {
                        let settings = *scene.feel.lock().map_err(|_| "feel lock poisoned")?;
                        let page = crate::feel_menu::Page {
                            model: &feel_model,
                            settings: &settings,
                        };
                        let mut overlay = Vec::new();
                        feel_view.emit(&page, container, scene.solid, &mut overlay)?;
                        gpu.draw(&overlay)?;
                    }
                    let batches = world_draw.batches
                        + hud_draw.batches
                        + tint_draw.batches
                        + water_draw.batches
                        + surface_draw.batches
                        + light_draw.batches;
                    let quads = world_draw.quads
                        + hud_draw.quads
                        + tint_draw.quads
                        + water_draw.quads
                        + surface_draw.quads
                        + light_draw.quads;
                    batch_counts.add(batches);
                    batch_total += batches;
                    quad_counts.add(quads);
                    quad_total += quads;
                    vertex_counts.add(
                        world_draw.vertices
                            + hud_draw.vertices
                            + tint_draw.vertices
                            + light_draw.vertices,
                    );
                    entity_view_counts.add(picture.entity_bounds_in_view);
                    if let Some(f) = &mut feedback {
                        f.request(swap_calls + 1, p.tick as u64)?;
                    }
                    draw.add(timer.finish());
                    if digest_every.is_some_and(|n| current.completed.is_multiple_of(n)) {
                        let dump = digest_dump
                            .as_ref()
                            .map(|d| d.join(format!("frame-{:06}.png", current.completed)));
                        let digest = gpu.frame_digest(dump.as_deref())?;
                        println!(
                            "RUST_FRAME_DIGEST completed={} tick={} zoom={} atlas={atlas} pipeline=true sha256={digest} clean_timing_excluded=true",
                            current.completed, p.tick, current.zoom
                        );
                    }
                    Ok(())
                })();
                (
                    worker
                        .join()
                        .map_err(|_| "simulation thread panicked".to_string()),
                    drawn,
                )
            });
            draw_result?;
            let (prepared, samples, held) = worker_result??;
            for sample in samples {
                sim.add(sample);
            }
            held_saved_frame_calls += held;
            completed += steps;
            if !uncapped {
                for _ in 0..steps {
                    clock.completed_one();
                }
            }
            pending = Some(prepared);
        } else {
            if !paused && !waiting_release {
                let owed = if uncapped { 1 } else { clock.owed() };
                let budget =
                    if let Some(target) = capture_tick.filter(|t| !captured && *t >= completed) {
                        owed.min(target - completed)
                    } else {
                        owed
                    };
                let budget = feel_demo
                    .as_ref()
                    .filter(|d| !d.running())
                    .map_or(budget, |d| budget.min(d.after.saturating_sub(completed)));
                for _ in 0..budget.min(stop - completed) {
                    let saved_tick = session.stats().tick;
                    let cursor = crate::call_cursor::index(cursor_start, completed)?;
                    let mask = if let Some(v) = &replay {
                        v[cursor]
                    } else {
                        controls.step_mask(live)
                    };
                    let timer = Timer::new();
                    session.advance(mask).map_err(|e| {
                        format!(
                            "tick={} mask={mask} refused without completion: {e}",
                            completed + 1
                        )
                    })?;
                    sim.add(timer.finish());
                    let timer = Timer::new();
                    sound.observe(&session);
                    let p = session.presentation_region([0; 4]);
                    sound.observe_feel(&p, *scene.feel.lock().map_err(|_| "feel lock poisoned")?);
                    audio_observe.add(timer.finish());
                    scene.observe_feel(&p, &session)?;
                    if session.stats().tick == saved_tick {
                        held_saved_frame_calls += 1;
                        if require_active_window {
                            return Err("required active performance window includes a held saved frame; correctness mode permits it".into());
                        }
                    }
                    completed += 1;
                    if !uncapped {
                        clock.completed_one();
                    }
                    saves.cadence(&session, cursor_start + completed, &mut save)?;
                }
            }
            let timer = Timer::new();
            let (map_index, mut focus) = session.presentation_view();
            if let Some(at) = view_at {
                focus = at;
            }
            let container = gpu.begin(scene.clear_color(map_index)?)?;
            let region = scene.presentation_region(
                map_index,
                focus,
                [container[0] as f64, container[1] as f64],
                zoom,
            )?;
            let mut p = session.presentation_region(region);
            if let Some(at) = view_at {
                p.follow.current = at;
                p.follow.previous = at;
            }
            let picture = scene.picture(&p, [container[0] as f64, container[1] as f64], zoom)?;
            zoom = picture.plan.zoom;
            zoom_min = picture.plan.zoom_min;
            zoom_max = picture.plan.zoom_max;
            resolved_scale = picture.plan.scale;
            if logged_scale != resolved_scale {
                println!("RUST_ZOOM scale={resolved_scale}");
                logged_scale = resolved_scale;
            }
            let world_draw = gpu.draw_lit_world(&picture.world, &picture.lights)?;
            let water_draw = gpu.water_fx(&picture.water)?;
            let surface_draw = gpu.draw(&picture.water_surface)?;
            let light_draw = gpu.lights(&picture.lights)?;
            gpu.darkness(picture.light_origin, picture.light_radius, picture.darkness)?;
            let tint_draw = if picture.tint.is_empty() {
                crate::gles::DrawCounts::default()
            } else {
                gpu.draw(&picture.tint)?
            };
            let hud_draw = gpu.draw(&picture.hud)?;
            if paused {
                let settings = *scene.feel.lock().map_err(|_| "feel lock poisoned")?;
                let page = crate::feel_menu::Page {
                    model: &feel_model,
                    settings: &settings,
                };
                let mut overlay = Vec::new();
                feel_view.emit(&page, container.map(f64::from), scene.solid, &mut overlay)?;
                gpu.draw(&overlay)?;
            }
            let batches = world_draw.batches
                + hud_draw.batches
                + tint_draw.batches
                + water_draw.batches
                + surface_draw.batches
                + light_draw.batches;
            let quads = world_draw.quads
                + hud_draw.quads
                + tint_draw.quads
                + water_draw.quads
                + surface_draw.quads
                + light_draw.quads;
            batch_counts.add(batches);
            batch_total += batches;
            quad_counts.add(quads);
            quad_total += quads;
            vertex_counts.add(
                world_draw.vertices + hud_draw.vertices + tint_draw.vertices + light_draw.vertices,
            );
            entity_view_counts.add(picture.entity_bounds_in_view);
            if let Some(f) = &mut feedback {
                f.request(swap_calls + 1, p.tick as u64)?;
            }
            draw.add(timer.finish());
            if digest_every.is_some_and(|n| {
                if paused && feel_demo.is_some() {
                    pause_frames.is_multiple_of(n)
                } else {
                    !paused && completed.is_multiple_of(n)
                }
            }) {
                let dump = digest_dump.as_ref().map(|d| {
                    d.join(if paused {
                        format!("frame-{completed:06}-feel-{pause_frames:06}.png")
                    } else {
                        format!("frame-{completed:06}.png")
                    })
                });
                let digest = gpu.frame_digest(dump.as_deref())?;
                println!(
                    "RUST_FRAME_DIGEST completed={completed} tick={} zoom={zoom} atlas={atlas} sha256={digest} clean_timing_excluded=true",
                    p.tick
                );
            }
            if capture_tick == Some(completed) && !captured {
                let path = Path::new(files.get("--capture").unwrap());
                let snapshot = session.snapshot().map_err(|e| e.to_string())?;
                gpu.capture(path)?;
                let snapshot_path = path.with_extension("v10");
                std::fs::write(&snapshot_path, &snapshot).map_err(|e| e.to_string())?;
                let metadata = serde_json::json!({"mode":"correctness-GPU-capture-not-clean-timing","input_offset":cursor_start,"successful_input_calls":completed,"input_call_cursor":cursor_start+completed,"saved_frame":p.tick,"level_raw_sha256":raw_hash,"snapshot_path":snapshot_path,"snapshot_sha256":hash(&snapshot),"startup_maps_path":startup_maps_path,"selected_player_pose":{"name":p.player.selected_pose.name,"tick":p.player.selected_pose.tick,"frame":p.player.selected_pose.frame},"swimming":p.player.swimming,"companion_mode":p.companions.mode,"semantic_entity_scales":p.entities.iter().filter_map(|e|e.visual.scale.map(|ratio|serde_json::json!({"token":e.token,"code":e.code,"ratio":ratio}))).collect::<Vec<_>>(),"pack_manifest_sha256":crate::pack::MANIFEST_SHA,"pack_file_inventory_sha256":crate::pack::INVENTORY_SHA,"framebuffer":container,"camera":{"scale":picture.plan.scale,"center":picture.plan.center,"visible":picture.plan.visible,"offset":picture.plan.offset,"rounded_root_offset":picture.plan.offset.map(crate::screen::godot_round)},"interpolation":"off","backend":"owned-GLES","gles_pipeline":gpu.pipeline_info(),"capture_pipeline":gpu.last_capture_pipeline(),"audio":audio_label});
                std::fs::write(
                    path.with_extension("json"),
                    serde_json::to_vec_pretty(&metadata).map_err(|e| e.to_string())?,
                )
                .map_err(|e| e.to_string())?;
                println!(
                    "RUST_CAPTURE_STATE input_call_cursor={} successful_calls={} saved_frame={} snapshot_sha256={}",
                    cursor_start + completed,
                    completed,
                    p.tick,
                    hash(&snapshot)
                );
                captured = true;
            }
        }
        if paused {
            pause_frames += 1;
        }
        let timer = Timer::new();
        gpu.present()?;
        present.add(timer.finish());
        swap_calls += 1;
        let now = Instant::now();
        if let Some(previous) = previous_present {
            let duration = now.duration_since(previous).as_nanos() as u64;
            intervals.add(duration);
            if duration > 16_666_667 {
                missed += 1;
            }
        }
        previous_present = Some(now);
        if last_report.elapsed() >= Duration::from_secs(1) {
            println!(
                "RUST_GAME_PROGRESS {}",
                serde_json::json!({"benchmark_unverified_level":benchmark_unverified_level,"wall_ms":ready.elapsed().as_millis(),"expected_ticks":stop,"completed_ticks":completed,"saved_tick":session.stats().tick,"owed_ticks":clock.owed(),"max_debt":clock.max_debt,"swap_calls":swap_calls,"swap_intervals_over_refresh_budget":missed,"input_events":controls.events,"paused":paused,"memory":memory_kib()})
            );
            flush()?;
            last_report = Instant::now();
        }
        if paused || (!uncapped && clock.owed() == 0) {
            thread::sleep(Duration::from_millis(1));
        }
        // game.gd: on the goal the simulation stops and the goal menu opens. Replays
        // keep the plain completed picture.
        if let Some(path) = files.get("--result").filter(|_| replay.is_none())
            && session.saved_field("goal_reached") == Some(1)
        {
            let deadline = ready + Duration::from_secs(seconds);
            let choice = goal_menu(
                &mut gpu,
                &scene,
                &session,
                &mut events,
                zoom,
                has_next,
                deadline,
                digest_dump.as_deref(),
            )?;
            std::fs::write(path, choice).map_err(|e| e.to_string())?;
            println!("RUST_GAME_GOAL completed={completed} choice={choice}");
            goal_choice = Some(choice);
            break;
        }
    }
    if !uncapped {
        clock.observe(Instant::now(), paused || release_gate.is_waiting());
    }
    gpu.check_error()?;
    let active_wall = ready.elapsed();
    if let Some(f) = &mut feedback {
        let deadline = Instant::now() + Duration::from_millis(500);
        while f.stats().pending != 0 && Instant::now() < deadline {
            for _ in events.poll_iter() {}
            f.collect()?;
            thread::sleep(Duration::from_millis(1));
        }
        f.collect()?;
        if f.stats().pending != 0 {
            return Err("Wayland delivery feedback did not drain; no completion proof".into());
        }
    }
    let writes = saves.finish(&session, &mut save)?;
    let mut summary = serde_json::json!({"purpose":if benchmark_unverified_level{"throwaway-scaling-speed-hint-not-correctness-not-target-A/B"}else{"correctness-verification-only-not-target-A/B"},"level_sha256":raw_hash,"mode":if uncapped{"uncapped-fixed-work"}else{"real-time"},"capture_tainted":capture_tick.is_some(),"audio":audio_label,"wall_ms":active_wall.as_millis(),"expected_ticks":stop,"completed_ticks":completed,"input_offset":cursor_start,"input_call_cursor":cursor_start+completed,"held_saved_frame_calls":held_saved_frame_calls,"require_active_window":require_active_window,"save_call_cadence":60,"saved_tick":session.stats().tick,"swap_calls":swap_calls,"actual_compositor_delivered_frames":feedback.as_ref().map(|f|f.delivered_unique),"wayland_presentation":feedback.as_ref().map(|f|f.summary()),"maximum_debt":clock.max_debt,"ending_debt":clock.owed(),"swap_intervals_over_16_667ms":missed,"swap_return_interval_ns":intervals.summary(),"presentation_feedback":if want_feedback{"wp_presentation requested; inspect actual callback/flags evidence"}else{"not instrumented; swap calls are not compositor-delivered-frame proof"},"quantile_method":"fixed-memory log histogram upper bounds, relative bucket width <=1/512 above512ns; exact maxima","sim":sim.summary(),"draw_submit":draw.summary(),"presentation_copy_and_swap":present.summary(),"gles_pipeline":gpu.pipeline_info(),"snapshot_enqueue":save.summary(),"save_writes":writes,"input_events":controls.events,"ignored_key_repeats":controls.repeat_events,"input_delivery":"one literal mask per successful advance call; explicit restore offset; live held state sampled per event batch; jump transitions delivered per simulation call","memory":memory_kib(),"stats":{"entity_steps":session.stats().entity_steps,"terrain_queries":session.stats().terrain_queries,"nearby_queries":session.stats().nearby_queries,"runtime_spawns":session.stats().runtime_spawns,"collections":session.stats().collections,"damage_events":session.stats().damage_events},"cpu_phases":"nonoverlapping main-thread samples; presentation_copy_and_swap includes fullscreen copy submission and SDL swap; capture-only allocation/copy/readback is outside these timers; asynchronous GPU and save-worker times not attributed to these CPU samples"});
    summary["benchmark_unverified_level"] = benchmark_unverified_level.into();
    summary["picture_invalid"] = benchmark_single_texture.into();
    summary["benchmark_single_texture"] = benchmark_single_texture.into();
    if benchmark_real_screen {
        summary["faithful_real_level"] = false.into();
        summary["visual_omissions"] = serde_json::json!(scene.visual_omissions);
        summary["stand_in"] = stand_in.into();
        summary["tint_overlay"] = "source-map_effects.gd-plan-real-alpha-overlay".into();
    }
    summary["atlas"] = gpu.atlas_info();
    summary["audio_observe"] = audio_observe.summary();
    summary["audio_derivation"] = serde_json::json!({"observations":sound.observations,"effect_cues":sound.heard,"effects_not_yet_decoded":sound.missing_clips,"scope":"audio_player.gd derive after each successful step on the simulation thread; outside the sim timer"});
    summary["audio_playback"] = audio_device
        .as_ref()
        .map_or(serde_json::Value::Null, |d| d.summary());
    summary["pipeline"] = serde_json::json!({"enabled":pipeline,"region_container_mismatch":region_container_mismatch,"drawn_frame":"state after the previous frame's steps; simulation runs on a second thread during drawing"});
    summary["saves_disabled"] = benchmark_unverified_level.into();
    summary["scale"] = serde_json::json!(resolved_scale);
    summary["draw_batches_per_frame"] = serde_json::json!({"frames":batch_counts.count,"mean":batch_total as f64/batch_counts.count.max(1) as f64,"quantiles":batch_counts.summary(),"scope":"world+HUD Gles::draw results; excludes darkness and presentation copy"});
    summary["draw_counts_per_frame"] = serde_json::json!({"frames":batch_counts.count,"quads":quad_counts.summary(),"batches":batch_counts.summary(),"vertices":vertex_counts.summary(),"scope":"actual DrawCounts for world (including explicit benchmark stand-ins)+optional real tint+HUD; darkness adds one draw when enabled, presentation copy adds one"});
    summary["entities_bounds_intersect_view_per_frame"] = serde_json::json!({"count":entity_view_counts.count,"quantiles":entity_view_counts.summary(),"bounds":"visible Core body hulls; inactive placed actors at immutable placement; not art envelopes; measurement only"});
    summary["drawn_quads_per_frame"] =
        serde_json::json!(quad_total as f64 / batch_counts.count.max(1) as f64);
    summary["zoom"] = zoom.into();
    summary["zoom_min"] = zoom_min.into();
    summary["zoom_max"] = zoom_max.into();
    if benchmark_unverified_level {
        summary["save_call_cadence"] = 0.into();
    }
    summary["startup_entity_steps"] = startup_entity_steps.into();
    summary["active_entity_steps"] = (session.stats().entity_steps - startup_entity_steps).into();
    summary["active_entity_steps_per_accepted_call"] = serde_json::json!(
        (session.stats().entity_steps - startup_entity_steps) as f64 / completed.max(1) as f64
    );
    println!("RUST_GAME_SUMMARY {summary}");
    flush()?;
    if controls.exit || goal_choice.is_some() {
        println!("RUST_GAME_EXIT user_requested=true completed={completed} expected={stop}");
        return Ok(RunExit::Success);
    }
    if completed != stop || capture_tick.is_some() && !captured {
        return Err("bounded game run incomplete; no successful completion marker".into());
    }
    println!(
        "RUST_GAME_DONE completed_ticks={completed} expected_ticks={stop} benchmark_unverified_level={benchmark_unverified_level} target_A_B_claim=false"
    );
    flush()?;
    Ok(RunExit::Success)
}

/// game.gd _summary.
fn goal_summary(p: &eggshell_spike_core::Presentation) -> String {
    format!(
        "Score {}. Time {}. Hurt {}, deaths {}.",
        p.hud.score,
        crate::hud::clock_text(p.hud.total_play_ticks),
        p.hud.hits,
        p.hud.deaths
    )
}

/// The goal menu over the completed picture (game.gd open_menu after goal_reached).
/// Returns "next", "restart", "levels" or "quit" for the level list launcher.
#[allow(clippy::too_many_arguments)]
fn goal_menu(
    gpu: &mut Gles,
    scene: &Scene,
    session: &Session,
    events: &mut sdl2::EventPump,
    zoom: f64,
    has_next: bool,
    deadline: Instant,
    shot: Option<&Path>,
) -> Result<&'static str, String> {
    use crate::{
        menu::{Model, Request},
        picker::{Command, Pad},
    };
    let p = session.presentation();
    let mut model = Model::goal(goal_summary(&p), has_next);
    let mut view = scene.menu_view()?;
    let mut pad = Pad::open(&gpu.sdl)?;
    let mut menu = Vec::new();
    let mut commands = Vec::new();
    // A button still held from play does not confirm at once.
    let opened = Instant::now();
    let mut frames = 0u64;
    println!(
        "RUST_GAME_GOAL_MENU summary={:?} has_next={has_next}",
        goal_summary(&p)
    );
    while Instant::now() < deadline {
        commands.clear();
        for event in events.poll_iter() {
            match event {
                sdl2::event::Event::Quit { .. } => commands.push(Command::Quit),
                sdl2::event::Event::KeyDown {
                    keycode: Some(key), ..
                } => commands.extend(crate::picker::key_command(key)),
                _ => {}
            }
        }
        pad.commands(
            Instant::now(),
            scene
                .feel
                .lock()
                .map_err(|_| "feel lock poisoned")?
                .button_layout,
            &mut commands,
        );
        if opened.elapsed() < Duration::from_millis(250) {
            commands.clear();
        }
        for command in commands.drain(..) {
            let request = match command {
                Command::Up => {
                    model.step(-1);
                    Request::None
                }
                Command::Down => {
                    model.step(1);
                    Request::None
                }
                Command::Confirm => model.confirm(),
                Command::Back => model.back(),
                Command::Quit => Request::LevelList,
                Command::PageUp | Command::PageDown => Request::None,
            };
            match request {
                Request::Next => return Ok("next"),
                Request::Restart => return Ok("restart"),
                Request::LevelList => return Ok("levels"),
                Request::Quit => return Ok("quit"),
                _ => {}
            }
        }
        let container = gpu.begin(scene.clear_color(p.map_index)?)?;
        let container = [container[0] as f64, container[1] as f64];
        let picture = scene.picture(&p, container, zoom)?;
        gpu.draw(&picture.world)?;
        gpu.darkness(picture.light_origin, picture.light_radius, picture.darkness)?;
        if !picture.tint.is_empty() {
            gpu.draw(&picture.tint)?;
        }
        gpu.draw(&picture.hud)?;
        menu.clear();
        view.emit(&model, container, scene.solid_image(), &mut menu)?;
        gpu.draw(&menu)?;
        frames += 1;
        // Shots runs: one picture of the menu, then back to the list.
        if let Some(dir) = shot
            && frames == 30
        {
            gpu.frame_digest(Some(&dir.join("goal-menu.png")))?;
            return Ok("levels");
        }
        gpu.present()?;
    }
    Ok("levels")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    #[test]
    fn goal_clears_once_even_off_cadence_and_blocks_all_later_autosaves() {
        for (lifetime, phase) in [
            (Lifetime::Goal, 0),
            (Lifetime::Active, 7),
            (Lifetime::Active, 8),
        ] {
            let policy = AutosavePolicy::default();
            assert_eq!(
                policy.action(Lifetime::Active, 0, false),
                AutosaveAction::Skip
            );
            assert_eq!(
                policy.action(Lifetime::Active, 0, true),
                AutosaveAction::Write
            );
            assert_eq!(policy.action(lifetime, phase, false), AutosaveAction::Clear);
            assert_eq!(policy.action(lifetime, phase, true), AutosaveAction::Skip);
            // A manual restore cannot re-enable autosave after completion.
            assert_eq!(
                policy.action(Lifetime::Active, 0, true),
                AutosaveAction::Skip
            );
        }
    }
    #[test]
    fn non_goal_phases_keep_autosave_cadence() {
        let policy = AutosavePolicy::default();
        for lifetime in [
            Lifetime::Active,
            Lifetime::Hurt,
            Lifetime::Separated,
            Lifetime::Rescuing,
            Lifetime::Dying,
            Lifetime::Respawning,
        ] {
            for phase in 0..=6 {
                assert_eq!(policy.action(lifetime, phase, false), AutosaveAction::Skip);
                assert_eq!(policy.action(lifetime, phase, true), AutosaveAction::Write);
            }
        }
    }
    #[test]
    fn goal_worker_removes_queued_autosave_without_touching_manual_slot() {
        let directory = test_save_directory("goal");
        let auto = directory.join("autosave.v10");
        let manual = directory.join("manual.v10");
        let writer = Writer::start();
        writer.enqueue(auto.clone(), vec![1, 2]).unwrap();
        writer.clear_autosave(auto.clone()).unwrap();
        writer.enqueue(manual.clone(), vec![3, 4]).unwrap();
        assert_eq!(writer.finish().unwrap(), 2);
        assert!(!auto.exists());
        assert!(!auto.with_extension("tmp").exists());
        assert_eq!(std::fs::read(manual).unwrap(), [3, 4]);
        std::fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn goal_cleanup_is_best_effort_and_manual_writes_still_finish() {
        let directory = test_save_directory("goal-best-effort");
        let auto = directory.join("autosave.v10");
        let writer = Writer::start();
        writer.clear_autosave(auto.clone()).unwrap(); // Missing is harmless.
        // A non-file path cannot be removed, but must not kill the worker.
        let blocked = directory.join("not-a-file");
        std::fs::create_dir(&blocked).unwrap();
        writer.clear_autosave(blocked).unwrap();
        writer
            .enqueue(directory.join("manual.v10"), vec![5])
            .unwrap();
        assert_eq!(writer.finish().unwrap(), 1);
        assert!(!auto.exists());
        assert_eq!(std::fs::read(directory.join("manual.v10")).unwrap(), [5]);
        std::fs::remove_dir_all(directory).unwrap();
    }
    fn test_save_directory(label: &str) -> PathBuf {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "eggshell-save-{label}-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).unwrap();
        directory
    }
    #[test]
    fn restart_exits_75_after_draining_and_removing_autosave_without_summary() {
        const CHILD_DIR: &str = "EGGSHELL_RESTART_TEST_DIR";
        if let Some(directory) = std::env::var_os(CHILD_DIR) {
            let directory = PathBuf::from(directory);
            let saves = SavePipeline::start(directory.clone(), false);
            let writer = saves.writer.as_ref().unwrap();
            writer
                .enqueue(directory.join("autosave.v10"), vec![1, 2])
                .unwrap();
            writer
                .enqueue(directory.join("manual.v10"), vec![3, 4])
                .unwrap();
            // Exercise the same shutdown and exit-code contract as the --play entry point.
            let outcome = restart(saves).unwrap();
            std::process::exit(outcome.code().into());
        }
        let directory = test_save_directory("restart-process");
        let output = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "game::tests::restart_exits_75_after_draining_and_removing_autosave_without_summary", "--nocapture"])
            .env(CHILD_DIR, &directory)
            .output().unwrap();
        assert_eq!(output.status.code(), Some(75), "{output:?}");
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert_eq!(stdout.matches("RUST_GAME_RESTART").count(), 1);
        assert!(!stdout.contains("RUST_GAME_DONE"));
        assert!(!stdout.contains("RUST_GAME_SUMMARY"));
        assert!(!directory.join("autosave.v10").exists());
        assert!(!directory.join("autosave.tmp").exists());
        assert_eq!(std::fs::read(directory.join("manual.v10")).unwrap(), [3, 4]);
        assert_eq!(RunExit::Success.code(), 0);
        std::fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn restart_with_no_autosave_is_safe_but_failed_removal_does_not_request_relaunch() {
        let directory = test_save_directory("restart-missing");
        assert_eq!(
            restart(SavePipeline::start(directory.clone(), false)).unwrap(),
            RunExit::Restart
        );
        std::fs::create_dir(directory.join("autosave.v10")).unwrap();
        assert!(restart(SavePipeline::start(directory.clone(), false)).is_err());
        std::fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn restart_joins_a_failed_worker_before_removing_existing_autosave() {
        let directory = test_save_directory("restart-failed-worker");
        std::fs::write(directory.join("autosave.v10"), [1]).unwrap();
        let saves = SavePipeline::start(directory.clone(), false);
        saves
            .writer
            .as_ref()
            .unwrap()
            .enqueue(directory.join("absent/manual.v10"), vec![2])
            .unwrap();
        assert_eq!(restart(saves).unwrap(), RunExit::Restart);
        assert!(!directory.join("autosave.v10").exists());
        std::fs::remove_dir_all(directory).unwrap();
    }
    #[test]
    fn startup_maps_are_private_nonempty_and_never_overwritten() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "eggshell-startup-maps-{}-{nonce}",
            std::process::id()
        ));
        std::fs::create_dir(&directory).unwrap();
        let path = startup_maps(&directory).unwrap();
        let first = std::fs::read(&path).unwrap();
        assert!(!first.is_empty());
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        // A second start writes the next name and leaves the first evidence alone.
        let second = startup_maps(&directory).unwrap();
        assert_ne!(second, path);
        assert!(second.ends_with("startup-process-2.maps"));
        assert_eq!(std::fs::read(&path).unwrap(), first);
        std::fs::remove_dir_all(&directory).unwrap();
    }
}

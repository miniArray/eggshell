//! Platform acceptance only. This executable never represents sprite animation as gameplay.
use eggshell_spike_player::{pack::Pack, platform::Platform};
use sdl2::{controller::Button, event::Event, keyboard::Keycode, pixels::Color, rect::Rect};
use std::{
    io::Write,
    path::PathBuf,
    time::{Duration, Instant},
};

fn main() {
    if let Err(error) = run() {
        eprintln!("RUST_ADMISSION_ERROR {error}");
        std::process::exit(2);
    }
}
fn run() -> Result<(), String> {
    if std::env::args().nth(1).as_deref() == Some("--benchmark-profile-host") {
        return eggshell_spike_player::diagnosis::profile_host(std::env::args().skip(2));
    }
    #[cfg(feature = "benchmark-work-counters")]
    if std::env::args().nth(1).as_deref() == Some("--benchmark-trace-host") {
        return eggshell_spike_player::diagnosis::trace_host(std::env::args().skip(2));
    }
    #[cfg(feature = "benchmark-work-counters")]
    if std::env::args().nth(1).as_deref() == Some("--benchmark-work-host") {
        return eggshell_spike_player::diagnosis::work_host(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--benchmark-zoom-range") {
        return eggshell_spike_player::benchmark::zoom_range(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--benchmark-host-check") {
        return eggshell_spike_player::benchmark::host_check(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--audio-decode-check") {
        let args: Vec<_> = std::env::args().skip(2).collect();
        if args.len() != 2 {
            return Err("--audio-decode-check PACK INVENTORY".into());
        }
        let pack = Pack::open(
            std::path::Path::new(&args[0]),
            std::path::Path::new(&args[1]),
        )?;
        return eggshell_spike_player::audio::decode_check(&pack);
    }
    if std::env::args().nth(1).as_deref() == Some("--blend-probe") {
        return eggshell_spike_player::blend_probe::run(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--fill-host") {
        return eggshell_spike_player::diagnosis::fill_host(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--save-info") {
        return eggshell_spike_player::diagnosis::save_info(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--next-level") {
        return eggshell_spike_player::picker::next_level(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--levels") {
        return eggshell_spike_player::picker::run(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--level-index") {
        return eggshell_spike_player::level_index::run(std::env::args().skip(2));
    }
    if std::env::args().nth(1).as_deref() == Some("--play") {
        return eggshell_spike_player::game::run(std::env::args().skip(2));
    }
    let real_assets = std::env::args().nth(1).as_deref() == Some("--validate-real-screen-assets");
    if real_assets || std::env::args().nth(1).as_deref() == Some("--validate-assets") {
        let args: Vec<_> = std::env::args().skip(2).collect();
        if args.len() != 6 {
            return Err(
                "--validate-assets LEVEL COLLISION PACK INVENTORY VIEW_METRICS PRIVATE_REPORT"
                    .into(),
            );
        }
        let compile = if real_assets {
            eggshell_spike_core::World::compile_benchmark_real_screen
        } else {
            eggshell_spike_core::World::compile
        };
        let world = compile(
            &std::fs::read_to_string(&args[0]).map_err(|e| e.to_string())?,
            &std::fs::read_to_string(&args[1]).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        let pack = Pack::open(
            std::path::Path::new(&args[2]),
            std::path::Path::new(&args[3]),
        )?;
        let prepare = if real_assets {
            eggshell_spike_player::scene::Scene::prepare_benchmark_real_screen
        } else {
            eggshell_spike_player::scene::Scene::prepare
        };
        // Placed codes plus everything the core can create during play.
        let codes: Vec<String> = world
            .maps
            .iter()
            .flat_map(|m| m.placements.iter().map(|p| p.code.clone()))
            .chain(
                eggshell_spike_core::RUNTIME_CODES
                    .iter()
                    .map(|c| c.to_string()),
            )
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect();
        let scene = prepare(&world, &codes, &pack, std::path::Path::new(&args[4]))?;
        let report = scene.validate_assets(&pack)?;
        std::fs::write(
            &args[5],
            serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        println!(
            "RUST_ASSET_BINDINGS_ONLY images={} rgba_payload_bytes={} maximum_dimensions={} gameplay_admitted=false GPU_parity=false report={}",
            report["image_count"],
            report["rgba_payload_bytes"],
            report["maximum_dimensions"],
            args[5]
        );
        return Ok(());
    }
    if std::env::args().nth(1).as_deref() == Some("--admit-game") {
        let paths: Vec<_> = std::env::args().skip(2).collect();
        if paths.len() != 3 {
            return Err("--admit-game requires LEVEL COLLISION SCHEMA paths".into());
        }
        let read = |p: &str| std::fs::read_to_string(p).map_err(|e| e.to_string());
        let session = eggshell_spike_core::Session::load(
            &read(&paths[0])?,
            &read(&paths[1])?,
            &read(&paths[2])?,
        )
        .map_err(|e| format!("authoritative core admission: {e}"))?;
        return Err(format!(
            "player gameplay presentation not yet admitted: terrain layers/transforms/polygons, three backgrounds, darkness, palettes, slices, player/companion/HUD, heads/poses/origins; core report={:?}",
            session.admission_report()
        ));
    }
    let start = Instant::now();
    let mut pack_path = None;
    let mut inventory_path = None;
    let mut seconds = 10u64;
    let mut fullscreen = true;
    let mut capture = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--pack-root" => {
                pack_path = Some(PathBuf::from(args.next().ok_or("--pack-root needs path")?))
            }
            "--pack-inventory" => {
                inventory_path = Some(PathBuf::from(
                    args.next().ok_or("--pack-inventory needs path")?,
                ))
            }
            "--seconds" => {
                seconds = args
                    .next()
                    .ok_or("--seconds needs integer")?
                    .parse()
                    .map_err(|_| "invalid seconds")?
            }
            "--windowed" => fullscreen = false,
            "--capture" => {
                capture = Some(PathBuf::from(
                    args.next().ok_or("--capture needs private path")?,
                ))
            }
            "--help" => {
                println!(
                    "THROWAWAY PLATFORM SMOKE, NOT GAMEPLAY\n--pack-root PATH --pack-inventory PATH [--seconds 1..60] [--windowed] [--capture PRIVATE.png]\nP/Start pauses animation; Escape/Guide exits. Back+Start exits. Bounded exit is always active.\nAudio is disabled; no audio feature parity."
                );
                return Ok(());
            }
            _ => {
                return Err(format!(
                    "unsupported argument: {arg}; no gameplay mode admitted"
                ));
            }
        }
    }
    if !(1..=60).contains(&seconds) {
        return Err("smoke duration must be 1..60 seconds".into());
    }
    let pack = Pack::open(
        &pack_path.ok_or("--pack-root required (private original pack)")?,
        &inventory_path.ok_or("--pack-inventory required (pinned 3028-file hashes)")?,
    )?;
    let idle = pack
        .manifest
        .pointer("/player/Idle0")
        .ok_or("pack missing Idle0")?;
    let frames = idle["frames"].as_array().ok_or("Idle0 missing frames")?;
    if frames.is_empty() {
        return Err("Idle0 empty".into());
    }
    let mut platform = Platform::open(fullscreen, true)?;
    let creator = platform.canvas.texture_creator();
    let mut textures = Vec::new();
    let mut dimensions = Vec::new();
    for frame in frames {
        let file = frame["file"].as_str().ok_or("frame has no file")?;
        let image = pack.png(file)?;
        let info = platform.canvas.info();
        if image.width > info.max_texture_width || image.height > info.max_texture_height {
            return Err("private texture exceeds hardware limit".into());
        }
        println!(
            "RUST_PRIVATE_ASSET file={file:?} sha256={} width={} height={}",
            image.sha256, image.width, image.height
        );
        dimensions.push((image.width, image.height));
        textures.push(Platform::upload(&creator, &image)?);
    }
    let mut events = platform.sdl.event_pump()?;
    let ready = Instant::now();
    println!(
        "RUST_SMOKE_READY mode=presentation-only-not-gameplay startup_ms={:.3} pause=P-or-Start exit=Escape-or-Guide-or-Back+Start duration_seconds={seconds} joystick_handles={} controller_handles={}",
        start.elapsed().as_secs_f64() * 1000.0,
        platform.joysticks.len(),
        platform.controllers.len()
    );
    std::io::stdout().flush().map_err(|e| e.to_string())?;
    let mut paused = false;
    let mut frames_drawn = 0u64;
    let mut last_report = Instant::now();
    let mut animation = Duration::ZERO;
    let mut last = Instant::now();
    let mut captured = false;
    let mut user_exit = false;
    let mut input_events = 0u64;
    while ready.elapsed() < Duration::from_secs(seconds) {
        for event in events.poll_iter() {
            match event {
                Event::Quit { .. }
                | Event::KeyDown {
                    keycode: Some(Keycode::Escape),
                    ..
                }
                | Event::ControllerButtonDown {
                    button: Button::Guide,
                    ..
                } => user_exit = true,
                Event::KeyDown {
                    keycode: Some(Keycode::P),
                    repeat: false,
                    ..
                }
                | Event::ControllerButtonDown {
                    button: Button::Start,
                    ..
                } => paused = !paused,
                Event::JoyButtonDown { .. }
                | Event::JoyButtonUp { .. }
                | Event::JoyHatMotion { .. }
                | Event::JoyAxisMotion { .. }
                | Event::ControllerButtonDown { .. }
                | Event::ControllerButtonUp { .. } => {
                    println!("RUST_INPUT_EVENT {event:?}");
                    input_events += 1;
                }
                _ => {}
            }
        }
        if platform
            .controllers
            .iter()
            .any(|c| c.button(Button::Back) && c.button(Button::Start))
        {
            user_exit = true;
        }
        if user_exit {
            break;
        }
        let now = Instant::now();
        if !paused {
            animation += now.duration_since(last);
        }
        last = now;
        // Exactly pack_frames.gd's tick/fps/duration sampling (presentation clock only).
        let tick = (animation.as_secs_f64() * 60.0).floor();
        let fps = idle["fps"].as_f64().unwrap_or(0.0);
        let total: f64 = frames
            .iter()
            .map(|f| f["duration"].as_f64().unwrap_or(1.0))
            .sum();
        if total <= 0.0 {
            return Err("invalid animation duration".into());
        }
        let mut position = (tick * fps / 60.0).max(0.0);
        if idle["loop"].as_bool().unwrap_or(true) {
            position %= total;
        } else {
            position = position.min(total);
        }
        let mut end = 0.0;
        let index = frames
            .iter()
            .position(|f| {
                end += f["duration"].as_f64().unwrap_or(1.0);
                position < end
            })
            .unwrap_or(frames.len() - 1);
        let (w, h) = dimensions[index];
        let (width, height) = platform.canvas.output_size()?;
        platform.canvas.set_draw_color(Color::RGB(0, 8, 48));
        platform.canvas.clear();
        // Original pixels and origins at density1; no synthetic art, no scene/game claim.
        let origin = &frames[index]["origin"];
        let x = width as f64 / 2.0 - origin[0].as_f64().unwrap_or(0.0) / pack.density as f64;
        let y = height as f64 / 2.0 - origin[1].as_f64().unwrap_or(0.0) / pack.density as f64;
        platform.canvas.copy(
            &textures[index],
            None,
            Rect::new(
                x.round() as i32,
                y.round() as i32,
                w / pack.density,
                h / pack.density,
            ),
        )?;
        if !captured && let Some(path) = &capture {
            let pixels = platform
                .canvas
                .read_pixels(None, sdl2::pixels::PixelFormatEnum::RGBA32)?;
            let file = std::fs::File::create(path).map_err(|e| e.to_string())?;
            let mut encoder = png::Encoder::new(file, width, height);
            encoder.set_color(png::ColorType::Rgba);
            let mut writer = encoder.write_header().map_err(|e| e.to_string())?;
            writer
                .write_image_data(&pixels)
                .map_err(|e| e.to_string())?;
            println!("RUST_CAPTURE mode=GPU-readback-not-clean-timing path={path:?}");
            captured = true;
        }
        platform.canvas.present();
        frames_drawn += 1;
        if last_report.elapsed() >= Duration::from_secs(1) {
            println!(
                "RUST_SMOKE_PROGRESS elapsed_ms={} presented_frames={frames_drawn} input_events={input_events} paused={paused}",
                ready.elapsed().as_millis()
            );
            std::io::stdout().flush().map_err(|e| e.to_string())?;
            last_report = Instant::now();
        }
        // SDL vsync may not block on all compositors. Smoke is not a throughput test.
        std::thread::sleep(Duration::from_millis(1));
    }
    if frames_drawn == 0 {
        return Err("no private asset frame presented".into());
    }
    println!(
        "RUST_SMOKE_DONE mode=presentation-only-not-gameplay elapsed_ms={} presented_frames={frames_drawn} input_events={input_events} user_exit={user_exit} input_acceptance=enumerated-not-physical audio=disabled",
        ready.elapsed().as_millis()
    );
    std::io::stdout().flush().map_err(|e| e.to_string())?;
    Ok(())
}

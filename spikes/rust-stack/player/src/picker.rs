//! `--levels`: the level list screen. Shows the bundle's level index (menu.rs) and writes
//! the chosen level's file name to `--choice`; the launcher then plays it and comes back.
//! Controls: D-pad up/down move (held: repeat), L1/R1 page, A or Start play, B back,
//! Select+Start quit. Keyboard on a host: arrows, Page Up/Down, Enter, Backspace, Escape.
use crate::{
    binding::Catalog,
    gles::Gles,
    hud::Font,
    level_list::Entry,
    menu::{Model, Request, View},
    pack::{Image, Pack},
    timing::{Samples, Timer},
};
use sdl2::{controller::Button, event::Event, keyboard::Keycode};
use std::{
    io::Write,
    path::PathBuf,
    time::{Duration, Instant},
};

/// Godot's default clear colour (0.3 grey): no level is drawn behind the menu.
const CLEAR: [u8; 3] = [77, 77, 77];
/// Held D-pad repeat: first repeat after this delay, then at this interval.
const REPEAT_DELAY: Duration = Duration::from_millis(300);
const REPEAT_EVERY: Duration = Duration::from_millis(60);
/// Frames between scripted commands (shots mode).
const SCRIPT_FRAMES: u64 = 12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Command {
    Up,
    Down,
    PageUp,
    PageDown,
    Confirm,
    Back,
    Quit,
}
fn parse_command(text: &str) -> Result<Command, String> {
    Ok(match text {
        "up" => Command::Up,
        "down" => Command::Down,
        "page_up" => Command::PageUp,
        "page_down" => Command::PageDown,
        "confirm" => Command::Confirm,
        "back" => Command::Back,
        "quit" => Command::Quit,
        _ => return Err(format!("unknown menu command: {text}")),
    })
}

/// The menu command of a host key: arrows, Page Up/Down, Enter, Backspace, Escape.
pub(crate) fn key_command(key: Keycode) -> Option<Command> {
    Some(match key {
        Keycode::Up => Command::Up,
        Keycode::Down => Command::Down,
        Keycode::PageUp => Command::PageUp,
        Keycode::PageDown => Command::PageDown,
        Keycode::Return | Keycode::KpEnter | Keycode::Space => Command::Confirm,
        Keycode::Backspace => Command::Back,
        Keycode::Escape => Command::Quit,
        _ => return None,
    })
}

/// `--next-level INDEX FILE`: prints the next playable file after FILE in the index
/// (level_list.gd next_index over playable entries), or nothing at the end.
pub fn next_level(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let args: Vec<String> = arguments.collect();
    if args.len() != 2 {
        return Err("--next-level INDEX FILE".into());
    }
    let parsed: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&args[0]).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let levels: Vec<Entry> = serde_json::from_value(parsed["levels"].clone())
        .map_err(|e| format!("level index: {e}"))?;
    if let Some(next) = next_playable(&levels, &args[1]) {
        println!("{next}");
    }
    Ok(())
}
/// The next playable entry after `file`; None when `file` is unlisted or last.
pub fn next_playable<'a>(levels: &'a [Entry], file: &str) -> Option<&'a str> {
    let at = levels.iter().position(|e| e.file == file)?;
    levels[at + 1..]
        .iter()
        .find(|e| e.ok)
        .map(|e| e.file.as_str())
}

/// Controller buttons sampled as held states across every opened handle, so a pad
/// reported through two interfaces gives one command per press.
pub(crate) struct Pad {
    controllers: Vec<sdl2::controller::GameController>,
    held: [bool; 8],
    since: [Option<Instant>; 2],
    last_repeat: [Option<Instant>; 2],
    chord: bool,
}
const PAD_BUTTONS: [Button; 8] = [
    Button::DPadUp,
    Button::DPadDown,
    Button::LeftShoulder,
    Button::RightShoulder,
    Button::A,
    Button::B,
    Button::Start,
    Button::Guide,
];
impl Pad {
    pub(crate) fn open(sdl: &sdl2::Sdl) -> Result<Self, String> {
        let js = sdl.joystick()?;
        let gc = sdl.game_controller()?;
        let mut controllers = Vec::new();
        for i in 0..js.num_joysticks()? {
            if gc.is_game_controller(i) {
                controllers.push(gc.open(i).map_err(|e| e.to_string())?);
            }
        }
        println!("RUST_LEVELS_INPUT controllers={}", controllers.len());
        Ok(Self {
            controllers,
            held: [false; 8],
            since: [None; 2],
            last_repeat: [None; 2],
            chord: false,
        })
    }
    pub(crate) fn commands(&mut self, now: Instant, out: &mut Vec<Command>) {
        let pressed = |b: Button| self.controllers.iter().any(|c| c.button(b));
        let back_held = pressed(Button::Back);
        let state: [bool; 8] = PAD_BUTTONS.map(pressed);
        for (i, &down) in state.iter().enumerate() {
            let edge = down && !self.held[i];
            if edge {
                out.push(match PAD_BUTTONS[i] {
                    Button::DPadUp => Command::Up,
                    Button::DPadDown => Command::Down,
                    Button::LeftShoulder => Command::PageUp,
                    Button::RightShoulder => Command::PageDown,
                    Button::A => Command::Confirm,
                    Button::B => Command::Back,
                    // With Select held, Start is the quit chord below.
                    Button::Start if back_held => continue,
                    Button::Start => Command::Confirm,
                    _ => Command::Quit,
                });
            }
            if i < 2 {
                if edge {
                    self.since[i] = Some(now);
                    self.last_repeat[i] = None;
                } else if down && let Some(start) = self.since[i] {
                    let due = match self.last_repeat[i] {
                        None => now.duration_since(start) >= REPEAT_DELAY,
                        Some(last) => now.duration_since(last) >= REPEAT_EVERY,
                    };
                    if due {
                        self.last_repeat[i] = Some(now);
                        out.push(if i == 0 { Command::Up } else { Command::Down });
                    }
                } else if !down {
                    self.since[i] = None;
                }
            }
        }
        // Select+Start quits, whichever of the two is pressed last.
        let chord = back_held && state[6];
        if chord && !self.chord {
            out.push(Command::Quit);
        }
        self.chord = chord;
        self.held = state;
    }
}

pub fn run(arguments: impl Iterator<Item = String>) -> Result<(), String> {
    let mut args = arguments;
    let mut index = None;
    let mut pack_root = None;
    let mut inventory = None;
    let mut metrics = None;
    let mut choice = None;
    let mut focus = None;
    let mut status = String::new();
    let mut seconds = 900u64;
    let mut fullscreen = true;
    let mut script: Vec<Command> = Vec::new();
    let mut dump: Option<PathBuf> = None;
    while let Some(key) = args.next() {
        let mut value = || args.next().ok_or(format!("{key} needs a value"));
        match key.as_str() {
            "--index" => index = Some(PathBuf::from(value()?)),
            "--pack-root" => pack_root = Some(PathBuf::from(value()?)),
            "--pack-inventory" => inventory = Some(PathBuf::from(value()?)),
            "--view-metrics" => metrics = Some(PathBuf::from(value()?)),
            "--choice" => choice = Some(PathBuf::from(value()?)),
            "--focus" => focus = Some(value()?),
            "--status" => status = value()?,
            "--seconds" => {
                seconds = value()?
                    .parse()
                    .ok()
                    .filter(|s| (1..=900).contains(s))
                    .ok_or("--seconds must be 1..900")?
            }
            "--script" => {
                script = value()?
                    .split(',')
                    .filter(|s| !s.is_empty())
                    .map(parse_command)
                    .collect::<Result<_, _>>()?
            }
            "--frame-dump-dir" => dump = Some(PathBuf::from(value()?)),
            "--windowed" => fullscreen = false,
            _ => return Err(format!("unrecognized level list argument: {key}")),
        }
    }
    let index = index.ok_or("--index required")?;
    let choice = choice.ok_or("--choice required")?;
    let parsed: serde_json::Value =
        serde_json::from_slice(&std::fs::read(&index).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let levels: Vec<Entry> = serde_json::from_value(parsed["levels"].clone())
        .map_err(|e| format!("level index: {e}"))?;
    let pack = Pack::open(
        &pack_root.ok_or("--pack-root required")?,
        &inventory.ok_or("--pack-inventory required")?,
    )?;
    let mut catalog = Catalog::default();
    let font = Font::prepare(
        &pack.manifest,
        &mut catalog,
        &metrics.ok_or("--view-metrics required")?,
    )?;
    let mut gpu = Gles::open_game(fullscreen, true)?;
    let font_image = pack.png(&catalog.files[font.image()])?;
    let font_size = [font_image.width as f64, font_image.height as f64];
    if gpu.upload(&font_image)? != 0 {
        return Err("font image binding mismatch".into());
    }
    let solid = gpu.upload(&Image {
        width: 1,
        height: 1,
        rgba: vec![255; 4],
        sha256: String::new(),
    })?;
    let mut model = Model::open(levels, focus.as_deref());
    model.status = status;
    let mut view = View::new(font, font_size, pack.density > 1);
    let mut pad = Pad::open(&gpu.sdl)?;
    let mut events = gpu.sdl.event_pump()?;
    let started = Instant::now();
    println!(
        "RUST_LEVELS_READY levels={} playable={} scripted={}",
        model.levels.len(),
        model.playable(),
        !script.is_empty()
    );
    std::io::stdout().flush().map_err(|e| e.to_string())?;
    let mut draw = Samples::default();
    let mut frames = 0u64;
    let mut script_at = 0usize;
    let mut chosen: Option<String> = None;
    let mut quit = false;
    let mut quads = Vec::new();
    let mut commands = Vec::new();
    while started.elapsed() < Duration::from_secs(seconds) {
        commands.clear();
        for event in events.poll_iter() {
            match event {
                Event::Quit { .. } => commands.push(Command::Quit),
                Event::KeyDown {
                    keycode: Some(key), ..
                } => commands.extend(key_command(key)),
                _ => {}
            }
        }
        pad.commands(Instant::now(), &mut commands);
        let shot = !script.is_empty() && frames > 0 && frames.is_multiple_of(SCRIPT_FRAMES);
        if shot {
            if let Some(dir) = &dump {
                std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
                gpu.frame_digest(Some(&dir.join(format!("levels-{script_at:03}.png"))))?;
            }
            match script.get(script_at) {
                Some(c) => commands.push(*c),
                None => quit = true,
            }
            script_at += 1;
        }
        for command in commands.drain(..) {
            match command {
                Command::Up => model.step(-1),
                Command::Down => model.step(1),
                Command::PageUp => model.page_step(-1, view.visible_rows),
                Command::PageDown => model.page_step(1, view.visible_rows),
                Command::Back => {
                    model.back();
                }
                Command::Quit => quit = true,
                Command::Confirm => match model.confirm() {
                    Request::Open(i) => chosen = Some(model.levels[i].file.clone()),
                    Request::Quit => quit = true,
                    _ => {}
                },
            }
            println!("RUST_LEVELS_COMMAND {command:?} focus={}", model.focused());
        }
        if quit || chosen.is_some() {
            break;
        }
        let timer = Timer::new();
        let container = gpu.begin(CLEAR)?;
        quads.clear();
        view.emit(
            &model,
            [container[0] as f64, container[1] as f64],
            solid,
            &mut quads,
        )?;
        gpu.draw(&quads)?;
        draw.add(timer.finish());
        gpu.present()?;
        frames += 1;
    }
    if let Some(file) = &chosen {
        std::fs::write(&choice, file).map_err(|e| e.to_string())?;
    }
    println!(
        "RUST_LEVELS_SUMMARY {}",
        serde_json::json!({"frames":frames,"chosen":chosen,"quit":quit,"draw_submit":draw.summary(),"wall_ms":started.elapsed().as_millis()})
    );
    std::io::stdout().flush().map_err(|e| e.to_string())?;
    Ok(())
}

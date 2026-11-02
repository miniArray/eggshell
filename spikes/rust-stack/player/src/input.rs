//! SDL input adapter. Core owns gameplay held/released edge semantics.
use crate::feel::ButtonLayout;
use sdl2::{
    controller::{Axis, Button, GameController},
    event::Event,
    joystick::Joystick,
    keyboard::Keycode,
};
use std::{
    collections::{BTreeSet, VecDeque},
    path::Path,
};

pub struct Controls {
    controllers: Vec<GameController>,
    _joysticks: Vec<Joystick>,
    keyboard: u8,
    jump: JumpSteps,
    previous_actions: u16,
    layout: ButtonLayout,
    wait_faces: bool,
    pub events: u64,
    pub repeat_events: u64,
    pub pause_toggle: bool,
    pub menu_mask: u8,
    pub exit: bool,
    pub zoom_delta: i32,
    pub zoom_reset: bool,
    pub save: bool,
    pub restore: bool,
}
// Literal src/sim/move_input.gd bits and src/view/game.gd mappings.
pub const LEFT: u8 = 1;
pub const RIGHT: u8 = 2;
pub const JUMP: u8 = 4;
pub const USE: u8 = 8;
pub const UP: u8 = 16;
pub const DOWN: u8 = 32;
pub const THROW: u8 = 64;
pub const LOCK: u8 = 128;
impl Controls {
    pub fn open(sdl: &sdl2::Sdl) -> Result<Self, String> {
        let js = sdl.joystick()?;
        let gc = sdl.game_controller()?;
        let mut controllers = Vec::new();
        let mut joysticks = Vec::new();
        let count = js.num_joysticks()?;
        println!("RUST_OWNED_INPUT_ENUM count={count}");
        for i in 0..count {
            let joy = js.open(i).map_err(|e| e.to_string())?;
            println!(
                "RUST_OWNED_INPUT index={i} name={:?} guid={} axes={} buttons={} hats={} controller={}",
                joy.name(),
                joy.guid(),
                joy.num_axes(),
                joy.num_buttons(),
                joy.num_hats(),
                gc.is_game_controller(i)
            );
            if gc.is_game_controller(i) {
                let c = gc.open(i).map_err(|e| e.to_string())?;
                println!("RUST_OWNED_MAPPING index={i} mapping={:?}", c.mapping());
                controllers.push(c);
            }
            joysticks.push(joy);
        }
        if joysticks.is_empty() {
            return Err("built-in input enumeration gate failed".into());
        }
        if controllers.is_empty() {
            return Err("built-in controller unmapped; explicit mapping required (raw enumerated, never silently guessed)".into());
        }
        Ok(Self {
            controllers,
            _joysticks: joysticks,
            keyboard: 0,
            jump: JumpSteps::default(),
            previous_actions: 0,
            layout: ButtonLayout::default(),
            wait_faces: false,
            events: 0,
            repeat_events: 0,
            pause_toggle: false,
            menu_mask: 0,
            exit: false,
            zoom_delta: 0,
            zoom_reset: false,
            save: false,
            restore: false,
        })
    }
    /// Consume exactly once per simulation call, not once per render/event batch.
    pub fn step_mask(&mut self, live: u8) -> u8 {
        self.jump.next_mask(live)
    }
    pub fn clear_steps(&mut self) {
        self.jump.pending.clear();
    }
    pub fn reset_actions(&mut self) {
        self.pause_toggle = false;
        self.zoom_delta = 0;
        self.zoom_reset = false;
        self.save = false;
        self.restore = false;
    }
    pub fn event(&mut self, event: Event) {
        let keymask = |k| match k {
            Keycode::Left | Keycode::A => LEFT,
            Keycode::Right | Keycode::D => RIGHT,
            Keycode::Space | Keycode::Z => JUMP,
            Keycode::LShift | Keycode::X => USE,
            Keycode::Down | Keycode::S => DOWN,
            Keycode::Up | Keycode::W => UP,
            Keycode::C => THROW,
            Keycode::V => LOCK,
            _ => 0,
        };
        match event {
            Event::Quit { .. } => self.exit = true,
            Event::KeyDown {
                keycode: Some(key),
                repeat,
                ..
            } => {
                if repeat {
                    self.repeat_events += 1;
                    return;
                }
                self.events += 1;
                if keymask(key) == JUMP {
                    self.jump.event(key_source(key), true);
                }
                self.keyboard |= keymask(key) & !JUMP;
                match key {
                    Keycode::Escape => self.exit = true,
                    Keycode::P => self.pause_toggle = !self.pause_toggle,
                    Keycode::Equals | Keycode::KpPlus => self.zoom_delta += 1,
                    Keycode::Minus | Keycode::KpMinus => self.zoom_delta -= 1,
                    Keycode::Num0 | Keycode::Kp0 => self.zoom_reset = true,
                    Keycode::F5 => self.save = true,
                    Keycode::F9 => self.restore = true,
                    _ => {}
                }
            }
            Event::KeyUp {
                keycode: Some(key), ..
            } => {
                self.events += 1;
                if keymask(key) == JUMP {
                    self.jump.event(key_source(key), false);
                }
                self.keyboard &= !keymask(key);
            }
            Event::ControllerButtonDown { which, button, .. } => {
                self.events += 1;
                if [Button::A, Button::B].contains(&button) {
                    self.jump.event(pad_source(which, button), true);
                }
            }
            Event::ControllerButtonUp { which, button, .. } => {
                self.events += 1;
                if [Button::A, Button::B].contains(&button) {
                    self.jump.event(pad_source(which, button), false);
                }
            }
            Event::ControllerAxisMotion { .. } => self.events += 1,
            Event::Window {
                win_event: sdl2::event::WindowEvent::FocusLost,
                ..
            } => {
                self.keyboard = 0;
                let pads: Vec<_> = self
                    .jump
                    .sources
                    .iter()
                    .copied()
                    .filter(|id| *id < (1_u64 << 63))
                    .collect();
                self.jump.sample(pads);
                self.jump.pending.clear();
            }
            _ => {}
        }
    }
    /// Call once after each event batch. OR held states across device handles,
    /// then sample action edges once; duplicate interfaces cannot double-toggle.
    pub fn mask(&mut self, layout: ButtonLayout) -> u8 {
        let pressed = |b| self.controllers.iter().any(|c| c.button(layout.button(b)));
        if layout != self.layout {
            self.wait_faces = true;
            self.layout = layout;
        }
        if ![Button::A, Button::B, Button::X, Button::Y]
            .into_iter()
            .any(pressed)
        {
            self.wait_faces = false;
        }
        let axis = |a, positive| {
            self.controllers.iter().any(|c| {
                if positive {
                    c.axis(a) > 8191
                } else {
                    c.axis(a) < -8191
                }
            })
        };
        let back = pressed(Button::Back);
        let start = pressed(Button::Start);
        if back && start || pressed(Button::Guide) {
            self.exit = true;
        }
        // Reconcile dropped events/focus changes atomically with the authoritative
        // SDL held snapshot, without erasing transitions already captured in order.
        let mut sources: Vec<u64> = self
            .controllers
            .iter()
            .flat_map(|c| {
                [Button::A, Button::B]
                    .into_iter()
                    .filter(|b| c.button(*b))
                    .map(|b| pad_source(c.instance_id(), b))
            })
            .collect();
        sources.extend(
            self.jump
                .sources
                .iter()
                .copied()
                .filter(|id| *id >= (1_u64 << 63)),
        );
        let keyboard = self.keyboard
            | if sources.iter().any(|id| *id >= (1_u64 << 63)) {
                JUMP
            } else {
                0
            };
        self.jump.sample(sources);
        let faces = face_masks(layout, |b| self.controllers.iter().any(|c| c.button(b)));
        let mut result = keyboard;
        for (held, bit) in [
            (pressed(Button::DPadLeft) || axis(Axis::LeftX, false), LEFT),
            (pressed(Button::DPadRight) || axis(Axis::LeftX, true), RIGHT),
            (faces.0 & JUMP != 0, JUMP),
            (faces.0 & USE != 0, USE),
            (pressed(Button::DPadUp) || axis(Axis::LeftY, false), UP),
            (pressed(Button::DPadDown) || axis(Axis::LeftY, true), DOWN),
            (pressed(Button::LeftShoulder) && !back, THROW),
            (pressed(Button::RightShoulder) && !back, LOCK),
        ] {
            if held {
                result |= bit;
            }
        }
        // A and B are separate on the paused page, even though both jump in play.
        self.menu_mask = result & (LEFT | RIGHT | UP | DOWN);
        if keyboard & JUMP != 0 || (!self.wait_faces && faces.1 & JUMP != 0) {
            self.menu_mask |= JUMP;
        }
        if keyboard & USE != 0 || (!self.wait_faces && faces.1 & USE != 0) {
            self.menu_mask |= USE;
        }
        // Slot chords suppress keyboard throw/lock as the reference global action does.
        if back {
            result &= !(THROW | LOCK);
        }
        // Right stick up or R2 zooms in; right stick down or L2 zooms out. The H700
        // pad reports L2/R2 as digital keys that SDL maps to full trigger axes.
        let zoom_up = self
            .controllers
            .iter()
            .any(|c| c.axis(Axis::RightY) < -19660 || c.axis(Axis::TriggerRight) > 16384);
        let zoom_down = self
            .controllers
            .iter()
            .any(|c| c.axis(Axis::RightY) > 19660 || c.axis(Axis::TriggerLeft) > 16384);
        let states = [
            start,
            back && pressed(Button::LeftShoulder),
            back && pressed(Button::RightShoulder),
            pressed(Button::RightStick),
            zoom_up,
            zoom_down,
        ];
        let flags = states
            .iter()
            .enumerate()
            .fold(0u16, |a, (i, v)| a | ((*v as u16) << i));
        let edges = flags & !self.previous_actions;
        self.previous_actions = flags;
        if edges & 1 != 0 {
            self.pause_toggle = !self.pause_toggle;
        }
        if edges & 2 != 0 {
            self.save = true;
        }
        if edges & 4 != 0 {
            self.restore = true;
        }
        if edges & 8 != 0 {
            self.zoom_reset = true;
        }
        if edges & 16 != 0 {
            self.zoom_delta += 1;
        }
        if edges & 32 != 0 {
            self.zoom_delta -= 1;
        }
        result
    }
}
fn pad_source(id: u32, button: Button) -> u64 {
    (u64::from(id) << 8) | button as u64
}
fn key_source(key: Keycode) -> u64 {
    (1_u64 << 63) | key.into_i32() as u32 as u64
}

/// Preserve aggregate jump transitions until a successful simulation call can
/// consume each one. A/B and duplicate interfaces still form one held action.
#[derive(Default)]
struct JumpSteps {
    sources: BTreeSet<u64>,
    pending: VecDeque<bool>,
}
impl JumpSteps {
    fn event(&mut self, source: u64, down: bool) {
        let was = !self.sources.is_empty();
        if down {
            self.sources.insert(source);
        } else {
            self.sources.remove(&source);
        }
        let held = !self.sources.is_empty();
        if was != held {
            self.pending.push_back(held);
        }
    }
    fn sample(&mut self, sources: impl IntoIterator<Item = u64>) {
        let was = !self.sources.is_empty();
        self.sources = sources.into_iter().collect();
        let held = !self.sources.is_empty();
        if was != held {
            self.pending.push_back(held);
        }
    }
    fn next_mask(&mut self, live: u8) -> u8 {
        let held = self.pending.pop_front().unwrap_or(!self.sources.is_empty());
        (live & !JUMP) | if held { JUMP } else { 0 }
    }
}

/// Shared label mapping for live gameplay and Feel input. Gameplay deliberately
/// aliases A/B to jump and X/Y to use, as in the reference; menus keep A/B distinct.
pub fn face_masks(layout: ButtonLayout, physical: impl Fn(Button) -> bool) -> (u8, u8) {
    let pressed = |b| physical(layout.button(b));
    let play = if pressed(Button::A) || pressed(Button::B) {
        JUMP
    } else {
        0
    } | if pressed(Button::X) || pressed(Button::Y) {
        USE
    } else {
        0
    };
    let menu = if pressed(Button::A) { JUMP } else { 0 } | if pressed(Button::B) { USE } else { 0 };
    (play, menu)
}
pub fn replay(path: &Path) -> Result<Vec<u8>, String> {
    let data = std::fs::read(path).map_err(|e| e.to_string())?;
    let masks: Vec<u8> = serde_json::from_slice(&data)
        .map_err(|e| format!("input replay must be literal eight-bit mask array: {e}"))?;
    if masks.is_empty() {
        return Err("empty input replay not an active benchmark".into());
    }
    println!(
        "RUST_REPLAY sha256={} ticks={} format=literal-u8-masks position_playback=false",
        crate::pack::hash(&data),
        masks.len()
    );
    Ok(masks)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn layouts_swap_labels_for_faces_and_keep_reference_gameplay_aliases() {
        for (button, snes, xbox) in [
            (Button::A, (JUMP, JUMP), (JUMP, USE)),
            (Button::B, (JUMP, USE), (JUMP, JUMP)),
            (Button::X, (USE, 0), (USE, 0)),
            (Button::Y, (USE, 0), (USE, 0)),
        ] {
            assert_eq!(face_masks(ButtonLayout::Snes, |b| b == button), snes);
            assert_eq!(face_masks(ButtonLayout::Xbox, |b| b == button), xbox);
        }
        for button in [
            Button::A,
            Button::B,
            Button::X,
            Button::Y,
            Button::Start,
            Button::LeftShoulder,
        ] {
            assert_eq!(
                ButtonLayout::Xbox.button(ButtonLayout::Xbox.button(button)),
                button
            );
        }
        assert_eq!(ButtonLayout::Xbox.button(Button::X), Button::Y);
        assert_eq!(ButtonLayout::Xbox.button(Button::Y), Button::X);
    }

    #[test]
    fn releases_and_presses_survive_batches_without_steps_and_aliases_do_not_retrigger() {
        let mut steps = JumpSteps::default();
        steps.event(1, true);
        assert_eq!(steps.next_mask(RIGHT | JUMP), RIGHT | JUMP);
        steps.event(1, false);
        steps.event(1, true);
        steps.sample([1]); // sampling while no step owed must not drain the queue
        steps.sample([1]);
        assert_eq!(steps.next_mask(JUMP), 0);
        assert_eq!(steps.next_mask(JUMP), JUMP);
        assert_eq!(steps.next_mask(JUMP), JUMP);
        steps.event(2, true); // B held while A releases: reference OR alias, no new edge
        steps.event(1, false);
        assert_eq!(steps.next_mask(JUMP), JUMP);
        steps.event(2, false);
        assert_eq!(steps.next_mask(0), 0);
        steps.event(1, true);
        steps.event(1, false); // complete quick tap between steps still reaches sim
        assert_eq!(steps.next_mask(0), JUMP);
        assert_eq!(steps.next_mask(0), 0);
    }
    #[test]
    fn input_bits_match_reference_order() {
        assert_eq!(
            [
                super::LEFT,
                super::RIGHT,
                super::JUMP,
                super::USE,
                super::UP,
                super::DOWN,
                super::THROW,
                super::LOCK
            ],
            [1, 2, 4, 8, 16, 32, 64, 128]
        );
    }
}

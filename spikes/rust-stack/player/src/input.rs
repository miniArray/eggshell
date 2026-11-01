//! SDL input adapter. Core owns gameplay held/released edge semantics.
use sdl2::{
    controller::{Axis, Button, GameController},
    event::Event,
    joystick::Joystick,
    keyboard::Keycode,
};
use std::path::Path;

pub struct Controls {
    controllers: Vec<GameController>,
    _joysticks: Vec<Joystick>,
    keyboard: u8,
    previous_actions: u16,
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
            previous_actions: 0,
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
                self.keyboard |= keymask(key);
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
                self.keyboard &= !keymask(key);
            }
            Event::ControllerButtonDown { .. }
            | Event::ControllerButtonUp { .. }
            | Event::ControllerAxisMotion { .. } => self.events += 1,
            Event::Window {
                win_event: sdl2::event::WindowEvent::FocusLost,
                ..
            } => self.keyboard = 0,
            _ => {}
        }
    }
    /// Call once after each event batch. OR held states across device handles,
    /// then sample action edges once; duplicate interfaces cannot double-toggle.
    pub fn mask(&mut self) -> u8 {
        let pressed = |b| self.controllers.iter().any(|c| c.button(b));
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
        let mut result = self.keyboard;
        for (held, bit) in [
            (pressed(Button::DPadLeft) || axis(Axis::LeftX, false), LEFT),
            (pressed(Button::DPadRight) || axis(Axis::LeftX, true), RIGHT),
            (pressed(Button::A) || pressed(Button::B), JUMP),
            (pressed(Button::X) || pressed(Button::Y), USE),
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
        if self.keyboard & JUMP != 0 || pressed(Button::A) {
            self.menu_mask |= JUMP;
        }
        if self.keyboard & USE != 0 || pressed(Button::B) {
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

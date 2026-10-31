//! timed_switch.gd (o14): a modal press animation followed by a shared, restartable
//! switch interval that toggles o15 linked blocks and dotted coins.
use crate::{
    blocks::BlockKind, entity::Kind, items::PickupKind, state::Run, Error, Placement, SCALE as S,
};
const READY: i64 = 0;
const FLATTEN: i64 = 1;
const UNFLATTEN: i64 = 2;
const HIDDEN: i64 = 3;
const BOX: [i64; 4] = [-20 * S, -26 * S, 20 * S, 16 * S];
const INTERVAL: i64 = 630;
const JUMP: i64 = 4;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Switch {
    pub repeat: i64,
    pub phase: i64,
    pub ticks: i64,
    pub press_y: i64,
}

/// timed_switch.gd LEVEL_FIELDS: the shared interval and its own sound channel.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Clock {
    pub ticks: i64,
    pub sound_serial: i64,
    pub sound_kind: i64,
    pub sound_x: i64,
    pub sound_y: i64,
}

impl Clock {
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "switch_ticks" => self.ticks,
            "switch_sound_serial" => self.sound_serial,
            "switch_sound_kind" => self.sound_kind,
            "switch_sound_x" => self.sound_x,
            "switch_sound_y" => self.sound_y,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "switch_ticks" => self.ticks = value,
            "switch_sound_serial" => self.sound_serial = value,
            "switch_sound_kind" => self.sound_kind = value,
            "switch_sound_x" => self.sound_x = value,
            "switch_sound_y" => self.sound_y = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..=INTERVAL).contains(&self.ticks)
            && self.sound_serial >= 0
            && (0..=3).contains(&self.sound_kind)
    }
    /// timed_switch.gd _sound
    fn sound(&mut self, kind: i64, x: i64, y: i64) {
        self.sound_serial = if self.sound_serial == i64::MAX {
            1
        } else {
            self.sound_serial + 1
        };
        self.sound_kind = kind;
        self.sound_x = x;
        self.sound_y = y;
    }
}

/// timed_switch.gd _flatten / _unflatten (S-scaled amounts).
fn flatten(tick: i64) -> Result<i64, Error> {
    crate::math::sine(tick * 90_000 / 18, 360_000, S)
}
fn unflatten(tick: i64) -> Result<i64, Error> {
    Ok(S - crate::math::sine(90_000 + tick * 90_000 / 9, 360_000, S)?)
}

impl Switch {
    /// timed_switch.gd prepare + create. F above 1 degrades in Godot; refused here.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        if !(0..=1).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("switch form F={}", p.variant)],
            });
        }
        Ok(Self {
            repeat: i64::from(p.variant == 1),
            phase: READY,
            ticks: 0,
            press_y: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        if self.phase == HIDDEN {
            [0; 4]
        } else {
            BOX
        }
    }
    /// timed_switch.gd view_state: (visible, frame, size in pixels).
    pub fn view(&self) -> Result<(bool, i64, [f64; 2]), Error> {
        let (amount, frame) = match self.phase {
            FLATTEN => (flatten(self.ticks)?, self.repeat + 2),
            UNFLATTEN => (S - unflatten(self.ticks)?, 4),
            _ => (0, self.repeat),
        };
        Ok((
            self.phase != HIDDEN,
            frame,
            [
                40.0 + 32.0 * amount as f64 / S as f64,
                42.0 - 24.0 * amount as f64 / S as f64,
            ],
        ))
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "repeat" => self.repeat,
            "phase" => self.phase,
            "ticks" => self.ticks,
            "press_y" => self.press_y,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "repeat" => self.repeat = value,
            "phase" => self.phase = value,
            "ticks" => self.ticks = value,
            "press_y" => self.press_y = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        [0, 1].contains(&self.repeat)
            && (READY..=HIDDEN).contains(&self.phase)
            && (0..=18).contains(&self.ticks)
    }
}

impl Run {
    fn switch(&mut self, index: usize) -> &mut Switch {
        match &mut self.entities[index].kind {
            Kind::Switch(s) => s,
            _ => unreachable!("switch index"),
        }
    }
    /// registry.gd toggle_switch: every toggle type in table order (item_block.gd o15,
    /// pickup.gd dotted coins). Solid rows are refreshed by the caller.
    pub(crate) fn toggle_switch(&mut self) -> Vec<usize> {
        let pb = self.player.bounds();
        let p = self.player.body;
        let player = [p.x + pb[0], p.y + pb[1], p.x + pb[2], p.y + pb[3]];
        let mut blocks = Vec::new();
        for (index, e) in self.entities.iter_mut().enumerate() {
            match &mut e.kind {
                Kind::Block(b) if b.kind == BlockKind::Linked => {
                    b.enabled = 1 - b.enabled;
                    let r = b.bounds();
                    let overlaps = e.body.x + r[2] > player[0]
                        && e.body.x + r[0] < player[2]
                        && e.body.y + r[3] > player[1]
                        && e.body.y + r[1] < player[3];
                    b.solid_ready = i64::from(b.enabled != 0 && !overlaps);
                    blocks.push(index);
                }
                Kind::Pickup(p) if p.kind != PickupKind::Flower && p.moving == 0 => {
                    p.phase = 0;
                    if p.dotted != 0 && e.collected == 0 {
                        p.enabled = 1 - p.enabled;
                    }
                }
                _ => {}
            }
        }
        blocks
    }
    /// timed_switch.gd step.
    pub(crate) fn switch_step(&mut self, index: usize, map: &crate::body::Probe) {
        // _clock_owner: the first standing switch in table order runs the interval.
        let owner = self
            .entities
            .iter()
            .position(|o| matches!(o.kind, Kind::Switch(_)) && o.status == 1);
        if owner == Some(index) && self.clock.ticks != 0 {
            self.clock.ticks -= 1;
            if self.clock.ticks == 0 {
                for block in self.toggle_switch() {
                    self.refresh_block_solid(block, map);
                }
                self.clock.sound(3, 0, 0);
                for o in &mut self.entities {
                    let Kind::Switch(s) = &mut o.kind else {
                        continue;
                    };
                    if s.phase != HIDDEN {
                        continue;
                    }
                    if s.repeat != 0 {
                        s.phase = READY;
                        o.body.y -= 16 * S;
                        o.can_despawn = 1;
                        o.body.vy = 0;
                    } else {
                        o.status = 3;
                    }
                }
            }
        }
        let e = &mut self.entities[index];
        let Kind::Switch(s) = &e.kind else {
            return;
        };
        if s.phase != READY || e.status != 1 {
            return;
        }
        let body = &mut e.body;
        if body.prepare(map, BOX) {
            let support = body.track(map, BOX, true);
            if support != 0 {
                body.vy = 0;
            }
            let vx = body.vx;
            // collision.gd horizontal defaults.
            body.horizontal(map, BOX, vx, support, crate::body::HorizontalMove::Item);
            let vy = body.vy;
            body.vertical_support(map, BOX, vy, support);
        }
        if body.floor(map, BOX) != 0 {
            body.vy = 0;
        } else {
            body.vy = (body.vy + 2048).min(704 * 60);
        }
    }
    /// timed_switch.gd contact: landing on a ready switch starts the modal press.
    pub(crate) fn switch_contact(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Switch(s) = &e.kind else {
            return;
        };
        let p = self.player.body;
        if s.phase != READY
            || self.message.modal_token != 0
            || self.player.captured_by != 0
            || self.player.blocks_step()
            || p.vy <= e.body.vy
            || p.y >= e.body.y - 8 * S
        {
            return;
        }
        let b = self.player.bounds();
        if p.x + b[2] < e.body.x - 20 * S
            || p.x + b[0] > e.body.x + 20 * S
            || p.y + b[3] < e.body.y - 26 * S
            || p.y + b[1] > e.body.y + 16 * S
        {
            return;
        }
        let token = e.origin.token();
        let e = &mut self.entities[index];
        e.body.y += 16 * S;
        e.can_despawn = 0;
        let s = self.switch(index);
        s.phase = FLATTEN;
        s.ticks = 0;
        s.press_y = p.y;
        self.message.modal_token = token;
        self.player.interrupt();
    }
    /// timed_switch.gd modal_step. True: the step is consumed.
    pub(crate) fn switch_modal_step(&mut self, index: usize, input: i64) -> Result<bool, Error> {
        self.player.previous_input = input;
        self.player.pressed_input = 0;
        let (x, y) = (self.entities[index].body.x, self.entities[index].body.y);
        let s = self.switch(index);
        if s.phase == FLATTEN {
            s.ticks = (s.ticks + 1).min(18);
            let (ticks, press_y) = (s.ticks, s.press_y);
            self.player.body.y = press_y + 24 * S * flatten(ticks)? / S;
            if ticks == 18 {
                let s = self.switch(index);
                s.phase = UNFLATTEN;
                s.ticks = 0;
                self.clock.sound(1, x, y);
                self.sound.emit(3, x, y);
            }
            return Ok(true);
        }
        if s.phase == UNFLATTEN {
            s.ticks = (s.ticks + 1).min(9);
            let (ticks, press_y) = (s.ticks, s.press_y);
            self.player.body.y = press_y + 24 * S * (S - unflatten(ticks)?) / S;
            if ticks == 9 {
                self.switch_finish(index, input);
            }
            return Ok(true);
        }
        self.message.modal_token = 0;
        Ok(false)
    }
    /// timed_switch.gd _finish: start (or restart) the interval and bounce the player.
    fn switch_finish(&mut self, index: usize, input: i64) {
        if self.clock.ticks == 0 {
            // Before collision binding: the next begin_step rebuilds the solid rows.
            self.toggle_switch();
        }
        self.clock.ticks = INTERVAL;
        self.clock.sound(2, 0, 0);
        let s = self.switch(index);
        s.phase = HIDDEN;
        s.ticks = 0;
        let press_y = s.press_y;
        self.message.modal_token = 0;
        let jump = input & JUMP != 0;
        let p = &mut self.player;
        p.body.y = press_y;
        p.body.vy = if jump { -1008 * 60 } else { -448 * 60 };
        p.on_floor = 0;
        p.support_bridge = 0;
        p.jump_buffer = 0;
        p.flutter_ready = 1;
        p.boosted_flutter = i64::from(jump);
    }
}

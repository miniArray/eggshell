//! Held food, eggs, aim and the saved four-request history (moves.gd, move_requests.gd).
//! Requests are latched by serial; consumers poll them with their own saved cursor.
use crate::{
    body::Probe,
    player::{Player, Sound},
    SCALE as S,
};

pub(crate) const EGG: i64 = 1;
pub(crate) const SPIT: i64 = 2;
pub(crate) const SEED: i64 = 3;
pub(crate) const HEAT: i64 = 4;
pub(crate) const COLD: i64 = 5;
pub(crate) const CONSUME: i64 = 6;
pub(crate) const STORED_EGG: i64 = 7;
/// Ammunition kinds held in the mouth (moves.gd SEED/HEAT/COLD).
pub(crate) const AMMO_SEED: i64 = 1;
pub(crate) const AMMO_HEAT: i64 = 2;
pub(crate) const AMMO_COLD: i64 = 3;

// Actions (moves.gd).
pub(crate) const NORMAL: i64 = 0;
pub(crate) const POUND_START: i64 = 1;
pub(crate) const POUND_FALL: i64 = 2;
pub(crate) const POUND_LAND: i64 = 3;
pub(crate) const TONGUE: i64 = 4;
pub(crate) const SPITTING: i64 = 5;
pub(crate) const LAY: i64 = 6;
pub(crate) const EMIT: i64 = 7;
pub(crate) const TOSS: i64 = 8;
pub(crate) const HEAD_BUMP: i64 = 9;
pub(crate) const LAND: i64 = 10;
pub(crate) const SWALLOW: i64 = 11;

// Input bits (move_input.gd).
pub(crate) const UP: u8 = 16;
pub(crate) const DOWN: u8 = 32;
pub(crate) const USE: u8 = 8;
pub(crate) const THROW: u8 = 64;
pub(crate) const LOCK: u8 = 128;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Request {
    pub serial: i64,
    pub kind: i64,
    pub item: i64,
    pub x: i64,
    pub y: i64,
    pub angle: i64,
    pub vx: i64,
    pub vy: i64,
}

/// move_emit_* (slot 0) .. move_emit_3_* (slot 3); slot 0 is the latest.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct Requests {
    pub slots: [Request; 4],
}

#[allow(dead_code)] // Request consumers (enemy bodies, items, eggs) land next in P1.
pub(crate) enum Since {
    Requests(Vec<Request>),
    Error,
}

impl Requests {
    pub fn serial(&self) -> i64 {
        self.slots[0].serial
    }
    #[allow(clippy::too_many_arguments)]
    pub fn emit(&mut self, kind: i64, item: i64, x: i64, y: i64, angle: i64, vx: i64, vy: i64) {
        if self.slots[0].serial == i64::MAX {
            self.slots = [Request::default(); 4];
        }
        for slot in (1..4).rev() {
            self.slots[slot] = self.slots[slot - 1];
        }
        self.slots[0] = Request {
            serial: self.slots[0].serial + 1,
            kind,
            item,
            x,
            y,
            angle,
            vx,
            vy,
        };
    }
    /// Requests newer than `after`, oldest first; `Error` matches the original's
    /// invalid cursor, reset and expired-history cases.
    #[allow(dead_code)]
    pub fn since(&self, after: i64) -> Since {
        let current = self.serial();
        if after < 0 || after > current || current - after > 4 {
            return Since::Error;
        }
        Since::Requests(
            (0..4)
                .rev()
                .map(|slot| self.slots[slot])
                .filter(|r| r.serial > after)
                .collect(),
        )
    }
    pub fn valid(&self) -> bool {
        let latest = self.slots[0].serial;
        latest >= 0
            && self.slots.iter().enumerate().all(|(slot, r)| {
                r.serial == (latest - slot as i64).max(0)
                    && (0..=STORED_EGG).contains(&r.kind)
                    && r.item >= 0
                    && (-180000..=180000).contains(&r.angle)
                    && if r.serial == 0 {
                        *r == Request::default()
                    } else {
                        r.kind != 0
                    }
            })
    }
    pub fn field(&self, name: &str) -> Option<i64> {
        let (slot, part) = split(name)?;
        let r = &self.slots[slot];
        Some(match part {
            "serial" => r.serial,
            "kind" => r.kind,
            "item" => r.item,
            "x" => r.x,
            "y" => r.y,
            "angle" => r.angle,
            "vx" => r.vx,
            "vy" => r.vy,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, name: &str, value: i64) -> bool {
        let Some((slot, part)) = split(name) else {
            return false;
        };
        let r = &mut self.slots[slot];
        let target = match part {
            "serial" => &mut r.serial,
            "kind" => &mut r.kind,
            "item" => &mut r.item,
            "x" => &mut r.x,
            "y" => &mut r.y,
            "angle" => &mut r.angle,
            "vx" => &mut r.vx,
            "vy" => &mut r.vy,
            _ => return false,
        };
        *target = value;
        true
    }
}

fn split(name: &str) -> Option<(usize, &str)> {
    let rest = name.strip_prefix("move_emit_")?;
    for (slot, prefix) in [(1usize, "1_"), (2, "2_"), (3, "3_")] {
        if let Some(part) = rest.strip_prefix(prefix) {
            return Some((slot, part));
        }
    }
    Some((0, rest))
}

/// The mouth state of moves.gd: held food, ammunition, eggs and aim.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Food {
    pub aim: i64,
    pub aim_angle: i64,
    pub aim_dir: i64,
    pub aim_lock: i64,
    pub aim_up: i64,
    pub eggs: i64,
    pub held_id: i64,
    pub digest: i64,
    pub instant: i64,
    pub digest_ticks: i64,
    pub ammo: i64,
    pub ammo_count: i64,
    pub held_speed: i64,
    pub swallow_queue: i64,
    pub spread: i64,
    pub requests: Requests,
}

impl Default for Food {
    fn default() -> Self {
        Self {
            aim: 0,
            aim_angle: 45000,
            aim_dir: -1,
            aim_lock: 0,
            aim_up: 0,
            eggs: 0,
            held_id: 0,
            digest: 0,
            instant: 0,
            digest_ticks: 0,
            ammo: 0,
            ammo_count: 0,
            held_speed: 256 * 60,
            swallow_queue: 0,
            spread: 0,
            requests: Requests::default(),
        }
    }
}

impl Food {
    pub fn full(&self) -> bool {
        self.held_id != 0 || self.ammo_count != 0
    }
    pub fn field(&self, name: &str) -> Option<i64> {
        Some(match name {
            "move_aim" => self.aim,
            "move_aim_angle" => self.aim_angle,
            "move_aim_dir" => self.aim_dir,
            "move_aim_lock" => self.aim_lock,
            "move_aim_up" => self.aim_up,
            "move_eggs" => self.eggs,
            "move_held_id" => self.held_id,
            "move_digest" => self.digest,
            "move_instant" => self.instant,
            "move_digest_ticks" => self.digest_ticks,
            "move_ammo" => self.ammo,
            "move_ammo_count" => self.ammo_count,
            "move_held_speed" => self.held_speed,
            "move_swallow_queue" => self.swallow_queue,
            "move_spread" => self.spread,
            _ => return self.requests.field(name),
        })
    }
    pub fn set_field(&mut self, name: &str, value: i64) -> bool {
        let target = match name {
            "move_aim" => &mut self.aim,
            "move_aim_angle" => &mut self.aim_angle,
            "move_aim_dir" => &mut self.aim_dir,
            "move_aim_lock" => &mut self.aim_lock,
            "move_aim_up" => &mut self.aim_up,
            "move_eggs" => &mut self.eggs,
            "move_held_id" => &mut self.held_id,
            "move_digest" => &mut self.digest,
            "move_instant" => &mut self.instant,
            "move_digest_ticks" => &mut self.digest_ticks,
            "move_ammo" => &mut self.ammo,
            "move_ammo_count" => &mut self.ammo_count,
            "move_held_speed" => &mut self.held_speed,
            "move_swallow_queue" => &mut self.swallow_queue,
            "move_spread" => &mut self.spread,
            _ => return self.requests.set_field(name, value),
        };
        *target = value;
        true
    }
    /// The food part of moves.gd valid_state.
    pub fn valid(&self, swimming: i64, duck: i64) -> bool {
        [
            self.aim,
            self.aim_lock,
            self.aim_up,
            self.digest,
            self.instant,
            self.swallow_queue,
        ]
        .iter()
        .all(|v| (0..=1).contains(v))
            && (-90000..=45000).contains(&self.aim_angle)
            && (0..=6).contains(&self.eggs)
            && (0..=AMMO_COLD).contains(&self.ammo)
            && (0..=60).contains(&self.ammo_count)
            && (0..=18).contains(&self.digest_ticks)
            && (0..=14000).contains(&self.spread)
            && self.held_id >= 0
            && self.held_speed >= 0
            && [-1, 1].contains(&self.aim_dir)
            && !(self.aim != 0 && (self.eggs == 0 || swimming != 0 || duck != 0))
            && !(self.digest != 0 && self.held_id == 0)
            && !(self.instant != 0 && self.held_id == 0)
            && !(self.ammo_count != 0 && self.ammo == 0)
            && self.requests.valid()
    }
    pub fn clear(&mut self) {
        self.held_id = 0;
        self.digest = 0;
        self.instant = 0;
        self.ammo = 0;
        self.ammo_count = 0;
        self.held_speed = 256 * 60;
    }
}

impl Player {
    #[allow(clippy::too_many_arguments)]
    fn emit(&mut self, kind: i64, item: i64, x: i64, y: i64, angle: i64, vx: i64, vy: i64) {
        self.food.requests.emit(kind, item, x, y, angle, vx, vy);
    }
    /// move_tongue.gd mouth()
    pub(crate) fn mouth_at(&self, spitting: bool) -> [i64; 2] {
        let (mut x, mut y) = (24 * S, -24 * S);
        if self.tongue.axis != 0 {
            x = if self.action_wet != 0 { 4 * S } else { 14 * S };
            y = -38 * S;
            if spitting {
                x = if self.action_wet != 0 { 13 * S } else { 14 * S };
                y = if self.action_wet != 0 {
                    -41 * S - S / 15
                } else {
                    -38 * S
                };
            }
        }
        [self.body.x + self.facing * x, self.body.y + y]
    }
    /// move_tongue.gd probe()
    pub(crate) fn probe(&self, spitting: bool) -> [i64; 4] {
        let (mut x, mut y) = (32 * S, -24 * S);
        if self.tongue.axis != 0 {
            x = if self.action_wet != 0 { 10 * S } else { 20 * S };
            y = -52 * S;
            if self.action_wet != 0 && spitting {
                x = 18 * S + 2 * S / 5;
                y = -56 * S - 14 * S / 15;
            }
        }
        let x = self.body.x + self.facing * x;
        let y = y + self.body.y;
        [x - 12 * S, y - 12 * S, x + 12 * S, y + 12 * S]
    }
    /// move_tongue.gd ammo_mouth()
    fn ammo_mouth(&self) -> [i64; 2] {
        let swimming = self.water.swimming != 0;
        let (mut x, mut y) = if swimming {
            (34 * S, -24 * S)
        } else {
            (30 * S, -28 * S)
        };
        if self.tongue.axis != 0 {
            x = if swimming { 16 * S } else { 18 * S };
            y = if swimming { -60 * S } else { -54 * S };
        }
        [self.body.x + self.facing * x, self.body.y + y]
    }
    /// moves.gd _tick_action
    pub(crate) fn tick_action(&mut self, input: u8, rng: &mut crate::math::Rng, sound: &mut Sound) {
        if self.food.digest_ticks != 0 {
            self.food.digest_ticks -= 1;
            if self.food.digest_ticks == 0 {
                self.food.eggs = (self.food.eggs + 1).min(6);
                let (x, y) = (self.body.x, self.body.y - 16 * S);
                self.emit(STORED_EGG, 0, x, y, 0, 0, 0);
            }
        }
        if self.action != EMIT {
            self.food.spread = 0;
        }
        if self.action != NORMAL || self.food.aim != 0 {
            self.action_tick = (self.action_tick + 1).min(35);
        }
        match self.action {
            POUND_START => {
                if self.action_tick >= 24 {
                    self.set_action(POUND_FALL, sound);
                    self.body.vy = 2 * 2048 * 60;
                }
            }
            TONGUE => {
                if self.action_tick >= self.tongue_end_tick() {
                    self.set_action(NORMAL, sound);
                    self.tongue.length = 16 * S;
                    if self.food.instant != 0 && self.food.held_id != 0 {
                        let (item, x, y) = (self.food.held_id, self.body.x, self.body.y);
                        self.emit(CONSUME, item, x, y, 0, 0, 0);
                        self.food.held_id = 0;
                        self.food.digest = 0;
                        self.food.instant = 0;
                        self.set_action(SWALLOW, sound);
                    } else if self.food.swallow_queue != 0
                        && self.food.digest != 0
                        && self.food.held_id != 0
                    {
                        self.begin_lay(sound);
                    }
                }
            }
            SPITTING | HEAD_BUMP => {
                if self.action_tick >= 10 {
                    self.set_action(NORMAL, sound);
                }
            }
            LAND => {
                if self.action_tick >= 4 {
                    self.set_action(NORMAL, sound);
                }
            }
            TOSS => {
                if self.action_tick >= 13 {
                    self.set_action(NORMAL, sound);
                }
            }
            LAY => {
                if self.action_tick >= 25 {
                    self.set_action(NORMAL, sound);
                }
            }
            SWALLOW => {
                if self.action_tick >= 35 {
                    self.set_action(NORMAL, sound);
                }
            }
            EMIT => {
                if self.food.ammo == AMMO_SEED {
                    if self.action_tick >= 4 {
                        if self.food.ammo_count != 0 {
                            self.emit_ammo(rng);
                        }
                        if input & USE != 0 && self.food.ammo_count != 0 {
                            self.action_tick = 0;
                        } else {
                            self.set_action(NORMAL, sound);
                            self.food.spread = 0;
                        }
                    }
                } else if self.action_tick >= 30 {
                    self.set_action(NORMAL, sound);
                }
            }
            _ => {}
        }
    }
    /// moves.gd _actions; `false` from the pound start ends this step's actions like
    /// the original's early return (the caller sees it through `self.action`).
    pub(crate) fn actions(
        &mut self,
        map: &Probe,
        input: u8,
        pressed: u8,
        frozen: bool,
        rng: &mut crate::math::Rng,
        sound: &mut Sound,
    ) {
        if input & DOWN != 0
            && self.on_floor == 0
            && self.water.swimming == 0
            && self.pound_delay == 0
            && self.food.digest == 0
            && ![TONGUE, LAY, POUND_START, POUND_FALL, POUND_LAND].contains(&self.action)
        {
            self.cancel_flutter();
            self.food.aim = 0;
            self.set_action(POUND_START, sound);
            self.body.vx = 0;
            self.body.vy = 0;
            return;
        }
        if self.food.aim != 0 {
            if pressed & USE != 0 || self.water.swimming != 0 || self.duck != 0 {
                self.food.aim = 0;
                return;
            }
            if pressed & THROW != 0 {
                let mut angle = if self.facing > 0 {
                    self.food.aim_angle
                } else {
                    180000 - self.food.aim_angle
                };
                if angle > 180000 {
                    angle -= 360000;
                }
                let (x, y) = (self.body.x, self.body.y - 32 * S);
                self.emit(EGG, 0, x, y, angle, 0, 0);
                self.food.eggs -= 1;
                self.food.aim = 0;
                self.set_action(TOSS, sound);
                return;
            }
            if pressed & LOCK != 0 {
                self.food.aim_lock = 1 - self.food.aim_lock;
            }
            if input & UP != 0 {
                self.food.aim_angle = -90000;
                self.food.aim_up = 1;
            } else if self.food.aim_up != 0 {
                self.food.aim_up = 0;
                self.food.aim_dir = 1;
            } else if self.food.aim_lock == 0 && !frozen {
                self.food.aim_angle += self.food.aim_dir * 2250;
                if self.food.aim_angle <= -90000 {
                    self.food.aim_angle = -90000;
                    self.food.aim_dir = 1;
                } else if self.food.aim_angle >= 45000 {
                    self.food.aim_angle = 45000;
                    self.food.aim_dir = -1;
                }
            }
        } else if pressed & THROW != 0
            && pressed & USE == 0
            && self.water.swimming == 0
            && ![POUND_START, POUND_FALL, POUND_LAND, TONGUE].contains(&self.action)
        {
            if self.food.eggs != 0 {
                self.set_action(NORMAL, sound);
                let up = input & UP != 0;
                self.food.aim = 1;
                self.food.aim_angle = if up { -90000 } else { 45000 };
                self.food.aim_dir = if up { 1 } else { -1 };
                self.food.aim_lock = 0;
                self.food.aim_up = i64::from(up);
                self.action_tick = 0;
            } else if self.action != TOSS {
                self.set_action(TOSS, sound);
            }
            return;
        }
        if pressed & DOWN != 0 && self.action == TONGUE {
            self.food.swallow_queue = 1;
        }
        if pressed & DOWN != 0
            && self.food.held_id != 0
            && self.food.digest != 0
            && self.action != TONGUE
        {
            self.begin_lay(sound);
            return;
        }
        if pressed & USE != 0
            && ![POUND_START, POUND_FALL, POUND_LAND, LAY, TONGUE, TOSS, EMIT]
                .contains(&self.action)
            && self.push == 0
        {
            self.tongue.axis = i64::from(input & UP != 0);
            self.water.dive = 0;
            self.water.transition = 0;
            if self.food.ammo_count != 0 {
                self.set_action(EMIT, sound);
                if self.food.ammo != AMMO_SEED {
                    self.emit_ammo(rng);
                }
            } else if self.food.held_id != 0 {
                self.set_action(SPITTING, sound);
                let mouth = self.mouth_at(true);
                let probe = self.probe(true);
                if !(map.border_overlaps(probe) || map.terrain_overlaps(probe)) {
                    let axis = self.tongue.axis != 0;
                    let (item, speed) = (self.food.held_id, self.food.held_speed);
                    let angle = if axis {
                        -90000
                    } else if self.facing > 0 {
                        0
                    } else {
                        180000
                    };
                    let vx = if axis { 0 } else { self.facing * speed };
                    let vy = (if axis { -768 } else { -256 }) * 60;
                    self.emit(SPIT, item, mouth[0], mouth[1], angle, vx, vy);
                    self.food.clear();
                    self.flutter_ready = 1;
                }
            } else {
                self.start_tongue_at(map, pressed, sound);
            }
        }
    }
    /// moves.gd catch_item
    #[allow(dead_code, clippy::too_many_arguments)]
    pub(crate) fn catch_item(
        &mut self,
        entity_token: i64,
        digestible: i64,
        ammo: i64,
        count: i64,
        instant: i64,
        toss_speed: i64,
    ) -> bool {
        if self.action != TONGUE
            || ![1, 2].contains(&self.tongue.phase)
            || self.food.held_id != 0
            || entity_token <= 0
            || !(0..=AMMO_COLD).contains(&ammo)
            || !(0..=60).contains(&count)
            || (ammo == 0) != (count == 0)
            || toss_speed < 0
        {
            return false;
        }
        self.food.held_id = entity_token;
        self.food.digest = i64::from(digestible != 0);
        self.food.ammo = ammo;
        self.food.ammo_count = count;
        self.food.held_speed = toss_speed;
        self.food.instant = i64::from(instant != 0 || ammo != 0);
        true
    }
    #[allow(dead_code)]
    pub(crate) fn give_eggs(&mut self, count: i64) {
        self.food.eggs = (self.food.eggs + count.clamp(0, 6)).min(6);
    }
    fn begin_lay(&mut self, sound: &mut Sound) {
        let (item, x, y) = (self.food.held_id, self.body.x, self.body.y);
        self.emit(CONSUME, item, x, y, 0, 0, 0);
        self.food.clear();
        self.food.aim = 0;
        self.food.swallow_queue = 0;
        self.food.digest_ticks = 18;
        self.set_action(LAY, sound);
    }
    fn emit_ammo(&mut self, rng: &mut crate::math::Rng) {
        let kind = self.food.ammo;
        let mouth = self.ammo_mouth();
        let mut angle = if self.tongue.axis != 0 {
            -90000
        } else if self.facing > 0 {
            0
        } else {
            180000
        };
        if kind == AMMO_SEED {
            let r = rng.lcg_step();
            angle += r * (2 * self.food.spread + 1) / 2147483648 - self.food.spread;
            angle = (angle + 540000) % 360000 - 180000;
            self.food.spread = (self.food.spread + 2000).min(14000);
        }
        let request = match kind {
            AMMO_SEED => SEED,
            AMMO_HEAT => HEAT,
            _ => COLD,
        };
        self.emit(request, 0, mouth[0], mouth[1], angle, 0, 0);
        self.food.ammo_count = (self.food.ammo_count - 1).max(0);
        if self.food.ammo_count == 0 {
            self.food.digest = 0;
        }
    }
}

//! shy_ghost.gd (e26): a ghost that drifts toward the player through terrain and hides
//! while the player faces it; the pink forms are solid while hiding. blind_ghost.gd
//! (e39): a blindfolded ghost that hunts by ear. Both live in `Actor` (ActorKind::Shy and
//! ActorKind::Blind).
use crate::{
    actors::{Actor, ActorKind},
    body::{Body, Probe},
    entity::Kind,
    math::{angle_to, sine, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, SCALE as S,
};

// shy_ghost.gd
pub(crate) const STALK: i64 = 0;
pub(crate) const HIDE: i64 = 1;
const TURN_TICKS: i64 = 12;
const PEEK_TICKS: i64 = 15;

// blind_ghost.gd
const FOCUSING: i64 = 0;
const CHASING: i64 = 1;
const CONFUSED: i64 = 2;
const WANDERING: i64 = 3;
const FOCUS: i64 = 0;
const CHASE: i64 = 1;
const BECOME_CONFUSED: i64 = 2;
const TURN: i64 = 3;
const ANIMATIONS: [&str; 4] = ["Focus", "ChasingLocation", "BecomeConfused", "TurnAround"];
const ANIMATION_FRAMES: [i64; 4] = [1, 2, 1, 4];
const FRAME_TICKS: i64 = 4;
const TURN_FLIP_TICKS: i64 = 8;
pub(crate) const BLIND_HALF: i64 = 20 * S;
const SPEED: i64 = 192 * 60;
const PAST_SOUND: i64 = 128 * S;
const ARRIVED: i64 = 48 * S;
const STEER: i64 = 26467;
const STEER_SCALE: i64 = 1_000_000;
const LISTEN_TICKS: i64 = 120;
const SLOW_TICKS: i64 = 30;
const TURNS: i64 = 3;
const TURN_PAUSE_TICKS: i64 = 12;
const WANDER_PAUSE_TICKS: i64 = 24;
const RESTART_TURN: i64 = 1;
const START_WANDER: i64 = 2;
const FIRST_LEG: i64 = 96 * S;
const FIRST_LEG_TICKS: i64 = 150;
const LEG: i64 = 192 * S;
const LEG_TICKS: i64 = 300;
const WAVE_TICKS: i64 = 150;
const WAVE: i64 = 32 * S;
const MAX_COORD: i64 = 0x3fff_ffff_ffff;
/// sound_events.gd RELEASE: heard where the ghost is.
const SOUND_RELEASE: i64 = 4;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}
fn refuse(code: &str, p: &Placement) -> Error {
    Error::Unsupported {
        requirements: vec![format!(
            "{code} form F={} M={} R={}",
            p.variant, p.mirror, p.rotation
        )],
    }
}

impl Actor {
    /// shy_ghost.gd prepare (enemy_options.gd, forms 0..3) + create.
    pub fn shy(p: &Placement) -> Result<Self, Error> {
        if !(0..=3).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(refuse("e26", p));
        }
        let mut a = Actor::new(ActorKind::Shy, p.variant, p.mirror, p.position);
        a.phase = STALK;
        Ok(a)
    }
    fn shy_size(&self) -> i64 {
        if [1, 3].contains(&self.variant) {
            64 * S
        } else {
            32 * S
        }
    }
    pub(crate) fn shy_pink(&self) -> bool {
        [2, 3].contains(&self.variant)
    }
    pub(crate) fn shy_bounds(&self) -> [i64; 4] {
        let half = self.shy_size() * 7 / 16;
        [-half, -half, half, half]
    }
    /// shy_ghost.gd solid_box: a pink ghost is a full solid while hiding.
    pub(crate) fn shy_solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (self.kind == ActorKind::Shy && status == 1 && self.shy_pink() && self.phase == HIDE).then(
            || {
                let half = self.shy_size() / 2;
                [body.x - half, body.y - half, body.x + half, body.y + half]
            },
        )
    }
    pub fn shy_valid(&self) -> bool {
        (0..=3).contains(&self.variant)
            && [STALK, HIDE].contains(&self.phase)
            && (0..=TURN_TICKS).contains(&self.timer)
            && (0..=PEEK_TICKS).contains(&self.peek)
            && (0..=960).contains(&self.peek_wait)
    }
    /// shy_ghost.gd view_state animation and frame.
    pub fn shy_view(&self) -> (String, i64) {
        (
            format!(
                "{}{}",
                self.variant,
                if self.phase == HIDE { "Hide" } else { "Stalk" }
            ),
            i64::from(self.peek > 0),
        )
    }
    /// blind_ghost.gd prepare (enemy_options.gd, form 0) + create.
    pub fn blind(p: &Placement) -> Result<Self, Error> {
        if p.variant != 0 || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(refuse("e39", p));
        }
        let mut a = Actor::new(ActorKind::Blind, 0, p.mirror, p.position);
        a.mode = FOCUSING;
        a.anim = FOCUS;
        a.turns_left = TURNS;
        a.pause_ticks = 0;
        a.target_x = 0;
        a.target_y = 0;
        Ok(a)
    }
    pub fn blind_valid(&self, body: Body) -> bool {
        self.variant == 0
            && (FOCUSING..=WANDERING).contains(&self.mode)
            && (FOCUS..=TURN).contains(&self.anim)
            && (0..=ANIMATION_FRAMES[self.anim as usize] * FRAME_TICKS).contains(&self.anim_ticks)
            && (0..=LISTEN_TICKS).contains(&self.listen_ticks)
            && (0..=WANDER_PAUSE_TICKS).contains(&self.pause_ticks)
            && [0, RESTART_TURN, START_WANDER].contains(&self.pause_kind)
            && (0..=TURNS).contains(&self.turns_left)
            && (0..=SLOW_TICKS).contains(&self.slow_ticks)
            && [0, FIRST_LEG_TICKS, LEG_TICKS].contains(&self.leg_ticks)
            && (0..=self.leg_ticks).contains(&self.leg_tick)
            && [0, 1].contains(&self.wave_on)
            && (0..WAVE_TICKS).contains(&self.wave_phase)
            && self.heard >= 0
            && [body.vx, body.vy, self.slow_vx, self.slow_vy]
                .iter()
                .all(|v| v.abs() <= SPEED)
            && [self.target_x, self.target_y, self.leg_from, self.leg_to]
                .iter()
                .all(|v| v.abs() <= MAX_COORD)
    }
    /// blind_ghost.gd view_state animation and frame.
    pub fn blind_view(&self) -> (&'static str, i64) {
        let last = ANIMATION_FRAMES[self.anim as usize] - 1;
        (
            ANIMATIONS[self.anim as usize],
            (self.anim_ticks / FRAME_TICKS).min(last),
        )
    }
    fn blind_play(&mut self, animation: i64) {
        self.anim = animation;
        self.anim_ticks = 0;
    }
    /// blind_ghost.gd notice: a sound at (sx, sy) makes it listen, or chase if it was
    /// already listening.
    fn blind_notice(&mut self, body: &mut Body, facing: &mut i64, sx: i64, sy: i64) {
        self.listen_ticks = 0;
        self.wave_on = 0;
        self.wave_phase = 0;
        self.leg_ticks = 0;
        self.leg_tick = 0;
        let heading = heading(sx - body.x, sy - body.y);
        self.target_x = sx + turn_cosine(heading, PAST_SOUND);
        self.target_y = sy + turn_sine(heading, PAST_SOUND);
        if self.anim != FOCUS && self.anim != CHASE {
            self.mode = FOCUSING;
            self.blind_play(FOCUS);
            *facing = if sx < body.x { -1 } else { 1 };
        } else if self.anim == FOCUS {
            self.mode = CHASING;
            self.blind_play(CHASE);
            self.slow_ticks = 0;
        }
    }
    fn blind_chase(&mut self, body: &mut Body, facing: &mut i64) {
        let heading = heading(self.target_x - body.x, self.target_y - body.y);
        let aim_x = turn_cosine(heading, SPEED);
        let aim_y = turn_sine(heading, SPEED);
        body.vx += (aim_x - body.vx) * STEER / STEER_SCALE;
        body.vy += (aim_y - body.vy) * STEER / STEER_SCALE;
        *facing = if body.vx < 0 { -1 } else { 1 };
        let dx = self.target_x - body.x;
        let dy = self.target_y - body.y;
        if dx * dx + dy * dy < ARRIVED * ARRIVED {
            self.blind_play(FOCUS);
            self.mode = FOCUSING;
            self.slow_ticks = SLOW_TICKS;
            self.slow_vx = body.vx;
            self.slow_vy = body.vy;
        }
    }
    /// blind_ghost.gd _animate: (flipped, finished).
    fn blind_animate(&mut self) -> (bool, bool) {
        if self.anim == FOCUS {
            return (false, false);
        }
        let length = ANIMATION_FRAMES[self.anim as usize] * FRAME_TICKS;
        if self.anim_ticks >= length {
            return (false, false);
        }
        self.anim_ticks += 1;
        let flipped = self.anim == TURN && self.anim_ticks == TURN_FLIP_TICKS;
        let mut finished = self.anim_ticks == length;
        if finished && self.anim == BECOME_CONFUSED {
            self.blind_play(TURN);
            finished = false;
        }
        (flipped, finished)
    }
    fn blind_start_leg(&mut self, body: Body, facing: i64, distance: i64, ticks: i64) {
        self.leg_from = body.x;
        self.leg_to = body.x + facing * distance;
        self.leg_tick = 0;
        self.leg_ticks = ticks;
    }
    /// blind_ghost.gd _leg_step: true on the tick the eased leg ends.
    fn blind_leg_step(&mut self, body: &mut Body) -> bool {
        if self.leg_ticks <= 0 {
            return false;
        }
        self.leg_tick += 1;
        let length = self.leg_ticks;
        let tick = self.leg_tick;
        let delta = self.leg_to - self.leg_from;
        let part = if 2 * tick < length {
            delta * 2 * tick * tick / (length * length)
        } else {
            let rest = length - tick;
            delta - delta * 2 * rest * rest / (length * length)
        };
        body.x = self.leg_from + part;
        if tick < length {
            return false;
        }
        self.leg_ticks = 0;
        self.leg_tick = 0;
        true
    }
}

fn heading(dx: i64, dy: i64) -> i64 {
    if dx == 0 && dy == 0 {
        0
    } else {
        angle_to(dx, dy)
    }
}
/// blind_ghost.gd _floor_pixels
fn floor_pixels(value: i64) -> i64 {
    if value >= 0 {
        value / S
    } else {
        -((-value + S - 1) / S)
    }
}
/// blind_ghost.gd _drift: fly by the saved velocity; terrain tiles (not borders, not
/// solids) stop each axis, backing out up to the distance moved in whole pixels.
fn drift(body: &mut Body, map: &Probe) {
    let b = [-BLIND_HALF, -BLIND_HALF, BLIND_HALF, BLIND_HALF];
    for horizontal in [true, false] {
        let distance = if horizontal { body.vx } else { body.vy };
        if distance == 0 {
            continue;
        }
        let start = if horizontal { body.x } else { body.y };
        let set = |body: &mut Body, v: i64| {
            if horizontal {
                body.x = v
            } else {
                body.y = v
            }
        };
        set(body, start + distance);
        if !map.terrain_overlaps(world_box(*body, b)) {
            continue;
        }
        let back = -distance.signum() * S;
        let limit = floor_pixels(distance).abs().max(1);
        let mut free = false;
        for _ in 0..limit {
            let now = if horizontal { body.x } else { body.y };
            set(body, now + back);
            if !map.terrain_overlaps(world_box(*body, b)) {
                free = true;
                break;
            }
        }
        if !free {
            set(body, start);
        }
        if horizontal {
            body.vx = 0;
        } else {
            body.vy = 0;
        }
    }
}

impl Run {
    /// shy_ghost.gd step
    pub(crate) fn shy_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.process_actor(index, map).is_none() {
            return Ok(());
        }
        let p = self.player.body;
        let player_facing = self.player.facing;
        let Run { entities, rng, .. } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let width = w.shy_size();
        let right_of = e.body.x > p.x + width / 2;
        let left_of = e.body.x < p.x - width / 2;
        let watched = (right_of && player_facing > 0) || (left_of && player_facing < 0);
        let reach = if w.variant == 2 { width * 3 / 2 } else { width };
        let far = (e.body.x - p.x).abs() > reach;
        if w.timer != 0 {
            w.timer -= 1;
            if w.timer == 0 {
                w.phase = if w.phase == STALK { HIDE } else { STALK };
                w.peek = 0;
                w.peek_wait = 0;
            }
            return Ok(());
        }
        if w.phase == STALK {
            if watched {
                w.timer = TURN_TICKS;
                return Ok(());
            }
            let h = angle_to(p.x - e.body.x, p.y - e.body.y);
            e.body.x += 64 * 60 * turn_cosine(h, S) / S;
            e.body.y += 64 * 60 * turn_sine(h, S) / S;
            e.facing = if p.x > e.body.x { 1 } else { -1 };
        } else {
            if !watched && (right_of || left_of) && far {
                w.timer = TURN_TICKS;
                return Ok(());
            }
            if !w.shy_pink() {
                // shy_ghost.gd peek_step
                if w.peek != 0 {
                    w.peek -= 1;
                } else if w.peek_wait == 0 {
                    w.peek_wait = rng.ticks(480, 960);
                } else {
                    w.peek_wait -= 1;
                    if w.peek_wait == 0 {
                        w.peek = PEEK_TICKS;
                    }
                }
            }
        }
        Ok(())
    }
    /// shy_ghost.gd and blind_ghost.gd contact: any touch hurts.
    pub(crate) fn ghost_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        let b = if w.kind == ActorKind::Shy {
            w.shy_bounds()
        } else {
            [-BLIND_HALF, -BLIND_HALF, BLIND_HALF, BLIND_HALF]
        };
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, b), world_box(p, pb));
        w.contact = i64::from(touching);
        if touching {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
    /// shy_ghost.gd struck: only a hit at its face while it moves defeats it, leaving a
    /// star. Returns whether it was struck.
    pub(crate) fn shy_struck(&mut self, index: usize, travel: i64) -> Result<bool, Error> {
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return Ok(false);
        };
        if w.phase != STALK || w.timer != 0 || travel == 0 || travel.signum() != -e.facing {
            return Ok(false);
        }
        let (x, y) = (e.body.x, e.body.y);
        let vy = -self.rng.ticks(256 * 60, 512 * 60);
        let facing = if self.rng.ticks(0, 1) == 0 { -1 } else { 1 };
        let max_speed = self.rng.ticks(64 * 60, 128 * 60);
        // registry.gd spawn_dynamic: an exhausted serial spawns nothing.
        if self.next_serial().is_ok() {
            self.spawn_star(x, y, vy, facing, max_speed)?;
        }
        self.remove_enemy(index)?;
        Ok(true)
    }
    /// blind_ghost.gd step
    pub(crate) fn blind_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        if self.process_actor(index, map).is_none() {
            return Ok(());
        }
        let sound = (
            self.sound.serial,
            self.sound.kind,
            self.sound.x,
            self.sound.y,
        );
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        let facing = &mut e.facing;
        if sound.0 != w.heard {
            w.heard = sound.0;
            let at_self = sound.1 == SOUND_RELEASE;
            let (sx, sy) = if at_self {
                (body.x, body.y)
            } else {
                (sound.2, sound.3)
            };
            w.blind_notice(body, facing, sx, sy);
        }
        let leg_done = w.blind_leg_step(body);
        let slowing = w.slow_ticks > 0;
        if slowing {
            w.slow_ticks -= 1;
        }
        let mut confuse = false;
        if w.listen_ticks > 0 {
            w.listen_ticks -= 1;
            confuse = w.listen_ticks == 0;
        }
        let mut paused = 0;
        if w.pause_ticks > 0 {
            w.pause_ticks -= 1;
            if w.pause_ticks == 0 {
                paused = w.pause_kind;
                w.pause_kind = 0;
            }
        }
        drift(body, map);
        if w.wave_on != 0 {
            let before = sine(w.wave_phase, WAVE_TICKS, WAVE)?;
            w.wave_phase = (w.wave_phase + 1) % WAVE_TICKS;
            body.y += sine(w.wave_phase, WAVE_TICKS, WAVE)? - before;
        }
        let (flipped, finished) = w.blind_animate();
        if w.mode == FOCUSING {
            if w.listen_ticks == 0 && !confuse {
                w.listen_ticks = LISTEN_TICKS;
            }
            if slowing {
                body.vx = w.slow_vx * w.slow_ticks / SLOW_TICKS;
                body.vy = w.slow_vy * w.slow_ticks / SLOW_TICKS;
            }
        }
        if confuse {
            w.mode = CONFUSED;
            w.blind_play(BECOME_CONFUSED);
            w.turns_left = TURNS;
        }
        if w.mode == CONFUSED && w.anim == TURN {
            if flipped {
                *facing = -*facing;
            }
            if finished {
                w.turns_left -= 1;
                w.pause_ticks = if w.turns_left > 0 {
                    TURN_PAUSE_TICKS
                } else {
                    WANDER_PAUSE_TICKS
                };
                w.pause_kind = if w.turns_left > 0 {
                    RESTART_TURN
                } else {
                    START_WANDER
                };
            }
            if paused == RESTART_TURN {
                w.anim_ticks = 0;
            } else if paused == START_WANDER {
                w.mode = WANDERING;
                w.wave_on = 1;
                w.blind_start_leg(*body, *facing, FIRST_LEG, FIRST_LEG_TICKS);
            }
        }
        if w.mode == CHASING {
            w.blind_chase(body, facing);
        }
        if w.mode == WANDERING {
            if leg_done {
                w.anim_ticks = 0;
            } else if w.anim == TURN {
                if flipped {
                    *facing = -*facing;
                }
                if finished {
                    w.blind_start_leg(*body, *facing, LEG, LEG_TICKS);
                }
            }
        }
        Ok(())
    }
}

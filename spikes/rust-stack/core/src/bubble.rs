//! lava_bubble.gd (e16): a bubble that leaps out of its home along its rotation and drops
//! back, again and again. Swallowing it loads three fire shots (three ice shots for the
//! cold form F 3). Ice freezes the burning forms; fire only defeats the cold form. A frozen
//! bubble drops, shatters on landing and thaws after 8 s into a loose falling body.
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    math::{root, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
pub(crate) const COLD_FORM: i64 = 3;
const LAST_FORM: i64 = 4;
const WAIT: i64 = 0;
const RISE: i64 = 1;
const FALL: i64 = 2;
const SQUASH: i64 = 3;
/// A thawed bubble has lost its leaping motion and only falls.
const LOOSE: i64 = 4;
const MAX_SPEED: i64 = 256 * 60;
const ACCELERATION: i64 = 256;
const STEP_BACK: i64 = 16 * S;
const LEAP_UNIT: i64 = 32 * S;
const SQUASH_TICKS: i64 = 15;
const MAX_OPTION: f64 = 10000.0;
/// elements.gd BUBBLE_SHOTS and the moves.gd ammunition kinds HEAT (2) and COLD (3).
pub(crate) const BUBBLE_SHOTS: i64 = 3;

fn refuse(what: String) -> Error {
    Error::Unsupported {
        requirements: vec![format!("e16 {what}")],
    }
}
/// lava_bubble.gd _number: a number or numeric text; blank text is 0.
fn option(p: &Placement, key: &str) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => 0.0,
        Some(PropertyValue::String(s)) if s.trim().is_empty() => 0.0,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| refuse(format!("option {key}")))?,
        Some(PropertyValue::Number(v)) => *v,
        Some(_) => return Err(refuse(format!("option {key}"))),
    };
    if !value.is_finite() {
        return Err(refuse(format!("option {key}")));
    }
    if !(0.0..=MAX_OPTION).contains(&value) {
        // lava_bubble.gd prepare degrades the bubble; the degrade is not ported.
        return Err(refuse(format!("option {key} out of range")));
    }
    Ok(value)
}
fn ticks(seconds: f64) -> i64 {
    (seconds * 60.0 - 0.000001).ceil() as i64
}
fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}

impl Actor {
    /// lava_bubble.gd prepare + create for a placed e16.
    pub fn bubble(p: &Placement) -> Result<Self, Error> {
        if !(0..=LAST_FORM).contains(&p.variant)
            || !(0..360).contains(&p.rotation)
            || !(0..=2).contains(&p.mirror)
        {
            return Err(refuse(format!(
                "form F={} rotation R={} M={}",
                p.variant, p.rotation, p.mirror
            )));
        }
        let values = [
            option(p, "E1")?,
            option(p, "E2")?,
            option(p, "E3")?,
            option(p, "E4")?,
        ];
        let mut a = Actor::new(ActorKind::Bubble, p.variant, p.mirror, p.position);
        a.form = p.variant;
        a.rise_units = values[0] as i64;
        a.rise_extra = values[1] as i64;
        a.wait_ticks = ticks(values[2]);
        a.timer = ticks(values[3]);
        a.heading = ((p.rotation - 90) * 1000).rem_euclid(360_000);
        // It waits unseen at home, 16 px behind its placement, until the first leap.
        a.home_x = p.position.x - STEP_BACK * turn_cosine(a.heading, S) / S;
        a.home_y = p.position.y - STEP_BACK * turn_sine(a.heading, S) / S;
        a.hidden = 1;
        Ok(a)
    }
    /// lava_bubble.gd bounds: the body trails 16 px behind the leading point.
    pub(crate) fn bubble_bounds(&self) -> [i64; 4] {
        let pointing = self.heading + if self.phase == FALL { 180_000 } else { 0 };
        let cx = -16 * turn_cosine(pointing, S);
        let cy = -16 * turn_sine(pointing, S);
        [cx - 14 * S, cy - 14 * S, cx + 14 * S, cy + 14 * S]
    }
    pub(crate) fn bubble_valid(&self) -> bool {
        (0..=LAST_FORM).contains(&self.form)
            && self.form == self.variant
            && (0..=10000).contains(&self.rise_units)
            && (0..=10000).contains(&self.rise_extra)
            && self.wait_ticks >= 0
            && (0..360_000).contains(&self.heading)
            && (WAIT..=LOOSE).contains(&self.phase)
            && self.timer >= 0
            && (0..=MAX_SPEED).contains(&self.speed)
    }
    /// lava_bubble.gd view_state rotation, in degrees.
    pub(crate) fn bubble_rotation(&self) -> f64 {
        let pointing = self.heading + if self.phase == FALL { 180_000 } else { 0 };
        pointing.rem_euclid(360_000) as f64 / 1000.0
    }
    /// The ammunition swallowing this bubble loads: fire (2), or ice (3) for the cold form.
    pub(crate) fn bubble_ammo(&self) -> i64 {
        if self.form == COLD_FORM {
            3
        } else {
            2
        }
    }
    /// lava_bubble.gd _leap
    fn leap(&mut self, body: &mut Body, rng: &mut crate::math::Rng) {
        let r = rng.lcg_step();
        let extra = (r * (2 * self.rise_extra) / 2_147_483_648 + 1) / 2;
        self.target = LEAP_UNIT * (self.rise_units + extra) + STEP_BACK;
        self.travel = STEP_BACK;
        self.speed = MAX_SPEED;
        self.phase = RISE;
        self.hidden = 0;
        self.place(body);
    }
    /// lava_bubble.gd _move: one tick of straight travel toward `goal` along the leap axis.
    /// Returns true on arrival.
    fn travel_to(&mut self, goal: i64, acceleration: i64, deceleration: i64) -> bool {
        let distance = (goal - self.travel).abs();
        let mut speed = self.speed;
        let mut limit = MAX_SPEED;
        let mut braking = false;
        if deceleration > 0
            && (speed < MAX_SPEED || distance * 2 * deceleration * 10000 <= speed * speed * 10001)
        {
            // Exact braking keeps braking to the end; integer rounding must not undo it.
            braking = true;
            speed = root(2 * deceleration * distance);
            limit = speed;
            self.speed = speed;
        }
        let rate = if braking { -deceleration } else { acceleration };
        let advance = (speed + rate / 2).min(limit);
        if braking {
            self.speed = (self.speed - deceleration).max(0);
            if self.speed == 0 {
                self.travel = goal;
                return true;
            }
        } else {
            self.speed = if acceleration == 0 {
                limit
            } else {
                (self.speed + acceleration).min(limit)
            };
        }
        if distance <= advance {
            self.travel = goal;
            self.speed = 0;
            return true;
        }
        self.travel += if goal > self.travel {
            advance
        } else {
            -advance
        };
        false
    }
    /// lava_bubble.gd _place
    fn place(&self, body: &mut Body) {
        body.x = self.home_x + self.travel * turn_cosine(self.heading, S) / S;
        body.y = self.home_y + self.travel * turn_sine(self.heading, S) / S;
    }
}

impl Run {
    /// lava_bubble.gd step: _move_body, then _touch_lamps.
    pub(crate) fn bubble_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        self.bubble_move(index, map)?;
        self.bubble_touch_lamps(index);
        Ok(())
    }
    /// lava_bubble.gd _move_body
    fn bubble_move(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        {
            let Run {
                entities,
                player,
                rng,
                ..
            } = self;
            let e = &mut entities[index];
            let Kind::Walker(w) = &mut e.kind else {
                unreachable!("bubble index")
            };
            if w.started == 0 {
                // enemy_body.gd process: the first step's initialisation.
                w.started = 1;
                w.impact_cursor = player.impact;
                if w.mirror == 2 {
                    e.facing = if player.body.x > e.body.x { 1 } else { -1 };
                }
            }
            let step = ActorStep { map, player, rng };
            let action = w.process(
                token,
                &mut e.body,
                &mut e.facing,
                &mut e.status,
                &mut e.can_respawn,
                &step,
            );
            if [Hold::Held, Hold::Gone].contains(&action) {
                return Ok(());
            }
        }
        let (b, frozen_free) = {
            let Kind::Walker(w) = &self.entities[index].kind else {
                unreachable!()
            };
            (
                w.bubble_bounds(),
                w.frozen != 0 && w.held == 0 && w.spat == 0,
            )
        };
        if frozen_free {
            let e = &mut self.entities[index];
            let was_falling = e.body.vy > 0;
            if let Kind::Walker(w) = &mut e.kind {
                w.phase = LOOSE;
                w.hidden = 0;
            }
            if self.enemy_frozen_step(index, map, b)? {
                let e = &self.entities[index];
                let shatters = matches!(&e.kind, Kind::Walker(w) if w.frozen != 0)
                    && e.status == 1
                    && was_falling
                    && e.body.vy == 0;
                if shatters {
                    // element_reactions.gd shatter
                    self.remove_enemy(index)?;
                }
                return Ok(());
            }
        }
        let after = {
            let Run {
                entities,
                player,
                rng,
                ..
            } = self;
            let e = &mut entities[index];
            let Kind::Walker(w) = &mut e.kind else {
                unreachable!()
            };
            let mut step = ActorStep { map, player, rng };
            w.spit_step(
                &mut e.body,
                &mut e.facing,
                &mut e.status,
                &mut e.can_respawn,
                &mut step,
            )
        };
        match after {
            Some(After::HitOthers(b)) => return self.hit_others(index, b, HitKind::Spit, true),
            Some(_) => return Ok(()),
            None => {}
        }
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        let body = &mut e.body;
        if w.phase == LOOSE {
            body.gravity(map, b, false);
            if map.lava_overlaps(world_box(*body, b)) {
                self.remove_enemy(index)?;
            }
            return Ok(());
        }
        let phase = w.phase;
        match phase {
            WAIT => {
                if w.timer > 0 {
                    w.timer -= 1;
                    return Ok(());
                }
                w.leap(body, &mut self.rng);
            }
            RISE => {
                if w.travel_to(w.target, 0, ACCELERATION) {
                    // The way back starts at the end of this tick, 16 px below the peak.
                    w.phase = FALL;
                    w.travel -= STEP_BACK;
                    w.speed = 0;
                } else if map.border_overlaps(world_box(*body, w.bubble_bounds()))
                    || map.terrain_overlaps(world_box(*body, w.bubble_bounds()))
                {
                    w.phase = SQUASH;
                    w.timer = SQUASH_TICKS;
                    w.speed = 0;
                }
            }
            SQUASH => {
                w.timer -= 1;
                if w.timer <= 0 {
                    w.phase = FALL;
                    w.travel -= STEP_BACK;
                    w.speed = 0;
                }
            }
            FALL if w.travel_to(0, ACCELERATION, 0) => {
                w.phase = WAIT;
                w.hidden = 1;
                w.timer = w.wait_ticks;
            }
            _ => {}
        }
        w.place(body);
        Ok(())
    }
    /// lava_bubble.gd contact: frozen contact first; a visible bubble hurts on touch.
    pub(crate) fn bubble_contact(&mut self, index: usize, input: u8) -> Result<(), Error> {
        if self.frozen_contact(index, input)? {
            return Ok(());
        }
        let e = &self.entities[index];
        let Kind::Walker(w) = &e.kind else {
            return Ok(());
        };
        if w.hidden != 0 || w.held != 0 || w.spat != 0 || self.player.captured_by != 0 {
            return Ok(());
        }
        let b = w.bubble_bounds();
        let pb = self.player.bounds();
        let p = self.player.body;
        if e.body.x + b[0] < p.x + pb[2]
            && e.body.x + b[2] > p.x + pb[0]
            && e.body.y + b[1] < p.y + pb[3]
            && e.body.y + b[3] > p.y + pb[1]
        {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        Ok(())
    }
}

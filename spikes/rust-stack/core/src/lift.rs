//! arrow_lift.gd (o21): a ridable wheel with a top-only deck. Idle, it turns at its own
//! rate. Shortly after the player stands on it, it travels in its arrow's direction,
//! reflecting off solids, until the player falls below its deck. An optional lifetime
//! starts with the first ride; when it runs out the wheel vanishes until camera respawn.
use crate::{
    body::Probe,
    entity::{Entity, Kind},
    math::{angle_to, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
/// `angle` is in 1/60000 degree so a whole-degree rate per second adds exactly per tick.
const TURN: i64 = 360 * 60000;
const START_TICKS: i64 = 3;
const SHRINK_TICKS: i64 = 6;
const BODY: [i64; 4] = [-31 * S, -31 * S, 31 * S, 31 * S];
const MAX_RATE: f64 = 100_000.0;
const MAX_SPEED: f64 = 100_000.0;
const MAX_LIFE: f64 = 100_000.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Lift {
    pub angle: i64,
    pub turn_rate: i64,
    pub speed: i64,
    pub form: i64,
    pub life: i64,
    pub life_left: i64,
    pub start: i64,
    pub riding: i64,
    pub shrink: i64,
}

/// registry.gd numeric_option with a default for a missing or blank option.
fn number(p: &Placement, key: &str, default: f64) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => default,
        Some(PropertyValue::String(s)) if s.trim().is_empty() => default,
        Some(PropertyValue::String(s)) => s.trim().parse::<f64>().map_err(|_| refuse(key))?,
        Some(PropertyValue::Number(v)) => *v,
        Some(_) => return Err(refuse(key)),
    };
    if value.is_finite() {
        Ok(value)
    } else {
        Err(refuse(key))
    }
}
fn refuse(what: &str) -> Error {
    Error::Unsupported {
        requirements: vec![format!("o21 option {what}")],
    }
}

impl Lift {
    /// arrow_lift.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let rate = number(p, "E1", 0.0)?;
        let speed = number(p, "E2", 128.0)?;
        let life = number(p, "E3", 0.0)?;
        let rotation = number(p, "R", 0.0)?;
        if p.variant < 0 {
            return Err(refuse("F"));
        }
        if rate.abs() > MAX_RATE || speed.abs() > MAX_SPEED || life > MAX_LIFE {
            return Err(refuse("out of range"));
        }
        Ok(Self {
            angle: (((rotation - 90.0) * 60000.0).round() as i64).rem_euclid(TURN),
            turn_rate: rate as i64,
            speed: speed as i64,
            form: p.variant,
            life: ((life * 60.0 - 0.000001).ceil() as i64).max(0),
            life_left: -1,
            start: 0,
            riding: 0,
            shrink: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-32 * S, -32 * S, 32 * S, 32 * S]
    }
    /// arrow_lift.gd solid_box: the top-only deck.
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        (e.status == 1 && self.shrink == 0).then_some([
            e.body.x - 22 * S,
            e.body.y - 22 * S,
            e.body.x + 22 * S,
            e.body.y - 20 * S,
        ])
    }
    /// arrow_lift.gd view_state: (rotation in degrees, size in pixels).
    pub fn view(&self) -> (f64, f64) {
        let size = 64.0 * (SHRINK_TICKS - (self.shrink - 1).max(0)) as f64 / SHRINK_TICKS as f64;
        ((self.angle / 60000 + 90) as f64, size)
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "angle" => self.angle,
            "turn_rate" => self.turn_rate,
            "speed" => self.speed,
            "form" => self.form,
            "life" => self.life,
            "life_left" => self.life_left,
            "start" => self.start,
            "riding" => self.riding,
            "shrink" => self.shrink,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "angle" => self.angle = value,
            "turn_rate" => self.turn_rate = value,
            "speed" => self.speed = value,
            "form" => self.form = value,
            "life" => self.life = value,
            "life_left" => self.life_left = value,
            "start" => self.start = value,
            "riding" => self.riding = value,
            "shrink" => self.shrink = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..TURN).contains(&self.angle)
            && self.turn_rate.abs() <= MAX_RATE as i64
            && self.speed.abs() <= MAX_SPEED as i64
            && self.form >= 0
            && (0..=MAX_LIFE as i64 * 60).contains(&self.life)
            && (-1..=self.life).contains(&self.life_left)
            && (0..=START_TICKS).contains(&self.start)
            && [0, 1].contains(&self.riding)
            && (0..=SHRINK_TICKS).contains(&self.shrink)
    }
}

impl Run {
    /// arrow_lift.gd step (with travel).
    pub(crate) fn lift_step(&mut self, index: usize, map: &Probe) {
        let e = &mut self.entities[index];
        let Kind::Lift(l) = &mut e.kind else {
            return;
        };
        if l.shrink != 0 {
            l.shrink += 1;
            if l.shrink > SHRINK_TICKS {
                l.shrink = 0;
                l.riding = 0;
                l.start = 0;
                e.status = 2; // Queued: back only through camera respawn.
                e.offscreen = 0;
            }
            return;
        }
        if l.start != 0 {
            l.start -= 1;
            if l.start == 0 {
                l.riding = 1;
                if l.life > 0 && l.life_left < 0 {
                    l.life_left = l.life;
                }
            }
        }
        if l.life_left > 0 {
            l.life_left -= 1;
            if l.life_left == 0 {
                l.shrink = 1;
                return;
            }
        }
        if l.riding == 0 {
            l.angle = (l.angle + l.turn_rate * 1000).rem_euclid(TURN);
            return;
        }
        // Move one tick along the arrow. A blocked axis reflects that component, and
        // the arrow follows the new direction.
        let milli = l.angle / 60;
        let mut vx = l.speed * 60 * turn_cosine(milli, S) / S;
        let mut vy = l.speed * 60 * turn_sine(milli, S) / S;
        let mut flipped = false;
        if vx != 0 && e.body.overlaps(map, BODY, vx, 0) {
            vx = -vx;
            flipped = true;
        } else {
            e.body.x += vx;
        }
        if vy != 0 && e.body.overlaps(map, BODY, 0, vy) {
            vy = -vy;
            flipped = true;
        } else {
            e.body.y += vy;
        }
        if flipped {
            l.angle = angle_to(vx, vy) * 60;
        }
    }
    /// arrow_lift.gd contact: standing on the deck starts a ride; falling below it ends
    /// the ride.
    pub(crate) fn lift_contact(&mut self, index: usize) {
        let b = self.player.bounds();
        let p = self.player.body;
        let on_floor = self.player.on_floor != 0;
        let e = &mut self.entities[index];
        let Kind::Lift(l) = &mut e.kind else {
            return;
        };
        if l.shrink != 0 {
            return;
        }
        let feet = p.y + b[3];
        let top = e.body.y - 22 * S;
        let standing = on_floor
            && p.x + b[2] >= e.body.x - 22 * S
            && p.x + b[0] <= e.body.x + 22 * S
            && feet <= top
            && feet + 2 * S >= top;
        if l.riding != 0 {
            if !standing && feet > e.body.y - 16 * S {
                l.riding = 0;
            }
        } else if standing && l.start == 0 {
            l.start = START_TICKS;
        }
    }
}

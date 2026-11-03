//! rise_balloon.gd (o26): a balloon with a top-only deck that rises and drifts at its
//! placement speeds, optionally bobbing. Landing on it pauses it for a moment; while the
//! player stands on it, it rises at a fifth of its speed and stops bobbing.
use crate::{
    body::{HorizontalMove, Probe},
    entity::{Entity, Kind},
    math::turn_sine,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};

const BOX: [i64; 4] = [-30 * S, -30 * S, 30 * S, 30 * S];
/// 0.1 s pause after a landing.
const LAND_TICKS: i64 = 6;
const MAX_OPTION: i64 = 100_000;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Balloon {
    pub form: i64,
    pub rise: i64,
    pub drift: i64,
    pub bob: i64,
    pub bob_period: i64,
    pub age: i64,
    pub stepped: i64,
    pub land_delay: i64,
}

fn refuse(why: String) -> Error {
    Error::Unsupported {
        requirements: vec![format!("o26 {why}")],
    }
}

/// registry.gd numeric_option with rise_balloon.gd's default for a missing or blank
/// option.
fn number(p: &Placement, key: &str, default: f64) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => default,
        Some(PropertyValue::String(s)) if s.trim().is_empty() => default,
        Some(PropertyValue::String(s)) => s
            .trim()
            .parse::<f64>()
            .map_err(|_| refuse(format!("invalid balloon option {key}")))?,
        Some(PropertyValue::Number(v)) => *v,
        Some(_) => return Err(refuse(format!("invalid balloon option {key}"))),
    };
    if !value.is_finite() {
        return Err(refuse(format!("invalid balloon option {key}")));
    }
    if value.abs() > MAX_OPTION as f64 {
        return Err(refuse(format!(
            "balloon option {key} out of range (degrades to a placeholder)"
        )));
    }
    Ok(value)
}

impl Balloon {
    /// rise_balloon.gd prepare + create: E1 rise and E2 drift in px/s, E3 bob height in
    /// 32 px steps, E4 bob period in seconds (default 4).
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let rise = number(p, "E1", 0.0)? as i64;
        let drift = number(p, "E2", 0.0)? as i64;
        let bob = number(p, "E3", 0.0)? as i64;
        let period = number(p, "E4", 4.0)? as i64;
        let form = match p.properties.iter().find(|(k, _)| k == "F").map(|(_, v)| v) {
            None => 0,
            Some(PropertyValue::Number(v)) if v.is_finite() && *v >= 0.0 && *v == v.floor() => {
                *v as i64
            }
            Some(_) => return Err(refuse("invalid balloon colour".into())),
        };
        Ok(Self {
            form,
            rise,
            drift,
            bob: 32 * bob,
            bob_period: (period * 60).max(1),
            age: 0,
            stepped: 0,
            land_delay: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        BOX
    }
    /// rise_balloon.gd solid_box: the 60 x 2 deck.
    pub fn solid(&self, e: &Entity) -> Option<[i64; 4]> {
        (e.status == 1).then_some([
            e.body.x - 30 * S,
            e.body.y - 20 * S,
            e.body.x + 30 * S,
            e.body.y - 18 * S,
        ])
    }
    /// rise_balloon.gd bob_offset: the vertical bob offset for an age.
    fn bob_offset(&self, age: i64) -> i64 {
        if self.bob == 0 {
            return 0;
        }
        let phase = age.rem_euclid(self.bob_period) * 360_000 / self.bob_period;
        self.bob * turn_sine(phase, S)
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "form" => self.form,
            "rise" => self.rise,
            "drift" => self.drift,
            "bob" => self.bob,
            "bob_period" => self.bob_period,
            "age" => self.age,
            "stepped" => self.stepped,
            "land_delay" => self.land_delay,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "form" => self.form = value,
            "rise" => self.rise = value,
            "drift" => self.drift = value,
            "bob" => self.bob = value,
            "bob_period" => self.bob_period = value,
            "age" => self.age = value,
            "stepped" => self.stepped = value,
            "land_delay" => self.land_delay = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        self.form >= 0
            && self.rise.abs() <= MAX_OPTION
            && self.drift.abs() <= MAX_OPTION
            && self.bob.abs() <= 32 * MAX_OPTION
            && self.bob_period >= 1
            && (0..self.bob_period).contains(&self.age)
            && [0, 1].contains(&self.stepped)
            && (0..=LAND_TICKS).contains(&self.land_delay)
    }
}

impl Run {
    /// rise_balloon.gd step: drift (enemy_motion.gd move), rise, then bob.
    pub(crate) fn balloon_step(&mut self, index: usize, map: &Probe) {
        let e = &mut self.entities[index];
        let Kind::Balloon(b) = &mut e.kind else {
            return;
        };
        if b.land_delay != 0 {
            b.land_delay -= 1;
            e.body.vy = 0;
        } else {
            e.body.vx = b.drift * 60;
            e.body.vy = -b.rise * 60 / (4 * b.stepped + 1);
        }
        let dx = e.body.vx;
        if dx != 0 && e.body.prepare(map, BOX) {
            let support = e.body.floor(map, BOX);
            e.body
                .horizontal(map, BOX, dx, support, HorizontalMove::Actor);
        }
        let dy = e.body.vy;
        if dy != 0 && e.body.prepare(map, BOX) {
            e.body.vertical(map, BOX, dy);
        }
        if b.stepped == 0 && b.bob != 0 {
            e.body.y += b.bob_offset(b.age + 1) - b.bob_offset(b.age);
            b.age = (b.age + 1).rem_euclid(b.bob_period);
        }
    }
    /// rise_balloon.gd contact: landing on the deck pauses it; leaving it ends the ride.
    pub(crate) fn balloon_contact(&mut self, index: usize) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let on_floor = self.player.on_floor;
        let e = &mut self.entities[index];
        let Kind::Balloon(b) = &mut e.kind else {
            return;
        };
        let feet = p.y + pb[3];
        let top = e.body.y - 20 * S;
        let on_deck = p.x + pb[2] >= e.body.x - 30 * S
            && p.x + pb[0] <= e.body.x + 30 * S
            && feet <= top + 2 * S
            && feet + 4 * S >= top;
        if on_deck && b.stepped == 0 {
            b.land_delay = LAND_TICKS;
            e.body.vy = 0;
            b.stepped = on_floor;
        } else if b.stepped != 0 && !on_deck {
            b.stepped = 0;
        }
    }
}

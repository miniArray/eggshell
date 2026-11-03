//! spike_sack.gd (e34): a spiked sack that drifts in a straight line at 120 px/s from its
//! placement angle and reflects off solids. Touching it hurts; nothing defeats it. It
//! has no hit, tongue or projectile rule and is not an enemy.
use crate::{
    body::{Body, Probe},
    entity::Kind,
    math::{angle_to, turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const SPEED: i64 = 120 * 60;
/// Body half sizes in pixels for the large and small forms.
const HALF: [i64; 2] = [68, 38];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Sack {
    pub form: i64,
    pub heading: i64,
}

impl Sack {
    /// spike_sack.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let invalid = || Error::InvalidInput {
            context: "Invalid sack angle or form".into(),
        };
        let angle = match p.properties.iter().find(|(k, _)| k == "R").map(|(_, v)| v) {
            None => 0.0,
            Some(PropertyValue::Number(v)) => *v,
            Some(PropertyValue::String(s)) => s.trim().parse::<f64>().map_err(|_| invalid())?,
            Some(_) => return Err(invalid()),
        };
        if !angle.is_finite() || angle.abs() > (i64::MAX / S - 1) as f64 {
            return Err(invalid());
        }
        if !(0..=1).contains(&p.variant) {
            return Err(Error::Unsupported {
                requirements: vec![format!("e34 sack form F={}", p.variant)],
            });
        }
        let heading = (((angle - 90.0) * 1000.0).round() as i64).rem_euclid(360_000);
        Ok(Self {
            form: p.variant,
            heading,
        })
    }
    /// spike_sack.gd create: the starting velocity along the heading.
    pub fn velocity(&self) -> (i64, i64) {
        (
            SPEED * turn_cosine(self.heading, S) / S,
            SPEED * turn_sine(self.heading, S) / S,
        )
    }
    pub fn bounds(&self) -> [i64; 4] {
        let half = HALF[self.form.clamp(0, 1) as usize] * S;
        [-half, -half, half, half]
    }
    pub fn valid(&self) -> bool {
        [0, 1].contains(&self.form) && (0..360_000).contains(&self.heading)
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "form" => self.form,
            "heading" => self.heading,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "form" => self.form = value,
            "heading" => self.heading = value,
            _ => return false,
        }
        true
    }
    /// spike_sack.gd step: placed inside a solid it stays until free; otherwise each
    /// axis moves or reflects (collision.gd overlaps: terrain and full solids).
    pub(crate) fn step(&mut self, body: &mut Body, map: &Probe) {
        let b = self.bounds();
        if body.overlaps(map, b, 0, 0) {
            return;
        }
        let mut bounced = false;
        let (dx, dy) = (body.vx, body.vy);
        if dx != 0 && body.overlaps(map, b, dx, 0) {
            body.vx = -body.vx;
            bounced = true;
        } else {
            body.x += dx;
        }
        if dy != 0 && body.overlaps(map, b, 0, dy) {
            body.vy = -body.vy;
            bounced = true;
        } else {
            body.y += dy;
        }
        if bounced {
            self.heading = angle_to(body.vx, body.vy);
        }
    }
}

impl Run {
    /// spike_sack.gd contact: any touch hurts (open edges).
    pub(crate) fn sack_contact(&mut self, index: usize) -> bool {
        if self.player.captured_by != 0 {
            return false;
        }
        let e = &self.entities[index];
        let Kind::Sack(s) = &e.kind else {
            return false;
        };
        let b = s.bounds();
        let pb = self.player.bounds();
        let p = self.player.body;
        if p.x + pb[2] > e.body.x + b[0]
            && p.x + pb[0] < e.body.x + b[2]
            && p.y + pb[3] > e.body.y + b[1]
            && p.y + pb[1] < e.body.y + b[3]
        {
            let x = e.body.x;
            return self.player.hurt(x, &mut self.sound);
        }
        false
    }
}

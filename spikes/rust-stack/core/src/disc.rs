//! disc_block.gd (e38): a solid block that sends out spinning discs while the player is
//! within 336 px horizontally and draws them back in when the player leaves; and
//! orbit_disc.gd (enemy_disc): the runtime disc that orbits its block, grows out over
//! half a second, shrinks back when recalled, and hurts on contact.
use crate::{
    body::Body,
    entity::{Entity, Kind},
    math::{turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const RANGE: i64 = 336 * S;
const MAX_COUNT: i64 = 64;
const MAX_OPTION: i64 = 100_000;
const HALF: i64 = 16 * S;
/// orbit_disc.gd EXTEND_TICKS: 0.5 s out or back.
const EXTEND_TICKS: i64 = 30;
const MAX_AGE: i64 = 1_000_000;

fn refuse(what: String) -> Error {
    Error::Unsupported {
        requirements: vec![format!("e38 {what}")],
    }
}
/// registry.gd numeric_option with disc_block.gd's default for a blank option.
fn number(p: &Placement, key: &str, default: f64) -> Result<f64, Error> {
    let value = match p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v) {
        None => default,
        Some(PropertyValue::String(s)) if s.trim().is_empty() => default,
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
    Ok(value)
}

/// disc_block.gd FIELDS.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DiscBlock {
    pub count: i64,
    pub speed: i64,
    pub radius: i64,
    pub out: i64,
}

impl DiscBlock {
    /// disc_block.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let count = number(p, "E1", 1.0)? as i64;
        let speed = number(p, "E2", 96.0)? as i64;
        let radius = number(p, "E3", 96.0)? as i64;
        if !(0..=MAX_COUNT).contains(&count)
            || speed.abs() > MAX_OPTION
            || radius.abs() > MAX_OPTION
        {
            return Err(refuse(
                "option out of range (degrades to a placeholder)".into(),
            ));
        }
        Ok(Self {
            count,
            speed,
            radius,
            out: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-HALF, -HALF, HALF, HALF]
    }
    /// disc_block.gd solid_box
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (status == 1).then_some([body.x - HALF, body.y - HALF, body.x + HALF, body.y + HALF])
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "count" => self.count,
            "speed" => self.speed,
            "radius" => self.radius,
            "out" => self.out,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let target = match n {
            "count" => &mut self.count,
            "speed" => &mut self.speed,
            "radius" => &mut self.radius,
            "out" => &mut self.out,
            _ => return false,
        };
        *target = value;
        true
    }
    pub fn valid(&self) -> bool {
        (0..=MAX_COUNT).contains(&self.count)
            && self.speed.abs() <= MAX_OPTION
            && self.radius.abs() <= MAX_OPTION
            && [0, 1].contains(&self.out)
    }
}

/// orbit_disc.gd FIELDS.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Disc {
    pub owner: i64,
    pub offset: i64,
    pub speed: i64,
    pub radius: i64,
    pub age: i64,
    pub extend: i64,
    pub retracting: i64,
}

impl Default for Disc {
    fn default() -> Self {
        Self {
            owner: 0,
            offset: 0,
            speed: 96,
            radius: 96,
            age: 0,
            extend: 0,
            retracting: 0,
        }
    }
}

impl Disc {
    /// orbit_disc.gd half: half scale at rest, full scale when out.
    pub fn half(&self) -> i64 {
        8 * S + 8 * S * self.extend / EXTEND_TICKS
    }
    pub fn bounds(&self) -> [i64; 4] {
        let h = self.half();
        [-h, -h, h, h]
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "owner" => self.owner,
            "offset" => self.offset,
            "speed" => self.speed,
            "radius" => self.radius,
            "age" => self.age,
            "extend" => self.extend,
            "retracting" => self.retracting,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        let target = match n {
            "owner" => &mut self.owner,
            "offset" => &mut self.offset,
            "speed" => &mut self.speed,
            "radius" => &mut self.radius,
            "age" => &mut self.age,
            "extend" => &mut self.extend,
            "retracting" => &mut self.retracting,
            _ => return false,
        };
        *target = value;
        true
    }
    pub fn valid(&self) -> bool {
        self.owner >= 0
            && (0..=360_000).contains(&self.offset)
            && self.speed.abs() <= MAX_OPTION
            && self.radius.abs() <= MAX_OPTION
            && (0..=MAX_AGE).contains(&self.age)
            && (0..=EXTEND_TICKS).contains(&self.extend)
            && [0, 1].contains(&self.retracting)
    }
}

impl Run {
    /// disc_block.gd step: send the discs out when the player comes near; recall them when
    /// the player leaves.
    pub(crate) fn disc_block_step(&mut self, index: usize) -> Result<(), Error> {
        let player_x = self.player.body.x;
        let e = &mut self.entities[index];
        let Kind::DiscBlock(b) = &mut e.kind else {
            return Ok(());
        };
        let near = (e.body.x - player_x).abs() < RANGE;
        if near && b.out == 0 {
            b.out = 1;
            let (count, speed, radius) = (b.count, b.speed, b.radius);
            let (x, y, owner) = (e.body.x, e.body.y, e.origin.token());
            for slot in 0..count {
                // registry.gd spawn_dynamic: an exhausted serial spawns nothing.
                let Ok(serial) = self.next_serial() else {
                    break;
                };
                let disc = Disc {
                    owner,
                    offset: 360_000 * slot / count.max(1),
                    speed,
                    radius,
                    ..Disc::default()
                };
                let mut row = Entity::dynamic(
                    serial,
                    Kind::Disc(disc),
                    Body {
                        x,
                        y,
                        ..Body::default()
                    },
                    -1,
                    7,
                );
                row.can_despawn = 0;
                self.dynamic_serial = serial + 1;
                self.entities.push(row);
            }
        } else if !near && b.out != 0 {
            b.out = 0;
            let owner = e.origin.token();
            for o in &mut self.entities {
                if let Kind::Disc(d) = &mut o.kind {
                    if d.owner == owner {
                        d.retracting = 1;
                    }
                }
            }
        }
        Ok(())
    }
    /// orbit_disc.gd step (step phase 1): orbit the owner block.
    pub(crate) fn disc_step(&mut self, index: usize) {
        let Kind::Disc(d) = &self.entities[index].kind else {
            return;
        };
        let owner = self
            .find_token(d.owner)
            .filter(|i| self.entities[*i].status == 1)
            .map(|i| self.entities[i].body);
        let e = &mut self.entities[index];
        let Kind::Disc(d) = &mut e.kind else {
            return;
        };
        let Some(owner) = owner else {
            e.status = 3;
            return;
        };
        d.age = (d.age + 1).min(MAX_AGE);
        if d.retracting != 0 {
            d.extend -= 1;
            if d.extend <= 0 {
                e.status = 3;
                return;
            }
        } else {
            d.extend = (d.extend + 1).min(EXTEND_TICKS);
        }
        let angle = (d.offset + d.speed * 1000 * d.age / 60).rem_euclid(360_000);
        let reach = d.radius * S * d.extend / EXTEND_TICKS;
        e.body.x = owner.x + reach * turn_cosine(angle, S) / S;
        e.body.y = owner.y + reach * turn_sine(angle, S) / S;
    }
    /// orbit_disc.gd contact: touching the disc hurts.
    pub(crate) fn disc_contact(&mut self, index: usize) {
        let e = &self.entities[index];
        let Kind::Disc(d) = &e.kind else {
            return;
        };
        let h = d.half();
        let pb = self.player.bounds();
        let p = self.player.body;
        if e.body.x - h < p.x + pb[2]
            && e.body.x + h > p.x + pb[0]
            && e.body.y - h < p.y + pb[3]
            && e.body.y + h > p.y + pb[1]
        {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
    }
}

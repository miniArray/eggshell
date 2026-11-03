//! spin_span.gd (p11 red, p12 blue) and spin_block.gd (o30): resizable full-solid spans
//! that turn over when a switch block of their colour is struck. A span has no solid
//! body while it turns (0.625 s) and is flipped afterwards. The struck block lifts
//! briefly and pops bodies above it.
use crate::{body::Body, entity::Kind, state::Run, Error, Placement, PropertyValue, SCALE as S};

const EXTRA_WIDTH: i64 = 8;
const MAX_WIDTH: i64 = 1_000_000;
/// 0.625 s, rounded up to whole ticks.
const SPIN_TICKS: i64 = 38;
/// Degrees per second while turning.
const TURN_RATE: i64 = 1440;
/// 0.1 s up and 0.1 s back.
const BUMP_TICKS: i64 = 12;
const LIFT: i64 = 32 * S;
const BLOCK_BOX: [i64; 4] = [-16 * S, -16 * S, 16 * S, 16 * S];

fn property<'a>(p: &'a Placement, key: &str) -> Option<&'a PropertyValue> {
    p.properties.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn refuse(why: &str) -> Error {
    Error::Unsupported {
        requirements: vec![why.into()],
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SpinSpan {
    /// p11 turns on red (colour 0) switch blocks, p12 on blue (1).
    pub colour: i64,
    pub width: i64,
    pub flipped: i64,
    pub spin: i64,
}

impl SpinSpan {
    /// spin_span.gd prepare + create: E1 is the width in pixels (registry.gd
    /// numeric_option, default "96"), plus 8 px.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let value = match property(p, "E1") {
            None => 96.0,
            Some(PropertyValue::Number(n)) => *n,
            Some(PropertyValue::String(s)) => s
                .trim()
                .parse::<f64>()
                .map_err(|_| refuse("invalid turning span width"))?,
            Some(_) => return Err(refuse("invalid turning span width")),
        };
        if !value.is_finite() || !(0.0..=MAX_WIDTH as f64).contains(&value) {
            return Err(refuse("invalid turning span width"));
        }
        Ok(Self {
            colour: i64::from(p.code != "p11"),
            width: (value as i64 + EXTRA_WIDTH) * S,
            flipped: 0,
            spin: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-self.width / 2, -16 * S, self.width / 2, 8 * S]
    }
    /// spin_span.gd solid_box: none while turning. The support body is 24 px tall,
    /// centred 4 px above the drawn span.
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (status == 1 && self.width != 0 && self.spin == 0).then_some([
            body.x - self.width / 2,
            body.y - 16 * S,
            body.x + self.width / 2,
            body.y + 8 * S,
        ])
    }
    /// spin_span.gd step
    pub fn step(&mut self) {
        if self.spin > 0 {
            self.spin -= 1;
            if self.spin == 0 {
                self.flipped = 1 - self.flipped;
            }
        }
    }
    /// spin_span.gd view_state rotation, in degrees.
    pub fn rotation(&self) -> f64 {
        let direction = if self.colour == 0 { 1 } else { -1 };
        let turned = if self.spin != 0 {
            TURN_RATE * (SPIN_TICKS - self.spin) / 60
        } else {
            0
        };
        (180 * self.flipped + direction * turned).rem_euclid(360) as f64
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "width" => self.width,
            "flipped" => self.flipped,
            "spin" => self.spin,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "width" => self.width = value,
            "flipped" => self.flipped = value,
            "spin" => self.spin = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (0..=(MAX_WIDTH + EXTRA_WIDTH) * S).contains(&self.width)
            && [0, 1].contains(&self.flipped)
            && (0..=SPIN_TICKS).contains(&self.spin)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SpinBlock {
    pub colour: i64,
    pub home_y: i64,
    pub busy: i64,
}

impl SpinBlock {
    /// spin_block.gd prepare + create: F is the colour (0 red, 1 blue).
    pub fn new(p: &Placement) -> Result<Self, Error> {
        match property(p, "F") {
            None => {}
            Some(PropertyValue::Number(v)) if v.is_finite() && *v == v.floor() && *v >= 0.0 => {
                if *v > 1.0 {
                    return Err(refuse(&format!(
                        "switch block colour F={v} (degrades to a placeholder)"
                    )));
                }
            }
            Some(_) => return Err(refuse("invalid switch block colour")),
        }
        Ok(Self {
            colour: p.variant,
            home_y: p.position.y,
            busy: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        BLOCK_BOX
    }
    /// spin_block.gd solid_box: always solid while active, lifted or not.
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (status == 1).then_some([
            body.x + BLOCK_BOX[0],
            body.y + BLOCK_BOX[1],
            body.x + BLOCK_BOX[2],
            body.y + BLOCK_BOX[3],
        ])
    }
    /// spin_block.gd step: the lift and drop after a strike.
    pub fn step(&mut self, body: &mut Body) {
        if self.busy != 0 {
            self.busy -= 1;
            let offset = (BUMP_TICKS - self.busy).min(self.busy);
            body.y = self.home_y - LIFT * offset / (BUMP_TICKS / 2);
        }
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "colour" => self.colour,
            "home_y" => self.home_y,
            "busy" => self.busy,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "colour" => self.colour = value,
            "home_y" => self.home_y = value,
            "busy" => self.busy = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self, y: i64) -> bool {
        [0, 1].contains(&self.colour)
            && (0..=BUMP_TICKS).contains(&self.busy)
            && y <= self.home_y
            && y >= self.home_y - LIFT
    }
}

impl Run {
    /// spin_block.gd projectile_contact for a thrown egg: a lifted block is an ordinary
    /// solid (3); otherwise the strike turns the spans and takes the egg (1).
    pub(crate) fn spin_block_projectile_contact(&mut self, index: usize) -> Result<i64, Error> {
        let e = &self.entities[index];
        let Kind::SpinBlock(b) = &e.kind else {
            return Ok(0);
        };
        if e.status != 1 {
            return Ok(0);
        }
        if b.busy != 0 {
            return Ok(3);
        }
        self.spin_block_trigger(index)?;
        Ok(1)
    }
    /// spin_block.gd trigger: turn every idle span of this colour. With none idle but
    /// some turning, nothing happens; with no span of this colour at all, the block
    /// still lifts. Then lift and pop what stands on it.
    pub(crate) fn spin_block_trigger(&mut self, index: usize) -> Result<bool, Error> {
        let e = &self.entities[index];
        let Kind::SpinBlock(b) = &e.kind else {
            return Ok(false);
        };
        if b.busy != 0 || e.status != 1 {
            return Ok(false);
        }
        let colour = b.colour;
        let mut matching = Vec::new();
        let mut idle = false;
        for (i, o) in self.entities.iter().enumerate() {
            if let Kind::SpinSpan(s) = &o.kind {
                if o.status == 1 && s.colour == colour {
                    matching.push(i);
                    idle = idle || s.spin == 0;
                }
            }
        }
        if idle {
            for i in matching {
                // spin_span.gd start_turn
                if let Kind::SpinSpan(s) = &mut self.entities[i].kind {
                    if s.spin == 0 {
                        s.spin = SPIN_TICKS;
                    }
                }
            }
        } else if !matching.is_empty() {
            return Ok(false);
        }
        let e = &mut self.entities[index];
        if let Kind::SpinBlock(b) = &mut e.kind {
            b.busy = BUMP_TICKS;
        }
        let probe = [
            e.body.x - 16 * S,
            e.body.y - 24 * S,
            e.body.x + 16 * S,
            e.body.y + 8 * S,
        ];
        self.bump_box(index, probe)?;
        Ok(true)
    }
}

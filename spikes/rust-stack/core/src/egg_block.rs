//! egg_block.gd (o27): a full-solid block that, struck from below, stops being solid,
//! rises 64 px and drops back, then turns into a floating coloured egg (o7).
use crate::{
    body::Body,
    egg::Egg,
    entity::Kind,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};

const HALF_TICKS: i64 = 15;
const RISE: i64 = 64 * S;
/// Egg inventory colours: the plain form gives yellow, F=1 red.
const EGG_COLOURS: [i64; 2] = [1, 2];
const BOX: [i64; 4] = [-16 * S, -16 * S, 16 * S, 16 * S];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct EggBlock {
    pub colour: i64,
    pub home_y: i64,
    pub busy: i64,
}

impl EggBlock {
    /// egg_block.gd prepare + create.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: String| Error::Unsupported {
            requirements: vec![format!("o27 {why}")],
        };
        let colour = match p.properties.iter().find(|(k, _)| k == "F").map(|(_, v)| v) {
            None => 0,
            Some(PropertyValue::Number(v)) if v.is_finite() && *v == v.floor() && *v >= 0.0 => {
                p.variant
            }
            Some(_) => return Err(refuse("invalid egg block colour".into())),
        };
        if colour > 1 {
            return Err(refuse(format!(
                "egg block colour F={colour} (degrades to a placeholder)"
            )));
        }
        Ok(Self {
            colour,
            home_y: p.position.y,
            busy: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        BOX
    }
    /// egg_block.gd solid_box: gone while it rises and falls.
    pub fn solid(&self, status: i64, body: Body) -> Option<[i64; 4]> {
        (status == 1 && self.busy == 0).then_some([
            body.x + BOX[0],
            body.y + BOX[1],
            body.x + BOX[2],
            body.y + BOX[3],
        ])
    }
    /// egg_block.gd view_state animation.
    pub fn animation(&self) -> &'static str {
        if self.colour == 1 {
            "Red"
        } else {
            "Yellow"
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
            && (0..=2 * HALF_TICKS).contains(&self.busy)
            && y <= self.home_y
            && y >= self.home_y - RISE
    }
}

impl Run {
    fn egg_block(&mut self, index: usize) -> &mut EggBlock {
        match &mut self.entities[index].kind {
            Kind::EggBlock(b) => b,
            _ => unreachable!("egg block index"),
        }
    }
    /// egg_block.gd bump from below (side 0): rise, and BUMP whatever stands on it.
    pub(crate) fn egg_block_bump(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let Kind::EggBlock(b) = &e.kind else {
            return Ok(());
        };
        if b.busy != 0 || e.status != 1 {
            return Ok(());
        }
        let probe = [
            e.body.x - 16 * S,
            e.body.y - 24 * S,
            e.body.x + 16 * S,
            e.body.y + 8 * S,
        ];
        self.egg_block(index).busy = 2 * HALF_TICKS;
        // Near.strike: active, visible entities with a hit rule in the probe.
        self.bump_box(index, probe)
    }
    /// egg_block.gd step: the rise and fall, then a floating egg in its place.
    pub(crate) fn egg_block_step(&mut self, index: usize) -> Result<(), Error> {
        let e = &mut self.entities[index];
        let Kind::EggBlock(b) = &mut e.kind else {
            return Ok(());
        };
        if b.busy == 0 {
            return Ok(());
        }
        b.busy -= 1;
        let elapsed = 2 * HALF_TICKS - b.busy;
        let offset = elapsed.min(2 * HALF_TICKS - elapsed);
        e.body.y = b.home_y - RISE * offset / HALF_TICKS;
        if b.busy != 0 {
            return Ok(());
        }
        e.status = 3;
        let (x, y, colour, layer) = (e.body.x, b.home_y, EGG_COLOURS[b.colour as usize], 7);
        let mut egg = Egg::new(colour);
        egg.floating = 1;
        // item_egg.gd create: a runtime egg keeps can_despawn 1.
        self.push_dynamic(Kind::Egg(egg), x, y, 0, 0, -1, layer, 1)
    }
}

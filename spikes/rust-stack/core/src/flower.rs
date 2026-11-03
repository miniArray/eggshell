//! star_flower.gd (o22): swallows one spat-out body dropped into its cup, then releases a
//! number of health drops (coins once health is full) and wilts. Thrown eggs bounce off.
use crate::{
    body::Body,
    entity::{Entity, Kind},
    items::{Pickup, PickupKind},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
const OPEN: i64 = 0;
const FED: i64 = 1;
const CLOSING: i64 = 2;
const OPENING: i64 = 3;
const RELEASED: i64 = 4;
const WILTING: i64 = 5;
const MAX_STARS: i64 = 1000;
/// Cup sensor: 56 x 56 around a point 22 px below the flower centre, bottom-heavy.
const CUP: [i64; 4] = [-28 * S, -26 * S, 28 * S, 30 * S];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Flower {
    pub phase: i64,
    pub timer: i64,
    pub stars: i64,
    pub cup_y: i64,
}

/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Flower {
    /// star_flower.gd prepare + create: E1 is the star count (leading integer of a
    /// string, default 8).
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: &str| Error::Unsupported {
            requirements: vec![format!("o22 {why}")],
        };
        let stars = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => 8,
            Some(PropertyValue::String(s)) => {
                let text = s.trim();
                let mut digits = String::new();
                for (index, c) in text.chars().enumerate() {
                    if c.is_ascii_digit() || (index == 0 && c == '-') {
                        digits.push(c);
                    } else {
                        break;
                    }
                }
                digits.parse::<i64>().unwrap_or(0)
            }
            Some(PropertyValue::Number(v)) if v.is_finite() => *v as i64,
            Some(_) => return Err(refuse("star count")),
        };
        if stars > MAX_STARS {
            return Err(refuse("star count above 1000"));
        }
        Ok(Self {
            phase: OPEN,
            timer: 0,
            stars: stars.max(0),
            cup_y: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        [-32 * S, -32 * S, 32 * S, 32 * S]
    }
    fn cup(body: Body) -> [i64; 4] {
        [
            body.x + CUP[0],
            body.y + CUP[1],
            body.x + CUP[2],
            body.y + CUP[3],
        ]
    }
    /// star_flower.gd projectile_contact for an egg: an open cup drops it beside as a
    /// resting egg (2), else the egg goes on (0).
    pub fn egg_contact(&self, at: Body, egg: Body) -> Option<(i64, i64)> {
        if self.phase != OPEN {
            return None;
        }
        let b = [
            egg.x - 12 * S,
            egg.y - 12 * S,
            egg.x + 12 * S,
            egg.y + 12 * S,
        ];
        let vx = if egg.x < at.x { -384 * 60 } else { 384 * 60 };
        strict(b, Self::cup(at)).then_some((vx, -384 * 60))
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "phase" => self.phase,
            "timer" => self.timer,
            "stars" => self.stars,
            "cup_y" => self.cup_y,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "phase" => self.phase = value,
            "timer" => self.timer = value,
            "stars" => self.stars = value,
            "cup_y" => self.cup_y = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self) -> bool {
        (OPEN..=WILTING).contains(&self.phase)
            && (0..=120).contains(&self.timer)
            && (-1..=MAX_STARS).contains(&self.stars)
    }
}

impl Run {
    fn flower(&mut self, index: usize) -> &mut Flower {
        match &mut self.entities[index].kind {
            Kind::StarFlower(f) => f,
            _ => unreachable!("flower index"),
        }
    }
    /// star_flower.gd step.
    pub(crate) fn flower_step(&mut self, index: usize) -> Result<(), Error> {
        let collected = self.entities[index].collected;
        let f = self.flower(index);
        if f.phase == OPEN {
            if collected != 0 {
                // A flower already fed before the last reset does not come back.
                self.entities[index].status = 3;
                return Ok(());
            }
            return self.flower_swallow(index);
        }
        if f.timer > 0 {
            f.timer -= 1;
            if f.timer > 0 {
                return Ok(());
            }
        }
        match f.phase {
            FED | RELEASED => {
                if f.phase == RELEASED && f.stars <= 0 {
                    f.phase = WILTING;
                    f.timer = 120;
                } else {
                    f.phase = CLOSING;
                    f.timer = 15;
                }
            }
            CLOSING => {
                f.phase = OPENING;
                f.timer = 3;
            }
            OPENING => {
                f.stars -= 1;
                self.flower_release(index)?;
                let f = self.flower(index);
                f.phase = RELEASED;
                f.timer = 18;
            }
            WILTING => {
                // Recorded only now: a collected placement is hidden by the drawing layer.
                let e = &mut self.entities[index];
                e.collected = 1;
                e.status = 3;
            }
            _ => {}
        }
        Ok(())
    }
    /// star_flower.gd _swallow: the first spat body that drops into the cup from above
    /// its middle is removed and feeds the flower.
    fn flower_swallow(&mut self, index: usize) -> Result<(), Error> {
        let sensor = Flower::cup(self.entities[index].body);
        let flower_y = self.entities[index].body.y;
        let mut found = None;
        for (other, o) in self.entities.iter().enumerate() {
            let Kind::Walker(w) = &o.kind else {
                continue;
            };
            if other == index || o.status != 1 || w.held != 0 || w.spat != 1 {
                continue;
            }
            let local = crate::egg::entity_bounds(o);
            let b = [
                o.body.x + local[0],
                o.body.y + local[1],
                o.body.x + local[2],
                o.body.y + local[3],
            ];
            if !strict(b, sensor)
                || o.body.x <= sensor[0]
                || o.body.x >= sensor[2]
                || flower_y + 2 * S <= o.body.y + (b[3] - b[1]) / 2 - 6 * S
            {
                continue;
            }
            found = Some(other);
            break;
        }
        let Some(other) = found else {
            return Ok(());
        };
        let o = &mut self.entities[other];
        if let Kind::Walker(w) = &mut o.kind {
            if w.kind == crate::actors::ActorKind::Plant {
                return Err(Error::Unsupported {
                    requirements: vec!["star flower swallowing a plant (on_remove)".into()],
                });
            }
            w.remove(&mut o.status, &mut o.can_respawn);
        }
        o.status = 3;
        let e = &mut self.entities[index];
        e.can_despawn = 0;
        let f = self.flower(index);
        f.phase = FED;
        f.timer = 60;
        Ok(())
    }
    /// star_flower.gd _release: a health drop while health plus loose drops is under 30,
    /// else a coin.
    fn flower_release(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        let (x, top) = (e.body.x, e.body.y - 32 * S);
        self.sound.emit(4, e.body.x, e.body.y);
        let stars = self
            .entities
            .iter()
            .filter(|o| o.status == 1 && matches!(o.kind, Kind::Star(_)))
            .count() as i64;
        if self.player.life.health + stars < 30 {
            let vy = -self.rng.ticks(256 * 60, 512 * 60);
            let facing = if self.rng.ticks(0, 1) == 1 { 1 } else { -1 };
            let max_speed = self.rng.ticks(64 * 60, 128 * 60);
            self.spawn_star(x, top, vy, facing, max_speed)
        } else {
            let vx = self.rng.ticks(-192 * 60, 192 * 60);
            let vy = -self.rng.ticks(512 * 60, 768 * 60);
            let serial = self.next_serial()?;
            let mut pickup = Pickup::new(PickupKind::Coin, 0, top);
            pickup.moving = 1;
            pickup.despawn_ticks = 480;
            let mut row = Entity::dynamic(
                serial,
                Kind::Pickup(pickup),
                Body { x, y: top, vx, vy },
                -1,
                7,
            );
            row.can_despawn = 0;
            self.dynamic_serial = serial + 1;
            self.entities.push(row);
            Ok(())
        }
    }
}

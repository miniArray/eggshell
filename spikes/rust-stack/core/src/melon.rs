//! seed_melon.gd (o25): a melon that falls and waits to be eaten; eating a plain melon
//! loads seeds to spit. seed_shot.gd (runtime seed_shot): each SEED request becomes a seed
//! that flies straight, strikes the first object it reaches and stops at solids.
use crate::{
    body::{Body, Probe},
    eating::{HitKind, Projectile},
    entity::{Entity, Kind},
    food::{AMMO_SEED, SEED},
    math::{turn_cosine, turn_sine},
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};

pub(crate) const MELON_BOX: [i64; 4] = [-16 * S, -16 * S, 16 * S, 16 * S];
pub(crate) const SEED_BOX: [i64; 4] = [-4 * S, -4 * S, 4 * S, 4 * S];
/// Seeds loaded by each plain form.
const SEEDS: [i64; 3] = [30, 10, 60];
const SEED_SPEED: i64 = 768 * 60;
/// elements.gd LAST_MELON: forms above it degrade to an inert placeholder.
const LAST_MELON: i64 = 8;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Melon {
    pub form: i64,
    pub held: i64,
    pub request_cursor: i64,
}

impl Melon {
    /// seed_melon.gd prepare + create. Forms 3..8 load fire or ice shots (element_shot.gd),
    /// which the core does not run yet; they are refused.
    pub fn new(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: String| Error::Unsupported {
            requirements: vec![format!("o25 {why}")],
        };
        let form = match p.properties.iter().find(|(k, _)| k == "F").map(|(_, v)| v) {
            None => 0,
            Some(PropertyValue::Number(v)) if v.is_finite() && *v == v.floor() && *v >= 0.0 => {
                p.variant
            }
            Some(_) => return Err(refuse("invalid melon form".into())),
        };
        if form > LAST_MELON {
            return Err(refuse(format!(
                "melon form F={form} (degrades to a placeholder)"
            )));
        }
        if form >= SEEDS.len() as i64 {
            return Err(refuse(format!(
                "fire/ice melon form F={form} (needs element shots)"
            )));
        }
        Ok(Self {
            form,
            held: 0,
            request_cursor: 0,
        })
    }
    pub fn bounds(&self) -> [i64; 4] {
        MELON_BOX
    }
    /// seed_melon.gd ammunition: `[ammunition kind, count]` for a plain form.
    pub fn ammunition(&self) -> (i64, i64) {
        (AMMO_SEED, SEEDS[self.form as usize])
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        Some(match n {
            "form" => self.form,
            "held" => self.held,
            "request_cursor" => self.request_cursor,
            _ => return None,
        })
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        match n {
            "form" => self.form = value,
            "held" => self.held = value,
            "request_cursor" => self.request_cursor = value,
            _ => return false,
        }
        true
    }
    pub fn valid(&self, serial: i64) -> bool {
        (0..SEEDS.len() as i64).contains(&self.form)
            && [0, 1].contains(&self.held)
            && (0..=serial).contains(&self.request_cursor)
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Seed {
    pub heading: i64,
}

impl Seed {
    pub fn bounds(&self) -> [i64; 4] {
        SEED_BOX
    }
    pub fn field(&self, n: &str) -> Option<i64> {
        (n == "heading").then_some(self.heading)
    }
    pub fn set_field(&mut self, n: &str, value: i64) -> bool {
        if n == "heading" {
            self.heading = value;
            true
        } else {
            false
        }
    }
    pub fn valid(&self) -> bool {
        (0..360_000).contains(&self.heading)
    }
}

impl Run {
    /// seed_melon.gd step: a free melon falls (enemy_motion.gd gravity_box).
    pub(crate) fn melon_step(&mut self, index: usize, map: &Probe) {
        let e = &mut self.entities[index];
        if let Kind::Melon(m) = &e.kind {
            if m.held != 0 {
                return;
            }
            e.body.gravity_box(map, MELON_BOX, false, 2048, 704 * 60);
        }
    }
    /// seed_melon.gd tongue: a free active melon is caught whole and loads its seeds.
    pub(crate) fn melon_tongue(&mut self, index: usize) -> i64 {
        let blocks_step = self.player.blocks_step();
        let serial = self.player.food.requests.serial();
        let e = &mut self.entities[index];
        let token = e.origin.token();
        let Kind::Melon(m) = &mut e.kind else {
            return 0;
        };
        if m.held != 0 || e.status != 1 || blocks_step {
            return 0;
        }
        let (ammo, count) = m.ammunition();
        if self.player.catch_item(token, 0, ammo, count, 1, 256 * 60) {
            m.held = 1;
            e.body.vy = 0;
            m.request_cursor = serial;
            return 1;
        }
        0
    }
    /// seed_melon.gd consume_requests: a held melon is spent when it is swallowed.
    pub(crate) fn melon_consume(&mut self, index: usize) {
        let serial = self.player.food.requests.serial();
        let token = self.entities[index].origin.token();
        let list = match &self.entities[index].kind {
            Kind::Melon(m) if m.held != 0 => self.player.food.requests.since(m.request_cursor),
            _ => return,
        };
        let e = &mut self.entities[index];
        let Kind::Melon(m) = &mut e.kind else {
            return;
        };
        m.request_cursor = serial;
        let crate::food::Since::Requests(list) = list else {
            return;
        };
        for r in list {
            if r.item == token && r.kind == crate::food::CONSUME {
                m.held = 0;
                e.status = 3;
                e.can_respawn = 0;
            }
        }
    }
    /// seed_shot.gd consume_level_requests, for one SEED request: a runtime seed.
    pub(crate) fn spawn_seed(&mut self, x: i64, y: i64, angle: i64) -> Result<(), Error> {
        let serial = self.next_serial()?;
        let heading = angle.rem_euclid(360_000);
        let mut row = Entity::dynamic(
            serial,
            Kind::Seed(Seed { heading }),
            Body {
                x,
                y,
                vx: SEED_SPEED * turn_cosine(heading, S) / S,
                vy: SEED_SPEED * turn_sine(heading, S) / S,
            },
            -1,
            7,
        );
        row.can_despawn = 1;
        self.dynamic_serial = serial + 1;
        self.entities.push(row);
        Ok(())
    }
    /// seed_shot.gd step: fly straight; a seed that meets a solid drops away untouched,
    /// otherwise it strikes the first object it reaches.
    pub(crate) fn seed_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let e = &mut self.entities[index];
        e.body.x += e.body.vx;
        e.body.y += e.body.vy;
        if e.body.overlaps(map, SEED_BOX, 0, 0) {
            e.status = 3;
            return Ok(());
        }
        self.seed_strike(index)
    }
    /// seed_shot.gd strike: the entities near the seed when it looks (Near.nearby, in
    /// table order); enemies choose their reaction to a spit (projectile_contact), other
    /// objects with a hit rule take a Hits.SPIT hit (reaction 3). Any reaction stops it.
    fn seed_strike(&mut self, index: usize) -> Result<(), Error> {
        let body = self.entities[index].body;
        let projectile = Projectile {
            body,
            bounds: SEED_BOX,
            armored: false,
            spins: false,
            rolls: false,
            breaks: false,
        };
        let candidates = self.entities.len();
        for other in 0..candidates {
            if other == index || !self.spit_candidate(other, &projectile) {
                continue;
            }
            let reaction = self.spit_contact(other, &projectile, HitKind::Spit)?;
            if reaction != 0 {
                self.entities[index].status = 3;
                return Ok(());
            }
        }
        Ok(())
    }
}

/// seed_shot.gd consume_level_requests: the seeds to spawn, in request order.
pub(crate) fn seed_requests(list: &[crate::food::Request]) -> Vec<(i64, i64, i64)> {
    list.iter()
        .filter(|r| r.kind == SEED)
        .map(|r| (r.x, r.y, r.angle))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn seed_velocity_follows_heading() {
        assert_eq!(SEED_SPEED * turn_cosine(0, S) / S, SEED_SPEED);
        assert_eq!(SEED_SPEED * turn_sine(0, S) / S, 0);
        assert_eq!(SEED_SPEED * turn_sine(270_000, S) / S, -SEED_SPEED);
    }
    #[test]
    fn plain_melon_forms_load_seed_counts() {
        for (form, count) in [(0, 30), (1, 10), (2, 60)] {
            let m = Melon {
                form,
                held: 0,
                request_cursor: 0,
            };
            assert_eq!(m.ammunition(), (AMMO_SEED, count));
        }
    }
}

//! spear_guard.gd (e22): a small walker holding an upright spear of placement-defined
//! length. Strikes on its front push it back; strikes from behind defeat it. The spear
//! hurts on contact. The body lives in `Actor` (ActorKind::Spear).
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, HorizontalMove, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    state::Run,
    Error, Placement, PropertyValue, SCALE as S,
};
pub(crate) const BOX: [i64; 4] = [-10 * S, -18 * S, 10 * S, 16 * S];
const MAX_SPEAR: i64 = 4096;
const KNOCK_TICKS: i64 = 42;
const BLOCK_TICKS: i64 = 60;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// spear_guard.gd prepare + create.
    pub fn spear_guard(p: &Placement) -> Result<Self, Error> {
        let refuse = |why: String| Error::Unsupported {
            requirements: vec![format!("e22 {why}")],
        };
        let length = match p.properties.iter().find(|(k, _)| k == "E1").map(|(_, v)| v) {
            None => 0,
            Some(PropertyValue::String(s)) => {
                let mut digits = String::new();
                for (index, c) in s.trim().chars().enumerate() {
                    if c.is_ascii_digit() || (index == 0 && c == '-') {
                        digits.push(c);
                    } else {
                        break;
                    }
                }
                digits.parse::<i64>().unwrap_or(0)
            }
            Some(PropertyValue::Number(v)) if v.is_finite() => *v as i64,
            Some(_) => return Err(refuse("spear length".into())),
        };
        if length > MAX_SPEAR {
            return Err(refuse(format!("spear length {length}")));
        }
        if !(0..=4).contains(&p.variant) || !(0..=2).contains(&p.mirror) {
            return Err(refuse(format!("form F={} M={}", p.variant, p.mirror)));
        }
        let mut a = Actor::new(ActorKind::Spear, p.variant, p.mirror, p.position);
        a.spear = length.max(0) * S;
        Ok(a)
    }
    pub fn spear_valid(&self) -> bool {
        (0..=MAX_SPEAR * S).contains(&self.spear)
            && [0, 1].contains(&self.has_spear)
            && (0..=BLOCK_TICKS).contains(&self.block)
            && (0..=KNOCK_TICKS).contains(&self.knock_ticks)
            && self.knock_vx.abs() <= 200 * 60
            && [0, 1].contains(&self.grounded)
    }
    /// spear_guard.gd spear_box
    fn spear_box(&self, body: Body, facing: i64) -> Option<[i64; 4]> {
        (self.has_spear != 0).then(|| {
            let x = body.x - facing * S;
            [
                x - 7 * S,
                body.y - 24 * S - self.spear,
                x + 7 * S,
                body.y + 4 * S,
            ]
        })
    }
    /// spear_guard.gd activation_bounds, relative to the body: the spear raises the top.
    pub fn spear_activation(&self) -> [i64; 4] {
        let mut b = BOX;
        if self.has_spear != 0 {
            b[1] = b[1].min(-24 * S - self.spear);
        }
        b
    }
    /// spear_guard.gd knock
    pub(crate) fn spear_knock(&mut self, direction: i64) {
        self.knock_vx = direction * 200 * 60;
        self.knock_ticks = KNOCK_TICKS;
        self.block = BLOCK_TICKS;
    }
    /// spear_guard.gd view_state animation.
    pub fn spear_animation(&self) -> String {
        let pose = if self.block != 0 {
            "Block"
        } else if self.has_spear != 0 {
            "Spear"
        } else {
            "Walk"
        };
        format!("{}{pose}", self.variant)
    }
    /// spear_guard.gd projectile_contact for an egg heading `heading` (1 right): a
    /// front strike knocks it back, any other defeats it. The egg breaks (1).
    pub(crate) fn spear_egg(
        &mut self,
        facing: i64,
        status: &mut i64,
        can_respawn: &mut i64,
        heading: i64,
    ) {
        if self.has_spear != 0 && heading == -facing {
            self.spear_knock(heading);
        } else {
            self.has_spear = 0;
            self.remove(status, can_respawn);
        }
    }
}

impl Run {
    /// spear_guard.gd step.
    pub(crate) fn spear_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
        let token = self.entities[index].origin.token();
        let Run {
            entities,
            player,
            rng,
            frame,
            camera,
            ..
        } = self;
        let e = &mut entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            unreachable!()
        };
        if w.started == 0 {
            // enemy_body.gd process: the first step's initialisation.
            w.started = 1;
            w.impact_cursor = player.impact;
            if w.mirror == 2 {
                e.facing = if player.body.x > e.body.x { 1 } else { -1 };
            }
        }
        let mut step = ActorStep {
            map,
            frame: *frame,
            camera: *camera,
            player,
            rng,
        };
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
        // element_reactions.gd frozen_step
        match w.frozen_step(&mut e.body, e.status, map, BOX) {
            crate::elements::Frozen::Free => {}
            crate::elements::Frozen::Done => return Ok(()),
            crate::elements::Frozen::Lava => return self.remove_enemy(index),
        }
        if let Some(after) = w.spit_step(
            &mut e.body,
            &mut e.facing,
            &mut e.status,
            &mut e.can_respawn,
            &mut step,
        ) {
            if let After::HitOthers(b) = after {
                self.hit_others(index, b, HitKind::Spit, true)?;
            }
            return Ok(());
        }
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        let facing = &mut e.facing;
        if w.knock_ticks != 0 {
            w.knock_ticks -= 1;
            body.vx = w.knock_vx * w.knock_ticks / KNOCK_TICKS;
        } else if w.block != 0 {
            body.vx = 0;
        } else {
            body.vx = *facing * 48 * 60;
            if w.grounded != 0 {
                // enemy_motion.gd edge
                let left = if *facing > 0 { body.x } else { body.x - 12 * S };
                let bottom = body.y + BOX[3];
                if !map.support_in_box([left, bottom, left + 12 * S, bottom + 28 * S]) {
                    *facing = -*facing;
                    body.vx = -body.vx;
                }
            }
        }
        if w.block != 0 {
            w.block -= 1;
        }
        let distance = body.vx;
        let mut started = false;
        if distance != 0 {
            let actual = if body.prepare(map, BOX) {
                let support = body.floor(map, BOX);
                started = support != 0 && body.vy >= 0;
                body.horizontal(map, BOX, distance, support, HorizontalMove::Actor)
            } else {
                0
            };
            if actual != distance {
                if w.knock_ticks == 0 && w.block == 0 {
                    *facing = -*facing;
                }
                body.vx = 0;
            }
        }
        let landed = body.gravity(map, BOX, started);
        w.grounded = i64::from(landed || body.floor(map, BOX) != 0);
        Ok(())
    }
    /// spear_guard.gd contact.
    pub(crate) fn spear_contact(&mut self, index: usize, input: u8) {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return;
        };
        if w.held != 0 || w.spat != 0 || e.status != 1 || captured {
            return;
        }
        let player = world_box(p, pb);
        if let Some(spear) = w.spear_box(e.body, e.facing) {
            if strict(spear, player) {
                let x = e.body.x;
                self.player.hurt(x, &mut self.sound);
                let spear_x = (spear[0] + spear[2]) / 2;
                self.player.body.vx = if p.x < spear_x { -400 } else { 400 } * 60;
                return;
            }
        }
        // enemy_body.gd player_overlap (held, spat and captured already excluded).
        let touching = w.hidden == 0 && strict(world_box(e.body, BOX), player);
        if touching && e.body.y > p.y - 8 * S {
            if w.contact == 0 && w.has_spear == 0 {
                let vy = e.body.vy;
                if !pounding {
                    self.player.stomp(vy, input, &mut self.sound);
                }
                let e = &mut self.entities[index];
                if let Kind::Walker(w) = &mut e.kind {
                    w.remove(&mut e.status, &mut e.can_respawn);
                }
            }
        } else if touching {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        if let Kind::Walker(w) = &mut self.entities[index].kind {
            w.contact = i64::from(touching);
        }
    }
}

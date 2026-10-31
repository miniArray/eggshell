//! leap_bulk.gd (e17): a heavy hopper with a top-only deck. It waits, crouches and
//! leaps; a ground pound on its deck defeats it (F1 drops coins, F2 health). The body
//! lives in `Actor` (ActorKind::Bulk); its deck is a moving top-only solid.
use crate::{
    actors::{Actor, ActorKind, ActorStep},
    body::{Body, Probe},
    eating::{After, HitKind, Hold},
    entity::Kind,
    items::PickupKind,
    state::Run,
    Error, Placement, SCALE as S,
};
pub(crate) const WAIT: i64 = 0;
pub(crate) const FLATTEN: i64 = 1;
pub(crate) const RISE: i64 = 2;
pub(crate) const AIR: i64 = 3;
const WAIT_TICKS: i64 = 60;
const FLATTEN_TICKS: i64 = 12;
const RISE_TICKS: i64 = 6;
pub(crate) const BOX: [i64; 4] = [-18 * S, -28 * S, 18 * S, 16 * S];
const DECK_TOP: i64 = -26 * S;

fn world_box(body: Body, b: [i64; 4]) -> [i64; 4] {
    [body.x + b[0], body.y + b[1], body.x + b[2], body.y + b[3]]
}
/// enemy_body.gd overlap: strict on every side.
fn strict(a: [i64; 4], b: [i64; 4]) -> bool {
    a[0] < b[2] && a[2] > b[0] && a[1] < b[3] && a[3] > b[1]
}

impl Actor {
    /// leap_bulk.gd prepare + create.
    pub fn bulk(p: &Placement) -> Result<Self, Error> {
        if !(0..=2).contains(&p.variant) || !(0..=2).contains(&p.mirror) || p.rotation != 0 {
            return Err(Error::Unsupported {
                requirements: vec![format!(
                    "e17 form F={} M={} R={}",
                    p.variant, p.mirror, p.rotation
                )],
            });
        }
        Ok(Actor::new(ActorKind::Bulk, p.variant, p.mirror, p.position))
    }
    pub fn bulk_valid(&self) -> bool {
        (0..=2).contains(&self.variant)
            && (WAIT..=AIR).contains(&self.phase)
            && (0..=WAIT_TICKS).contains(&self.timer)
            && [0, 1].contains(&self.squashed)
    }
    /// leap_bulk.gd solid_box (status checked by the caller): the 34 x 2 deck.
    pub fn bulk_deck(&self, body: Body) -> Option<[i64; 4]> {
        (self.held == 0 && self.spat == 0).then(|| {
            let top = body.y + DECK_TOP;
            [body.x - 17 * S, top, body.x + 17 * S, top + 2 * S]
        })
    }
    /// leap_bulk.gd view_state: the squashed height.
    pub fn bulk_height(&self) -> Option<f64> {
        (self.phase == FLATTEN || self.squashed != 0).then_some(32.0)
    }
}

impl Run {
    /// leap_bulk.gd step.
    pub(crate) fn bulk_step(&mut self, index: usize, map: &Probe) -> Result<(), Error> {
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
        if w.frozen != 0 {
            return Err(Error::Unsupported {
                requirements: vec!["frozen e17 bulk (ice shots are not ported)".into()],
            });
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
        // enemy_body.gd hazards
        if map.lava_overlaps(world_box(e.body, BOX)) {
            w.remove(&mut e.status, &mut e.can_respawn);
            return Ok(());
        }
        let body = &mut e.body;
        let mut started = false;
        match w.phase {
            WAIT => {
                body.vx = 0;
                let grounded = body.floor(map, BOX) != 0;
                if grounded && w.squashed == 0 {
                    w.timer += 1;
                    if w.timer >= WAIT_TICKS {
                        w.phase = FLATTEN;
                        w.timer = FLATTEN_TICKS;
                    }
                }
            }
            FLATTEN | RISE => {
                w.timer -= 1;
                if w.timer <= 0 {
                    if w.phase == FLATTEN {
                        w.phase = RISE;
                        w.timer = RISE_TICKS;
                    } else {
                        w.phase = AIR;
                        w.timer = 0;
                        body.vy = -768 * 60;
                    }
                }
            }
            _ => {
                let wet = i64::from(map.water_overlaps(world_box(*body, BOX)));
                body.vx = e.facing * 206 * 60 / (wet + 1);
                let distance = body.vx;
                let (actual, on_floor) = w.movement_box(body, BOX, map, distance);
                started = on_floor;
                if actual != distance {
                    e.facing = -e.facing;
                }
            }
        }
        if body.gravity(map, BOX, started) && w.phase == AIR {
            w.phase = WAIT;
            w.timer = 0;
            body.vx = 0;
        }
        Ok(())
    }
    /// leap_bulk.gd contact.
    pub(crate) fn bulk_contact(&mut self, index: usize) -> Result<(), Error> {
        let pb = self.player.bounds();
        let p = self.player.body;
        let captured = self.player.captured_by != 0;
        let pounding = [2, 3].contains(&self.player.action);
        let on_floor = self.player.on_floor != 0;
        let e = &mut self.entities[index];
        let Kind::Walker(w) = &mut e.kind else {
            return Ok(());
        };
        // leap_bulk.gd standing: the player's feet within 4 px of the deck top.
        let feet = p.y + pb[3];
        let top = e.body.y + DECK_TOP;
        let on_deck = p.x + pb[2] >= e.body.x - 17 * S
            && p.x + pb[0] <= e.body.x + 17 * S
            && feet <= top + 4 * S
            && feet + 4 * S >= top;
        if on_deck && pounding {
            return self.bulk_defeat(index);
        }
        w.squashed = i64::from(on_deck && on_floor);
        // enemy_body.gd player_overlap
        let touching = w.hidden == 0
            && w.held == 0
            && w.spat == 0
            && e.status == 1
            && !captured
            && strict(world_box(e.body, BOX), world_box(p, pb));
        w.contact = i64::from(touching);
        if touching && !on_deck && e.body.y < p.y - 8 * S {
            let x = e.body.x;
            self.player.hurt(x, &mut self.sound);
        }
        Ok(())
    }
    /// leap_bulk.gd defeat: F1 drops three coins, F2 three health drops (coins once
    /// health is full); then it is removed.
    pub(crate) fn bulk_defeat(&mut self, index: usize) -> Result<(), Error> {
        let e = &self.entities[index];
        if e.status != 1 {
            return Ok(());
        }
        let Kind::Walker(w) = &e.kind else {
            return Ok(());
        };
        let (x, y, variant) = (e.body.x, e.body.y, w.variant);
        for n in 0..3 {
            if variant == 1 || (variant == 2 && self.player.life.health + n >= 30) {
                let vx = self.rng.ticks(-256 * 60, 256 * 60);
                let vy = -self.rng.ticks(256 * 60, 384 * 60);
                self.spawn_pickup(PickupKind::Coin, x, y, vx, vy)?;
            } else if variant == 2 {
                let vy = -self.rng.ticks(256 * 60, 512 * 60);
                let facing = if self.rng.ticks(0, 1) == 0 { -1 } else { 1 };
                let max_speed = self.rng.ticks(64 * 60, 128 * 60);
                self.spawn_star(x, y, vy, facing, max_speed)?;
            }
        }
        let e = &mut self.entities[index];
        if let Kind::Walker(w) = &mut e.kind {
            w.remove(&mut e.status, &mut e.can_respawn);
        }
        Ok(())
    }
}
